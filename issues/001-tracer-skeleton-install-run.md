# Tracer bullet: TS skeleton + dev/install + dev/run

**Type**: AFK

**Status:** ✅ Done (verified 2026-07-06)

## Parent

[PLAN.md](../PLAN.md) — decisions 2, 3, 5, 6, 7, 8, 11, 12 and the implementation notes.

## What to build

The clone-and-go moment: a fresh copy of the template runs
`./dev/install && ./dev/run` and a hello-world TypeScript app starts,
reloading on edit — with every hardening rule already in force.

End-to-end this slice includes:

- A minimal TS-first project skeleton: `package.json` (exact pins),
  committed `.npmrc` (`ignore-scripts=true`, `save-exact=true`), `tsconfig`,
  `src/index.ts` (hello world that stays alive, e.g. a tiny HTTP server, so
  `run`'s foreground/Ctrl-C behavior is demoable), and a lockfile.
- A single-source digest pin for `node:24-slim` that both dev scripts and the
  (future) Dockerfile read — e.g. a `dev/.node-image` file. Seed it with the
  current digest.
- A small shared helper the scripts source for the colorful, chatty output
  style (color + emoji, narrates security posture: network on/off, scripts
  ignored, env none). All later scripts reuse it.
- `dev/install`: ephemeral `docker run --rm`, repo dir as the only bind
  mount, per-project npm cache volume (named from the project dir) mounted at
  the npm cache dir, zero env (`HOME=/tmp`), non-root `node` user, network
  on, runs `npm ci`.
- `dev/run`: ephemeral foreground container holding the tty
  (`docker run --rm -it`), network on, `--env-file ~/.config/<project-dir-name>/env`
  (tolerate absence with a friendly note), runs `node --watch src/index.ts`
  via Node 24 native type stripping — no tsx/esbuild. Extra args pass through
  to `docker run` (e.g. `./dev/run -p 3000:3000`).

## Acceptance criteria

- [x] From a fresh clone with no host node/npm, `./dev/install` completes and
      produces `node_modules/` in the repo dir.
- [x] Second `./dev/install` after `rm -rf node_modules` is markedly faster
      (cache volume hit) and the volume name derives from the project dir.
- [x] `docker inspect` during install shows: only the repo dir bind-mounted,
      `HOME=/tmp`, non-root user, no other env passed.
- [x] Install output confirms scripts were not executed
      (`ignore-scripts` honored — verifiable by adding a canary postinstall
      to a test fixture or checking npm's script skip behavior).
- [x] `./dev/run` starts hello world in the foreground; editing
      `src/index.ts` triggers a reload; Ctrl-C exits and
      `docker ps -a` shows no leftover container.
- [x] With `~/.config/<project>/env` present, a variable from it is visible
      to the app under `run` and NOT visible inside `install`.
- [x] The image reference used by both scripts comes from the single pin
      file and includes a `@sha256:` digest.
- [x] Script output is colored, uses emoji, and states network/env/scripts
      posture for each command.

## Blocked by

None - can start immediately
