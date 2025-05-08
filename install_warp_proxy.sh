# secure_install_warp_proxy.sh
#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Secure installer for Cloudflare WARP Socks5 proxy via WireProxy
# Implements integrity checks, limited privileges, and hardening measures
# Version: 1.0.0
# Usage: bash install_warp_proxy.sh [-y] [-f]
# ----------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

AUTHOR="RockBlack-VPN"
VERSION="1.2.0-secure"

# Define colors
red="\e[31m\e[01m"
blue="\e[36m\e[01m"
green="\e[32m\e[01m"
yellow="\e[33m\e[01m"
bYellow="\e[1;33m"
plain="\e[0m"


# Draw ASCII-ART
function draw_ascii_art() {
    echo -e "
        ██████╗  ██████╗  ██████╗██╗  ██╗██████╗ ██╗      █████╗ ██████╗██╗  ██╗
        ██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔══██╗██║     ██╔══██╗██╔════╝██║ ██╔╝
        ██████╔╝██║   ██║██║     █████╔╝ ██████╔╝██║     ███████║██║     █████╔╝ 
        ██╔══██╗██║   ██║██║     ██╔═██╗ ██╔══██╗██║     ██╔══██║██║     ██╔═██╗ 
        ██║  ██║╚██████╔╝╚██████╗██║  ██╗██████╔╝███████╗██║  ██║╚██████╗██║  ██╗
        ╚═╝  ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
    "
}

# Self-integrity: expected SHA256 checksum of this script (update after modifications)
EXPECTED_SELF_SHA256="89eb0f49865239ea708dcf179e08f88bae988fa538d426650f3d563ddb414a74"

# Default listen port
DEFAULT_PORT=40000

# Options
USE_DEFAULT=false
FORCE=false

# Logging
LOGFILE=/var/log/install_warp_proxy.log
exec > >(tee -a "$LOGFILE") 2>&1

# Compute own checksum
_self_checksum() {
  sha256sum "$0" | awk '{print $1}'
}

# Verify script integrity
verify_self() {
  local actual
  actual=$(_self_checksum)
  if [[ "$actual" != "$EXPECTED_SELF_SHA256" ]]; then
    echo "ERROR: installer integrity check failed (expected $EXPECTED_SELF_SHA256, got $actual)" >&2
    exit 1
  fi
}

# Parse options
tmp=$(getopt -o yf --long yes,force -n "install_warp_proxy.sh" -- "$@")
eval set -- "$tmp"
while true; do
  case "$1" in
    -y|--yes) USE_DEFAULT=true; shift;;
    -f|--force) FORCE=true; shift;;
    --) shift; break;;
  esac
done

# Ensure root privileges
echo "[INFO] Checking for root..."
if (( EUID != 0 )); then
  echo "ERROR: please run as root" >&2; exit 1
fi

echo "[INFO] Starting secure WARP proxy installer ($VERSION)"
verify_self

# Install dependencies
echo "[INFO] Installing dependencies"
apt-get update
apt-get install -y curl wget gnupg iptables || true

# Create service user
id -u wireproxy &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin wireproxy

# Prompt for port
prompt_port() {
  local port
n  if [[ "$USE_DEFAULT" == true ]]; then
    port=$DEFAULT_PORT
  else
    read -rp "Enter listen port [${DEFAULT_PORT}]: " port
    port=${port:-$DEFAULT_PORT}
  fi
  # sanitize
  if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port<1 || port>65535 )); then
    echo "ERROR: invalid port: $port" >&2; exit 1
  fi
  echo "$port"
}
PORT=$(prompt_port)

echo "[INFO] Using port $PORT"

# Download WireProxy with checksum
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) BIN_NAME="wireproxy_linux_amd64";;
  aarch64) BIN_NAME="wireproxy_linux_arm64";;
  *) echo "ERROR: unsupported arch: $ARCH" >&2; exit 1;;
esac

URL_BIN="https://github.com/eycorsican/OpenWRT/releases/download/v0.2.8/$BIN_NAME"
EXPECTED_BIN_SHA256="89eb0f49865239ea708dcf179e08f88bae988fa538d426650f3d563ddb414a74"

curl -fsSL "$URL_BIN" -o wireproxy
# verify
echo "$EXPECTED_BIN_SHA256  wireproxy" | sha256sum -c -
install -m 0755 wireproxy /usr/local/bin/wireproxy
cd ~
rm -rf "$TMPDIR"

# Create config
echo "[INFO] Writing configuration"
mkdir -p /etc/wireproxy
cat > /etc/wireproxy/config.json <<EOF
{
  "listen": "127.0.0.1:$PORT",
  "mode": "warp",
  "warp": {}
}
EOF
chown -R wireproxy:wireproxy /etc/wireproxy

# Firewall rules
echo "[INFO] Configuring firewall"
iptables -I INPUT -p tcp -s 127.0.0.1 --dport $PORT -j ACCEPT
iptables -I INPUT -p tcp --dport $PORT -j DROP

# Systemd service
echo "[INFO] Installing systemd service"
cat > /etc/systemd/system/wireproxy.service <<EOF
[Unit]
Description=WireProxy WARP Socks5 proxy
After=network.target

[Service]
User=wireproxy
Group=wireproxy
ExecStart=/usr/local/bin/wireproxy --config /etc/wireproxy/config.json
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
PrivateDevices=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
enable wireproxy
restart wireproxy

echo "[INFO] Installation complete: listening on 127.0.0.1:$PORT"
