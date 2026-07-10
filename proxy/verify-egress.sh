#!/usr/bin/env bash
# Live acceptance test for the egress-control topology (HARDENING.md §2/§6).
# Brings the compose stack up, exercises the real controls end-to-end against
# the deployed tinyproxy, tears everything down, and exits non-zero on any
# failure. Run from the repo root: ./proxy/verify-egress.sh
#
# Empirically settled (tinyproxy 1.11.3): FilterType fnmatch matches the PARSED
# HOST, not the full URL string — so the userinfo trick (allowed@evil), the
# subdomain-suffix trick (allowed.evil), and non-allowlisted CONNECT are all
# denied. This script re-verifies that against whatever tinyproxy is deployed.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_IP=172.31.9.2
PROXY_IP=172.31.9.3
PORT="${HOST_PORT:-3000}"
fails=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
check() { # check <desc> <expected-substr> <actual>
  if printf '%s' "$3" | grep -qF "$2"; then pass "$1 -> $3"; else fail "$1 (want '$2', got '$3')"; fi
}

cleanup() { docker compose down -v --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== building & starting stack =="
docker compose build app >/dev/null
docker compose up -d >/dev/null
# wait for the app to answer through the forwarder
for _ in $(seq 1 20); do
  curl -sf -o /dev/null --max-time 3 "http://127.0.0.1:${PORT}/" && break || sleep 1
done

echo "== 1. host reaches published port (via forwarder) =="
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 "http://127.0.0.1:${PORT}/")
check "host -> 127.0.0.1:${PORT}" "200" "HTTP ${code}"

echo "== 2. app egress: allowlisted via proxy succeeds, non-allowlisted denied =="
allowed=$(docker compose exec -T app node -e 'fetch("https://discord.com/robots.txt",{signal:AbortSignal.timeout(12000)}).then(r=>console.log("HTTP",r.status)).catch(e=>console.log("ERR",e.cause?.code||e.message))')
check "proxy -> allowlisted discord.com" "HTTP" "$allowed"
denied=$(docker compose exec -T app node -e 'fetch("https://example.org/",{signal:AbortSignal.timeout(12000)}).then(r=>console.log("REACHED",r.status)).catch(e=>console.log("DENIED"))')
check "proxy -> non-allowlisted example.org" "DENIED" "$denied"

echo "== 3. app has NO direct route out (bypassing the proxy) =="
direct=$(docker compose exec -T -e https_proxy= -e http_proxy= -e no_proxy='*' app node -e 'fetch("https://example.org/",{signal:AbortSignal.timeout(9000)}).then(r=>console.log("REACHED",r.status)).catch(e=>console.log("BLOCKED"))')
check "direct fetch example.org (no proxy)" "BLOCKED" "$direct"

echo "== 4. a non-app container on the internal net cannot relay =="
# app is internal-only, so its single network is the internal one.
INTERNAL_NET=$(docker inspect "$(docker compose ps -q app)" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
# Digest-pinned like the compose services (see docker-compose.yml) so this
# verification stays reproducible and free of supply-chain drift.
BUSYBOX=busybox@sha256:9532d8c39891ca2ecde4d30d7710e01fb739c87a8b9299685c63704296b16028  # busybox 1.37
relay=$(docker run --rm --network "$INTERNAL_NET" "$BUSYBOX" sh -c \
  "printf 'GET http://discord.com/ HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n' | nc -w 5 ${PROXY_IP} 8888 | head -1" 2>/dev/null || true)
check "non-app relay attempt" "403 Access denied" "$relay"

echo "== 5. bypass denial tests against deployed tinyproxy (from app IP ${APP_IP}) =="
probe() { # probe <request-line>
  docker compose exec -T app node -e '
    const net=require("net"); const s=net.connect(8888,"'"$PROXY_IP"'"); let b="";
    s.setTimeout(8000);
    s.on("connect",()=>s.write(process.argv[1]+"\r\nHost: placeholder\r\nConnection: close\r\n\r\n"));
    s.on("data",d=>b+=d); s.on("timeout",()=>{console.log("TIMEOUT");s.destroy()});
    s.on("error",e=>console.log("ERR",e.code)); s.on("close",()=>console.log((b.split("\r\n")[0]||"none")));
  ' "$1"
}
ctrl=$(probe 'GET http://discord.com/ HTTP/1.1')
if printf '%s' "$ctrl" | grep -q '403'; then fail "control allowed GET discord.com (unexpectedly filtered) -> $ctrl"; else pass "control allowed GET discord.com -> $ctrl"; fi
check "userinfo         GET discord.com@example.org"  "403 Filtered" "$(probe 'GET http://discord.com@example.org/ HTTP/1.1')"
check "subdomain-suffix GET discord.com.example.org"  "403 Filtered" "$(probe 'GET http://discord.com.example.org/ HTTP/1.1')"
check "CONNECT          example.org:443"              "403 Filtered" "$(probe 'CONNECT example.org:443 HTTP/1.1')"
check "CONNECT userinfo discord.com@example.org:443"  "403 Filtered" "$(probe 'CONNECT discord.com@example.org:443 HTTP/1.1')"

echo
if [ "$fails" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "${fails} CHECK(S) FAILED"; exit 1; fi
