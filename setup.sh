#!/usr/bin/env bash
set -euo pipefail

# ===============================
# VOONO Ubuntu VPS Setup Script
# Supports:
#   default (full): Marzban + Warp + Nginx
#   custom flags: -m (marzban) -w (warp) -n (nginx)
# ===============================

GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"

log() { echo -e "${GREEN}[voono]${NC} $*"; }
warn() { echo -e "${YELLOW}[voono]${NC} $*"; }
err()  { echo -e "${RED}[voono] ERROR:${NC} $*" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Please run as root (e.g., sudo bash $0)."
    exit 1
  fi
}

detect_arch() {
  # Returns "amd64" or "arm64"
  local arch
  arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64|x86_64) echo "amd64" ;;
    arm64|aarch64) echo "arm64" ;;
    *)
      err "Unsupported architecture: $arch (only amd64/arm64)."
      exit 1
      ;;
  esac
}

APT="apt-get -y"
apt_update_once() {
  if [[ ! -f /var/lib/apt/periodic/update-success-stamp ]] || \
     [[ $(($(date +%s) - $(stat -c %Y /var/lib/apt/periodic/update-success-stamp 2>/dev/null || echo 0))) -gt 3600 ]]; then
    log "Updating apt cache..."
    apt-get update -y
  else
    log "Apt cache is fresh enough; skipping update."
  fi
}

# ---------------------------------
# Parse flags
# ---------------------------------
INSTALL_M=false
INSTALL_W=false
INSTALL_N=false

if [[ $# -eq 0 ]]; then
  # default = full install
  INSTALL_M=true
  INSTALL_W=true
  INSTALL_N=true
else
  while (( "$#" )); do
    case "$1" in
      -m) INSTALL_M=true ;;
      -w) INSTALL_W=true ;;
      -n) INSTALL_N=true ;;
      -h|--help)
        cat <<EOF
Usage: sudo bash $0 [options]

No options     Full install: Marzban Node + Warp + Nginx
-m             Install Marzban Node
-w             Install Warp (WireGuard + wgcf)
-n             Install Nginx (TLS, redirect, static index)
EOF
        exit 0
        ;;
      *)
        err "Unknown option: $1"
        exit 1
        ;;
    esac
    shift
  done
fi

