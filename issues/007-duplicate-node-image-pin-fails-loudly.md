# Fail loudly on duplicate NODE_IMAGE pin

**Type**: AFK

**Status:** ✅ Complete

## Parent

REVIEW.md (since removed) — Finding 1.

## What to build

The dev scripts and `docker compose` disagree about which line wins when `.env`
contains more than one `NODE_IMAGE=` entry: the shell helper takes the first,
compose interpolates the last. A duplicated pin therefore silently runs dev
against one digest and prod against another — defeating the digest pin, which
is the template's headline supply-chain control.

Make the pin reader refuse to proceed unless exactly one `NODE_IMAGE=` line
exists in the pin file, dying with a message that names the file and the count.
Since every dev script sources the shared helper, one guard covers `install`,
`update`, `test`, `shell`, `run`, and `bump-node` alike. (Compose itself can't
be guarded the same way, but a dev-side hard failure surfaces the duplicate
before anything ships.)

## Acceptance criteria

- [ ] With a `.env` containing two `NODE_IMAGE=` lines, every `dev/*` script
      exits non-zero before doing any work, and the error names `NODE_IMAGE`
      and the pin file.
- [ ] With zero `NODE_IMAGE=` lines, the scripts also fail loudly (no empty
      image ref passed to docker).
- [ ] With exactly one line, all dev scripts behave as before (`./dev/test`
      passes).

## Blocked by

None - can start immediately
