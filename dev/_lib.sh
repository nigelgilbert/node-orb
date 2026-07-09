# dev/_lib.sh — shared plumbing for all dev/* scripts. Source, don't run.
#
# Provides: $REPO_DIR $PROJECT $IMAGE $CACHE_VOLUME $ENV_FILE $LABEL
# and the chatty output helpers (say / ok / warn / die / posture).

set -euo pipefail

DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_DIR="$(dirname "$DEV_DIR")"

# Everything per-project derives from the directory name: cache volume,
# container labels, env-file path. Rename the dir and you get a fresh set.
# Sanitization mirrors compose's project-name normalization (lowercase, strip
# to [a-z0-9_-], trim leading _/-) so the secrets path here and the one
# docker-compose.yml interpolates from ${COMPOSE_PROJECT_NAME} stay identical.
PROJECT="$(basename "$REPO_DIR" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9_-]//g' -e 's/^[_-]*//')"
[ -n "$PROJECT" ] || { printf '💥 directory name %s sanitizes to nothing — rename it to something with a-z/0-9\n' "$(basename "$REPO_DIR")" >&2; exit 1; }

# Single source of truth for the base image: the NODE_IMAGE line in the
# committed root .env (no secrets there — those live in ~/.config/<project>/env).
# Dev scripts parse it here; docker compose auto-loads .env and feeds it to the
# Dockerfile as a build arg. dev/bump-node rewrites this one line.
PIN_FILE="$REPO_DIR/.env"
# Compose interpolates the LAST duplicate key; this helper would take the first.
# A duplicated pin would silently split dev and prod across two digests, so
# require exactly one NODE_IMAGE= line — fail loudly on 0 or >1.
PIN_COUNT="$(grep -c '^NODE_IMAGE=' "$PIN_FILE" 2>/dev/null || true)"
[ "$PIN_COUNT" = 1 ] || { printf '💥 expected exactly one NODE_IMAGE= line in %s, found %s\n' "$PIN_FILE" "${PIN_COUNT:-0}" >&2; exit 1; }
IMAGE="$(sed -n 's/^NODE_IMAGE=//p' "$PIN_FILE")"

CACHE_VOLUME="${PROJECT}-npm-cache"
ENV_FILE="$HOME/.config/$PROJECT/env"
LABEL="node-dev-template.project=$PROJECT"

# --- colorful, chatty output ------------------------------------------------
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''
fi

say()  { printf '%s\n' "${C_CYAN}$*${C_RESET}"; }
ok()   { printf '%s\n' "${C_GREEN}✅ $*${C_RESET}"; }
warn() { printf '%s\n' "${C_YELLOW}⚠️  $*${C_RESET}"; }
die()  { printf '%s\n' "${C_RED}💥 $*${C_RESET}" >&2; exit 1; }

# posture "📦 installing" "network: on" "scripts: ignored" "env: none"
posture() {
  local head="$1"; shift
  printf '%s' "${C_BOLD}${head}${C_RESET} ${C_DIM}("
  local first=1 p
  for p in "$@"; do
    [ "$first" = 1 ] && first=0 || printf ', '
    printf '%s' "$p"
  done
  printf ')%s\n' "…${C_RESET}"
}

# --- container plumbing -----------------------------------------------------

# Named npm-cache volume, owned by the non-root `node` user. The chown runs
# as root; recursive only when the mount point isn't already node-owned
# (fresh volumes are root-owned all the way down — a mount-point-only chown
# leaves npm hitting EACCES on the subdirs).
ensure_cache_volume() {
  # Hot path: an existing volume was already chowned to `node` when we first
  # created it, and that ownership persists. A `docker volume inspect` probe
  # (one cheap daemon round-trip) lets us skip the ~0.3–2s container start on
  # every dev/install, dev/update, and dev/shell after the one-time setup.
  docker volume inspect "$CACHE_VOLUME" >/dev/null 2>&1 && return 0
  # Cold path only: create the volume and fix ownership. The stat guard keeps
  # the recursive chown to the case that needs it (fresh volumes are root-owned
  # all the way down; a mount-point-only chown leaves npm hitting EACCES).
  docker volume create --label "$LABEL" "$CACHE_VOLUME" >/dev/null
  docker run --rm -u root -v "$CACHE_VOLUME:/tmp/.npm" "$IMAGE" \
    sh -c '[ "$(stat -c %U /tmp/.npm)" = node ] || chown -R node:node /tmp/.npm'
}

# Pull a `--net` opt-in out of the arg list (any position, so it composes with
# pass-through docker args). Sets: net_args, net_posture, pass_args. Parsed
# here, not positionally in each script — an unconsumed `--net` would reach
# docker run, where it swallows the next arg (the image ref) as its value.
parse_net_args() {
  net_args=(--network none); net_posture="network: OFF"; pass_args=()
  local arg
  for arg in "$@"; do
    if [ "$arg" = "--net" ]; then
      net_args=(); net_posture="network: ON (--net)"
    else
      pass_args+=("$arg")
    fi
  done
}

# The security floor shared by every dev container:
#   repo dir is the ONLY bind mount; non-root `node` user; HOME=/tmp is the
#   only env passed in — the container never sees host $HOME or host env.
BASE_ARGS=(
  --rm
  --init
  --label "$LABEL"
  -v "$REPO_DIR:/app"
  -w /app
  -u node
  -e HOME=/tmp
)

# -i always; -t only when we actually have a terminal. Computed here (not in
# a $() substitution, where stdout is a pipe and -t 1 would always be false).
if [ -t 0 ] && [ -t 1 ]; then TTY_FLAG='-it'; else TTY_FLAG='-i'; fi
