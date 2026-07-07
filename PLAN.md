# node-orb — decision log (2026-07-06)

> A clean, fun, hardened Node 24 dev-environment **template repo** for
> Docker/OrbStack. Vision and threat model: [HARDENING.md](HARDENING.md)
> (Shai-Hulud-class npm worms). Decisions reached in a /grill-me session;
> rationale inline.

## Decisions

1. **Shape: template repo.** Cloned/copied when starting a new Node project;
   each project owns its copy and may drift. Not a shared CLI, not a
   devcontainer. HARDENING.md's rules arrive pre-wired in every copy.

2. **Interface: plain shell scripts in `dev/`.** Zero host dependencies
   (no just/make/node on the Mac). Roster:
   `dev/install`, `dev/run`, `dev/test`, `dev/shell`, `dev/update`,
   `dev/bump-node`, `dev/clean`.

3. **Lifecycle: fully ephemeral.** Every command is `docker run --rm`;
   nothing persists except the repo bind-mount and the npm cache volume.
   Long-running servers run **foreground** in the terminal (`dev/run` holds
   the tty like `npm run dev` would natively; Ctrl-C stops and removes).
   No detached/compose mode in dev.

4. **Dev egress: tiered by command.** No proxy infra in dev.
   - `install`, `update`, `run` — network on (registry / app APIs).
   - `test`, `shell` — `--network none` by default; `--net` flag opts in.
   Blocks the common exfil path (require-time payloads during tests) without
   per-run proxy plumbing. Install-time is already covered by ignore-scripts.

5. **Base image: `node:24-slim`, digest-pinned** (glibc — fewer native-module
   surprises than Alpine). `dev/bump-node` fetches the current digest and
   rewrites the pin, so keeping it fresh is one command. Dev and prod stages
   share the same pin.

6. **Git stays on the host.** Editor, git, gh all run on the Mac; containers
   are purely the node/npm runtime with only the repo dir mounted. The
   never-mount-`$HOME` invariant stays absolute.

7. **Per-project npm cache volume** (named from the project dir), mounted at
   the container npm cache dir. Fast repeat installs; lockfile integrity
   hashes guard against cache tampering. `node_modules` is a plain bind-mount
   in the repo dir.

8. **Secrets: `~/.config/<project-dir-name>/env` (chmod 600), passed via
   `--env-file` to `dev/run` ONLY.** `install`/`test`/`shell` get zero env
   (`HOME=/tmp`, nothing else). Same rationale as HARDENING.md §9: anything
   in the bind-mounted repo dir is readable by compromised packages.

9. **Cooldown is tooling, not discipline: `dev/update` regenerates the
   lockfile with `npm --before=$(now − 7 days)`** so versions younger than
   7 days structurally cannot be resolved. `dev/install` stays lockfile-only
   (`npm ci`). Fresh package adds happen manually in `dev/shell --net`
   (deliberately not gated — accepted).

10. **Scope: dev + prod skeleton.** Template ships the production half too:
    multi-stage Dockerfile (build stage `tsc`; runtime stage
    `npm ci --omit=dev --ignore-scripts`, runs `node dist/index.js`),
    hardened `docker-compose.yml` (`read_only`, `tmpfs: [/tmp]`,
    `cap_drop: [ALL]`, `no-new-privileges`, `pids_limit`, `mem_limit`), and a
    **commented-out tinyproxy egress-sidecar block** enabled per project when
    it has secrets worth guarding.

11. **TS-first skeleton, runnable on clone:** `package.json` (exact pins +
    committed `.npmrc` with `ignore-scripts=true`, `save-exact=true`),
    `tsconfig`, `src/index.ts`, one `node:test` test.
    Dev-time execution uses **Node 24 native type stripping** —
    `dev/run` = `node --watch src/index.ts` — so there is no tsx/esbuild in
    the dev loop at all; `tsc` exists only in the prod build stage.
    First-run: `./dev/install && ./dev/run` just works.

12. **Fun = colorful, chatty output.** Scripts narrate with color + emoji and
    state their security posture as they run
    ("📦 installing (network: on, scripts: ignored)… ✅ 42 packages, cache warm").
    No separate help/doctor commands (considered, declined).

13. **`dev/clean` wipes `node_modules` + stray project containers.**
    `--all` additionally drops the project's npm cache volume and re-pulls
    the base image. Everyday clean is instant; factory reset is one flag.

## Implementation notes

- Dev containers run as the non-root `node` user with `HOME=/tmp`.
- The digest pin lives in one place both dev scripts and Dockerfile read
  (e.g. `dev/.node-image`), so `dev/bump-node` has a single write target.
- `dev/run` port publishing: pass-through args (`./dev/run -p 3000:3000`) or
  a small per-project config line — decide at implementation.

## Ledger

Resolved: all 13 above. Parked: none.
