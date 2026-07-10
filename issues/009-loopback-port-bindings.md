# Bind dev and prod port mappings to loopback

**Type**: AFK

**Status:** ✅ Complete

## Parent

REVIEW.md (since removed) — Finding 3 and the ports half of Finding 4.

## What to build

Both the dev runner and the shipped compose file publish the app port without
an IP prefix, so docker binds `0.0.0.0` — and both load the project env file,
so the process holding the secrets is reachable by any peer on the same LAN.

Prefix `127.0.0.1:` on the port mapping in both places (dev run script and
compose `ports:`), and note in HARDENING.md that loopback-only is the default
and how an operator deliberately exposes the port when they mean to.

## Acceptance criteria

- [ ] With the app running via `./dev/run`, `docker port` (or `docker inspect`)
      shows the binding on `127.0.0.1`, not `0.0.0.0`; `curl localhost:3000`
      still works.
- [ ] Same check passes for `docker compose up`.
- [ ] HARDENING.md documents the loopback default and the deliberate
      opt-out path.

## Blocked by

None - can start immediately
