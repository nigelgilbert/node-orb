# Security Review

**Date:** 2026-07-10  
**Scope:** Application source, development scripts, npm dependencies, Docker build, Compose topology, proxy configuration, and secret handling.

> Prepared by GPT 5.6.

## Summary

No critical or high-severity vulnerabilities were identified. The repository has a strong baseline: dependencies and container images are pinned, npm lifecycle scripts are disabled, the application runs non-root with a read-only filesystem, published ports bind to loopback by default, and production egress is routed through a restricted proxy.

The review found one medium-severity weakness in the default egress policy and three low-severity defense-in-depth gaps.

## Findings

### 1. Medium: default egress allowlist permits secret exfiltration

**Evidence:** `proxy/filter:13-17`, `MANIFESTO.md:44-49`, `MANIFESTO.md:69-73`

The shipped proxy filter contains placeholder Discord domains, including `discord.com`. Code executing inside the application can therefore POST environment secrets to an attacker-controlled Discord webhook. This bypasses the intended egress containment for the same compromised-dependency threat described by the hardening documentation.

The limitation is documented and the proxy still blocks arbitrary destinations, but the default configuration leaves a practical exfiltration channel enabled even though the template application does not need Discord access.

**Recommendation:** In `proxy/filter`, comment out (or delete) the placeholder destination lines `discord.com`, `*.discord.com`, and `gateway.discord.gg`, leaving only `api.anthropic.com` if this project actually calls it — otherwise ship the file with every destination commented out so `FilterDefaultDeny Yes` denies everything until a project opts a domain in. Keep the existing explanatory comment block. If Discord access is genuinely required, re-add the specific domains and document webhook exfiltration as an accepted residual risk in the project-specific threat model. Re-run `./proxy/verify-egress.sh` after editing (note: its test cases at lines 40, 42, 69-74 hard-code `discord.com` as the allowlisted control — update them to whatever domain remains allowlisted, or the acceptance test will fail against a deny-all filter).

### 2. Low: secret-file permissions are documented but not enforced

**Evidence:** `dev/run:16-40`, `docker-compose.yml:33-35`, `README.md:62-66`

Runtime secrets are correctly stored outside the repository, and the README instructs users to set mode `0600`. However, `dev/run` validates only the file's content syntax; it does not reject or warn about a group- or world-readable file. Compose also consumes the file without checking its ownership or permissions.

On a multi-user host, an accidentally created `0644` file could expose application tokens to other local users.

**Recommendation:** In `dev/run`, after confirming `[ -f "$ENV_FILE" ]` (line 16) and before adding `--env-file`, stat the file and refuse or loudly warn on group/world access — e.g. reject unless the owner is the current user and the mode masks to `0600`. A portable check using the existing `die`/`warn` helpers from `_lib.sh`:

```sh
# perms are octal from `stat`; BSD (macOS) uses -f %Lp, GNU uses -c %a
perms="$(stat -f '%Lp' "$ENV_FILE" 2>/dev/null || stat -c '%a' "$ENV_FILE")"
case "$perms" in *[1-7][0-7]|*[0-7][1-7]) warn "…group/world-accessible ($perms); run: chmod 600 $ENV_FILE";; esac
```

Since Compose (`docker-compose.yml:33-35`) consumes the same file, document the same preflight in the README secrets section rather than duplicating it in Compose, which has no hook to run a shell check.

### 3. Low: the TCP forwarder runs as container root

**Evidence:** `docker-compose.yml:102-121`, pinned `alpine/socat` image metadata

The `alpine/socat` image has no default `USER`, and the Compose service does not specify one. Consequently, the forwarder runs as container root even though it listens on unprivileged port 3000 and does not require elevated privileges.

The practical risk is limited because the service drops all capabilities, enables `no-new-privileges`, uses a read-only root filesystem, has resource limits, mounts no secrets, and runs only `socat`. Nevertheless, an explicit non-root UID/GID would reduce the impact of a vulnerability in the forwarder or container runtime.

**Recommendation:** Add `user: "65534:65534"` (the `nobody`/`nogroup` IDs present in `alpine/socat`) to the `forwarder` service in `docker-compose.yml`, alongside the existing `cap_drop`/`security_opt` lines. The forwarder binds unprivileged port 3000, so no capability is needed. Verify with `./proxy/verify-egress.sh` (check 1 exercises the forwarder path end-to-end).

### 4. Low: `dev/run` exposes secrets to unrestricted egress, unlike production

**Evidence:** `dev/run:16-58`, `dev/test:7`, `MANIFESTO.md:39-49`

The project's threat model is require-time exfiltration by a compromised dependency, and `dev/test`/`dev/shell` correctly default to `--network none` to close it. But `dev/run` starts `node --watch src/index.ts` with the default Docker bridge network (full egress — it never applies the `net_args=(--network none)` computed by `parse_net_args`) *and* loads the secrets file via `--env-file` (line 36). Production caps this exact combination with the tinyproxy allowlist; the dev loop has no equivalent, so a poisoned transitive dependency loaded at require time runs with the secrets in `process.env` and an open path to the internet.

The exposure is dev-only and requires a secrets file to exist. It cannot be closed by dropping the network — `dev/run` is a server and needs it — but the asymmetry with production should be surfaced.

**Recommendation:** Document the residual risk in the README/MANIFESTO (dev egress is uncapped by design, so keep secrets out of `~/.config/<project>/env` until an app truly needs them locally). Optionally, offer a proxied dev path — e.g. a Compose-based `dev/run` variant that reuses the production `internal`/`proxy` topology — for developers who must exercise secret-holding code paths locally.

## Positive controls observed

- Production and development use the same digest-pinned Node image.
- Proxy and forwarder images are digest-pinned.
- npm dependencies use exact versions and lockfile integrity hashes.
- npm lifecycle scripts are disabled through committed configuration and explicit build flags.
- The runtime image contains compiled JavaScript and no production dependencies today.
- The application runs as the non-root `node` user.
- Application storage is read-only apart from `/tmp`.
- Linux capabilities are dropped and `no-new-privileges` is enabled for every Compose service.
- The application is attached only to an internal Docker network and has no direct egress route.
- Tinyproxy listens only on its internal static address and accepts only the application's static address.
- The published application port binds to `127.0.0.1` by default.
- Network-related pass-through arguments in the development scripts are parsed defensively.
- Port parsing rejects malformed, non-decimal, and out-of-range values.
- Graceful shutdown is bounded and closes idle connections.

## Verification performed

- `npm audit --json`: zero known vulnerabilities across three development dependencies and no production packages.
- `npm test`: all 9 tests passed.
- `npm run build`: passed.
- `docker compose config --quiet`: passed.
- Resolved Compose configuration confirmed the loopback port binding and intended network memberships.
- Shellcheck reported no genuine defects in the development and proxy scripts. Running it file-by-file emits SC2154/SC2034/SC1091 notes, but these are artifacts of analyzing each script in isolation from its sourced `_lib.sh` (the variables are assigned there); with `-x`/`-s bash` they resolve to noise, not real issues.
- Local pinned-image metadata confirmed that tinyproxy is non-root and the forwarder defaults to root.

Docker Scout image-CVE scanning could not be completed because the installed scanner requires Docker authentication. Therefore, this review does not assert that the pinned operating-system packages are free of known vulnerabilities. Digest pinning ensures reproducibility, but the image pins should still be refreshed and scanned on a regular schedule.

## Review disposition

The repository is suitable as a hardened template after accepting the documented residual risks. The default proxy allowlist should be addressed before treating egress control as protection against deliberate in-process secret exfiltration. The three low-severity findings are defense-in-depth improvements rather than release blockers.