# ---------------------------------
# Step 1: Marzban Node
# ---------------------------------
install_marzban() {
  log "Installing Marzban Node prerequisites..."
  apt_update_once
  $APT install curl socat git wget unzip -y

  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
  else
    log "Docker already installed."
  fi

  # Ensure docker compose plugin exists
  if ! docker compose version >/dev/null 2>&1; then
    warn "Docker 'compose' plugin not detected. Attempting to install via apt..."
    $APT install docker-compose-plugin -y || true
  fi

  if [[ ! -d /root/Marzban-node ]]; then
    log "Cloning Marzban-node repo..."
    git clone https://github.com/Gozargah/Marzban-node /root/Marzban-node
  else
    log "Marzban-node already present. Pulling latest..."
    (cd /root/Marzban-node && git pull --ff-only || true)
  fi

  mkdir -p /var/lib/marzban-node
  mkdir -p /var/lib/marzban/assets
  mkdir -p /var/lib/marzban/xray-core

  # Replace docker-compose.yml with your config
  log "Writing docker-compose.yml..."
  cat >/root/Marzban-node/docker-compose.yml <<'YAML'
services:
  voono:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host

    environment:
      XRAY_EXECUTABLE_PATH: "/var/lib/marzban/xray-core/xray"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/voono.pem"
      SERVICE_PROTOCOL: "rest"
      SERVICE_PORT: 63050
      XRAY_API_PORT: 63051

    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
      - /var/lib/marzban:/var/lib/marzban
      - /var/lib/marzban/assets:/usr/local/share/xray
YAML

  # Write certificate
  if [[ ! -f /var/lib/marzban-node/voono.pem ]]; then
    log "Writing /var/lib/marzban-node/voono.pem..."
    cat >/var/lib/marzban-node/voono.pem <<'PEM'
-----BEGIN CERTIFICATE-----
MIIEnDCCAoQCAQAwDQYJKoZIhvcNAQENBQAwEzERMA8GA1UEAwwIR296YXJnYWgw
IBcNMjQxMDI0MDc1MTM5WhgPMjEyNDA5MzAwNzUxMzlaMBMxETAPBgNVBAMMCEdv
emFyZ2FoMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAjSoE1soRlxNz
I71Ex5JTC0R+U+n3rXCl7h0izm2chOUmm/CdRIsEE0gnYjbVI6XoggaXKbJi6enm
yWhmilxmeeOVHI3cBDHxNHD6WrMEe+CELWi7hsNmLvVUrMZtkqZQ+rMBZRxpRSfy
4WemgYdvleBCjDAR8HGM1AvMJ6lHLacPql3q1Pwa4S1P+nISRXn8VJ0Azr1jifzK
73g5Ud0fKcm0Veyj1VtI2bWJIVjOgo9xgyhxo3GhY4cHpP28CgPD98Ek/EcrhPfG
thepmWMVgNjxojUdnMEMN2iJP/eET29RDuhJSTCiPV8l42eF364CaxUnEfPwfXN8
k7rJeoOrRC/Lq9zHtXbxR2HnIkFUlnYnyUwDqy2F/uXWL6i2pCM5rVScoYLMBygm
bq+IAQ+I4E7ET9lH7wrB1y4+wlLsQ6JoIQjW5H4dDLe40loFwIOPRbYh0TzZDZsk
zkD+iJGTz4TdYtpD9IX1MGNFvD1iOTGxGZjT0nChY1ghwccAmZ/JfDeWLuIxiOwL
o/tVtQ0IAl/lbqnbj+1yytM5b9lddNsV3fM2X1mJ5+alA590ZgN0OSkJ5wRLTTm9
MUOZZJO6IhuHVr4RIfFA0dqu3xdzm2KSqPpuLIk6bDFXOOjSa1aqXANTRVi5Wiv6
ls9KRPAAejXh+wqHSDU0Zvh6dqwM4jUCAwEAATANBgkqhkiG9w0BAQ0FAAOCAgEA
Uyfx0YfANHgwbevM4SsCmkrMMOM7VxYrhODr2FWEP9oSTjjNYIXgKma2zdW6fcX7
rSlGJAB4VBeB8t3jG/TvU1I141jNHr121uU1yTihz4Fyt4S9667gIZCkIlvcOS1C
V6RXVXiJSxOn+OIRemlcOcSZyidv3zl31672EVOYaIE7NR9kRuIzvT1jgmmogO3c
kubYimf7s9vCKe/2VG4rb3iyefsyA+Iads0Dv3YphrwbqsfcUllpyeyga+72EMEH
mN6gPDccQXsukJaYWJxu6yh+LHljmENVAnaMHp2bFNKMnkI4LOprv0wPK6Dgo0dX
dGE8CmBkpAja3deirfLpjtNnK3AJOK/YGP2gIhwor/ipel+jVKpLkjo3g56w6wwS
TF9YZlXZEUUgRj6jlC+f+hg1gVaLRX2uj4uO5NswGqPAzuM7cWlei0Qqd/b3hyX4
BDvNE0E7uzxaS5HoHNu223iw0VxjImacr1Tm4o+Nxf/2M1XdeJGifa2/MzJRRsxB
Vmo5yLEZpTK9AXHWBohJZaNLg1jjWmWVkSNdiKvGV4A4+jmiqMXXI9aLkcVmKq4A
2LBVA0Zdg6QPJ6S+pQhpkDSz2MkJoj1peyaP0hPLOnRDB2j+OKfesYRq0cEESjE8
hJAYLVXV8q0aBcjQTGFF4OClzTU+VBY/Joq16uOk6YY=
-----END CERTIFICATE-----
PEM
    chmod 644 /var/lib/marzban-node/voono.pem
  else
    log "Certificate already exists; skipping write."
  fi

  # Download marzban assets
  log "Downloading Marzban assets (geosite/geoip/iran)..."
  wget -O /var/lib/marzban/assets/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
  wget -O /var/lib/marzban/assets/geoip.dat   https://github.com/v2fly/geoip/releases/latest/download/geoip.dat
  wget -O /var/lib/marzban/assets/iran.dat    https://github.com/bootmortis/iran-hosted-domains/releases/latest/download/iran.dat

  # Update Xray core
  local arch; arch="$(detect_arch)"
  log "Installing Xray core for ${arch}..."
  pushd /var/lib/marzban/xray-core >/dev/null
  rm -f Xray-linux-*.zip || true
  if [[ "$arch" == "amd64" ]]; then
    wget -O Xray.zip https://github.com/XTLS/xray-core/releases/latest/download/Xray-linux-64.zip
  else
    wget -O Xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip || \
    wget -O Xray.zip https://github.com/XTLS/xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip
  fi
  unzip -o Xray.zip
  rm -f Xray.zip
  chmod +x /var/lib/marzban/xray-core/xray || true
  popd >/dev/null

  # Run docker compose
  log "Starting Marzban Node (docker compose up -d)..."
  (cd /root/Marzban-node && docker compose up -d)

  log "Marzban-Node installed and configured successfully."
}

