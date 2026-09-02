#!/bin/sh
set -eu
REPO_DIR="${WORKSPACE_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
PORT="${DC_API_PORT:-${PORT:-8000}}"

if [ -z "${DC_API_TOKEN:-}" ]; then
  echo "ERROR: set DC_API_TOKEN before starting the control API." >&2
  exit 1
fi

mkdir -p "$REPO_DIR/logs"
cd "$REPO_DIR"
export DC_API_PORT="$PORT"
exec node "$REPO_DIR/dc-control-api.js"
