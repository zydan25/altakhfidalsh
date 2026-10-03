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

# Flask-Sock uses one thread per active WebSocket connection. PostgreSQL
# LISTEN/NOTIFY bridges events between Gunicorn workers, so multiple workers
# remain safe while still allowing a useful number of persistent sockets.
exec "$APP_ROOT/.venv/bin/gunicorn"   -w 3   -k gthread   --threads 20   --timeout 120   --bind 127.0.0.1:4008   'app:create_app()'
