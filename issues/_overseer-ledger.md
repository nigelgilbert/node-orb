# Overseer ledger — hardening issues 007–015

**010 HITL decision (2026-07-09): SHIP the egress implementation** (proxy sidecar + network split + proxy lockdown + empirical bypass tests).

## Tranche plan (no two agents write the same file within a tranche)

| Tranche | Issues | Expected files |
|---|---|---|
| 1 | 007, 011 | 007: dev/_lib.sh · 011: app server/tests, port comment trail (compose/dev-run comments only) |
| 2 | 009, 012 | 009: dev/run ports, compose ports, HARDENING.md · 012: dev/_lib.sh (ensure_cache_volume) |
| 3 | 008, 010, 013, 014 | 008: dev/_lib.sh (parse_net_args), dev/run, dev/test, dev/shell · 010: compose, tinyproxy conf, HARDENING.md · 013: app server · 014: dev/update |
| 4 | 015 | dev/run (env-file validator) |

Note: 011 (tranche 1) may add comments to dev/run and compose; 009/008/015 edit those later — sequential, OK. 007 and 012 both touch dev/_lib.sh but in different tranches.

## Status

| Issue | Tranche | Status | Notes |
|---|---|---|---|
| 007 | 1 | ✅ verified | Guard in dev/_lib.sh pin reader; ./dev/test 7/7; bump-node sed keeps exactly one line (safe) |
| 011 | 1 | ✅ verified | DEFAULT_PORT in src/index.ts is authority; strict /^\d+$/; test isolation; comment trail in compose + dev/run; suite 7/7 incl. PORT=8080 exported |
| 009 | 2 | pending | |
| 012 | 2 | pending | |
| 008 | 3 | pending | |
| 010 | 3 | pending | SHIP decision |
| 013 | 3 | pending | |
| 014 | 3 | pending | |
| 015 | 4 | pending | |

## Integration checks

- Tranche 1: ✅ PASS — dev/test 7/7, compose config valid, run smoke OK (curl 3000), _lib.sh + PORT story cohere. Note: container-side 3000 literal in compose/dev-run is comment-coupled to DEFAULT_PORT by design.
- Tranche 2: pending
- Tranche 3: pending
- Tranche 4: pending
- Final VERIFY.md run: pending
