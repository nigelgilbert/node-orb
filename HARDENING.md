# Supply-chain hardening — decision log (2026-07-05)

> Threat model: Shai-Hulud-class npm worms — malicious `postinstall` at install
> time (credential harvest + self-propagation), require-time payloads at
> runtime (exfil from the process holding secrets). Decisions reached in a
> /grill-me session; rationale inline so future-us doesn't re-litigate.

## Verified facts (grounding)

- Only two deps have install scripts: `esbuild` (works without it when the
  platform package is present) and `fsevents` (macOS-only, skipped in Linux).
  `--ignore-scripts` is therefore free for this tree.
- No node/npm/npx/pnpm/yarn/pm2 exists on the host Mac; `node_modules` holds
  only `@esbuild/linux-arm64` — all installs already happen in containers.
- The only harvestable host credential is `~/.config/gh/hosts.yml` (gh CLI
  token). Unreachable as long as install containers never mount `$HOME`.
- No runtime code invokes `scripts/refresh-oui.sh`; `data/oui.tsv` is
  generated out-of-band and only read at startup → read-only rootfs is viable.
  (Today's image doesn't even COPY `data/` — in-container vendor lookups run
  on the fallback. Bake `oui.tsv` into the image while we're in there.)

## Decisions

1. **Scope: all three surfaces** — image build, container runtime, dev
   workflow. The worm's primary target is the machine running `npm install`,
   not the deploy container.

2. **Egress: proxy sidecar.** App container on an `internal: true` compose
   network; a tinyproxy sidecar with a domain allowlist is the only route out:
   `discord.com`, `gateway.discord.gg`, `api.anthropic.com`, plus the router
   IP (with `internal: true` even LAN traffic goes via the proxy; curl in
   scripts honors `https_proxy` for free).
   *Accepted caveat:* an in-process attacker can still exfil via a Discord
   webhook on the allowlisted `discord.com` — this blocks the channels real
   Shai-Hulud payloads used (webhook.site, fresh GitHub repos, C2 domains),
   it is a bar-raise, not a wall.

3. **Commit `ignore-scripts=true` in repo `.npmrc`** (plus `save-exact=true`).
   Applies to every install, host-side or in-image. A future dep that
   genuinely needs scripts gets a deliberate `npm rebuild <pkg>`.

4. **Exact version pins + 7-day cooldown.** Drop carets. Updates are
   deliberate: bump only to versions published ≥7 days ago (worm releases get
   yanked within hours/days). `npm ci` + lockfile already covers the image;
   exact pins extend protection to lockfile-regeneration paths.

5. **Multi-stage image, ship compiled JS.** Build stage runs `tsc`; runtime
   stage gets `npm ci --omit=dev --ignore-scripts` (3 prod deps), runs
   `node dist/index.js`. No `npx` in CMD (registry-reach at runtime), no
   tsx/esbuild/typescript sitting next to the secrets.

6. **Full compose hardening, both services:** `read_only: true`,
   `tmpfs: [/tmp]`, `cap_drop: [ALL]`, `no-new-privileges:true`,
   `pids_limit`, `mem_limit`. `./config` stays the sole rw mount.

7. **Pin base image by digest** (`node:22-alpine@sha256:…`, both stages).
   Base updates become a reviewable git diff; we own bumping for Node
   security patches.

8. **Deploy target: this Mac, via OrbStack.** Same compose file for rehearsal
   and prod.

9. **Secrets: keep `.env` + `env_file`, but move it outside the repo** to
   `~/.config/home-manager/env` (chmod 600). Rationale: dev install/test
   containers bind-mount the repo dir; secrets in-repo would be readable by
   any compromised package running there. In-process env exposure is accepted
   — the app needs the tokens; egress control limits blast radius.

## Standing rules (dev hygiene)

- Install containers get the repo dir mounted — **never `$HOME`**.
- **Never run npm installs in an OrbStack Linux machine** (machines auto-share
  the macOS home dir, exposing the gh token); throwaway docker containers only.
- Install containers get no env passed in (`-e HOME=/tmp`, nothing else).

## Known work items (implementation, not decisions)

- Proxy wiring: undici `EnvHttpProxyAgent` as global dispatcher (covers
  Anthropic SDK + discord.js REST); a proxy agent for the Discord **gateway
  websocket** (discord.js ws options — the fiddly one); scripts' curl needs
  only `https_proxy` env.
- tinyproxy allowlist config + sidecar healthcheck.
- Bake `data/oui.tsv` into the image (build-stage `refresh-oui.sh` or COPY).
- `docker-compose.yml`: `env_file` → `${HOME}/.config/home-manager/env`.
