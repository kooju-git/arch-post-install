#!/usr/bin/env bash
set -euo pipefail

KEY="$HOME/.ssh/id_ed25519"
PUB="$KEY.pub"
GITHUB_KEYS_URL="https://github.com/settings/keys"

# 1) Tools (Firefox + clipboard utils + git/stow/openssh)
sudo pacman -Syu --noconfirm \
  git stow openssh firefox xclip wl-clipboard xdg-utils

# 2) Ensure ~/.ssh perms
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# 3) Generate SSH key if missing (PROMPTS for passphrase)
if [[ ! -f "$KEY" ]]; then
  ssh-keygen -t ed25519 -C "kooju-git@kooju-labs.org" -f "$KEY"
  chmod 600 "$KEY"
  chmod 644 "$PUB"
else
  echo "SSH key already exists at: $KEY (skipping generation)"
fi

# 4) Start agent & add key (will prompt passphrase once)
eval "$(ssh-agent -s)"
ssh-add "$KEY"

# 5) Copy public key to clipboard (Wayland or X11) if a GUI session is present
copy_ok=false
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" || -n "${WAYLAND_DISPLAY:-}" ]]; then
  if command -v wl-copy >/dev/null 2>&1; then
    wl-copy < "$PUB" && copy_ok=true
  fi
elif [[ -n "${DISPLAY:-}" ]]; then
  if command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard < "$PUB" && copy_ok=true
  fi
fi

echo
if $copy_ok; then
  echo "✅ Your PUBLIC key has been copied to the clipboard."
else
  echo "⚠️ Could not detect a GUI clipboard. Showing the key below; copy it manually:"
  echo
  cat "$PUB"
  echo
fi

# 6) Open GitHub SSH keys page in Firefox (in background if GUI available)
if command -v firefox >/dev/null 2>&1 && { [[ -n "${DISPLAY:-}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]; }; then
  nohup firefox --new-window "$GITHUB_KEYS_URL" >/dev/null 2>&1 &
  echo "🌐 Opening GitHub SSH keys page in Firefox..."
else
  echo "🔗 Open this URL to add your key: $GITHUB_KEYS_URL"
fi

echo
echo "Tip: after adding the key, test with:  ssh -T git@github.com"
