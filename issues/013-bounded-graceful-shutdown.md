# Bounded graceful shutdown on SIGTERM

**Type**: AFK

**Status:** ✅ Complete

## Parent

REVIEW.md (since removed) — Addendum A1.

## What to build

The SIGTERM handler calls `server.close()` and waits for every existing
connection — including idle HTTP/1.1 keep-alive sockets — to close naturally.
A client holding a keep-alive open blocks the callback until compose's
`stop_grace_period` (default 10s) expires and SIGKILLs the process, dropping
in-flight responses anyway and defeating the "finish in-flight and exit" goal.

Bound the wait: close idle connections immediately on SIGTERM
(`server.closeIdleConnections()`, Node 18+), and force-close the rest
(`closeAllConnections()`) after a timeout comfortably inside the grace period,
then exit cleanly.

## Acceptance criteria

- [ ] With an idle keep-alive connection held open, SIGTERM makes the process
      exit 0 within the bound (well under 10s), not via SIGKILL.
- [ ] An in-flight request at SIGTERM time still receives its response before
      the socket closes.
- [ ] Existing tests still pass.

## Blocked by

None - can start immediately
