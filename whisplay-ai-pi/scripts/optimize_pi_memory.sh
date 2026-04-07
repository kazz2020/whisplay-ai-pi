#!/usr/bin/env bash
set -euo pipefail

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

ZRAM_PERCENT="${ZRAM_PERCENT:-50}"
ZRAM_ALGO="${ZRAM_ALGO:-lz4}"
DISK_SWAP_MB="${DISK_SWAP_MB:-1024}"
SWAPPINESS="${SWAPPINESS:-100}"

log() {
  echo "[optimize-pi-memory] $*"
}

if ! command -v apt-get >/dev/null 2>&1; then
  log "Skipping memory tuning because apt-get is not available on this system."
  exit 0
fi

log "Installing zram-tools"
$SUDO apt-get update
$SUDO apt-get install -y zram-tools

log "Configuring zram-tools"
cat <<EOF | $SUDO tee /etc/default/zramswap >/dev/null
ALGO=${ZRAM_ALGO}
PERCENT=${ZRAM_PERCENT}
PRIORITY=100
EOF

if command -v systemctl >/dev/null 2>&1; then
  $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
  $SUDO systemctl enable zramswap >/dev/null 2>&1 || true
  $SUDO systemctl restart zramswap >/dev/null 2>&1 || true
fi

if [ -f /etc/dphys-swapfile ]; then
  log "Configuring disk swap fallback"
  if grep -Eq '^CONF_SWAPSIZE=' /etc/dphys-swapfile; then
    $SUDO sed -i "s/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=${DISK_SWAP_MB}/" /etc/dphys-swapfile
  else
    echo "CONF_SWAPSIZE=${DISK_SWAP_MB}" | $SUDO tee -a /etc/dphys-swapfile >/dev/null
  fi

  if command -v systemctl >/dev/null 2>&1; then
    $SUDO systemctl restart dphys-swapfile >/dev/null 2>&1 || true
  elif command -v dphys-swapfile >/dev/null 2>&1; then
    $SUDO dphys-swapfile setup || true
    $SUDO dphys-swapfile swapon || true
  fi
else
  log "dphys-swapfile not found; skipping disk swap configuration."
fi

log "Configuring kernel VM tuning"
cat <<EOF | $SUDO tee /etc/sysctl.d/99-whisplay-memory.conf >/dev/null
vm.swappiness=${SWAPPINESS}
vm.page-cluster=0
EOF

if command -v sysctl >/dev/null 2>&1; then
  $SUDO sysctl --system >/dev/null 2>&1 || true
fi

log "Memory tuning applied. Reboot the Pi for the cleanest start."