# ---------------------------------
# Step 2: WARP (wgcf + wireguard)
# ---------------------------------
install_warp() {
  log "Installing Warp (wgcf + wireguard)..."
  apt_update_once
  $APT install wireguard -y

  local arch; arch="$(detect_arch)"
  local tmp="/tmp/wgcf"
  if [[ "$arch" == "amd64" ]]; then
    wget -O "$tmp" https://github.com/ViRb3/wgcf/releases/download/v2.2.29/wgcf_2.2.29_linux_amd64
  else
    wget -O "$tmp" https://github.com/ViRb3/wgcf/releases/download/v2.2.29/wgcf_2.2.29_linux_arm64
  fi
  mv "$tmp" /usr/bin/wgcf
  chmod +x /usr/bin/wgcf

  # Try to auto-accept any prompt (some versions accept empty stdin)
  log "Registering wgcf (may briefly prompt; auto-accepting if possible)..."
  (echo | wgcf register) || wgcf register || true

  log "Generating wgcf profile..."
  wgcf generate

  if [[ ! -f wgcf-profile.conf ]]; then
    err "wgcf-profile.conf not found; wgcf generate may have failed."
    exit 1
  fi

  # Edit config: remove DNS line, add Table = off
  log "Adjusting wgcf-profile.conf (remove DNS, add Table=off)..."
  awk '
    BEGIN { removed_dns=0; }
    /^DNS *=/ { next }  # remove DNS line
    /^\[Interface\]/ { print; getline; print $0; iface=1; next }
    iface && /^MTU *=/ { print; print "Table = off"; iface=0; next }
    { print }
  ' wgcf-profile.conf > wgcf-profile.tmp || true

  # Fallback if the above didn’t inject Table after MTU (e.g., order differs)
  if ! grep -q "^Table *= *off" wgcf-profile.tmp 2>/dev/null; then
    sed -i '/^\[Interface\]/,/^\[Peer\]/{/^\[Peer\]/!{/^Table *=/!{/^MTU *=/a Table = off}}}' wgcf-profile.tmp || true
  fi

  mv wgcf-profile.tmp wgcf-profile.conf

  mv wgcf-profile.conf /etc/wireguard/warp.conf

  # resolv.conf handling
  if [[ -f /etc/resolv.conf ]]; then
    chattr -i /etc/resolv.conf 2>/dev/null || true
    rm -f /etc/resolv.conf
  fi
  cat >/etc/resolv.conf <<'RESOLV'
nameserver 1.1.1.1
nameserver 8.8.8.8
RESOLV
  chattr +i /etc/resolv.conf || true

  systemctl enable --now wg-quick@warp
  systemctl status wg-quick@warp --no-pager || true

  log "WireGuard Warp installed and configured successfully."
}

