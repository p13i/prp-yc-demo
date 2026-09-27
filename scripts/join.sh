#!/usr/bin/env bash
# Join the prima.cpp Qwen ring as one rank.
#
# Rank 0 serves the OpenAI-compatible API on --port; every
# other rank runs a llama-cli worker. On macOS the script
# installs the brew dependencies, clones and builds the fork
# into ./prima.cpp next to this repo's Makefile, pulls the
# model from the master's file server (Hugging Face as the
# fallback), verifies its sha256, and starts the rank.
#
#   join.sh --rank N --world W --master IP --next IP
#           [--ngl LAYERS] [--model-dir DIR] [--model PATH]
#           [--repo DIR] [--port 8080] [--gpu-mem GIB]
#           [--ctx 4096] [--model-url URL] [--sha256 HEX]
#           [--extra "..."] [--only deps|build|model|join|all]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

RANK=""
WORLD=""
MASTER=""
NEXT=""
NGL=""
MODEL_DIR="${HOME}/models"
MODEL_NAME="Qwen2.5-7B-Instruct-Q4_K_M.gguf"
MODEL=""
REPO="${ROOT}/prima.cpp"
PORT="8080"
GPU_MEM=""
CTX="4096"
MODEL_URL=""
HF_URL="https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/${MODEL_NAME}"
SHA256="65b8fcd92af6b4fefa935c625d1ac27ea29dcb6ee14589c55a8f115ceaaa1423"
EXTRA=""
ONLY="all"
FORK_URL="https://github.com/p13i/prima.cpp-yc-hackathon"

while [ $# -gt 0 ]; do
  case "$1" in
    --rank) RANK="$2"; shift 2 ;;
    --world) WORLD="$2"; shift 2 ;;
    --master) MASTER="$2"; shift 2 ;;
    --next) NEXT="$2"; shift 2 ;;
    --ngl) NGL="$2"; shift 2 ;;
    --model-dir) MODEL_DIR="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --gpu-mem) GPU_MEM="$2"; shift 2 ;;
    --ctx) CTX="$2"; shift 2 ;;
    --model-url) MODEL_URL="$2"; shift 2 ;;
    --sha256) SHA256="$2"; shift 2 ;;
    --extra) EXTRA="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$RANK" ] || [ -z "$WORLD" ] || [ -z "$MASTER" ] || [ -z "$NEXT" ]; then
  echo "usage: join.sh --rank N --world W --master IP --next IP [options]" >&2
  exit 2
fi

case "$ONLY" in
  deps|build|model|join|all) ;;
  *) echo "--only must be one of deps, build, model, join, all" >&2; exit 2 ;;
esac

if [ -z "$MODEL" ]; then
  MODEL="${MODEL_DIR}/${MODEL_NAME}"
fi
if [ -z "$MODEL_URL" ]; then
  MODEL_URL="http://${MASTER}:8090/$(basename "$MODEL")"
fi

log() {
  echo "[join.sh $(date +%H:%M:%S)] $*" >&2
}

install_mac_deps() {
  if [ "$(uname -s)" != "Darwin" ]; then
    log "not macOS; skipping brew dependencies"
    return
  fi
  if ! command -v brew >/dev/null 2>&1; then
    log "Homebrew is required on macOS: https://brew.sh"
    exit 1
  fi
  local missing=()
  local formula
  for formula in zeromq highs fio cmake make wget; do
    if ! brew list --formula "$formula" >/dev/null 2>&1; then
      missing+=("$formula")
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    log "brew install ${missing[*]}"
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_UPGRADE=1 brew install "${missing[@]}"
  else
    log "brew dependencies present"
  fi
}

build_repo() {
  if [ ! -d "$REPO/.git" ]; then
    log "cloning $FORK_URL to $REPO"
    git clone --depth 1 "$FORK_URL" "$REPO"
  fi
  if [ -x "$REPO/llama-cli" ] && [ -x "$REPO/llama-server" ]; then
    log "prima.cpp already built in $REPO"
    return
  fi
  log "building prima.cpp in $REPO"
  local jobs
  jobs="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
  if [ "$RANK" = "0" ]; then
    make -C "$REPO" USE_HIGHS=1 -j "$jobs"
  else
    make -C "$REPO" -j "$jobs"
  fi
}

fetch_model() {
  if [ -f "$MODEL" ]; then
    log "model present at $MODEL"
  else
    mkdir -p "$(dirname "$MODEL")"
    log "downloading $MODEL_URL"
    if ! curl -fL --connect-timeout 10 -C - -o "$MODEL" "$MODEL_URL"; then
      log "master file server unreachable; downloading $HF_URL"
      curl -fL --connect-timeout 10 -C - -o "$MODEL" "$HF_URL"
    fi
  fi
  local served
  served="$(curl -fsS --connect-timeout 5 "http://${MASTER}:8090/MODEL.sha256" 2>/dev/null | awk '{print $1}' || true)"
  if [ -n "$served" ]; then
    SHA256="$served"
  fi
  if [ -n "$SHA256" ]; then
    log "verifying sha256 of $MODEL"
    local actual
    if command -v shasum >/dev/null 2>&1; then
      actual="$(shasum -a 256 "$MODEL" | awk '{print $1}')"
    else
      actual="$(sha256sum "$MODEL" | awk '{print $1}')"
    fi
    if [ "$actual" != "$SHA256" ]; then
      log "sha256 mismatch: expected $SHA256 got $actual"
      exit 1
    fi
    log "sha256 ok"
  fi
}

run_rank() {
  local common=(-m "$MODEL" --world "$WORLD" --rank "$RANK" --master "$MASTER" --next "$NEXT" --prefetch)
  if [ -n "$GPU_MEM" ]; then
    common+=(--gpu-mem "$GPU_MEM")
  fi

  cd "$REPO"
  echo "============================================================" >&2
  echo " prima.cpp Qwen ring" >&2
  echo "   rank   $RANK of world $WORLD" >&2
  echo "   master $MASTER (data port 9000, signal port 10000)" >&2
  echo "   next   $NEXT (data port $((9000 + (RANK + 1) % WORLD)))" >&2
  echo "   ngl    ${NGL:-auto}" >&2
  echo "   model  $MODEL" >&2
  echo "   repo   $REPO" >&2
  echo "============================================================" >&2
  if [ "$RANK" = "0" ]; then
    log "starting llama-server rank 0 on :$PORT (world $WORLD)"
    echo "./llama-server ${common[*]} -c $CTX --host 0.0.0.0 --port $PORT -np 2 --cont-batching $EXTRA" >&2
    # shellcheck disable=SC2086
    exec ./llama-server "${common[@]}" -c "$CTX" --host 0.0.0.0 --port "$PORT" -np 2 --cont-batching $EXTRA
  else
    if [ -n "$NGL" ]; then
      common+=(-ngl "$NGL")
    fi
    log "starting llama-cli worker rank $RANK (world $WORLD)"
    echo "./llama-cli ${common[*]} $EXTRA" >&2
    # shellcheck disable=SC2086
    exec ./llama-cli "${common[@]}" $EXTRA
  fi
}

case "$ONLY" in
  deps)
    install_mac_deps
    ;;
  build)
    build_repo
    ;;
  model)
    fetch_model
    ;;
  join)
    run_rank
    ;;
  all)
    install_mac_deps
    build_repo
    fetch_model
    run_rank
    ;;
esac
