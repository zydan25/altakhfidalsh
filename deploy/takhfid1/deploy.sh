#!/usr/bin/env bash
set -Eeuo pipefail

export PM2_HOME="/home/root/.pm2"

APP_ROOT="/home/root/projects/takhfid1"
REPO_URL="\${REPO_URL:-https://github.com/zydan25/altakhfidalsh.git}"
DOMAIN="takhfidsh.alattab.site"
PORT="4006"
DB_NAME="takhfid1"
DB_USER="takhfid1"
DB_PASSWORD="\${TAKHFID1_DB_PASSWORD:-takhfid1}"
ADMIN_PHONE="\${ADMIN_PHONE:-967774952665}"
WHATSAPP_BASE_URL="\${WHATSAPP_BASE_URL:-https://whatsapp.alattab.site}"
WHATSAPP_SESSION="\${WHATSAPP_SESSION:-basheer}"

log() { printf '\n[takhfid1] %s\n' "$*"; }
die() { echo "[takhfid1][ERROR] $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "شغّل السكربت كـroot."

for cmd in git python3 psql nginx node pm2 openssl curl runuser; do
  command -v "$cmd" >/dev/null 2>&1 || die "الأمر غير موجود: $cmd"
done

if [ -d "$APP_ROOT" ] && [ ! -d "$APP_ROOT/.git" ]; then
  die "$APP_ROOT موجود لكنه ليس Git repository. لن أحذفه تلقائيًا."
fi

mkdir -p "$(dirname "$APP_ROOT")"

if [ -d "$APP_ROOT/.git" ]; then
  log "تحديث المشروع الموجود إلى main..."
  git -C "$APP_ROOT" fetch --prune origin main
  git -C "$APP_ROOT" checkout -B main origin/main
  git -C "$APP_ROOT" reset --hard origin/main
else
  log "سحب main إلى $APP_ROOT..."
  git clone --branch main --single-branch "$REPO_URL" "$APP_ROOT"
fi

cd "$APP_ROOT"

log "إعداد Python virtualenv..."
python3 -m venv "$APP_ROOT/.venv"
"$APP_ROOT/.venv/bin/python" -m pip install --upgrade pip
"$APP_ROOT/.venv/bin/pip" install -r "$APP_ROOT/requirements.txt"

mkdir -p "$APP_ROOT/storage/media"
chmod 755 "$APP_ROOT/storage" "$APP_ROOT/storage/media"

log "إدخال مفتاح WhatsApp..."
if [ -t 0 ]; then
  read -rsp "WHATSAPP_API_KEY: " WHATSAPP_API_KEY
  echo
else
  WHATSAPP_API_KEY="\${WHATSAPP_API_KEY:-}"
fi
[ -n "\${WHATSAPP_API_KEY:-}" ] || die "WHATSAPP_API_KEY مطلوب."

TAKHIFID1_SECRET_KEY="\${TAKHIFID1_SECRET_KEY:-}"
TAKHIFID1_ADMIN_PASSWORD="\${TAKHIFID1_ADMIN_PASSWORD:-}"
WHATSAPP_WEBHOOK_SECRET="\${WHATSAPP_WEBHOOK_SECRET:-}"

[ -n "$TAKHIFID1_SECRET_KEY" ] || TAKHIFID1_SECRET_KEY="$(openssl rand -hex 32)"
[ -n "$TAKHIFID1_ADMIN_PASSWORD" ] || TAKHIFID1_ADMIN_PASSWORD="$(openssl rand -hex 24)"
[ -n "$WHATSAPP_WEBHOOK_SECRET" ] || WHATSAPP_WEBHOOK_SECRET="$(openssl rand -hex 32)"

export APP_ROOT DOMAIN PORT DB_NAME DB_USER DB_PASSWORD ADMIN_PHONE
export WHATSAPP_BASE_URL WHATSAPP_SESSION WHATSAPP_API_KEY
export TAKHIFID1_SECRET_KEY TAKHIFID1_ADMIN_PASSWORD WHATSAPP_WEBHOOK_SECRET

log "إنشاء/تحديث PostgreSQL..."
runuser -u postgres -- psql -v ON_ERROR_STOP=1 \
  -v db_password="$DB_PASSWORD" \
  -f "$APP_ROOT/deploy/takhfid1/postgres/init_takhfid1.sql"

log "إنشاء/تحديث .env..."
"$APP_ROOT/.venv/bin/python" - <<'PY'
from pathlib import Path
import os
import shlex
import tempfile

app_root = Path(os.environ["APP_ROOT"])
env_file = app_root / ".env"

managed = {
    "FLASK_APP": "app:create_app",
    "FLASK_ENV": "production",
    "SECRET_KEY": os.environ["TAKHIFID1_SECRET_KEY"],
    "DATABASE_URL": f"postgresql+psycopg://{os.environ['DB_USER']}:{os.environ['DB_PASSWORD']}@127.0.0.1:5432/{os.environ['DB_NAME']}",
    "APP_TIMEZONE": "Asia/Aden",
    "MAX_UPLOAD_BYTES": "26214400",
    "MEDIA_ROOT": str(app_root / "storage/media"),
    "MEDIA_BASE_URL": "/media",
    "MEDIA_MAX_SIDE": "1600",
    "MEDIA_WEBP_QUALITY": "82",
    "ADMIN_DEV_BYPASS": "0",
    "SESSION_COOKIE_HTTPONLY": "1",
    "SESSION_COOKIE_SAMESITE": "Lax",
    "SESSION_COOKIE_SECURE": "1",
    "CORS_ORIGINS": f"https://{os.environ['DOMAIN']}",
    "ADMIN_USERNAME": "admin",
    "ADMIN_PHONE": os.environ["ADMIN_PHONE"],
    "ADMIN_PASSWORD": os.environ["TAKHIFID1_ADMIN_PASSWORD"],
    "ADMIN_OTP_MESSAGE": "رمز دخول لوحة إدارة التخفيض: {code}",
    "WHATSAPP_BASE_URL": os.environ["WHATSAPP_BASE_URL"],
    "WHATSAPP_SESSION": os.environ["WHATSAPP_SESSION"],
    "WHATSAPP_API_KEY": os.environ["WHATSAPP_API_KEY"],
    "WHATSAPP_WEBHOOK_SECRET": os.environ["WHATSAPP_WEBHOOK_SECRET"],
    "WHATSAPP_TIMEOUT": "20",
    "WHATSAPP_EXTERNAL_URL": f"https://{os.environ['DOMAIN']}",
}

existing = {}
if env_file.exists():
    for raw in env_file.read_text(encoding="utf-8").splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#") or "=" not in raw:
            continue
        key = raw.split("=", 1)[0].strip()
        if key:
            existing[key] = raw

for key, value in managed.items():
    existing[key] = f"{key}={shlex.quote(str(value))}"

order = []
seen = set()
if env_file.exists():
    for raw in env_file.read_text(encoding="utf-8").splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#") or "=" not in raw:
            order.append(("__RAW__", raw))
            continue
        key = raw.split("=", 1)[0].strip()
        if key and key not in seen:
            order.append((key, None))
            seen.add(key)

for key in managed:
    if key not in seen:
        order.append((key, None))
        seen.add(key)

lines = []
for key, raw in order:
    lines.append(raw if key == "__RAW__" else existing[key])

fd, tmp = tempfile.mkstemp(prefix=".env.", dir=str(app_root), text=True)
tmp_path = Path(tmp)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines).rstrip() + "\n")
    os.chmod(tmp_path, 0o600)
    tmp_path.replace(env_file)
