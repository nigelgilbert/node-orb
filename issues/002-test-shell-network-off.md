# dev/test + dev/shell with network-off default

**Type**: AFK

**Status:** ✅ Done (verified 2026-07-07)

## Parent

[PLAN.md](../PLAN.md) — decisions 2, 4, 11, 12.

## What to build

The network-restricted commands, plus the skeleton's first test.

- One `node:test` test for the hello-world app (run with Node 24 native type
  stripping — no build step).
- `dev/test`: ephemeral container, `--network none` by default, `--net` flag
  opts in to network; zero env (`HOME=/tmp`), non-root, repo-only mount,
  runs the package's test command.
- `dev/shell`: same isolation defaults (`--network none`, no env), drops into
  an interactive shell in the container; `--net` opts in (this is the
  documented path for adding new packages: `./dev/shell --net` then
  `npm install <pkg>` — exact pins and ignore-scripts come from the committed
  `.npmrc`).
- Both narrate their posture via the shared output helper, making the
  network-off default visible ("🧪 testing (network: OFF)…").

## Acceptance criteria

- [x] `./dev/test` passes on the skeleton and a network probe inside the test
      environment (e.g. fetch to example.com) fails under the default mode.
- [x] `./dev/test --net` makes the same probe succeed.
- [x] `./dev/shell` gives an interactive prompt as the non-root user with
      `HOME=/tmp`; `env` shows no host variables; exiting leaves no container
      behind.
- [x] `npm install <some-pkg>` inside `./dev/shell --net` records an exact
      version (no caret) in package.json and runs no lifecycle scripts.
- [x] Both commands state their network posture in colored output.

## Blocked by

- #001
