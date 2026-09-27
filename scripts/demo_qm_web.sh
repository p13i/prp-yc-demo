#!/usr/bin/env bash
# Start the QM web UI (plugins/web-ui) in the foreground against the
# core started by scripts/demo_qm.sh, reachable by phones on the LAN.
#
#   MASTER=172.17.23.252 bash scripts/demo_qm_web.sh
#   bash scripts/demo_qm_web.sh --master 100.78.165.127 --port 8085 --web-port 8096
#
# Sign-in is a cookie set by POST /signin {"user":"<id>"}; there is no
# loopback check, so a phone on the same network can use the UI at
# http://<MASTER>:<web-port>.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MASTER="${MASTER:-172.17.23.252}"
PORT="${PORT:-8085}"
WEB_PORT="${WEB_PORT:-8096}"
QM_DIR="$HERE/qm"
WEB_DIR="$QM_DIR/plugins/web-ui"

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
    --web-port)
      WEB_PORT="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,11p' "$0"
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

if [ ! -d "$WEB_DIR" ]; then
  echo "$WEB_DIR is missing; run make demo-qm first" >&2
  exit 1
fi
if ! curl -s -m 5 -o /dev/null "http://127.0.0.1:$PORT/v1/turns"; then
  echo "no QM core answering on :$PORT; run make demo-qm first" >&2
  exit 1
fi

log "npm install (plugins/web-ui)"
(cd "$WEB_DIR" && npm install)

log "web UI on http://$MASTER:$WEB_PORT -> core http://localhost:$PORT"
echo "    sign in from any device on the network:"
echo "    curl -c cookies.txt -X POST http://$MASTER:$WEB_PORT/signin -H 'content-type: application/json' -d '{\"user\":\"U1\"}'"
echo "    a turn through the WAN ring can take 1-3 minutes"
cd "$WEB_DIR"
exec env PORT="$WEB_PORT" CORE_SIGNING_SECRET= CORE_API_URL="http://localhost:$PORT" CORE_ORG_ID=acme \
  WEB_UI_PRINCIPALS= WEB_UI_BASE= WEB_UI_DEV=1 WEB_UI_PUBLIC_URL="http://$MASTER:$WEB_PORT" CODEX_AUTH_FILE= \
  node --env-file-if-exists=../../.env server/index.ts