finally:
    if tmp_path.exists():
        tmp_path.unlink()
PY
chmod 600 "$APP_ROOT/.env"

log "تشغيل migrations وseed..."
set -a
source "$APP_ROOT/.env"
set +a
"$APP_ROOT/.venv/bin/flask" db upgrade
"$APP_ROOT/.venv/bin/python" "$APP_ROOT/scripts/seed.py"

log "ضبط Nginx..."
cp "$APP_ROOT/deploy/takhfid1/ecosystem.config.cjs" "$APP_ROOT/ecosystem.config.cjs"
ln -sf "$APP_ROOT/deploy/takhfid1/nginx/$DOMAIN.conf" "/etc/nginx/sites-available/$DOMAIN.conf"
ln -sf "/etc/nginx/sites-available/$DOMAIN.conf" "/etc/nginx/sites-enabled/$DOMAIN.conf"
rm -f /etc/nginx/sites-enabled/default || true
nginx -t
systemctl reload nginx

log "تشغيل PM2..."
pm2 delete takhfid1 >/dev/null 2>&1 || true
pm2 start "$APP_ROOT/ecosystem.config.cjs"
pm2 save

pm2 startup systemd -u root --hp /home/root >/tmp/takhfid1-pm2-startup.txt 2>&1 || true
systemctl enable pm2-root >/dev/null 2>&1 || true
systemctl start pm2-root >/dev/null 2>&1 || true
pm2 save

