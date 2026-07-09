# PORT correctness end-to-end: strict parsing, test isolation, single source of truth

**Type**: AFK

**Status:** 🔲 Not started

## Parent

[REVIEW.md](../REVIEW.md) — Finding 7, Addendum A4, and the altitude note.

## What to build

Three related PORT problems, one slice:

- **Strict parsing.** The port resolver accepts hex, octal, and scientific
  notation (`PORT=0x50` silently binds 80). Restrict acceptance to plain
  decimal digits so garbage fails loudly, per the resolver's own stated
  contract.
- **Test isolation.** The "defaults to 3000 when PORT is unset" test never
  deletes `process.env.PORT`, so an exported `PORT` in the host shell or CI
  flips the result. Clear it at the top of the test, as the sibling greeting
  test already does for `GREETING`.
- **Single source of truth.** The port number is pinned independently in
  compose, the dev run script, and the app's default, with no declared
  authority — changing it means editing all three, and a missed one fails
  silently. Name one authority (a comment trail pointing at it is enough for a
  template) so a port move is a one-place edit or at least a guided one.

## Acceptance criteria

- [ ] `PORT=0x50`, `PORT=1e3`, and `PORT=0o17` each make the app exit
      non-zero with a clear message instead of binding.
- [ ] Tests cover the rejection cases above and pass.
- [ ] The full test suite passes with `PORT=8080` exported in the invoking
      shell.
- [ ] Each place the port is pinned either derives from, or carries a comment
      naming, the single declared source of truth.

## Blocked by

None - can start immediately
