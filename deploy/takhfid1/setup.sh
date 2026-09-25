#!/usr/bin/env bash
set -Eeuo pipefail

export PM2_HOME="${PM2_HOME:-/home/root/.pm2}"
APP_ROOT="/home/root/projects/takhfid1"
REPO_URL="${REPO_URL:-https://github.com/zydan25/altakhfidalsh.git}"
DOMAIN="takhfidsh.alattab.site"
PORT="4006"
DB_NAME="takhfid1"
DB_USER="takhfid1"
DB_PASSWORD="${TAKHFID1_DB_PASSWORD:-takhfid1}"

log(){ printf '\n[takhfid1] %s\n' "$*"; }
die(){ echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "شغّل السكربت كـroot عبر sudo bash deploy/takhfid1/setup.sh"
for cmd in git python3 psql nginx node pm2 openssl curl runuser; do
  command -v "$cmd" >/dev/null 2>&1 || die "الأمر غير موجود: $cmd"
done

mkdir -p /home/root/projects
if [ ! -d "$APP_ROOT/.git" ]; then
  git clone --branch main --single-branch "$REPO_URL" "$APP_ROOT"
else
  git -C "$APP_ROOT" fetch origin main
  git -C "$APP_ROOT" reset --hard origin/main
fi

log "إنشاء PostgreSQL"
runuser -u postgres -- psql -v ON_ERROR_STOP=1 -v db_password="$DB_PASSWORD" -f "$APP_ROOT/deploy/takhfid1/postgres/init_takhfid1.sql"

log "Python environment"
python3 -m venv "$APP_ROOT/.venv"
"$APP_ROOT/.venv/bin/pip" install --upgrade pip
"$APP_ROOT/.venv/bin/pip" install -r "$APP_ROOT/requirements.txt"
mkdir -p "$APP_ROOT/storage/media"

ENV_FILE="$APP_ROOT/.env"
if [ -f "$ENV_FILE" ]; then
  log "الملف .env موجود؛ سيتم الحفاظ على الأسرار الحالية."
else
  SECRET_KEY="${TAKHIFID1_SECRET_KEY:-$(openssl rand -hex 32)}"
  ADMIN_PASSWORD="${TAKHIFID1_ADMIN_PASSWORD:-$(openssl rand -hex 24)}"
  WHATSAPP_API_KEY="${WHATSAPP_API_KEY:-}"
  WHATSAPP_WEBHOOK_SECRET="${WHATSAPP_WEBHOOK_SECRET:-}"
  cat > "$ENV_FILE" <<EOF
FLASK_APP=app:create_app
FLASK_ENV=production
SECRET_KEY=$SECRET_KEY
DATABASE_URL=postgresql+psycopg://$DB_USER:$DB_PASSWORD@127.0.0.1:5432/$DB_NAME
APP_TIMEZONE=Asia/Aden
MAX_UPLOAD_BYTES=26214400
MEDIA_ROOT=$APP_ROOT/storage/media
MEDIA_BASE_URL=/media
MEDIA_MAX_SIDE=1600
MEDIA_WEBP_QUALITY=82
ADMIN_DEV_BYPASS=0
SESSION_COOKIE_HTTPONLY=1
SESSION_COOKIE_SAMESITE=Lax
SESSION_COOKIE_SECURE=1
CORS_ORIGINS=https://$DOMAIN

ADMIN_USERNAME=admin
ADMIN_PHONE=967774952665
ADMIN_PASSWORD=$ADMIN_PASSWORD
ADMIN_OTP_MESSAGE=رمز دخول لوحة إدارة التخفيض: {code}

WHATSAPP_BASE_URL=https://whatsapp.alattab.site
WHATSAPP_SESSION=basheer
WHATSAPP_API_KEY=$WHATSAPP_API_KEY
WHATSAPP_WEBHOOK_SECRET=$WHATSAPP_WEBHOOK_SECRET
WHATSAPP_TIMEOUT=20
WHATSAPP_EXTERNAL_URL=https://$DOMAIN
EOF
  chmod 600 "$ENV_FILE"
fi

set -a
source "$ENV_FILE"
set +a

cd "$APP_ROOT"
"$APP_ROOT/.venv/bin/flask" db upgrade
PYTHONPATH="$APP_ROOT" "$APP_ROOT/.venv/bin/python" "$APP_ROOT/scripts/seed.py"

cp "$APP_ROOT/deploy/takhfid1/ecosystem.config.cjs" "$APP_ROOT/ecosystem.config.cjs"
ln -sf "$APP_ROOT/deploy/takhfid1/nginx/$DOMAIN.conf" "/etc/nginx/sites-available/$DOMAIN.conf"
ln -sf "/etc/nginx/sites-available/$DOMAIN.conf" "/etc/nginx/sites-enabled/$DOMAIN.conf"
rm -f /etc/nginx/sites-enabled/default || true
nginx -t
systemctl reload nginx

pm2 delete takhfid1 >/dev/null 2>&1 || true
pm2 start "$APP_ROOT/ecosystem.config.cjs"
pm2 save

# Enable PM2 resurrection on Ubuntu if the startup unit is not already active.
if command -v systemctl >/dev/null 2>&1; then
  pm2 startup systemd -u root --hp /home/root >/tmp/takhfid1-pm2-startup.txt 2>&1 || true
  systemctl enable pm2-root >/dev/null 2>&1 || true
  systemctl start pm2-root >/dev/null 2>&1 || true
fi

sleep 3
curl -fsS "http://127.0.0.1:$PORT/health"

cat <<EOF

takhfid1 deployed
APP_ROOT=$APP_ROOT
PORT=$PORT
DOMAIN=https://$DOMAIN
PM2=takhfid1
DB_NAME=$DB_NAME
DB_USER=$DB_USER
APP_ROOT=$APP_ROOT
PORT=$PORT
DOMAIN=https://$DOMAIN
PM2=takhfid1

SSL:
certbot --nginx -d $DOMAIN

PM2 status:
pm2 status

PM2 logs:
pm2 logs takhfid1 --lines 100
EOF
