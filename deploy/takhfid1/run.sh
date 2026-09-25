#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="/home/root/projects/takhfid1"

if [ ! -f "$APP_ROOT/.env" ]; then
  echo "[takhfid1] ERROR: missing $APP_ROOT/.env" >&2
  exit 1
fi

set -a
source "$APP_ROOT/.env"
set +a

exec "$APP_ROOT/.venv/bin/gunicorn"   -w 3   -k gthread   --threads 4   --timeout 120   --bind 127.0.0.1:4008   'app:create_app()'
