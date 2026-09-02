#!/bin/sh
set -eu
REPO_DIR="${WORKSPACE_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
ENV_FILE="${DC_API_ENV_FILE:-$REPO_DIR/.env}"

# Load local .env without requiring an external dotenv package.
if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

PORT="${DC_API_PORT:-${PORT:-9102}}"

if [ "${DC_API_AUTH_REQUIRED:-true}" != "false" ] && [ "${DC_API_AUTH_REQUIRED:-true}" != "0" ] && [ -z "${DC_API_TOKEN:-}" ]; then
  echo "ERROR: set DC_API_TOKEN or disable auth with DC_API_AUTH_REQUIRED=false." >&2
  exit 1
fi

mkdir -p "$REPO_DIR/logs"
cd "$REPO_DIR"
export DC_API_PORT="$PORT"
exec node "$REPO_DIR/dc-control-api.js"
