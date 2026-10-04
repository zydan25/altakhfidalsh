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

echo "[takhfid1] Nginx + WebSocket..."
DOMAIN="takhfidsh.alattab.site"
NGINX_TEMPLATE="$APP_ROOT/deploy/takhfid1/nginx/$DOMAIN.conf"
NGINX_AVAILABLE="/etc/nginx/sites-available/$DOMAIN.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMAIN.conf"
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

# Keep a backup whenever a real existing site configuration is about to be replaced.
if [ -e "$NGINX_AVAILABLE" ] || [ -L "$NGINX_AVAILABLE" ]; then
  CURRENT_NGINX="$(readlink -f "$NGINX_AVAILABLE" 2>/dev/null || true)"
  if [ "$CURRENT_NGINX" != "$NGINX_TEMPLATE" ]; then
    cp -a "$NGINX_AVAILABLE" "$NGINX_AVAILABLE.bak.$(date +%Y%m%d%H%M%S)"
  fi
fi

ln -sf "$NGINX_TEMPLATE" "$NGINX_AVAILABLE"
ln -sf "$NGINX_AVAILABLE" "$NGINX_ENABLED"
rm -f /etc/nginx/sites-enabled/default || true

# If an existing Let's Encrypt certificate is present, restore the HTTPS
# server after installing the repo's WebSocket-capable HTTP configuration.
SSL_EXPECTED=0
if command -v certbot >/dev/null 2>&1 \
  && [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] \
  && [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
  SSL_EXPECTED=1
  if ! certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email -d "$DOMAIN" --redirect; then
    echo "[takhfid1] ERROR: certbot could not restore HTTPS for $DOMAIN." >&2
    exit 1
  fi
fi

nginx -t
systemctl reload nginx

echo "[takhfid1] PM2..."
cp "$APP_ROOT/deploy/takhfid1/ecosystem.config.cjs" "$APP_ROOT/ecosystem.config.cjs"
pm2 delete takhfid1 >/dev/null 2>&1 || true
pm2 start "$APP_ROOT/ecosystem.config.cjs" --only takhfid1 --update-env
pm2 save

sleep 2
curl -fsS "http://127.0.0.1:4008/health"
echo
# Ensure the production endpoint is reachable through the reverse proxy.
if curl -fsS --max-time 15 "https://$DOMAIN/health" >/dev/null 2>&1; then
  echo "[takhfid1] public HTTPS health OK"
elif [ "$SSL_EXPECTED" -eq 1 ]; then
  echo "[takhfid1] ERROR: HTTPS health failed although an SSL certificate is installed." >&2
  exit 1
else
  echo "[takhfid1] warning: public HTTPS health check failed; verify DNS/SSL separately."
fi
ADMIN_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:4008/admin/)"
case "$ADMIN_STATUS" in
  200|302|303) echo "[takhfid1] admin route OK (HTTP $ADMIN_STATUS)" ;;
  *) echo "[takhfid1] ERROR: /admin/ returned HTTP $ADMIN_STATUS" >&2; exit 1 ;;
esac
echo "[takhfid1] تم التحديث بنجاح."
