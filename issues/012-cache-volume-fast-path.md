# ensure_cache_volume fast path — stop spinning a container per invocation

**Type**: AFK

**Status:** ✅ Complete

## Parent

REVIEW.md (since removed) — Finding 8.

## What to build

`ensure_cache_volume` runs a full `docker run --rm -u root …` (container
create + start + remove, ~0.3–2s) on every `dev/install`, `dev/update`, and
`dev/shell` call; the in-container `stat` only short-circuits the `chown`, not
the container start. After first use the volume's ownership persists, so this
is a permanent per-invocation tax for a one-time setup.

Check the volume's existence with `docker volume inspect` first and skip the
container entirely on the hot path, only paying container-start cost when the
volume is missing (or ownership actually needs fixing).

## Acceptance criteria

- [ ] With the cache volume already initialized, `dev/install` / `dev/update` /
      `dev/shell` create zero extra containers for the cache check (verify via
      `docker events` or timing).
- [ ] With the volume deleted, the next invocation recreates it with correct
      non-root ownership and the calling script succeeds.
- [ ] `./dev/clean` followed by `./dev/install` still works end-to-end.

## Blocked by

None - can start immediately
