# dev/update: stop misdiagnosing every failure as the 7-day cooldown

**Type**: AFK

**Status:** ✅ Complete

## Parent

REVIEW.md (since removed) — Addendum A2.

## What to build

`dev/update`'s failure path prints one fixed message — "a dep pinned to a
version published in the last 7 days cannot satisfy the cooldown; retry once
it ages past 7 days" — for *any* non-zero exit. A transient registry error,
disk-full, or malformed `package.json` sends the user on a 7-day wait for a
30-second blip.

Separate the failure modes: reserve the cooldown explanation for failures that
actually look like the cooldown (based on npm's output/exit context), and
surface everything else with the underlying error plus a generic "update
failed, lockfile restored" note. The EXIT-trap lockfile restore stays as-is.

## Acceptance criteria

- [ ] A simulated network failure (e.g. unreachable registry) prints the real
      error and does not mention the 7-day cooldown.
- [ ] A genuine cooldown conflict still gets the cooldown explanation.
- [ ] In both cases the lockfile is restored and the exit code is non-zero.

## Blocked by

None - can start immediately
