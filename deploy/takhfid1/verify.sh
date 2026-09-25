#!/usr/bin/env bash
set -Eeuo pipefail

export PM2_HOME="${PM2_HOME:-$HOME/.pm2}"
APP_ROOT="/home/root/projects/takhfid1"
DOMAIN="takhfidsh.alattab.site"
PORT="4008"

ok(){ printf "\033[32m[OK]\033[0m %s\n" "$*"; }
fail(){ printf "\033[31m[FAIL]\033[0m %s\n" "$*" >&2; exit 1; }

[ -d "$APP_ROOT" ] || fail "المسار غير موجود: $APP_ROOT"
[ -f "$APP_ROOT/.env" ] || fail "ملف .env غير موجود"
[ -x "$APP_ROOT/.venv/bin/python" ] || fail "Python venv غير جاهز"

curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null || fail "تطبيق Flask لا يستجيب على 127.0.0.1:$PORT"
ok "Flask health"

ADMIN_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/admin/)"
case "$ADMIN_STATUS" in
  200|302|303) ok "Admin route (HTTP $ADMIN_STATUS)" ;;
  *) fail "مسار /admin/ يعيد HTTP $ADMIN_STATUS" ;;
esac

pm2 describe takhfid1 >/dev/null 2>&1 || fail "عملية PM2 takhfid1 غير موجودة"
pm2 pid takhfid1 | grep -Eq '[0-9]+' || fail "عملية PM2 takhfid1 ليست قيد التشغيل"
ok "PM2 takhfid1"

nginx -t >/dev/null 2>&1 || fail "اختبار Nginx فشل"
ok "Nginx configuration"

if command -v psql >/dev/null 2>&1; then
  set -a
  source "$APP_ROOT/.env"
  set +a
  "$APP_ROOT/.venv/bin/python" - <<'PY'
from app import create_app
from app.extensions import db
app = create_app()
with app.app_context():
    with db.engine.connect() as conn:
        conn.exec_driver_sql("SELECT 1")
print("db-ok")
PY
  ok "PostgreSQL"
fi

echo
echo "Local:  http://127.0.0.1:$PORT/health"
echo "Public: https://$DOMAIN/health"
echo "PM2:    pm2 status takhfid1"
