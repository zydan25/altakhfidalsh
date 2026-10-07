#!/usr/bin/env bash
set -Eeuo pipefail
APP_ROOT="/home/root/projects/takhfid_web_4017"
WEB_ROOT="$APP_ROOT/current"
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/flutter/build/web" >&2
  exit 1
fi
SOURCE="$1"
[ -f "$SOURCE/index.html" ] || { echo "Source must contain Flutter build/web/index.html" >&2; exit 1; }
mkdir -p "$APP_ROOT"
TMP_DIR="$(mktemp -d "$APP_ROOT/.deploy.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
cp -a "$SOURCE"/. "$TMP_DIR"/
rm -rf "$WEB_ROOT.next" "$WEB_ROOT.prev"
mv "$TMP_DIR" "$WEB_ROOT.next"
[ ! -d "$WEB_ROOT" ] || mv "$WEB_ROOT" "$WEB_ROOT.prev"
mv "$WEB_ROOT.next" "$WEB_ROOT"
pm2 startOrReload "$APP_ROOT/ecosystem.config.cjs" --update-env
pm2 save
echo "Flutter Web is live locally on 127.0.0.1:4017"
