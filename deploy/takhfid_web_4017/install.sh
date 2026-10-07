#!/usr/bin/env bash
set -Eeuo pipefail
APP_ROOT="/home/root/projects/takhfid_web_4017"
mkdir -p "$APP_ROOT/current"
cd "$APP_ROOT"
command -v node >/dev/null 2>&1 || { echo "Node.js is required." >&2; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "npm is required." >&2; exit 1; }
command -v pm2 >/dev/null 2>&1 || { echo "PM2 is required: npm install -g pm2" >&2; exit 1; }
[ -f "$APP_ROOT/package.json" ] || npm init -y >/dev/null
npm install --save-exact serve@14.2.6
echo "Installed isolated Flutter Web runtime in $APP_ROOT"
