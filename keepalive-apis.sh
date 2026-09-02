#!/bin/sh
# keepalive-apis.sh — ensure DC control API instances are running.
# Port 9102: primary control API (mobile ngrok domain m-c2c8f47b166c3338.ngrok.app maps here,
#             but that platform tunnel is currently offline after container restart).
# Port 8002: public fallback via general preview domain
#             app-preview-d196cc3d81223edb310f4627cf8cda08.codebanana.com (verified working).
# Verify current mapping with get_all_domains_ports() before hardcoding elsewhere.
set -u
REPO_DIR="${WORKSPACE_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"

start_if_missing() {
  _port="$1"; _logfile="$2"
  if ss -tln 2>/dev/null | grep -q ":${_port} "; then
    echo "[$(date '+%F %T')] port ${_port}: already listening"
    return 0
  fi
  ( cd "$REPO_DIR" && setsid nohup env WORKSPACE_PATH="$REPO_DIR" \
      DC_API_PORT="$_port" DC_API_AUTH_REQUIRED=false DC_API_HOST=0.0.0.0 \
      node "$REPO_DIR/dc-control-api.js" >>"$_logfile" 2>&1 </dev/null & )
  sleep 1
  if ss -tln 2>/dev/null | grep -q ":${_port} "; then
    echo "[$(date '+%F %T')] port ${_port}: started"
  else
    echo "[$(date '+%F %T')] port ${_port}: FAILED to start" >&2
    return 1
  fi
}

start_if_missing 9102 "$LOG_DIR/dc-control-api.log"
start_if_missing 8002 "$LOG_DIR/dc-control-api-8002.log"

# Also ensure the Desktop Commander remote session is alive (idempotent wrapper).
sh "$REPO_DIR/dc-remote.sh start" >>"$LOG_DIR/desktop-commander.log" 2>&1 || true

echo "[$(date '+%F %T')] keepalive check done"
