#!/usr/bin/env bash
# Run GBrain (p13i/gbrain-yc-hackathon) against the ring master's
# OpenAI-compatible endpoint with no cloud API keys.
#
#   MASTER=172.17.23.252 QUESTION="..." bash scripts/demo_gbrain.sh
#   bash scripts/demo_gbrain.sh --master 100.78.165.127 --question "..."
#
# Clones the fork into ./gbrain, installs with Bun, creates a PGLite
# brain in ./gbrain-home, imports ./sample-notes, points chat, think
# and expansion at llama-server:qwen2.5-7b, and prints the answer to
# QUESTION.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MASTER="${MASTER:-172.17.23.252}"
QUESTION="${QUESTION:-Which machines form the prima.cpp ring and what does each one run?}"
GBRAIN_REPO="${GBRAIN_REPO:-https://github.com/p13i/gbrain-yc-hackathon}"
GBRAIN_BRANCH="${GBRAIN_BRANCH:-master}"
GBRAIN_DIR="$HERE/gbrain"
GBRAIN_HOME_DIR="$HERE/gbrain-home"
NOTES_DIR="$HERE/sample-notes"

while [ $# -gt 0 ]; do
  case "$1" in
    --master)
      MASTER="$2"
      shift 2
      ;;
    --question)
      QUESTION="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ENDPOINT="http://$MASTER:8088/v1"

log() {
  printf '\033[1;36m==> %s\033[0m\n' "$*"
}

if ! command -v bun >/dev/null 2>&1; then
  echo "bun is required: brew install oven-sh/bun/bun" >&2
  exit 1
fi

log "ring master: $ENDPOINT"
if ! curl -sf -m 10 "$ENDPOINT/models"; then
  echo "cannot reach $ENDPOINT/models; is the master up and MASTER correct?" >&2
  exit 1
fi
echo

if [ ! -d "$GBRAIN_DIR/.git" ]; then
  log "cloning $GBRAIN_REPO ($GBRAIN_BRANCH) into ./gbrain"
  git clone --branch "$GBRAIN_BRANCH" --depth 1 "$GBRAIN_REPO" "$GBRAIN_DIR"
else
  log "using existing ./gbrain"
fi

log "bun install"
(cd "$GBRAIN_DIR" && bun install)

# GBRAIN_HOME must be a physical path (gbrain refuses a symlinked
# content root) and gbrain appends .gbrain to it itself.
mkdir -p "$GBRAIN_HOME_DIR"
GBRAIN_HOME_DIR="$(cd "$GBRAIN_HOME_DIR" && pwd -P)"

# Every gbrain call: cloud keys stripped, endpoint and home pinned.
gb() {
  (
    cd "$GBRAIN_DIR" &&
      env -u OPENAI_API_KEY -u ANTHROPIC_API_KEY -u VOYAGE_API_KEY -u OPENAI_BASE_URL \
        LLAMA_SERVER_BASE_URL="$ENDPOINT" \
        GBRAIN_HOME="$GBRAIN_HOME_DIR" \
        bun run src/cli.ts "$@"
  )
}

if [ ! -d "$GBRAIN_HOME_DIR/.gbrain" ]; then
  log "gbrain init --pglite --no-embedding --git  (home: $GBRAIN_HOME_DIR)"
  gb init --pglite --no-embedding --git
else
  log "using existing brain in $GBRAIN_HOME_DIR/.gbrain"
fi

log "gbrain import sample-notes --no-embed"
gb import "$NOTES_DIR" --no-embed

log "gbrain config set models.{chat,think,expansion} llama-server:qwen2.5-7b"
gb config set models.chat llama-server:qwen2.5-7b
gb config set models.think llama-server:qwen2.5-7b
gb config set models.expansion llama-server:qwen2.5-7b

log "gbrain think \"$QUESTION\"  (a think prompt is ~3.4k tokens; expect 1-3 minutes on the ring)"
gb think "$QUESTION"

echo
log "done. To serve this brain to phones on the LAN (stop it before running think again):"
echo "  (cd gbrain && LLAMA_SERVER_BASE_URL=$ENDPOINT GBRAIN_HOME=$GBRAIN_HOME_DIR bun run src/cli.ts serve --http --bind 0.0.0.0 --port 3131)"
