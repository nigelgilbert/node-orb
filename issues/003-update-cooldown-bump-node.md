# dev/update (7-day cooldown) + dev/bump-node

**Type**: AFK

**Status:** ✅ Done (verified 2026-07-07)

## Parent

[PLAN.md](../PLAN.md) — decisions 5, 9, 12; HARDENING.md decisions 4 and 7.

## What to build

The two maintenance commands that turn supply-chain discipline into tooling.

- `dev/update`: ephemeral container with network, regenerates the lockfile
  with npm's `--before` set to now minus 7 days, so versions published in the
  last week structurally cannot be resolved. Shows a before/after diff
  summary of changed packages and reminds that `dev/install` (npm ci) applies
  it. Zero env, repo-only mount, same isolation as install.
- `dev/bump-node`: fetches the current digest for the pinned `node:24-slim`
  tag (e.g. via `docker manifest inspect` or a pull) and rewrites the single
  pin file. Output shows old → new digest; a no-op when already current. This
  is the one command that keeps dev and prod base images fresh, reviewable as
  a one-line git diff.

## Acceptance criteria

- [x] `./dev/update` rewrites the lockfile and no resolved version in it was
      published within the last 7 days (spot-checkable via
      `npm view <pkg>@<version> time`).
- [x] A dep with a release younger than 7 days resolves to the newest version
      OLDER than 7 days, not the latest.
- [x] `./dev/update` output lists which packages changed and their old → new
      versions.
- [x] `./dev/bump-node` updates the pin file to the registry's current digest
      and prints old → new; running it twice in a row makes the second run a
      stated no-op.
- [x] After a bump, `./dev/install` uses the new digest without any other
      file changing.

## Blocked by

- #001
