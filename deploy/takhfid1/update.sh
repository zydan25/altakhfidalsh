#!/usr/bin/env bash
set -Eeuo pipefail

export PM2_HOME="${PM2_HOME:-$HOME/.pm2}"
APP_ROOT="/home/root/projects/takhfid1"

[ "$(id -u)" -eq 0 ] || { echo "شغّل هذا السكربت كـroot." >&2; exit 1; }
[ -d "$APP_ROOT/.git" ] || { echo "المشروع غير موجود في $APP_ROOT" >&2; exit 1; }

cd "$APP_ROOT"
echo "[takhfid1] تحديث main..."
git fetch origin main
git reset --hard origin/main

echo "[takhfid1] تحديث Python dependencies..."
"$APP_ROOT/.venv/bin/pip" install -r "$APP_ROOT/requirements.txt"

echo "[takhfid1] migrations..."
set -a
source "$APP_ROOT/.env"
set +a
"$APP_ROOT/.venv/bin/flask" db upgrade
PYTHONPATH="$APP_ROOT" "$APP_ROOT/.venv/bin/python" "$APP_ROOT/scripts/seed.py"

echo "[takhfid1] Nginx..."
nginx -t
systemctl reload nginx

echo "[takhfid1] PM2..."
pm2 delete takhfid1 >/dev/null 2>&1 || true
pm2 start "$APP_ROOT/ecosystem.config.cjs" --only takhfid1 --update-env
pm2 save

sleep 2
curl -fsS "http://127.0.0.1:4008/health"
echo
ADMIN_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:4008/admin/)"
case "$ADMIN_STATUS" in
  200|302|303) echo "[takhfid1] admin route OK (HTTP $ADMIN_STATUS)" ;;
  *) echo "[takhfid1] ERROR: /admin/ returned HTTP $ADMIN_STATUS" >&2; exit 1 ;;
esac
echo "[takhfid1] تم التحديث بنجاح."
