# Security Review

**Date:** 2026-07-10  
**Scope:** Application source, development scripts, npm dependencies, Docker build, Compose topology, proxy configuration, and secret handling.

> Prepared by GPT 5.6.

## Summary

No critical or high-severity vulnerabilities were identified. The repository has a strong baseline: dependencies and container images are pinned, npm lifecycle scripts are disabled, the application runs non-root with a read-only filesystem, published ports bind to loopback by default, and production egress is routed through a restricted proxy.

The review found one medium-severity weakness in the default egress policy and two low-severity defense-in-depth gaps.

## Findings

### 1. Medium: default egress allowlist permits secret exfiltration

**Evidence:** `proxy/filter:13-17`, `HARDENING.md:44-49`, `HARDENING.md:67-73`

The shipped proxy filter contains placeholder Discord domains, including `discord.com`. Code executing inside the application can therefore POST environment secrets to an attacker-controlled Discord webhook. This bypasses the intended egress containment for the same compromised-dependency threat described by the hardening documentation.

The limitation is documented and the proxy still blocks arbitrary destinations, but the default configuration leaves a practical exfiltration channel enabled even though the template application does not need Discord access.

**Recommendation:** Ship a deny-all filter with no active destinations. Require each project to explicitly add only the domains it needs. If Discord access is required, treat webhook exfiltration as an accepted residual risk and document it in the project-specific threat model.

### 2. Low: secret-file permissions are documented but not enforced

**Evidence:** `dev/run:16-40`, `docker-compose.yml:33-35`, `README.md:62-66`

Runtime secrets are correctly stored outside the repository, and the README instructs users to set mode `0600`. However, `dev/run` validates only the file's content syntax; it does not reject or warn about a group- or world-readable file. Compose also consumes the file without checking its ownership or permissions.

On a multi-user host, an accidentally created `0644` file could expose application tokens to other local users.

**Recommendation:** Before loading the file, reject it or emit a prominent warning unless it is owned by the current user and has no group/world permissions. Apply an equivalent preflight check to the documented Compose workflow.

### 3. Low: the TCP forwarder runs as container root

**Evidence:** `docker-compose.yml:102-121`, pinned `alpine/socat` image metadata

The `alpine/socat` image has no default `USER`, and the Compose service does not specify one. Consequently, the forwarder runs as container root even though it listens on unprivileged port 3000 and does not require elevated privileges.

The practical risk is limited because the service drops all capabilities, enables `no-new-privileges`, uses a read-only root filesystem, has resource limits, mounts no secrets, and runs only `socat`. Nevertheless, an explicit non-root UID/GID would reduce the impact of a vulnerability in the forwarder or container runtime.

**Recommendation:** Configure the forwarder with a tested unprivileged numeric `user`.

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
- Shellcheck completed without findings for the development and proxy scripts.
- Local pinned-image metadata confirmed that tinyproxy is non-root and the forwarder defaults to root.

Docker Scout image-CVE scanning could not be completed because the installed scanner requires Docker authentication. Therefore, this review does not assert that the pinned operating-system packages are free of known vulnerabilities. Digest pinning ensures reproducibility, but the image pins should still be refreshed and scanned on a regular schedule.

## Review disposition

The repository is suitable as a hardened template after accepting the documented residual risks. The default proxy allowlist should be addressed before treating egress control as protection against deliberate in-process secret exfiltration. The two low-severity findings are defense-in-depth improvements rather than release blockers.
