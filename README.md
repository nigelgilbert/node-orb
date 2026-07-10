# node-orb

A clean, fun, **hardened** Node 24 + TypeScript dev-environment template for
Docker/OrbStack on macOS. Copy it, rename it, and every supply-chain rule from
[MANIFESTO.md](MANIFESTO.md) is already in force — no host node/npm needed, ever.

## 60-second quickstart

```sh
./dev/install   # npm ci in a throwaway container
./dev/run       # hello world on :3000, reloads on edit, Ctrl-C stops
```

That's it. Try `curl localhost:3000`, edit `src/index.ts`, watch it reload.

## The dev/ roster

| command | what it does | network | env |
|---|---|---|---|
| `./dev/install` | `npm ci` from the lockfile | on | none |
| `./dev/run [docker args]` | foreground `node --watch src/index.ts` on `localhost:3000` (`HOST_PORT=8080 ./dev/run` to move it); extra args pass to `docker run` | on | `~/.config/<project>/env` |
| `./dev/test [--net]` | `npm test` (node:test, native TS) | **off** (`--net` opts in) | none |
| `./dev/shell [--net]` | interactive bash in the container | **off** (`--net` opts in) | none |
| `./dev/update` | regenerate lockfile with a **7-day cooldown** (`npm --before`) | on | none |
| `./dev/bump-node` | refresh the base-image digest pin in `.env` | on | none |
| `./dev/clean [--all]` | rm `node_modules` + stray containers; `--all` also drops the npm cache volume and re-pulls the base image | — | none |

(`dev/_lib.sh` is the shared helper the commands source — not a command.)

Every command is `docker run --rm` — fully ephemeral. The only things that
persist are the repo directory (the **only** bind mount, ever) and a
per-project npm cache volume named `<project-dir>-npm-cache`.

## Security model, in brief

Threat model: Shai-Hulud-class npm worms — malicious `postinstall` at install
time, require-time exfil at runtime. Full rationale: [MANIFESTO.md](MANIFESTO.md).

- **Containers never see your host env or `$HOME`.** Every container runs as
  the non-root `node` user with `HOME=/tmp` and zero env passed in. Your gh
  token, ssh keys, etc. are structurally unreachable.
- **Lifecycle scripts never run.** The committed [.npmrc](.npmrc) sets
  `ignore-scripts=true` + `save-exact=true` for every install, everywhere.
- **`test` and `shell` default to `--network none`** — require-time payloads
  have no exfil path while tests exercise your dependency tree. `--net` opts in.
- **7-day cooldown on updates.** `./dev/update` resolves nothing published in
  the last week; worm releases get yanked within hours/days.
- **One digest pin.** The `NODE_IMAGE=` line in [.env](.env) pins
  `node:24-slim@sha256:…` for the dev scripts *and* the prod Dockerfile
  (compose auto-loads `.env` and passes it as a build arg). `./dev/bump-node`
  is the single writer; bumps are a one-line reviewable diff.

## Secrets

Runtime secrets live **outside the repo** (a bind-mounted repo dir is readable
by any compromised package) at `~/.config/<project>/env`, where `<project>`
is your project directory name lowercased and stripped to `a-z0-9_-` (the
same normalization compose applies, so dev scripts and compose read the same
file). `./dev/run` prints the exact path it looks for.

```sh
mkdir -p ~/.config/node-orb           # ← your sanitized project dir name
printf 'MY_TOKEN=…\n' > ~/.config/node-orb/env
chmod 600 ~/.config/node-orb/env
```

The `chmod 600` is enforced, not just suggested — but only on the `./dev/run`
path: it refuses a secrets file that is group/world-accessible or owned by
someone else. `docker compose up` reads the same file but runs no such check —
it will load a mis-permissioned file without complaint — so keep it `0600`
yourself. The `./dev/run` guard only covers its own path.

One dialect note: write plain `KEY=value` lines — no quotes (docker run keeps
them literally), no bare `KEY` lines (`./dev/run` rejects those; docker would
import the value from your host env, which these containers must never see).

**Known asymmetry with production:** `./dev/run` is a live-reload server, so
it has full, unproxied network access *and* loads this secrets file — the
exact combination production caps with the tinyproxy allowlist. A compromised
dependency loaded at require time in dev therefore has both your tokens and an
open path out. Keep secrets out of `~/.config/<project>/env` until the app
truly needs them locally, and prefer `docker compose up` (egress-capped) when
exercising secret-holding code paths.

Only `./dev/run` and `docker compose up` read it (`--env-file` / `env_file`).
`install`/`test`/`shell` get nothing. Missing file is fine — you'll get a
friendly note instead of an error.

## Adding a package

```sh
./dev/shell --net
npm install <pkg>      # exact pin + no scripts, via the committed .npmrc
exit
```

Then commit `package.json` + `package-lock.json`. (Fresh adds deliberately skip
the 7-day cooldown: adding a package is a conscious, manual act in an
interactive shell — the cooldown exists to gate the *automated* bulk update
path in `./dev/update`.)

## Production

```sh
docker compose build   # multi-stage: tsc in build stage; runtime = prod deps + dist/ only
docker compose up      # read_only rootfs, cap_drop ALL, no-new-privileges, pids/mem limits
```

The runtime image contains compiled JS and production deps only — no
`typescript`, no `src/`, no `npx` in CMD. Publish port defaults to 3000;
override with `HOST_PORT=8080 docker compose up`.

### Egress-allowlist sidecar (optional)

When the app holds secrets worth guarding, uncomment the `proxy` service and
`networks:` block in [docker-compose.yml](docker-compose.yml) plus the
`networks`/`environment` lines on `app`. The app then sits on an
`internal: true` network with **no direct route out** — the tinyproxy
allowlist in [proxy/filter](proxy/filter) is the only door. (Its published
port survives via the un-masqueraded `ingress` network: inbound keeps
working, outbound doesn't — `internal: true` alone would silently stop
publishing the port.) The filter ships **deny-all** (every example entry
commented out); uncomment/add the domains your app actually calls — it
matches the *full* hostname, so list `discord.com` and `*.discord.com`
separately — and keep `NODE_USE_ENV_PROXY=1` so Node's `fetch` honors the
proxy (SDKs using undici get it too).

## Adapting the template for a new project

1. Copy the directory: `cp -R node-orb my-app && cd my-app` (delete `.git` if
   you cloned, then `git init`).
2. Rename in `package.json` (`name`) and `src/index.ts` (the greeting).
3. Everything per-project — npm cache volume, container labels, secrets path
   `~/.config/my-app/env` — derives from the directory name automatically.
4. `./dev/install && ./dev/run`. Done.

Optional upkeep: `./dev/bump-node` now and then (review the one-line diff),
`./dev/update` before releases.
