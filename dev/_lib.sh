# dev/_lib.sh — shared plumbing for all dev/* scripts. Source, don't run.
#
# Provides: $REPO_DIR $PROJECT $IMAGE $CACHE_VOLUME $ENV_FILE $LABEL
# and the chatty output helpers (say / ok / warn / die / posture).

set -euo pipefail

DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_DIR="$(dirname "$DEV_DIR")"

# Everything per-project derives from the directory name: cache volume,
# container labels, env-file path. Rename the dir and you get a fresh set.
PROJECT="$(basename "$REPO_DIR" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9_.-]/-/g' -e 's/^[-.]*//')"

# Single source of truth for the base image: the NODE_IMAGE line in the
# committed root .env (no secrets there — those live in ~/.config/<project>/env).
# Dev scripts parse it here; docker compose auto-loads .env and feeds it to the
# Dockerfile as a build arg. dev/bump-node rewrites this one line.
PIN_FILE="$REPO_DIR/.env"
IMAGE="$(sed -n 's/^NODE_IMAGE=//p' "$PIN_FILE" | head -n1)"
[ -n "$IMAGE" ] || { printf '💥 no NODE_IMAGE= line in %s\n' "$PIN_FILE" >&2; exit 1; }

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
# as root but only touches the volume mount point (cheap + idempotent).
ensure_cache_volume() {
  docker volume create --label "$LABEL" "$CACHE_VOLUME" >/dev/null
  docker run --rm -u root -v "$CACHE_VOLUME:/tmp/.npm" "$IMAGE" \
    chown node:node /tmp/.npm
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