log "فحص health..."
healthy=0
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    healthy=1
    break
  fi
  sleep 1
done

if [ "$healthy" -ne 1 ]; then
  pm2 status || true
  pm2 logs takhfid1 --lines 80 --nostream || true
  die "التطبيق لم ينجح في الاستجابة على 127.0.0.1:$PORT/health"
fi

log "محاولة تفعيل SSL..."
SSL_RESULT="SKIPPED"
if command -v certbot >/dev/null 2>&1 && getent hosts "$DOMAIN" >/dev/null 2>&1; then
  if certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email -d "$DOMAIN" --redirect; then
    SSL_RESULT="OK"
    nginx -t
    systemctl reload nginx
  else
    SSL_RESULT="FAILED"
    echo "[takhfid1] تحذير: certbot فشل. تأكد أن DNS للنطاق يشير إلى الخادم ثم أعد certbot."
  fi
elif ! command -v certbot >/dev/null 2>&1; then
  echo "[takhfid1] تحذير: certbot غير مثبت؛ تم تجاوز SSL."
else
  echo "[takhfid1] تحذير: $DOMAIN لا يُحل DNS الآن؛ تم تجاوز SSL."
fi

log "الفحص النهائي..."
curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null
pm2 describe takhfid1 >/dev/null
nginx -t >/dev/null

echo
echo "============================================================"
echo " TAKHFID1 DEPLOYMENT COMPLETE"
echo "============================================================"
echo "Project : $APP_ROOT"
echo "Branch  : $(git -C "$APP_ROOT" branch --show-current 2>/dev/null || true)"
echo "Commit  : $(git -C "$APP_ROOT" rev-parse --short HEAD)"
echo "PM2     : takhfid1"
echo "Port    : $PORT"
echo "Domain  : https://$DOMAIN"
echo "DB      : $DB_NAME / $DB_USER"
echo "WhatsApp: $WHATSAPP_BASE_URL / session=$WHATSAPP_SESSION"
echo "SSL     : $SSL_RESULT"
echo
echo "Admin   : https://$DOMAIN/admin/"
echo "WhatsApp: https://$DOMAIN/admin/whatsapp"
echo "Health  : https://$DOMAIN/health"
echo
echo "OTP phone: $ADMIN_PHONE"
echo "WHATSAPP_API_KEY محفوظ داخل $APP_ROOT/.env ولا يتم طباعته."
echo
echo "Commands:"
echo "  pm2 status"
echo "  pm2 logs takhfid1 --lines 100"
echo "  cd $APP_ROOT && bash deploy/takhfid1/verify.sh"
echo "============================================================"
