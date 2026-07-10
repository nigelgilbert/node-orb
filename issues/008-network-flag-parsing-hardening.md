# Harden network-flag parsing and make the posture banner truthful

**Type**: AFK

**Status:** ✅ Complete

## Parent

REVIEW.md (since removed) — Findings 2 and 6.

## What to build

The network-off security floor is bypassable: `parse_net_args` consumes only
the exact token `--net`, so `--net=host`, `--network`, and `--network=host`
fall through into the pass-through args, which docker emits after
`--network none` — last-flag-wins gives the container host networking while
the posture banner still prints `network: OFF`. Separately, `dev/run` forwards
`"$@"` to docker without any parsing at all, so a stray `--net` swallows the
next token and produces a confusing docker error.

Close both holes end-to-end:

- Match every spelling — `--net`, `--net=*`, `--network`, `--network=*`
  (including the following token for the space-separated forms) — and either
  consume them into the sanctioned opt-in or reject them with a clear error.
  Passing raw network flags through must become impossible.
- Derive the posture banner from the final parsed state, so what it prints is
  what docker actually gets.
- `dev/run` (network-on by design) adopts the same parsing, rejecting
  network flags outright with a message explaining that run always has network.

## Acceptance criteria

- [ ] `./dev/test --net=host`, `./dev/test --network host`, and
      `./dev/test --network=host` each either run with network OFF or exit
      with a clear rejection — a network probe inside the container confirms
      no host networking sneaks through.
- [ ] The banner never prints `network: OFF` for an invocation whose container
      can reach the network (spot-check with an in-container probe under
      `--net`).
- [ ] `./dev/run --net` exits with a clean, self-explanatory error instead of
      a docker "unknown network" / missing-image failure.
- [ ] `./dev/shell --net` (the documented package-install path) still works.

## Blocked by

None - can start immediately
