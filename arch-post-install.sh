#!/usr/bin/env bash
set -euo pipefail

# ---- Config ----
KEY_EMAIL="kooju-git@kooju-labs.org"
KEY_PATH="$HOME/.ssh/id_ed25519"
PUB_PATH="${KEY_PATH}.pub"

# ---- Helpers ----
log() { printf '\033[1;32m[info]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }

need_pkg() {
  local missing=()
  for p in "$@"; do
    pacman -Qi "$p" &>/dev/null || missing+=("$p")
  done
  if ((${#missing[@]})); then
    sudo pacman -S --noconfirm "${missing[@]}"
  fi
}

# ---- 0) Update base + essential tools ----
log "Updating system and installing base tools..."
sudo pacman -Syu --noconfirm
need_pkg git stow openssh xclip wl-clipboard qrencode

# ---- 1) VM detection & guest additions ----
virt="$(systemd-detect-virt || true)"
case "$virt" in
  kvm|qemu)
    log "Detected $virt → installing SPICE & QEMU guest agents"
    need_pkg spice-vdagent qemu-guest-agent spice-webdavd
    sudo systemctl enable --now qemu-guest-agent.service || true
    ;;
  oracle)
    log "Detected VirtualBox → installing guest utils"
    need_pkg virtualbox-guest-utils virtualbox-guest-modules-arch
    sudo systemctl enable --now vboxservice.service || true
    ;;
  vmware)
    log "Detected VMware → installing open-vm-tools"
    need_pkg open-vm-tools
    sudo systemctl enable --now vmtoolsd.service || true
    sudo systemctl enable --now vmware-vmblock-fuse.service || true
    ;;
  microsoft)
    log "Detected Hyper-V → installing hyperv guest bits"
    need_pkg hyperv
    ;;
  none|"")
    log "Bare metal or unknown hypervisor → skipping guest additions"
    ;;
  *)
    warn "Unrecognized virt: $virt → skipping guest additions"
    ;;
esac

# ---- 2) SSH keypair ----
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ ! -f "$KEY_PATH" ]]; then
  log "Generating Ed25519 SSH key (you will be prompted for a passphrase)..."
  ssh-keygen -t ed25519 -C "$KEY_EMAIL" -f "$KEY_PATH"
  chmod 600 "$KEY_PATH"
  chmod 644 "$PUB_PATH"
else
  log "SSH key already exists at $KEY_PATH (skipping generation)"
fi

# ---- 3) Start agent & add key ----
if ! pgrep -u "$USER" ssh-agent >/dev/null 2>&1; then
  eval "$(ssh-agent -s)"
fi

log "Adding key to ssh-agent (you may be prompted for passphrase once)..."
ssh-add "$KEY_PATH" || true

# ---- 4) Clipboard + QR ----
copied=false
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" || -n "${WAYLAND_DISPLAY:-}" ]]; then
  if command -v wl-copy >/dev/null 2>&1; then
    wl-copy < "$PUB_PATH" && copied=true
  fi
elif [[ -n "${DISPLAY:-}" ]]; then
  if command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard < "$PUB_PATH" && copied=true
  fi
fi

echo
if $copied; then
  log "Your PUBLIC key is in the clipboard."
else
  warn "Could not copy to clipboard (no GUI clipboard detected)."
fi

log "Public key (for manual copy if needed):"
cat "$PUB_PATH"
echo

log "QR code (scan with your phone to copy):"
qrencode -t ansiutf8 < "$PUB_PATH" || warn "qrencode failed (is your terminal too small?)"
echo

log "After adding your key to GitHub, test with: ssh -T git@github.com"
