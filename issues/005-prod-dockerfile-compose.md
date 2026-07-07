# Prod skeleton: multi-stage Dockerfile + hardened compose

**Type**: AFK

**Status:** ✅ Done (verified 2026-07-07)

## Parent

[PLAN.md](../PLAN.md) — decision 10; HARDENING.md decisions 5, 6, 7, and the
proxy-wiring work items.

## What to build

The deploy-ready production half of the template, sharing the dev digest pin.

- Multi-stage `Dockerfile`: build stage runs `npm ci --ignore-scripts` +
  `tsc` to `dist/`; runtime stage gets `npm ci --omit=dev --ignore-scripts`
  and `CMD ["node", "dist/index.js"]` (no npx, no TS tooling in the runtime
  layer). Both stages `FROM node:24-slim@<digest>` using the same digest as
  the pin file (build arg or generated — keep one source of truth; note the
  chosen mechanism in the README slice).
- `docker-compose.yml` with full hardening on the app service:
  `read_only: true`, `tmpfs: [/tmp]`, `cap_drop: [ALL]`,
  `no-new-privileges:true`, `pids_limit`, `mem_limit`, and
  `env_file: ${HOME}/.config/<project>/env` (same file dev/run uses).
- A **commented-out** tinyproxy egress-sidecar block: `internal: true` app
  network, proxy service with a placeholder domain allowlist and healthcheck,
  and comments explaining what to uncomment and how the app must honor
  `https_proxy` (per HARDENING.md's undici/EnvHttpProxyAgent notes). Off by
  default; enabling it is a per-project decision.

## Acceptance criteria

- [x] `docker compose build` succeeds from the skeleton and the resulting
      runtime image contains `dist/` but no `typescript` in `node_modules`
      and no `src/`.
- [x] `docker compose up` runs hello world; `docker inspect` on the running
      container shows read-only rootfs, no capabilities, no-new-privileges,
      and the pids/mem limits.
- [x] Writing to `/` inside the running container fails; writing to `/tmp`
      succeeds.
- [x] The digest in the built image matches the dev pin file (one source of
      truth verified).
- [x] Uncommenting the proxy block (as a test) yields a compose config where
      the app network is `internal: true` and direct egress from the app
      container fails while proxied egress to an allowlisted domain succeeds.

## Blocked by

- #001
