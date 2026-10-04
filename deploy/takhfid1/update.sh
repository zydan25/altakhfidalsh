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

# IMPORTANT: never replace an existing production Nginx vhost during an app update.
# The previous implementation could overwrite a custom/SSL vhost with the repo's
# HTTP-only template, causing HTTPS to answer with another site's certificate.
if [ -e "$NGINX_AVAILABLE" ] || [ -L "$NGINX_AVAILABLE" ]; then
  CURRENT_NGINX="$(readlink -f "$NGINX_AVAILABLE" 2>/dev/null || true)"

  # If a previous update already replaced the vhost with our template, recover
  # the newest backup created by that update before doing anything else.
  if [ "$CURRENT_NGINX" = "$NGINX_TEMPLATE" ]; then
    LAST_BACKUP="$(ls -1t "$NGINX_AVAILABLE".bak.* 2>/dev/null | head -n 1 || true)"
    if [ -n "$LAST_BACKUP" ] && [ -e "$LAST_BACKUP" ]; then
      echo "[takhfid1] restoring previous Nginx vhost: $LAST_BACKUP"
      cp -aL "$LAST_BACKUP" "$NGINX_AVAILABLE"
      CURRENT_NGINX="$(readlink -f "$NGINX_AVAILABLE" 2>/dev/null || true)"
    fi
  fi

  # If there is an existing real configuration, keep it intact and back it up
  # only when it is not already the repo template.
  if [ "$CURRENT_NGINX" != "$NGINX_TEMPLATE" ] && [ -f "$NGINX_AVAILABLE" ]; then
    BACKUP="$NGINX_AVAILABLE.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$NGINX_AVAILABLE" "$BACKUP"
    echo "[takhfid1] preserved Nginx vhost backup: $BACKUP"
  fi
else
  echo "[takhfid1] no existing Nginx vhost; installing repo template"
  ln -sf "$NGINX_TEMPLATE" "$NGINX_AVAILABLE"
fi

# Keep the chosen production vhost enabled. Do not remove Nginx's default site:
# other applications on this server may use it.
ln -sf "$NGINX_AVAILABLE" "$NGINX_ENABLED"

# Add the WebSocket location without touching existing SSL certificates,
# redirects, upstreams, or other application locations.
WS_MARKER="location /api/v1/notifications/ws"
WS_SNIPPET="$(mktemp)"
trap 'rm -f "$WS_SNIPPET"' EXIT
cat > "$WS_SNIPPET" <<'EOF'
    location /api/v1/notifications/ws {
        proxy_pass http://127.0.0.1:4008;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Sec-WebSocket-Protocol $http_sec_websocket_protocol;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
    }
EOF

"$APP_ROOT/.venv/bin/python" - "$NGINX_AVAILABLE" "$WS_MARKER" "$WS_SNIPPET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
marker = sys.argv[2]
snippet = Path(sys.argv[3]).read_text(encoding="utf-8").rstrip()

text = path.read_text(encoding="utf-8")
if marker not in text:
    # Insert the location before the closing brace of every server block that
    # explicitly serves our domain. This preserves the existing SSL/HTTP config.
    lines = text.splitlines()
    out = []
    brace_depth = 0
    server_start = None
    server_has_domain = False

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("server {"):
            server_start = len(out)
            server_has_domain = False
            brace_depth = 1
            out.append(line)
            continue

        if server_start is not None:
            if "server_name" in line and "takhfidsh.alattab.site" in line:
                server_has_domain = True

            opens = line.count("{")
            closes = line.count("}")

            if closes and brace_depth + opens - closes == 0:
                if server_has_domain:
                    out.extend(["", snippet, ""])
                out.append(line)
                server_start = None
                server_has_domain = False
                brace_depth = 0
                continue

            brace_depth += opens - closes
            out.append(line)
        else:
            out.append(line)

    path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
else:
    print("[takhfid1] WebSocket location already present")
PY
rm -f "$WS_SNIPPET"
trap - EXIT

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
