# README + template finishing pass

**Type**: AFK

**Status:** ✅ Done (verified 2026-07-07)

## Parent

[PLAN.md](../PLAN.md) — decisions 1, 12; the whole log informs the README.

## What to build

The new-clone experience, documented and verified end-to-end.

- `README.md` written for future-you cloning this for a new project:
  the 60-second quickstart (`./dev/install && ./dev/run`), the full script
  roster with one-liners, the secrets convention
  (`~/.config/<project-dir-name>/env`, chmod 600) and how to set it up, the
  security model in brief (link to HARDENING.md/PLAN.md for rationale), how
  to add a package (`./dev/shell --net`), how to rename/adapt the template
  for a new project, and when/how to enable the prod proxy sidecar.
- A finishing sweep across all scripts for consistency: shared output style
  everywhere, uniform flag handling (`--net`, `--all`), `.gitignore`
  covering `node_modules`/`dist`, and removal of anything stale left from
  earlier slices.
- Verify the whole template as a user would: copy the repo to a fresh
  directory with a different name and walk every documented command.

## Acceptance criteria

- [x] A copy of the repo under a new directory name passes the full
      quickstart exactly as the README states it, with no undocumented steps.
- [x] Every script in `dev/` appears in the README roster, and every command
      shown in the README exists and runs.
- [x] The per-project resources (cache volume name, env-file path, container
      labels) all follow the NEW directory name in the copied repo,
      confirming nothing is hardcoded to "node-orb".
- [x] `git status` in a fresh clone after running install/test/run shows no
      untracked junk (gitignore is complete).

## Blocked by

- #002
- #003
- #004
- #005
