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
| 009 | 2 | ✅ verified | BIND_ADDR (default 127.0.0.1) host-side prefix in dev/run + compose; HARDENING.md decision 10 documents opt-out BIND_ADDR=0.0.0.0 |
| 012 | 2 | ✅ verified | volume-inspect fast path in ensure_cache_volume; hot path 46ms/0 containers; clean→install E2E OK |
| 008 | 3 | ✅ verified | parse_net_args matches all spellings, value forms rejected; --reject-net mode for dev/run (forwards pass_args); banner from parsed state; probes verified both postures |
| 010 | 3 | ✅ verified | SHIPPED: internal net (app+proxy) / egress / ingress split; tinyproxy 1.11.3 Listen+Allow locked to app IP; fnmatch = parsed-host-only (userinfo NOT a bypass); all denial tests 403; DEVIATION: socat forwarder sidecar publishes 127.0.0.1:3000→app:3000 because internal:true can't publish ports (Docker Desktop masquerade-off leaks); proxy/verify-egress.sh added |
| 013 | 3 | ✅ verified | 5s SHUTDOWN_TIMEOUT_MS backstop, closeIdleConnections on SIGTERM; idle keep-alive exits 0 in ~175ms; in-flight gets response; 9/9 tests |
| 014 | 3 | ✅ verified | cooldown fingerprints (ENOVERSIONS/ETARGET) grepped from captured npm output; real error always echoed; generic msg otherwise; verified both branches E2E, lockfile restored, exit 1 |
| 015 | 4 | ✅ verified | dev/run validator: reject unquoted value + whitespace+# (ambiguity named); accept indented KEY=value (both parsers trim — empirically confirmed); a#b still allowed; plain files pass |

## Integration checks

- Tranche 1: ✅ PASS — dev/test 7/7, compose config valid, run smoke OK (curl 3000), _lib.sh + PORT story cohere. Note: container-side 3000 literal in compose/dev-run is comment-coupled to DEFAULT_PORT by design.
- Tranche 2: ✅ PASS — dev/test 7/7, compose config shows host_ip 127.0.0.1, run smoke OK, _lib.sh fast path + pin guard cohere, HARDENING decision 10 matches actual behavior.
- Tranche 3: ✅ PASS — dev/test 9/9 (banner OFF), compose config topology correct, run smoke + --net rejection OK, compose-up smoke + verify-egress.sh ALL CHECKS PASSED, posture story coherent across 008/009/010. Minor doc gap (DEFAULT_PORT comment missing forwarder call site) fixed by corrective agent.
- Tranche 4: ✅ PASS — dev/test 9/9, compose config valid, run smoke OK, inline-comment env file rejected with clear die message, dev/run + _lib.sh coherence confirmed.
- Final VERIFY.md run: ✅ ALL PASS (independent agent, Docker 29.2.1 / Compose v5.0.2 / Node v24.13.0). Every acceptance box for 007–015 passed; zero failures. Notes: 010 verified on the SHIP path (human decision 2026-07-09); 014 cooldown branch exercised via ETARGET simulation (genuine cooldown is time-sensitive); one 008 rc=125 in an intermediate loop was a word-splitting harness artifact, not a code defect. Repo left clean (no modified tracked files, no leftover containers/networks, .env md5 intact).
