# The node-orb manifesto

**A Node + TypeScript template you can trust the day you clone it.** Not a
checklist to work through later — the supply-chain defenses are wired in from
the first `./dev/install`. This document is the *why*; the code is the *how*.

## What we're defending against

Shai-Hulud-class npm worms. They strike in two moments:

- **Install time** — a malicious `postinstall` harvests host credentials (the
  gh token in `~/.config/gh/hosts.yml` is the prize) and self-propagates.
- **Runtime** — a require-time payload exfiltrates from the process that holds
  your secrets.

Every goal below traces back to shrinking one of those two blast radii.

## What we believe

**1. The host stays clean.** No node, npm, or npx ever runs on your Mac. Every
install, test, and run happens in a throwaway container. There is nothing on
the host for an install script to find.

**2. Containers see the repo, never your home.** The repo directory is the only
bind mount, ever — never `$HOME`. Containers run as non-root with `HOME=/tmp`
and zero host env. Your gh token and ssh keys are structurally unreachable, not
merely unmentioned.

**3. Lifecycle scripts don't run.** `ignore-scripts=true` is committed in
`.npmrc`, so it holds everywhere — host-side and in-image. A dep that genuinely
needs a build gets a deliberate, visible `npm rebuild <pkg>`. Silence is the
default; noise is opt-in.

**4. Every version is exact and aged.** No carets. `save-exact=true` pins what
you resolve, and `./dev/update` refuses anything published in the last 7 days —
worm releases get yanked within hours. Updates are a conscious act with a
reviewable diff, never a background drift.

**5. Secrets live outside the repo.** They sit at
`~/.config/<project>/env` (chmod 600), because a bind-mounted repo is readable
by any compromised package. The app needs its tokens in memory — we accept
that — so we cap the damage with egress control instead.

**6. The secret-holder has no way out.** In production the app sits on an
`internal: true` network with no gateway. Its only door to the internet is a
tinyproxy sidecar with a domain allowlist. Inbound traffic reaches it through a
secrets-free socat forwarder; the app itself keeps no route out. An in-process
attacker can still abuse an allowlisted domain — this is a bar-raise, not a
wall, and we say so plainly.

**7. Everything ships pinned and minimal.** The base image is digest-pinned in
both build stages; the proxy and forwarder images too. The runtime image
carries compiled JS and prod deps only — no `typescript`, no `src/`, no `npx`
sitting next to the secrets. Bumps are one-line diffs we own.

**8. Defaults are safe; exposure is deliberate.** The published port binds
`127.0.0.1` so a peer on café WiFi can't reach the process holding your tokens.
`test` and `shell` run `--network none`. Opening any of these up
(`BIND_ADDR=0.0.0.0`, `--net`) is always an explicit, typed-out choice.

## The standing rules

- Install containers get the repo dir — **never `$HOME`**, never host env.
- **Never run npm inside an OrbStack Linux machine** — machines auto-share the
  macOS home, exposing the gh token. Throwaway docker containers only.

## Where the work still lives

The proxy allowlist ships **deny-all** — every example entry in `proxy/filter`
is commented out, so nothing gets out until you opt a domain in. Each domain
you uncomment is an accepted exfil channel for an in-process attacker (a
Discord webhook is a ready-made one), so allowlist exactly what *your* app
calls and nothing more. Global `fetch` honors the proxy for free; SDKs that
build their own undici transport want `EnvHttpProxyAgent`, and websocket
clients need an explicit proxy agent. Re-run `./proxy/verify-egress.sh`
whenever you touch the pinned proxy or the filter.

The dev loop is the accepted gap in rule 6: `./dev/run` needs the network
(it's a live-reload server) and loads the secrets file, with no proxy in
between — the exact combination production caps. So keep the secrets file
minimal (or absent) until the app genuinely needs a token locally, and
exercise secret-holding paths through `docker compose up` instead.
