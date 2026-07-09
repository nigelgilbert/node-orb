# Supply-chain hardening — decision log (2026-07-05)

> Threat model: Shai-Hulud-class npm worms — malicious `postinstall` at install
> time (credential harvest + self-propagation), require-time payloads at
> runtime (exfil from the process holding secrets). Decisions reached in a
> /grill-me session; rationale inline so future-us doesn't re-litigate.

## Verified facts (grounding)

- The template ships zero runtime deps and two dev deps (`typescript`,
  `@types/node`), neither of which has an install script —
  `--ignore-scripts` is therefore free for this tree. Re-verify when adding
  deps that need native builds (`npm rebuild <pkg>` is the deliberate escape
  hatch, decision 3).
- No node/npm/npx/pnpm/yarn/pm2 exists on the host Mac — all installs happen
  in containers.
- The canonical harvestable host credential is `~/.config/gh/hosts.yml`
  (gh CLI token). Unreachable as long as install containers never mount
  `$HOME`.
- The app only reads config at startup and writes nothing → read-only rootfs
  (+ tmpfs `/tmp`) is viable.

## Decisions

1. **Scope: all three surfaces** — image build, container runtime, dev
   workflow. The worm's primary target is the machine running `npm install`,
   not the deploy container.

2. **Egress: proxy sidecar (LIVE in docker-compose.yml).** The app container
   sits on an `internal: true` network with **no gateway** — verified: a direct
   fetch from inside the app to a non-allowlisted host fails (external DNS
   SERVFAILs, `EAI_AGAIN`). A tinyproxy sidecar (also on `internal`, plus an
   `egress` bridge) with a domain allowlist (`proxy/filter`) is the only route
   out: `discord.com`, `*.discord.com`, `gateway.discord.gg`, `api.anthropic.com`
   (placeholders — edit to what the app truly calls). The app is wired to it via
   `NODE_USE_ENV_PROXY=1` + `https_proxy`/`http_proxy` (Node global fetch honors
   these for free; curl in scripts too).

   *Proxy is not an open relay.* `tinyproxy.conf` `Listen`s only on the proxy's
   internal IP (`172.31.9.3`) — nothing on the egress side can reach the proxy
   port — and `Allow`s only the app's static internal IP (`172.31.9.2`). Any
   other container, even one attached to the internal network, gets
   `403 Access denied` before filtering even runs (verified from a foreign
   busybox container on the internal net).

   *Empirical filter semantics (tinyproxy 1.11.3, `FilterType fnmatch`,
   `FilterDefaultDeny Yes`).* Verified against the deployed proxy that fnmatch
   matches the **parsed host only**, not the full URL string or path. So the
   review's open question is settled — these all return `403 Filtered`:
   - userinfo trick `http://discord.com@evil.com/` → host parsed as `evil.com`,
     denied (the allowed string in the userinfo is ignored);
   - subdomain-suffix `http://discord.com.evil.com/` → denied;
   - CONNECT form `CONNECT evil.com:443` and `CONNECT discord.com@evil.com:443`
     → denied.
   The reverse (`http://evil.com@discord.com/`) returns 200, confirming the
   match target is the parsed host. Anchoring caveats (fnmatch `*` also matches
   dots, so a leading-`*` glob like `*discord.com` would match `evildiscord.com`;
   `*.discord.com` does not cover the apex) are documented in `proxy/filter`.
   Re-run `./proxy/verify-egress.sh` to reconfirm against whatever tinyproxy is
   pinned.

   *Accepted caveat:* an in-process attacker can still exfil via a Discord
   webhook on the allowlisted `discord.com` — this blocks the channels real
   Shai-Hulud payloads used (webhook.site, fresh GitHub repos, C2 domains),
   it is a bar-raise, not a wall.

3. **Commit `ignore-scripts=true` in repo `.npmrc`** (plus `save-exact=true`).
   Applies to every install, host-side or in-image. A future dep that
   genuinely needs scripts gets a deliberate `npm rebuild <pkg>`.

4. **Exact version pins + 7-day cooldown.** Drop carets. Updates are
   deliberate: bump only to versions published ≥7 days ago (worm releases get
   yanked within hours/days). `npm ci` + lockfile already covers the image;
   exact pins extend protection to lockfile-regeneration paths.

5. **Multi-stage image, ship compiled JS.** Build stage runs `tsc`; runtime
   stage gets `npm ci --omit=dev --ignore-scripts` (prod deps only — zero
   today), runs `node dist/index.js`. No `npx` in CMD (registry-reach at
   runtime), no tsx/esbuild/typescript sitting next to the secrets.

