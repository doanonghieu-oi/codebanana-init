#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
STATE_DIR="${DESKTOP_COMMANDER_STATE_DIR:-$HOME/.desktop-commander-device}"
STATE_FILE="$STATE_DIR/device.json"
BACKUP_DIR="$REPO_DIR/.desktop-commander-backup"
BACKUP_FILE="$BACKUP_DIR/device.json"

umask 077
mkdir -p "$BACKUP_DIR"

backup() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "ERROR: Desktop Commander state not found: $STATE_FILE" >&2
    return 1
  fi
  cp "$STATE_FILE" "$BACKUP_FILE.tmp"
  chmod 600 "$BACKUP_FILE.tmp"
  mv "$BACKUP_FILE.tmp" "$BACKUP_FILE"
  echo "Backed up session state to $BACKUP_FILE"
}

restore() {
  if [ ! -f "$BACKUP_FILE" ]; then
    echo "No backup exists yet; starting with current/local auth state."
    return 0
  fi
  mkdir -p "$STATE_DIR"
  cp "$BACKUP_FILE" "$STATE_FILE.tmp"
  chmod 600 "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
  echo "Restored session state from $BACKUP_FILE"
}

start() {
  restore
  exec npx -y @wonderwhy-er/desktop-commander@latest remote --persist-session
}

case "${1:-start}" in
  backup) backup ;;
  restore) restore ;;
  start) start ;;
  *) echo "Usage: $0 {start|backup|restore}" >&2; exit 2 ;;
esac
