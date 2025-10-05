#!/usr/bin/env bash
set -euo pipefail

# --- self-delete als het script succesvol eindigt ---
# SELF="${BASH_SOURCE[0]:-$0}"
# trap 'status=$?;
#       if (( status == 0 )) && [[ -f "$SELF" && -w "$SELF" && -O "$SELF" ]]; then
#         rm -f -- "$SELF"
#       fi' EXIT

# --- config ---
KEY_EMAIL="kooju-git@kooju-labs.org"
KEY_PATH="$HOME/.ssh/id_ed25519"
PUB_PATH="${KEY_PATH}.pub"

log()  { printf '\033[1;32m[info]\033[0m %s\n' "$*"; }
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

# 1) tools
sudo pacman -Syu --noconfirm
need_pkg openssh qrencode xclip wl-clipboard

# 2) ssh key (prompt for passphrase)
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
if [[ ! -f "$KEY_PATH" ]]; then
  log "Generating Ed25519 SSH key (you will be prompted for a passphrase)…"
  ssh-keygen -t ed25519 -C "$KEY_EMAIL" -f "$KEY_PATH"
  chmod 600 "$KEY_PATH"; chmod 644 "$PUB_PATH"
else
  log "SSH key already exists at $KEY_PATH (skipping generation)"
fi

# 3) agent + add
if ! pgrep -u "$USER" ssh-agent >/dev/null 2>&1; then
  eval "$(ssh-agent -s)"
fi
ssh-add "$KEY_PATH" || true

# 4) clipboard + QR
copied=false
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" || -n "${WAYLAND_DISPLAY:-}" ]]; then
  command -v wl-copy >/dev/null && wl-copy < "$PUB_PATH" && copied=true
elif [[ -n "${DISPLAY:-}" ]]; then
  command -v xclip   >/dev/null && xclip -selection clipboard < "$PUB_PATH" && copied=true
fi

echo
if $copied; then
  log "Public key copied to clipboard."
else
  warn "No GUI clipboard detected; copy manually from below."
fi

log "Public key:"
cat "$PUB_PATH"
echo

log "QR code (scan with your phone):"
qrencode -t ansiutf8 < "$PUB_PATH" || warn "qrencode failed (try enlarging the terminal)"
echo

log "After adding your key to GitHub, test with: ssh -T git@github.com"
