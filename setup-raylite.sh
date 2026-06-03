#!/usr/bin/env bash
# RayLite: one-click VMess + WebSocket + TLS + Nginx + Cloudflare-friendly deployment.
# SPDX-License-Identifier: GPL-3.0-only
#
# This script invokes the V2Fly fhs-install-v2ray installer by default and
# uses similar cross-distribution package-manager ideas. See README for credits.
# shellcheck shell=bash
set -Eeuo pipefail

VERSION="1.0.0"
PROJECT_NAME="RayLite"
DEFAULT_V2RAY_INSTALL_URL="https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh"

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
WS_PATH="${WS_PATH:-/ray}"
V2_PORT="${V2_PORT:-10086}"
UUID="${UUID:-}"
PS="${PS:-}"
OUTPUT_DIR="${OUTPUT_DIR:-/root/raylite}"
WEB_ROOT="${WEB_ROOT:-}"
SSH_PORT="${SSH_PORT:-22}"
ENABLE_FIREWALL="${ENABLE_FIREWALL:-1}"
ADD_SWAP="${ADD_SWAP:-1}"
SWAP_SIZE="${SWAP_SIZE:-1G}"
ENABLE_BBR="${ENABLE_BBR:-1}"
CERT_STAGING="${CERT_STAGING:-0}"
FORCE_CERT_RENEW="${FORCE_CERT_RENEW:-0}"
CERT_MODE="${CERT_MODE:-standalone}"
V2RAY_INSTALL_URL="${V2RAY_INSTALL_URL:-$DEFAULT_V2RAY_INSTALL_URL}"
OS_RELEASE_FILE="${RAYLITE_OS_RELEASE_FILE:-/etc/os-release}"
DRY_RUN="${DRY_RUN:-0}"
ROOT_DIR="${ROOT_DIR:-}"
CLIENT_ONLY="${CLIENT_ONLY:-0}"
ASSUME_YES="${ASSUME_YES:-0}"

OS_ID=""
OS_NAME=""
OS_VERSION=""
OS_LIKE=""
PKG_MANAGER=""
NGINX_SERVICE="nginx"
V2RAY_SERVICE="v2ray"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
CURRENT_STEP=0
TOTAL_STEPS=16

MODIFIED_FILES=()
SUMMARY_LINES=()
WARNINGS=()

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold || true)"
  RESET="$(tput sgr0 || true)"
  RED="$(tput setaf 1 || true)"
  GREEN="$(tput setaf 2 || true)"
  YELLOW="$(tput setaf 3 || true)"
  BLUE="$(tput setaf 4 || true)"
else
  BOLD=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""
fi

usage() {
  cat <<USAGE
$PROJECT_NAME $VERSION

Usage:
  sudo DOMAIN=v1.example.com bash setup-raylite.sh
  sudo bash setup-raylite.sh --domain v1.example.com --email you@example.com
  bash setup-raylite.sh --client-only --domain v1.example.com --uuid xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

Options:
  --domain DOMAIN          Required domain, for example v1.example.com
  --email EMAIL            Optional Let's Encrypt email
  --ws-path PATH           WebSocket path, default: /ray
  --v2-port PORT           Local V2Ray port, default: 10086
  --uuid UUID              Optional custom UUID. If empty, one is generated.
  --ps NAME                Client profile name
  --output-dir DIR         Output directory, default: /root/raylite
  --web-root DIR           Static camouflage website root. Default: /var/www/raylite/DOMAIN
  --ssh-port PORT          SSH port allowed by firewall, default: 22
  --no-firewall            Do not touch ufw/firewalld
  --no-swap                Do not create swap
  --no-bbr                 Do not write TCP/BBR sysctl tuning
  --staging                Use Let's Encrypt staging environment
  --force-cert-renew       Re-issue certificate even if cert path exists
  --cert-mode MODE         standalone or none, default: standalone
  --dry-run                Print intended actions without changing system
  --root-dir DIR           With --dry-run, write preview files under DIR
  --client-only            Only generate client JSON and vmess:// link; no root needed
  -y, --yes                Non-interactive confirmation
  -h, --help               Show this help

Environment variables are also supported:
  DOMAIN, EMAIL, WS_PATH, V2_PORT, UUID, PS, OUTPUT_DIR, WEB_ROOT, SSH_PORT,
  ENABLE_FIREWALL, ADD_SWAP, SWAP_SIZE, ENABLE_BBR, CERT_STAGING,
  FORCE_CERT_RENEW, CERT_MODE, V2RAY_INSTALL_URL, DRY_RUN, ROOT_DIR, CLIENT_ONLY, ASSUME_YES
USAGE
}

