#!/bin/sh
# dc-remote.sh — portable Desktop Commander Remote launcher for CodeBanana
# Usage: sh dc-remote.sh {start|stop|restart|status|logs|backup|restore|doctor}
set -u

# CodeBanana exposes the current workspace through WORKSPACE_PATH.
# Fall back to the directory containing this script for portability.
REPO_DIR="${WORKSPACE_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
if [ ! -d "$REPO_DIR" ]; then
  echo "ERROR: workspace does not exist: $REPO_DIR" >&2; exit 1
fi

STATE_DIR="${DESKTOP_COMMANDER_STATE_DIR:-$HOME/.desktop-commander-device}"
STATE_FILE="$STATE_DIR/device.json"
BACKUP_DIR="$REPO_DIR/.desktop-commander-backup"
BACKUP_FILE="$BACKUP_DIR/device.json"
LOG_DIR="$REPO_DIR/logs"
LOG_FILE="$LOG_DIR/desktop-commander.log"
PID_FILE="$LOG_DIR/desktop-commander.pid"
LOCK_FILE="$LOG_DIR/desktop-commander.lock"
NPM_CACHE_DIR="${NPM_CONFIG_CACHE:-$REPO_DIR/.npm-cache}"
RUN_CMD="npx -y @wonderwhy-er/desktop-commander@latest remote --persist-session"

umask 077
mkdir -p "$STATE_DIR" "$BACKUP_DIR" "$LOG_DIR"

dc_pids() {
  pgrep -f 'npm exec @wonderwhy-er/desktop-commander|desktop-commander.*(remote --persist-session|/dist/index\.js)' 2>/dev/null || true
}
is_running() { [ -n "$(dc_pids)" ]; }

backup() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "ERROR: no runtime state at $STATE_FILE (authenticate first)" >&2
    return 1
  fi
  cp "$STATE_FILE" "$BACKUP_FILE.tmp" && chmod 600 "$BACKUP_FILE.tmp" && mv "$BACKUP_FILE.tmp" "$BACKUP_FILE"
  echo "Backed up session state -> $BACKUP_FILE ($(wc -c < "$BACKUP_FILE") bytes)"
}

restore() {
  if [ ! -f "$BACKUP_FILE" ]; then
    echo "No backup yet ($BACKUP_FILE). First start may require authentication."
    return 0
  fi
  mkdir -p "$STATE_DIR"
  cp "$BACKUP_FILE" "$STATE_FILE.tmp" && chmod 600 "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
  echo "Restored session state from $BACKUP_FILE"
}

start() {
  exec 9>"$LOCK_FILE" || true
  if command -v flock >/dev/null 2>&1 && ! flock -n 9; then
    echo "Another start/heartbeat is already in progress."; exit 0
  fi
  if is_running; then
    echo "Already running (pids: $(dc_pids | tr '\n' ' ')). Nothing to do."; exit 0
  fi
  restore
  echo "---- [$(date '+%Y-%m-%d %H:%M:%S')] start (launcher pid $$) ----" >>"$LOG_FILE"
  OFFSET=$(wc -c < "$LOG_FILE")
  cd "$REPO_DIR" || exit 1
  NPM_CONFIG_CACHE="$NPM_CACHE_DIR" setsid nohup sh -c "$RUN_CMD" >>"$LOG_FILE" 2>&1 </dev/null &
  NEWPID=$!
  echo "$NEWPID" >"$PID_FILE"
  echo "Launched pid $NEWPID. Waiting for startup markers..."
  i=0; STATUS=""
  while [ $i -lt 90 ]; do
    i=$((i + 1)); sleep 1
    if ! kill -0 "$NEWPID" 2>/dev/null; then STATUS="DEAD"; break; fi
    if tail -c +$((OFFSET + 1)) "$LOG_FILE" 2>/dev/null | grep -q "Device ready"; then STATUS="READY"; break; fi
    if tail -c +$((OFFSET + 1)) "$LOG_FILE" 2>/dev/null | grep -q "Authenticating with Remote MCP"; then STATUS="NEEDS_AUTH"; break; fi
  done
  case "$STATUS" in
    READY)
      echo 'OK: Desktop Commander Remote is connected ("Device ready").'
      tail -c +$((OFFSET + 1)) "$LOG_FILE" | tail -n 6
      backup || true
      ;;
    NEEDS_AUTH)
      echo "WAITING FOR AUTH (first run). Complete authentication, then run: sh dc-remote.sh backup"
      tail -c +$((OFFSET + 1)) "$LOG_FILE" | tail -n 12
      ;;
    DEAD)
      echo "FAILED: process exited during startup. Last log lines:" >&2
      tail -n 15 "$LOG_FILE" >&2
      exit 1
      ;;
    *)
      echo "TIMEOUT: process may still be starting. Last log lines:"
      tail -n 10 "$LOG_FILE"
      ;;
  esac
}

stop() {
  PIDS="$(dc_pids)"
  if [ -z "$PIDS" ]; then echo "Not running."; return 0; fi
  echo "Stopping pids: $(echo "$PIDS" | tr '\n' ' ')"
  for p in $PIDS; do kill "$p" 2>/dev/null || true; done
  i=0
  while [ $i -lt 10 ] && is_running; do i=$((i + 1)); sleep 1; done
  if is_running; then
    pkill -9 -f 'npm exec @wonderwhy-er/desktop-commander' 2>/dev/null || true
    pkill -9 -f 'desktop-commander.*(remote --persist-session|/dist/index\.js)' 2>/dev/null || true
    sleep 1
  fi
  is_running && { echo "WARNING: some processes survived"; return 1; } || echo "Stopped cleanly."
}

status() {
  echo "== Desktop Commander Remote =="
  if is_running; then
    for p in $(dc_pids); do
      echo "running pid: $p (up: $(ps -o etime= -p "$p" 2>/dev/null | tr -d ' '))"
    done
  else echo "running: NO"; fi
  [ -f "$STATE_FILE" ] && echo "runtime state : $STATE_FILE ($(wc -c < "$STATE_FILE") bytes)" || echo "runtime state : MISSING"
  [ -f "$BACKUP_FILE" ] && echo "persistent bak: $BACKUP_FILE ($(wc -c < "$BACKUP_FILE") bytes)" || echo "persistent bak: MISSING"
  echo "workspace     : $REPO_DIR"
  echo "== last log lines =="
  tail -n 8 "$LOG_FILE" 2>/dev/null || true
}

logs() { tail -n "${2:-80}" "$LOG_FILE" 2>/dev/null; }

doctor() {
  echo "workspace: $REPO_DIR"
  echo "WORKSPACE_PATH: ${WORKSPACE_PATH:-<unset>}"
  echo "node: $(command -v node || echo MISSING) $(node -v 2>/dev/null)"
  echo "npx:  $(command -v npx || echo MISSING)"
  echo "state: $([ -f "$STATE_FILE" ] && echo present || echo missing) | backup: $([ -f "$BACKUP_FILE" ] && echo present || echo missing)"
  echo "procs: $(dc_pids | tr '\n' ' ')"
  echo "npm cache: $NPM_CACHE_DIR $(du -sh "$NPM_CACHE_DIR" 2>/dev/null | cut -f1)"
}

case "${1:-status}" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  logs) logs "$@" ;;
  backup) backup ;;
  restore) restore ;;
  doctor) doctor ;;
  *) echo "Usage: $0 {start|stop|restart|status|logs|backup|restore|doctor}" >&2; exit 2 ;;
esac
