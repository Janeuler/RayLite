#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/setup-raylite.sh"
OUT="${TMPDIR:-/tmp}/raylite-dry-run-test.log"
PREVIEW_ROOT="${TMPDIR:-/tmp}/raylite-preview-root"
rm -rf "$PREVIEW_ROOT"

bash -n "$SCRIPT"

bash "$SCRIPT" \
  --dry-run \
  --root-dir "$PREVIEW_ROOT" \
  --domain v1.example.com \
  --uuid 11111111-1111-4111-8111-111111111111 \
  --yes > "$OUT" 2>&1

grep -q 'Deployment finished' "$OUT"
grep -q 'Detected:' "$OUT"
grep -q 'WS path: /ray' "$OUT"
grep -q 'vmess.txt' "$OUT"

test -f "$PREVIEW_ROOT/usr/local/etc/v2ray/config.json"
test -f "$PREVIEW_ROOT/etc/nginx/conf.d/raylite-v1.example.com.conf"
test -f "$PREVIEW_ROOT/root/raylite/client/v1.example.com.json"
test -f "$PREVIEW_ROOT/root/raylite/client/v1.example.com.vmess.txt"
test -f "$PREVIEW_ROOT/root/raylite/client/v1.example.com.v2ray-client.json"
python3 -m json.tool "$PREVIEW_ROOT/usr/local/etc/v2ray/config.json" >/dev/null
python3 -m json.tool "$PREVIEW_ROOT/root/raylite/client/v1.example.com.json" >/dev/null
python3 -m json.tool "$PREVIEW_ROOT/root/raylite/client/v1.example.com.v2ray-client.json" >/dev/null
grep -q '"listen": "127.0.0.1"' "$PREVIEW_ROOT/usr/local/etc/v2ray/config.json"
grep -q '"port": 10086' "$PREVIEW_ROOT/usr/local/etc/v2ray/config.json"

echo "dry-run-ok: $OUT"
echo "preview-root: $PREVIEW_ROOT"
