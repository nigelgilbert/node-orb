# Egress control: ship the network split + proxy hardening, or drop the claim

**Type**: HITL (ship-vs-drop is a design decision, and tinyproxy's filter
semantics need live verification before the allowlist can be trusted)

**Status:** 🔲 Not started

## Parent

[REVIEW.md](../REVIEW.md) — the egress half of Finding 4, and Finding 5.

## What to build

HARDENING.md §2 (egress allowlist) and §6 (network isolation) are currently
prose, not controls: the proxy sidecar, the `internal`/`ingress` network split,
and the app's `networks:` membership are all commented out in compose. Even
uncommenting the sidecar alone leaves the app with direct egress, bypassing the
allowlist entirely. And the proxy config as written is an open relay
(`Listen 0.0.0.0` + `Allow 0.0.0.0/0`).

Decide with a human: either implement the design for real, or delete the §2/§6
claims from HARDENING.md so the doc stops overstating the posture. If shipping:

- Enable the sidecar and the network split so the app's only egress path is
  through the proxy.
- Restrict the proxy's `Allow` to the app service alias only.
- Verify — against the actual tinyproxy version in use — what
  `FilterType fnmatch` matches (parsed host vs. full URL string), and add
  denial tests for the userinfo trick (`allowed.example@evil.com`), the
  subdomain-suffix trick (`allowed.example.evil.com`), and the CONNECT form
  (`evil.com:443`). The review flagged the userinfo bypass as unverified;
  settle it empirically.

## Acceptance criteria

- [ ] Either: HARDENING.md no longer claims egress allowlisting / network
      isolation as controls; or all of the below.
- [ ] From inside the app container, a direct fetch to a non-allowlisted host
      fails, and a fetch to an allowlisted host via the proxy succeeds.
- [ ] A container that is not the app service cannot relay through the proxy.
- [ ] Denial tests pass for the userinfo, subdomain-suffix, and CONNECT bypass
      forms, run against the deployed tinyproxy version.

## Blocked by

None - can start immediately
