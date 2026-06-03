#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/setup-raylite.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

bash -n "$SCRIPT"
pass "bash syntax"

bash "$SCRIPT" --help >/dev/null
pass "help output"

DRY_ROOT="$TMP_DIR/dry-root"
bash "$SCRIPT" \
  --dry-run \
  --root-dir "$DRY_ROOT" \
  --domain v1.example.com \
  --uuid 11111111-1111-4111-8111-111111111111 \
  -y >/dev/null

test -s "$DRY_ROOT/usr/local/etc/v2ray/config.json" || fail "missing dry-run v2ray config"
test -s "$DRY_ROOT/etc/nginx/conf.d/raylite-v1.example.com.conf" || fail "missing dry-run nginx config"
test -s "$DRY_ROOT/root/raylite/client/v1.example.com.json" || fail "missing dry-run client JSON"
test -s "$DRY_ROOT/root/raylite/client/v1.example.com.vmess.txt" || fail "missing dry-run VMess link"
test -s "$DRY_ROOT/root/raylite/client/v1.example.com.v2ray-client.json" || fail "missing dry-run V2Ray Core client config"
pass "dry-run preview files"

python3 -m json.tool "$DRY_ROOT/usr/local/etc/v2ray/config.json" >/dev/null
python3 -m json.tool "$DRY_ROOT/root/raylite/client/v1.example.com.json" >/dev/null
python3 -m json.tool "$DRY_ROOT/root/raylite/client/v1.example.com.v2ray-client.json" >/dev/null
pass "generated JSON is valid"

CLIENT_OUT="$TMP_DIR/client-only"
bash "$SCRIPT" \
  --client-only \
  --domain v1.example.com \
  --uuid 11111111-1111-4111-8111-111111111111 \
  --output-dir "$CLIENT_OUT" >/dev/null

test -s "$CLIENT_OUT/client/v1.example.com.json" || fail "missing client-only JSON"
test -s "$CLIENT_OUT/client/v1.example.com.vmess.txt" || fail "missing client-only VMess link"
test -s "$CLIENT_OUT/client/v1.example.com.v2ray-client.json" || fail "missing client-only V2Ray Core client config"
python3 -m json.tool "$CLIENT_OUT/client/v1.example.com.v2ray-client.json" >/dev/null

python3 - "$CLIENT_OUT/client/v1.example.com.json" "$CLIENT_OUT/client/v1.example.com.vmess.txt" <<'PY'
import base64, json, pathlib, sys
json_path = pathlib.Path(sys.argv[1])
link_path = pathlib.Path(sys.argv[2])
obj = json.loads(json_path.read_text())
assert obj["add"] == "v1.example.com"
assert obj["host"] == "v1.example.com"
assert obj["sni"] == "v1.example.com"
assert obj["path"] == "/ray"
assert obj["id"] == "11111111-1111-4111-8111-111111111111"
link = link_path.read_text().strip()
assert link.startswith("vmess://")
raw = link[len("vmess://"):]
raw += "=" * (-len(raw) % 4)
decoded = json.loads(base64.b64decode(raw).decode())
assert decoded == obj
PY
pass "client-only VMess link decodes correctly"

test_distro() {
  local name="$1"
  local expected="$2"
  local content="$3"
  local os_file="$TMP_DIR/os-release-${name// /_}"
  printf '%s\n' "$content" >"$os_file"
  local out
  out="$(RAYLITE_OS_RELEASE_FILE="$os_file" bash "$SCRIPT" \
    --dry-run \
    --root-dir "$TMP_DIR/dry-${name// /_}" \
    --domain distro-test.example.com \
    --uuid 11111111-1111-4111-8111-111111111111 \
    -y 2>&1)"
  printf '%s\n' "$out" | grep -q "package manager: $expected" || {
    printf '%s\n' "$out" >&2
    fail "$name should map to $expected"
  }
  pass "$name -> $expected"
}

test_distro "Debian" "apt" $'ID=debian\nNAME="Debian GNU/Linux"\nVERSION_ID="13"'
test_distro "Ubuntu" "apt" $'ID=ubuntu\nNAME="Ubuntu"\nVERSION_ID="24.04"\nID_LIKE=debian'
test_distro "Fedora" "dnf" $'ID=fedora\nNAME="Fedora Linux"\nVERSION_ID="41"'
test_distro "Rocky" "dnf" $'ID=rocky\nNAME="Rocky Linux"\nVERSION_ID="9"\nID_LIKE="rhel fedora"'
test_distro "Arch" "pacman" $'ID=arch\nNAME="Arch Linux"'
test_distro "openSUSE" "zypper" $'ID=opensuse-leap\nNAME="openSUSE Leap"\nID_LIKE="suse opensuse"'

printf '[PASS] all validation tests completed\n'