# ---------------------------------
# Step 3: Nginx + Certbot + site
# ---------------------------------
install_nginx() {
  apt_update_once

  # Ensure certbot (apt or snap fallback)
  if ! command -v certbot >/dev/null 2>&1; then
    $APT install certbot -y || true
  fi
  if ! command -v certbot >/dev/null 2>&1; then
    $APT install snapd -y || true
    snap install --classic certbot
    ln -sf /snap/bin/certbot /usr/bin/certbot
  fi

  local DOMAIN
  read -rp "Enter your domain for TLS (e.g. example.com): " DOMAIN
  if [[ -z "${DOMAIN:-}" ]]; then
    err "Domain is required for Nginx step."
    exit 1
  fi

  log "Requesting certificate for ${DOMAIN} (standalone)..."
  if ! certbot certonly --standalone --agree-tos --register-unsafely-without-email -d "$DOMAIN"; then
    err "certbot failed; aborting Nginx installation."
    exit 1
  fi

  log "Installing nginx (with stream module via nginx-full)..."
  $APT install nginx nginx-full -y

  # --- inject only the stream block, do not replace the whole nginx.conf ---
  log "Injecting stream block into /etc/nginx/nginx.conf (non-destructive)..."
  local CONF="/etc/nginx/nginx.conf"
  local BAK="/etc/nginx/nginx.conf.$(date +%Y%m%d%H%M%S).bak"

  # The stream block you requested
  local STREAM_BLOCK
  STREAM_BLOCK=$(cat <<'SBLOCK'
# --- voono stream block (autogenerated) ---
stream {
    map $ssl_preread_protocol $route_upstream {
        ""           http_clear_fallback;
        default      tls_terminator;
    }

    upstream http_clear_fallback { server 127.0.0.1:80; }
    upstream tls_terminator      { server 127.0.0.1:5000; }

    server {
        listen 127.0.0.1:8443 reuseport;
        proxy_pass $route_upstream;
        ssl_preread on;
    }
}
# --- end voono stream block ---
SBLOCK
)

  # Skip if a prior injection is detected (by upstream name or comment tag)
  if grep -Eq '(^|\s)upstream\s+tls_terminator\b|voono stream block' "$CONF"; then
    log "Stream block already present; skipping injection."
  else
    cp "$CONF" "$BAK"
    awk -v sb="$STREAM_BLOCK" '
      BEGIN{inserted=0}
      /^[ \t]*http[ \t]*\{/ && !inserted { print sb; inserted=1 }
      { print }
      END{ if(!inserted) print sb }
    ' "$BAK" > "$CONF"
  fi
  # -------------------------------------------------------------------------

  # Site config unchanged (your redirect + TLS site)
  log "Fetching index.html..."
  mkdir -p /var/www/html
  wget -O /var/www/html/index.html https://raw.githubusercontent.com/voono/waffle/refs/heads/main/index.html

  log "Writing /etc/nginx/sites-available/default..."
  cat >/etc/nginx/sites-available/default <<NGSITE
server {
    listen 80 default_server;
    server_name _;
    return 301 https://$DOMAIN\$request_uri;
}

server {
    listen 127.0.0.1:5000 ssl default_server;
    server_name _;

    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    return 301 https://$DOMAIN\$request_uri;
}

server {
    listen 127.0.0.1:5000 ssl http2;
    server_name $DOMAIN;

    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    root /var/www/html;
    index index.html;

    ssl_protocols TLSv1.3;
}
NGSITE

  log "Testing nginx config..."
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx || systemctl restart nginx

  # Optional: open firewall if UFW is enabled
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
  fi

  log "Nginx is installed and configured successfully."
}

# ---------------------------------
# MAIN
# ---------------------------------
require_root

log "Selected actions:"
$INSTALL_M && echo "  - Marzban Node"
$INSTALL_W && echo "  - Warp (wgcf + WireGuard)"
$INSTALL_N && echo "  - Nginx + TLS"
if ! $INSTALL_M && ! $INSTALL_W && ! $INSTALL_N; then
  warn "Nothing selected. Exiting."
  exit 0
fi

# Run chosen steps
$INSTALL_M && install_marzban
$INSTALL_W && install_warp
$INSTALL_N && install_nginx

log "All done. ✨"