log() { printf '%b\n' "$*"; }
info() { log "${BLUE}[INFO]${RESET} $*"; }
success() { log "${GREEN}[OK]${RESET} $*"; }
warn() { WARNINGS+=("$*"); log "${YELLOW}[WARN]${RESET} $*"; }
fail() { log "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  log ""
  log "${BOLD}${BLUE}[$CURRENT_STEP/$TOTAL_STEPS] $*${RESET}"
}

record_file() {
  local path="$1"
  MODIFIED_FILES+=("$path")
}

record_summary() {
  SUMMARY_LINES+=("$*")
}

target_path() {
  local path="$1"
  if [[ "$DRY_RUN" == "1" && -n "$ROOT_DIR" && "$path" == /* ]]; then
    printf '%s%s' "${ROOT_DIR%/}" "$path"
  else
    printf '%s' "$path"
  fi
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[DRY-RUN]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

run_shell() {
  local cmd="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] bash -c $(printf '%q' "$cmd")"
  else
    bash -c "$cmd"
  fi
}

write_text() {
  local path="$1"
  local target
  target="$(target_path "$path")"
  if [[ "$DRY_RUN" == "1" && -z "$ROOT_DIR" ]]; then
    log "[DRY-RUN] write file: $path"
    cat >/dev/null
    record_file "planned: $path"
  else
    mkdir -p "$(dirname "$target")"
    cat >"$target"
    if [[ "$DRY_RUN" == "1" && -n "$ROOT_DIR" ]]; then
      log "[DRY-RUN] wrote preview file: $target"
      record_file "$path -> $target"
    else
      record_file "$path"
    fi
  fi
}

append_once() {
  local path="$1"
  local line="$2"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] ensure line in $path: $line"
    return 0
  fi
  touch "$path"
  if ! grep -Fxq "$line" "$path"; then
    printf '%s\n' "$line" >>"$path"
    record_file "$path"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain) DOMAIN="${2:?missing value for --domain}"; shift 2 ;;
      --email) EMAIL="${2:?missing value for --email}"; shift 2 ;;
      --ws-path) WS_PATH="${2:?missing value for --ws-path}"; shift 2 ;;
      --v2-port) V2_PORT="${2:?missing value for --v2-port}"; shift 2 ;;
      --uuid) UUID="${2:?missing value for --uuid}"; shift 2 ;;
      --ps) PS="${2:?missing value for --ps}"; shift 2 ;;
      --output-dir) OUTPUT_DIR="${2:?missing value for --output-dir}"; shift 2 ;;
      --web-root) WEB_ROOT="${2:?missing value for --web-root}"; shift 2 ;;
      --ssh-port) SSH_PORT="${2:?missing value for --ssh-port}"; shift 2 ;;
      --no-firewall) ENABLE_FIREWALL=0; shift ;;
      --no-swap) ADD_SWAP=0; shift ;;
      --no-bbr) ENABLE_BBR=0; shift ;;
      --staging) CERT_STAGING=1; shift ;;
      --force-cert-renew) FORCE_CERT_RENEW=1; shift ;;
      --cert-mode) CERT_MODE="${2:?missing value for --cert-mode}"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --root-dir) ROOT_DIR="${2:?missing value for --root-dir}"; shift 2 ;;
      --client-only) CLIENT_ONLY=1; shift ;;
      -y|--yes) ASSUME_YES=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done
}

validate_domain() {
  [[ -n "$DOMAIN" ]] || fail "DOMAIN is required. Example: DOMAIN=v1.example.com bash setup-raylite.sh"
  [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || fail "Invalid domain: $DOMAIN"
  [[ "$DOMAIN" != *..* ]] || fail "Invalid domain: $DOMAIN"
}

validate_ws_path() {
  [[ "$WS_PATH" == /* ]] || fail "WS_PATH must start with '/', for example /ray"
  [[ "$WS_PATH" =~ ^/[A-Za-z0-9._~/-]*$ ]] || fail "WS_PATH should use a simple safe path, for example /ray or /api/ray"
  case "$CERT_MODE" in
    standalone|none) ;;
    *) fail "CERT_MODE must be standalone or none" ;;
  esac
}

validate_port() {
  local port="$1"
  local name="$2"
  [[ "$port" =~ ^[0-9]+$ ]] || fail "$name must be a number: $port"
  (( port >= 1 && port <= 65535 )) || fail "$name out of range: $port"
}

generate_uuid() {
  if [[ -n "$UUID" ]]; then
    return 0
  fi
  if command -v uuidgen >/dev/null 2>&1; then
    UUID="$(uuidgen | tr 'A-Z' 'a-z')"
    return 0
  fi
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    UUID="$(cat /proc/sys/kernel/random/uuid | tr 'A-Z' 'a-z')"
    return 0
  fi

  local hex variant
  if command -v openssl >/dev/null 2>&1; then
    hex="$(openssl rand -hex 16)"
  else
    hex="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  fi
  variant="$(printf '%x' $(( (0x${hex:16:1} & 0x3) | 0x8 )))"
  UUID="${hex:0:8}-${hex:8:4}-4${hex:13:3}-${variant}${hex:17:3}-${hex:20:12}"
}

validate_uuid() {
  [[ "$UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || fail "Invalid UUID: $UUID"
  UUID="$(printf '%s' "$UUID" | tr 'A-Z' 'a-z')"
}

b64_nowrap() {
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi
}

json_escape() {
  local x="$1"
  x="${x//\\/\\\\}"
  x="${x//\"/\\\"}"
  x="${x//$'\n'/\\n}"
  printf '%s' "$x"
}

make_client_json() {
  local ps_json
  ps_json="$(json_escape "$PS")"
  cat <<CLIENT_JSON
{
  "v": "2",
  "ps": "${ps_json}",
  "add": "${DOMAIN}",
  "port": "443",
  "id": "${UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "---",
  "host": "${DOMAIN}",
  "path": "${WS_PATH}",
  "tls": "tls",
  "sni": "${DOMAIN}",
  "alpn": "",
  "fp": "",
  "insecure": "0"
}
CLIENT_JSON
}


make_v2ray_core_client_json() {
  cat <<CLIENT_CORE_JSON
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "udp": true
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10809,
      "protocol": "http",
      "settings": {}
    }
  ],
  "outbounds": [
    {
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "${DOMAIN}",
            "port": 443,
            "users": [
              {
                "id": "${UUID}",
                "alterId": 0,
                "security": "auto"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${DOMAIN}",
          "allowInsecure": false
        },
        "wsSettings": {
          "path": "${WS_PATH}",
          "headers": {
            "Host": "${DOMAIN}"
          }
        }
      }
    }
  ]
}
CLIENT_CORE_JSON
}

generate_client_files() {
  local client_dir="${OUTPUT_DIR%/}/client"
  local client_json
  local core_client_json
  local vmess_link
  client_json="$(make_client_json)"
  core_client_json="$(make_v2ray_core_client_json)"
  vmess_link="vmess://$(printf '%s' "$client_json" | b64_nowrap)"

  if [[ "$DRY_RUN" == "1" && -z "$ROOT_DIR" ]]; then
    log "[DRY-RUN] write VMess share JSON: ${client_dir}/${DOMAIN}.json"
    log "[DRY-RUN] write VMess link: ${client_dir}/${DOMAIN}.vmess.txt"
    log "[DRY-RUN] write V2Ray Core client config: ${client_dir}/${DOMAIN}.v2ray-client.json"
    record_file "planned: ${client_dir}/${DOMAIN}.json"
    record_file "planned: ${client_dir}/${DOMAIN}.vmess.txt"
    record_file "planned: ${client_dir}/${DOMAIN}.v2ray-client.json"
  else
    local client_target_dir
    client_target_dir="$(target_path "$client_dir")"
    mkdir -p "$client_target_dir"
    printf '%s\n' "$client_json" >"${client_target_dir}/${DOMAIN}.json"
    printf '%s\n' "$vmess_link" >"${client_target_dir}/${DOMAIN}.vmess.txt"
    printf '%s\n' "$core_client_json" >"${client_target_dir}/${DOMAIN}.v2ray-client.json"
    chmod 600 "${client_target_dir}/${DOMAIN}.json" "${client_target_dir}/${DOMAIN}.vmess.txt" "${client_target_dir}/${DOMAIN}.v2ray-client.json" 2>/dev/null || true
    if [[ "$DRY_RUN" == "1" && -n "$ROOT_DIR" ]]; then
      log "[DRY-RUN] wrote preview client files under: $client_target_dir"
      record_file "${client_dir}/${DOMAIN}.json -> ${client_target_dir}/${DOMAIN}.json"
      record_file "${client_dir}/${DOMAIN}.vmess.txt -> ${client_target_dir}/${DOMAIN}.vmess.txt"
      record_file "${client_dir}/${DOMAIN}.v2ray-client.json -> ${client_target_dir}/${DOMAIN}.v2ray-client.json"
    else
      record_file "${client_dir}/${DOMAIN}.json"
      record_file "${client_dir}/${DOMAIN}.vmess.txt"
      record_file "${client_dir}/${DOMAIN}.v2ray-client.json"
    fi
  fi

  record_summary "VMess share JSON: ${client_dir}/${DOMAIN}.json"
  record_summary "VMess link: ${client_dir}/${DOMAIN}.vmess.txt"
  record_summary "V2Ray Core client config: ${client_dir}/${DOMAIN}.v2ray-client.json"

  log ""
  log "${BOLD}VMess import link:${RESET}"
  log "$vmess_link"
}

require_root_unless_client_only_or_dry_run() {
  if [[ "$CLIENT_ONLY" == "1" || "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || fail "Please run as root, for example: sudo DOMAIN=$DOMAIN bash setup-raylite.sh"
}

confirm_before_install() {
  if [[ "$ASSUME_YES" == "1" || "$DRY_RUN" == "1" || "$CLIENT_ONLY" == "1" ]]; then
    return 0
  fi
  cat <<CONFIRM

About to deploy $PROJECT_NAME with:
  Domain:           $DOMAIN
  WebSocket path:   $WS_PATH
  Local V2Ray port: 127.0.0.1:$V2_PORT
  UUID:             $UUID
  Certificate mode: $CERT_MODE
  Output directory: $OUTPUT_DIR
  Web root:         $WEB_ROOT

This will install/configure packages, V2Ray, Nginx, TLS certificate, sysctl tuning,
and client files. Continue? [y/N]
CONFIRM
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]] || fail "Cancelled"
}

detect_os_and_pkg_manager() {
  step "Detect operating system and package manager"
  [[ "$(uname -s)" == "Linux" ]] || fail "Only Linux is supported"
  [[ -r "$OS_RELEASE_FILE" ]] || fail "$OS_RELEASE_FILE not found; unsupported distribution"
  # shellcheck disable=SC1090
  source "$OS_RELEASE_FILE"
  OS_ID="${ID:-unknown}"
  OS_NAME="${NAME:-unknown}"
  OS_VERSION="${VERSION_ID:-unknown}"
  OS_LIKE="${ID_LIKE:-}"

  if [[ "$DRY_RUN" != "1" ]]; then
    command -v systemctl >/dev/null 2>&1 || fail "systemctl not found; this script supports systemd-based Linux only"
    if [[ ! -d /run/systemd/system ]] && ! ps -p 1 -o comm= 2>/dev/null | grep -q '^systemd$'; then
      warn "systemd does not appear to be PID 1. Service operations may fail."
    fi
  fi

  local ids=" ${OS_ID} ${OS_LIKE} "
  if [[ "$ids" == *" debian "* ]] || [[ "$ids" == *" ubuntu "* ]] || [[ "$OS_ID" =~ ^(linuxmint|pop|zorin|kali)$ ]]; then
    PKG_MANAGER="apt"
  elif [[ "$ids" == *" arch "* ]] || [[ "$OS_ID" =~ ^(arch|manjaro|endeavouros)$ ]]; then
    PKG_MANAGER="pacman"
  elif [[ "$ids" == *" suse "* ]] || [[ "$OS_ID" =~ ^(opensuse-leap|opensuse-tumbleweed|sles)$ ]]; then
    PKG_MANAGER="zypper"
  elif [[ "$ids" == *" fedora "* ]] || [[ "$ids" == *" rhel "* ]] || [[ "$OS_ID" =~ ^(fedora|rhel|centos|rocky|almalinux|ol|oracle)$ ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      PKG_MANAGER="dnf"
    elif command -v dnf >/dev/null 2>&1; then
      PKG_MANAGER="dnf"
    else
      PKG_MANAGER="yum"
    fi
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER="zypper"
  elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
  else
    fail "Unsupported package manager. Supported: apt, dnf, yum, zypper, pacman."
  fi

  if [[ "$DRY_RUN" != "1" ]]; then
    case "$PKG_MANAGER" in
      apt) command -v apt-get >/dev/null 2>&1 || fail "apt-get not found" ;;
      dnf) command -v dnf >/dev/null 2>&1 || fail "dnf not found" ;;
      yum) command -v yum >/dev/null 2>&1 || fail "yum not found" ;;
      zypper) command -v zypper >/dev/null 2>&1 || fail "zypper not found" ;;
      pacman) command -v pacman >/dev/null 2>&1 || fail "pacman not found" ;;
    esac
  fi

  success "Detected: $OS_NAME $OS_VERSION; package manager: $PKG_MANAGER"
  record_summary "OS: $OS_NAME $OS_VERSION ($OS_ID; like: ${OS_LIKE:-none})"
  record_summary "Package manager: $PKG_MANAGER"
}

install_dependencies() {
  step "Install base dependencies"
  case "$PKG_MANAGER" in
    apt)
      run_cmd apt-get update
      run_cmd apt-get install -y --no-install-recommends curl wget unzip ca-certificates openssl nginx certbot dnsutils ufw procps iproute2
      ;;
    dnf)
      if [[ "$OS_ID $OS_LIKE" =~ (rhel|centos|rocky|alma|amzn) ]]; then
        run_cmd dnf -y install epel-release || warn "EPEL bootstrap failed or is not needed; continuing"
      fi
      run_cmd dnf -y install curl wget unzip ca-certificates openssl nginx certbot bind-utils procps-ng iproute firewalld util-linux
      ;;
    yum)
      if [[ "$OS_ID $OS_LIKE" =~ (rhel|centos|rocky|alma|amzn) ]]; then
        run_cmd yum -y install epel-release || warn "EPEL bootstrap failed or is not needed; continuing"
      fi
      run_cmd yum -y install curl wget unzip ca-certificates openssl nginx certbot bind-utils procps-ng iproute firewalld util-linux
      ;;
    zypper)
      run_cmd zypper --non-interactive refresh
      run_cmd zypper --non-interactive install --no-recommends curl wget unzip ca-certificates openssl nginx certbot bind-utils procps iproute2 firewalld util-linux
      ;;
    pacman)
      run_cmd pacman -Sy --noconfirm --needed curl wget unzip ca-certificates openssl nginx certbot bind procps-ng iproute2 ufw util-linux
      ;;
  esac
  success "Base dependency step completed"
}

install_v2ray_core() {
  step "Install or update V2Ray Core using fhs-install-v2ray"
  run_shell "bash <(curl -L '$V2RAY_INSTALL_URL')"
  record_summary "V2Ray installer: $V2RAY_INSTALL_URL"
}

create_v2ray_user() {
  step "Create dedicated v2ray system user"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] create group/user: v2ray"
    return 0
  fi
  local nologin_shell="/usr/sbin/nologin"
  [[ -x "$nologin_shell" ]] || nologin_shell="/sbin/nologin"
  getent group v2ray >/dev/null 2>&1 || groupadd --system v2ray
  id -u v2ray >/dev/null 2>&1 || useradd --system --gid v2ray --no-create-home --shell "$nologin_shell" v2ray
  success "v2ray user is ready"
}

write_v2ray_config() {
  step "Write V2Ray VMess + WebSocket server config"
  write_text /usr/local/etc/v2ray/config.json <<V2CONF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${V2_PORT},
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "level": 1,
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${WS_PATH}"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
V2CONF

  write_text /etc/systemd/system/v2ray.service.d/20-raylite-user.conf <<'V2USER'
[Service]
User=v2ray
Group=v2ray
V2USER

  record_summary "V2Ray config: /usr/local/etc/v2ray/config.json"
  record_summary "V2Ray systemd override: /etc/systemd/system/v2ray.service.d/20-raylite-user.conf"

  if [[ "$DRY_RUN" != "1" ]]; then
    systemctl daemon-reload
    if [[ -x /usr/local/bin/v2ray ]]; then
      /usr/local/bin/v2ray test -config /usr/local/etc/v2ray/config.json
    else
      warn "/usr/local/bin/v2ray not found after installer; service start may fail"
    fi
  fi
}

ensure_swap() {
  step "Configure swap for low-memory VPS"
  if [[ "$ADD_SWAP" != "1" ]]; then
    warn "Swap creation skipped by option"
    return 0
  fi
  if [[ "$DRY_RUN" != "1" ]] && swapon --show --noheadings | grep -q .; then
    success "Swap already exists; skip"
    return 0
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] create /swapfile with size $SWAP_SIZE if no swap exists"
    return 0
  fi
  if [[ ! -f /swapfile ]]; then
    fallocate -l "$SWAP_SIZE" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress
    chmod 600 /swapfile
    mkswap /swapfile
    record_file /swapfile
  fi
  swapon /swapfile
  append_once /etc/fstab "/swapfile none swap sw 0 0"
  success "Swap is enabled"
}

write_sysctl_tuning() {
  step "Write TCP/BBR and low-memory sysctl tuning"
  if [[ "$ENABLE_BBR" != "1" ]]; then
    warn "BBR/sysctl tuning skipped by option"
    return 0
  fi
  write_text /etc/sysctl.d/99-raylite.conf <<'SYSCTL'
vm.swappiness=10
vm.vfs_cache_pressure=50

net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=4096
net.ipv4.tcp_fastopen=3

net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5

net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_tw_reuse=2
SYSCTL
  if [[ "$DRY_RUN" != "1" ]]; then
    sysctl --system >/dev/null || warn "sysctl --system returned non-zero; check kernel support for BBR/TFO"
  fi
  record_summary "Sysctl tuning: /etc/sysctl.d/99-raylite.conf"
}

configure_firewall() {
  step "Configure firewall for SSH, HTTP, and HTTPS"
  if [[ "$ENABLE_FIREWALL" != "1" ]]; then
    warn "Firewall configuration skipped by option"
    return 0
  fi
  if command -v ufw >/dev/null 2>&1; then
    run_cmd ufw allow "${SSH_PORT}/tcp"
    run_cmd ufw allow 80/tcp
    run_cmd ufw allow 443/tcp
    run_shell "ufw --force enable"
    record_summary "Firewall: ufw allow ${SSH_PORT}/tcp, 80/tcp, 443/tcp"
  elif command -v firewall-cmd >/dev/null 2>&1; then
    run_cmd systemctl enable --now firewalld
    run_cmd firewall-cmd --permanent --add-port="${SSH_PORT}/tcp"
    run_cmd firewall-cmd --permanent --add-service=http
    run_cmd firewall-cmd --permanent --add-service=https
    run_cmd firewall-cmd --reload
    record_summary "Firewall: firewalld allow ${SSH_PORT}/tcp, http, https"
  else
    warn "No supported firewall manager found. Manually allow TCP ${SSH_PORT}, 80, and 443 in your VPS/cloud firewall."
  fi
}

check_dns_hint() {
  step "Check DNS hint for domain"
  if command -v dig >/dev/null 2>&1; then
    local dns_result
    dns_result="$(dig +short "$DOMAIN" A || true)"
    if [[ -z "$dns_result" ]]; then
      warn "No A record returned for $DOMAIN. Certificate issuance may fail."
    else
      info "A records for $DOMAIN:"
      printf '%s\n' "$dns_result"
      if printf '%s\n' "$dns_result" | grep -Eq '^(104\.|172\.(6[4-9]|7[0-9]|8[0-9]|9[0-9]|1[0-9]{2}|2[0-9]{2})\.|188\.114\.|190\.93\.|197\.234\.|198\.41\.)'; then
        warn "DNS appears to be Cloudflare-proxied. This is expected for orange-cloud mode; if certbot fails, switch to DNS only temporarily."
      fi
    fi
  else
    warn "dig not found; DNS hint skipped"
  fi
}

issue_certificate() {
  step "Issue or reuse Let's Encrypt TLS certificate"
  if [[ "$CERT_MODE" == "none" ]]; then
    warn "Certificate issuance skipped because CERT_MODE=none. Put fullchain.pem and privkey.pem under /etc/letsencrypt/live/${DOMAIN}/ before starting Nginx."
    record_summary "TLS certificate: skipped by CERT_MODE=none"
    return 0
  fi
  local cert_path="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  if [[ "$FORCE_CERT_RENEW" != "1" && -f "$cert_path" ]]; then
    success "Certificate already exists: $cert_path"
    return 0
  fi

  local certbot_args=(certonly --standalone -d "$DOMAIN" --agree-tos --non-interactive --preferred-challenges http)
  if [[ -n "$EMAIL" ]]; then
    certbot_args+=(--email "$EMAIL")
  else
    certbot_args+=(--register-unsafely-without-email)
  fi
  if [[ "$CERT_STAGING" == "1" ]]; then
    certbot_args+=(--staging)
  fi
  if [[ "$FORCE_CERT_RENEW" == "1" ]]; then
    certbot_args+=(--force-renewal)
  fi

  run_shell "systemctl stop ${NGINX_SERVICE} 2>/dev/null || true"
  run_cmd certbot "${certbot_args[@]}"
  record_summary "TLS certificate: /etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
}


write_certbot_hooks() {
  step "Write Certbot standalone renewal hooks"
  if [[ "$CERT_MODE" != "standalone" ]]; then
    warn "Certbot renewal hooks skipped because CERT_MODE=${CERT_MODE}"
    return 0
  fi
  write_text /etc/letsencrypt/renewal-hooks/pre/raylite-stop-nginx.sh <<'HOOK'
#!/usr/bin/env bash
systemctl stop nginx 2>/dev/null || true
HOOK
  write_text /etc/letsencrypt/renewal-hooks/post/raylite-start-nginx.sh <<'HOOK'
#!/usr/bin/env bash
systemctl start nginx 2>/dev/null || true
HOOK
  if [[ "$DRY_RUN" != "1" ]]; then
    chmod +x /etc/letsencrypt/renewal-hooks/pre/raylite-stop-nginx.sh /etc/letsencrypt/renewal-hooks/post/raylite-start-nginx.sh
  fi
  record_summary "Certbot renewal hooks: /etc/letsencrypt/renewal-hooks/pre/raylite-stop-nginx.sh and /etc/letsencrypt/renewal-hooks/post/raylite-start-nginx.sh"
}

write_nginx_config() {
  step "Write Nginx camouflage site and /ray WebSocket reverse proxy"
  WEB_ROOT="${WEB_ROOT:-/var/www/raylite/${DOMAIN}}"
  local nginx_site="/etc/nginx/conf.d/raylite-${DOMAIN}.conf"
  local nginx_map="/etc/nginx/conf.d/00-raylite-websocket-map.conf"

  write_text "${WEB_ROOT}/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Welcome</title>
  <style>
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #222; background: #f7f7f7; }
    main { max-width: 640px; padding: 32px; }
    h1 { font-size: 28px; margin-bottom: 8px; }
    p { line-height: 1.7; color: #555; }
  </style>
</head>
<body>
  <main>
    <h1>Welcome</h1>
    <p>This site is running normally.</p>
  </main>
</body>
</html>
HTML

  write_text "$nginx_map" <<'NGINXMAP'
map $http_upgrade $raylite_connection_upgrade {
    default upgrade;
    '' close;
}
NGINXMAP

  write_text "$nginx_site" <<NGINXCONF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root ${WEB_ROOT};
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    root ${WEB_ROOT};
    index index.html;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    access_log off;
    error_log /var/log/nginx/raylite-${DOMAIN}.error.log warn;

    location = ${WS_PATH} {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${V2_PORT};
        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$raylite_connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_buffering off;
        proxy_connect_timeout 5s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;
    }

    location = / {
        try_files /index.html =404;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ /\. {
        deny all;
    }
}
NGINXCONF

  record_summary "Web root: ${WEB_ROOT}"
  record_summary "Nginx map: ${nginx_map}"
  record_summary "Nginx site: ${nginx_site}"

  if [[ -e /etc/nginx/sites-enabled/default || -L /etc/nginx/sites-enabled/default ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log "[DRY-RUN] remove default Debian Nginx site: /etc/nginx/sites-enabled/default"
      record_file "planned remove: /etc/nginx/sites-enabled/default"
    else
      rm -f /etc/nginx/sites-enabled/default
      record_file "/etc/nginx/sites-enabled/default (removed)"
    fi
  fi

  if [[ "$DRY_RUN" != "1" ]]; then
    nginx -t
  fi
}

start_services() {
  step "Enable and restart services"
  run_cmd systemctl daemon-reload
  run_cmd systemctl enable --now "$V2RAY_SERVICE"
  run_cmd systemctl restart "$V2RAY_SERVICE"
  run_cmd systemctl enable --now "$NGINX_SERVICE"
  run_cmd systemctl restart "$NGINX_SERVICE"
  record_summary "Services: ${V2RAY_SERVICE}, ${NGINX_SERVICE} enabled and restarted"
}

post_install_checks() {
  step "Run post-install checks"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] nginx -t; v2ray test; ss -lntp; curl checks"
    return 0
  fi
  nginx -t
  /usr/local/bin/v2ray test -config /usr/local/etc/v2ray/config.json || warn "V2Ray config test failed"
  ss -lntp | grep -E ':80|:443|:10086' || warn "Expected listening ports not found in ss output"
  curl -I --connect-timeout 8 --max-time 20 "https://${DOMAIN}/" || warn "HTTPS homepage check failed. If using Cloudflare, verify DNS/SSL mode."
}

write_install_report() {
  step "Write deployment summary and file list"
  local report="${OUTPUT_DIR%/}/install-report-${DOMAIN}-${TIMESTAMP}.txt"
  local report_target
  report_target="$(target_path "$report")"
  if [[ "$DRY_RUN" == "1" && -z "$ROOT_DIR" ]]; then
    log "[DRY-RUN] write install report: $report"
    record_file "planned: $report"
    return 0
  fi
  mkdir -p "$(dirname "$report_target")"
  {
    echo "$PROJECT_NAME deployment report"
    echo "Generated at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo
    echo "Domain: $DOMAIN"
    echo "WebSocket path: $WS_PATH"
    echo "Local V2Ray inbound: 127.0.0.1:$V2_PORT"
    echo "UUID: $UUID"
    echo
    echo "Summary:"
    for line in "${SUMMARY_LINES[@]}"; do
      echo "- $line"
    done
    echo
    echo "Generated or modified files:"
    if [[ ${#MODIFIED_FILES[@]} -eq 0 ]]; then
      echo "- none recorded"
    else
      printf '%s\n' "${MODIFIED_FILES[@]}" | awk '!seen[$0]++ { print "- " $0 }'
    fi
    echo
    echo "Manual checks:"
    echo "- Cloudflare DNS A record should point to this VPS or be proxied to it."
    echo "- Cloudflare SSL/TLS mode should be Full or Full (strict)."
    echo "- Cloudflare Network -> WebSockets should be On."
    echo "- VPS/cloud firewall should allow TCP ${SSH_PORT}, 80, and 443."
    echo "- Import the VMess link from ${OUTPUT_DIR%/}/client/${DOMAIN}.vmess.txt into your client."
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
      echo
      echo "Warnings:"
      for warning in "${WARNINGS[@]}"; do
        echo "- $warning"
      done
    fi
  } >"$report_target"
  if [[ "$DRY_RUN" == "1" && -n "$ROOT_DIR" ]]; then
    record_file "$report -> $report_target"
    success "Preview report written: $report_target"
  else
    record_file "$report"
    success "Report written: $report"
  fi
}

print_final_summary() {
  log ""
  log "${BOLD}${GREEN}Deployment finished.${RESET}"
  log "Domain: ${DOMAIN}"
  log "WS path: ${WS_PATH}"
  log "Certificate mode: ${CERT_MODE}"
  log "Client link file: ${OUTPUT_DIR%/}/client/${DOMAIN}.vmess.txt"
  log "Client JSON file: ${OUTPUT_DIR%/}/client/${DOMAIN}.json"
  log ""
  log "Modified/generated files:"
  if [[ ${#MODIFIED_FILES[@]} -eq 0 ]]; then
    log "  none recorded"
  else
    printf '%s\n' "${MODIFIED_FILES[@]}" | awk '!seen[$0]++ { print "  - " $0 }'
  fi
  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    log ""
    log "Warnings:"
    for warning in "${WARNINGS[@]}"; do
      log "  - $warning"
    done
  fi
  log ""
  log "Useful checks:"
  log "  curl -I https://${DOMAIN}/"
  log "  curl -v --http1.1 -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' https://${DOMAIN}${WS_PATH}"
}

main() {
  parse_args "$@"
  validate_domain
  validate_ws_path
  validate_port "$V2_PORT" "V2_PORT"
  validate_port "$SSH_PORT" "SSH_PORT"
  generate_uuid
  validate_uuid
  PS="${PS:-${PROJECT_NAME}-${DOMAIN}}"
  WEB_ROOT="${WEB_ROOT:-/var/www/raylite/${DOMAIN}}"

  require_root_unless_client_only_or_dry_run

  log "${BOLD}${PROJECT_NAME} ${VERSION}${RESET}"
  log "VMess + WebSocket + TLS + camouflage domain + Cloudflare reverse-proxy friendly deployment"

  if [[ "$CLIENT_ONLY" == "1" ]]; then
    step "Generate client files only"
    generate_client_files
    print_final_summary
    exit 0
  fi

  confirm_before_install
  detect_os_and_pkg_manager
  install_dependencies
  ensure_swap
  write_sysctl_tuning
  configure_firewall
  check_dns_hint
  install_v2ray_core
  create_v2ray_user
  write_v2ray_config
  issue_certificate
  write_certbot_hooks
  write_nginx_config
  step "Generate client import files"
  generate_client_files
  start_services
  post_install_checks
  write_install_report
  print_final_summary
}

main "$@"
