# dev/clean

**Type**: AFK

**Status:** ✅ Done (verified 2026-07-07)

## Parent

[PLAN.md](../PLAN.md) — decisions 7, 13.

## What to build

The reset command, two-tier:

- `dev/clean` (default): deletes `node_modules/` and removes any stray
  containers belonging to this project (labeled or name-prefixed at
  `docker run` time by the other scripts — add that label/prefix in this
  slice if #001 didn't). Instant, safe, everyday.
- `dev/clean --all`: additionally drops the project's npm cache volume and
  re-pulls the pinned base image. Factory reset.
- Chatty output enumerates what it removed (and what it found nothing of),
  in the shared style.

## Acceptance criteria

- [x] `./dev/clean` removes `node_modules/` and any project-labeled
      containers, and touches nothing else (cache volume still exists,
      other projects' containers untouched).
- [x] `./dev/clean --all` also removes the project's cache volume
      (`docker volume ls` no longer shows it) and re-pulls the pinned image.
- [x] `./dev/install` after `--all` performs a cold install (observably
      slower / re-downloads) and succeeds.
- [x] Running clean when there is nothing to clean succeeds with a friendly
      no-op message.

## Blocked by

- #001
