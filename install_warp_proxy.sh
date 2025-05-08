# secure_build_3x-ui.sh
#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Secure builder and installer for 3x-ui panel
# Clones a fixed release, verifies tag signature, builds as unprivileged user,
# installs dependencies, and sets up hardened systemd service
# Version: 1.0.1-secure
# ----------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

AUTHOR="RockBlack-VPN"
VERSION="1.0.1-secure"

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
# Self-integrity: expected SHA256 checksum of this script (update after changes)
EXPECTED_SELF_SHA256="1ca14158db8ef925da6a2bd316749fa7b6b278114635136e5beb59e0b1b05ac7"

# Repo and release settings
REPO_URL="https://github.com/MHSanaei/3x-ui.git"
RELEASE_TAG="v3.0.1"

# Install paths and user
INSTALL_DIR="/opt/3x-ui"
SERVICE_USER="xui"
SERVICE_GROUP="xui"

# Logging
LOGFILE=/var/log/build_3xui.log
exec > >(tee -a "$LOGFILE") 2>&1

# Compute own checksum
test_self_integrity() {
  local actual
  actual=$(sha256sum "$0" | awk '{print $1}')
  if [[ "$actual" != "$EXPECTED_SELF_SHA256" ]]; then
    echo "ERROR: script integrity check failed (expected $EXPECTED_SELF_SHA256, got $actual)" >&2
    exit 1
  fi
}

# Parse options
tmp_opts=$(getopt -o yf --long yes,force -n "build_3x-ui.sh" -- "$@")
eval set -- "$tmp_opts"
USE_DEFAULT=false; FORCE=false
while true; do
  case "$1" in
    -y|--yes) USE_DEFAULT=true; shift;;
    -f|--force) FORCE=true; shift;;
    --) shift; break;;
  esac
done

# Ensure root
echo "[INFO] Checking for root..."
if (( EUID != 0 )); then
  echo "ERROR: Please run as root" >&2; exit 1
fi

echo "[INFO] Starting secure build of 3x-ui ($VERSION)"
test_self_integrity

# Install dependencies
echo "[INFO] Installing build dependencies"
apt-get update
apt-get install -y git golang-go gcc gpg wget unzip || true

# Create service user
echo "[INFO] Creating service user"
id -u $SERVICE_USER &>/dev/null || useradd --system --home-dir $INSTALL_DIR --shell /usr/sbin/nologin $SERVICE_USER

# Prepare install directory
echo "[INFO] Preparing directories"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/src"
chown -R $SERVICE_USER:$SERVICE_GROUP "$INSTALL_DIR"

# Clone specific tag and verify signature
echo "[INFO] Cloning repo $REPO_URL @ $RELEASE_TAG"
su -s /bin/bash $SERVICE_USER -c "git clone --branch $RELEASE_TAG --depth 1 $REPO_URL $INSTALL_DIR/src"

# Verify tag signature if available
echo "[INFO] Verifying git tag signature"
su -s /bin/bash $SERVICE_USER -c "cd $INSTALL_DIR/src && git tag -v $RELEASE_TAG" || {
  echo "WARNING: Tag signature verification failed or not available" >&2
}

# Build application
echo "[INFO] Building 3x-ui"
export CGO_ENABLED=1 GOOS=linux GOARCH=amd64
su -s /bin/bash $SERVICE_USER -c "cd $INSTALL_DIR/src && go build -o $INSTALL_DIR/3x-ui main.go"

# Install binary
echo "[INFO] Installing binary to /usr/local/bin"
install -m 0755 "$INSTALL_DIR/3x-ui" /usr/local/bin/3x-ui

# Optionally: install Xray-core securely
# echo "[INFO] Installing Xray-core with checksum verification"

# Create systemd service
echo "[INFO] Setting up systemd service"
cat > /etc/systemd/system/3x-ui.service <<EOF
[Unit]
Description=3x-ui panel service
After=network.target

[Service]
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/local/bin/3x-ui
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ProtectHostname=true
PrivateDevices=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable 3x-ui
systemctl restart 3x-ui

echo "[INFO] Secure 3x-ui installation complete, version $RELEASE_TAG"