6. **Full compose hardening + network isolation (LIVE).** Every service —
   `app`, `proxy`, and the `forwarder` (below) — runs `read_only: true`,
   `tmpfs: [/tmp]`, `cap_drop: [ALL]`, `no-new-privileges:true`, `pids_limit`,
   `mem_limit`.

   *Network topology.* Three networks:
   - `internal` (`internal: true`, no gateway, fixed subnet `172.31.9.0/24`):
     app (`.2`) and proxy (`.3`). The app has no route out; the proxy is its
     only door.
   - `egress` (plain bridge): the proxy's route to the internet.
   - `ingress` (bridge, host-facing): carries the published port only.

   *Why the app doesn't publish its own port.* An `internal: true` network
   cannot publish ports, and the original masquerade-off trick (put the app on a
   bridge with `enable_ip_masquerade: false` so inbound DNAT works but outbound
   dies un-NATed) does **not** cut egress under Docker Desktop's VM NAT —
   verified: a direct fetch from the app still returned `200`, so the app kept a
   working route out and the allowlist was bypassed. The portable fix is to keep
   the app strictly internal-only and publish through a tiny `alpine/socat`
   **forwarder** on `ingress` + `internal` that pipes `127.0.0.1:${HOST_PORT}` →
   `app:3000`. The forwarder holds no secrets and runs no untrusted code, so a
   route out on its bridge costs nothing; the secrets-holding app still has none.
   The published-port contract is unchanged: `${BIND_ADDR:-127.0.0.1}:${HOST_PORT:-3000}:3000`,
   loopback by default (decision 10).

7. **Pin base image by digest** (`node:24-slim@sha256:…`, both stages).
   Base updates become a reviewable git diff; we own bumping for Node
   security patches.

8. **Deploy target: this Mac, via OrbStack.** Same compose file for rehearsal
   and prod.

9. **Secrets: keep `.env` + `env_file`, but move it outside the repo** to
   `~/.config/<project>/env` (chmod 600). Rationale: dev install/test
   containers bind-mount the repo dir; secrets in-repo would be readable by
   any compromised package running there. In-process env exposure is accepted
   — the app needs the tokens; egress control limits blast radius.

10. **Published port binds loopback by default.** Both `./dev/run` and the
    compose `ports:` mapping publish the app port as
    `127.0.0.1:${HOST_PORT:-3000}:3000`, so docker binds `127.0.0.1` rather than
    `0.0.0.0`. The dev process and prod container both load the project env file
    (`~/.config/<project>/env`); a `0.0.0.0` bind would let any peer on the same
    LAN (coffee-shop/office WiFi) `curl <host-ip>:3000` and reach the process
    holding those secrets. Loopback keeps it reachable only from the host.
    *Deliberate opt-out:* set `BIND_ADDR=0.0.0.0` (or a specific host IP) in the
    environment for `./dev/run` or `docker compose up` when you genuinely mean to
    expose the port — e.g. `BIND_ADDR=0.0.0.0 docker compose up`. The container-
    side port stays pinned to `DEFAULT_PORT` (src/index.ts); `BIND_ADDR` and
    `HOST_PORT` only steer the host side of the mapping.

## Standing rules (dev hygiene)

- Install containers get the repo dir mounted — **never `$HOME`**.
- **Never run npm installs in an OrbStack Linux machine** (machines auto-share
  the macOS home dir, exposing the gh token); throwaway docker containers only.
- Install containers get no env passed in (`-e HOME=/tmp`, nothing else).

## Known work items (implementation, not decisions)

- Proxy wiring in the app is shipped for global `fetch` (`NODE_USE_ENV_PROXY=1`
  + `https_proxy`/`http_proxy` in compose). Still on the app author when adding
  clients that build their own transport: SDKs that construct their own undici
  agents want `EnvHttpProxyAgent` as the global dispatcher; websocket clients
  need an explicit proxy agent (the fiddly one). Scripts' curl already honors
  `https_proxy`.
- `proxy/filter` ships placeholders (`discord.com`, `api.anthropic.com`, …).
  Trim to exactly what THIS app calls before relying on it.
- The proxy image is digest-pinned (`kalaksi/tinyproxy@sha256:fafa…`, tinyproxy
  1.11.3) and the forwarder image too (`alpine/socat@sha256:188f…`); bump them
  deliberately like the base image (decision 7).
