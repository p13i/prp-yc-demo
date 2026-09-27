#!/usr/bin/env bash
# Run QM (p13i/qm-yc-hackathon) core against the ring master's
# OpenAI-compatible endpoint with no cloud API keys, then send one turn.
#
#   MASTER=172.17.23.252 bash scripts/demo_qm.sh
#   bash scripts/demo_qm.sh --master 100.78.165.127 --port 8085 --text "Reply with one word: mesh"
#   bash scripts/demo_qm.sh --stop
#
# Clones the fork into ./qm, runs npm install, writes ./qm/.env from
# scripts/qm.env.template with generated secrets, starts the core in
# the background (pidfile ./qm/qm-core.pid, log ./qm/qm-core.log),
# waits for "listening", POSTs one turn to /v1/turns and prints the
# reply. The core keeps running; --stop (make demo-qm-stop) kills it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MASTER="${MASTER:-172.17.23.252}"
PORT="${PORT:-8085}"
TEXT="${TEXT:-Reply with one word: mesh}"
QM_REPO="${QM_REPO:-https://github.com/p13i/qm-yc-hackathon}"
QM_BRANCH="${QM_BRANCH:-main}"
QM_DIR="$HERE/qm"
TEMPLATE="$HERE/scripts/qm.env.template"
ENV_FILE="$QM_DIR/.env"
PIDFILE="$QM_DIR/qm-core.pid"
LOG="$QM_DIR/qm-core.log"
ACTION="run"

while [ $# -gt 0 ]; do
  case "$1" in
    --master)
      MASTER="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --text)
      TEXT="$2"
      shift 2
      ;;
    --stop)
      ACTION="stop"
      shift
      ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

log() {
  printf '\033[1;36m==> %s\033[0m\n' "$*"
}

core_pid() {
  if [ -f "$PIDFILE" ]; then
    cat "$PIDFILE"
  else
    echo ""
  fi
}

core_running() {
  local pid
  pid="$(core_pid)"
  if [ -z "$pid" ]; then
    return 1
  fi
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  return 1
}

if [ "$ACTION" = "stop" ]; then
  if core_running; then
    pid="$(core_pid)"
    log "stopping QM core (pid $pid)"
    kill "$pid"
    for _ in $(seq 1 20); do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 0.5
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  else
    log "QM core is not running"
  fi
  rm -f "$PIDFILE"
  exit 0
fi

ENDPOINT="http://$MASTER:8088/v1"

if ! command -v node >/dev/null 2>&1; then
  echo "node >= 22 is required (brew install node)" >&2
  exit 1
fi
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$NODE_MAJOR" -lt 22 ]; then
  echo "node >= 22 is required, found $(node --version)" >&2
  exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate secrets" >&2
  exit 1
fi

log "ring master: $ENDPOINT"
if ! curl -sf -m 10 "$ENDPOINT/models"; then
  echo "cannot reach $ENDPOINT/models; is the master up and MASTER correct?" >&2
  exit 1
fi
echo

if [ ! -d "$QM_DIR/.git" ]; then
  log "cloning $QM_REPO ($QM_BRANCH) into ./qm"
  git clone --branch "$QM_BRANCH" --depth 1 "$QM_REPO" "$QM_DIR"
else
  log "using existing ./qm"
fi

if core_running; then
  log "QM core already running (pid $(core_pid)); reusing it. Run --stop first to restart with a new MASTER or PORT."
else
  log "npm install"
  (cd "$QM_DIR" && npm install)

  log "writing ./qm/.env from scripts/qm.env.template (MASTER=$MASTER PORT=$PORT, secrets from openssl rand -hex 32)"
  : > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *__SECRET__*)
        line="${line//__SECRET__/$(openssl rand -hex 32)}"
        ;;
    esac
    line="${line//__MASTER__/$MASTER}"
    line="${line//__PORT__/$PORT}"
    printf '%s\n' "$line" >> "$ENV_FILE"
  done < "$TEMPLATE"

  log "starting QM core on :$PORT (log: $LOG)"
  (
    cd "$QM_DIR" &&
      PORT="$PORT" CORE_SIGNING_SECRET= ALLOW_UNAUTHENTICATED_CORE=1 SESSION_STORE=memory \
        RUN_STORE=memory DEV_INSTANCE_NO_SLACK=1 SLACK_BOT_TOKEN= SLACK_APP_TOKEN= \
        PUBLIC_WEB_URL=http://localhost:8129 CORE_ORG_ID=acme SHUTDOWN_DRAIN_MS=2000 \
        nohup node --env-file-if-exists=.env src/index.ts > "$LOG" 2>&1 &
    echo $! > "$PIDFILE"
  )

  log "waiting for \"listening on :$PORT\""
  for _ in $(seq 1 240); do
    if grep -q "listening on :$PORT" "$LOG" 2>/dev/null; then
      break
    fi
    if ! core_running; then
      echo "QM core exited before listening; last log lines:" >&2
      tail -n 30 "$LOG" >&2
      rm -f "$PIDFILE"
      exit 1
    fi
    sleep 0.5
  done
  if ! grep -q "listening on :$PORT" "$LOG" 2>/dev/null; then
    echo "QM core did not report listening within 120s; last log lines:" >&2
    tail -n 30 "$LOG" >&2
    exit 1
  fi
  grep -E 'listening on|UNAUTHENTICATED' "$LOG" || true
fi

THREAD="demo-$(date +%s)"
log "POST http://127.0.0.1:$PORT/v1/turns  text=\"$TEXT\"  (thread $THREAD)"
echo "    a turn through the WAN ring can take 1-3 minutes: the harness prompt is ~2.9k tokens"
BODY="$(printf '{"surface":"battery","actor":{"externalId":"U1"},"conversation":{"kind":"dm","threadRef":"%s"},"text":"%s"}' "$THREAD" "$TEXT")"
RESPONSE="$(curl -s -m 600 "http://127.0.0.1:$PORT/v1/turns" -H 'content-type: application/json' -d "$BODY")"

echo
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$RESPONSE" | jq '{reply, sessionId, status}'
elif command -v python3 >/dev/null 2>&1; then
  printf '%s' "$RESPONSE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps({k: d.get(k) for k in ("reply","sessionId","status")}, indent=2))'
else
  printf '%s\n' "$RESPONSE"
fi
echo
log "QM core is still running on :$PORT (pid $(core_pid)); stop it with: make demo-qm-stop"
