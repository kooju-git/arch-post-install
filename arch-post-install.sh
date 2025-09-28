#!/usr/bin/env bash
set -euo pipefail

# Update system and install tools
sudo pacman -Syu --noconfirm git stow openssh qrencode

# Ensure ~/.ssh exists with safe perms
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

KEY="$HOME/.ssh/id_ed25519"

# Generate key if missing (will prompt for passphrase)
if [[ ! -f "$KEY" ]]; then
  ssh-keygen -t ed25519 -C "kooju-git@kooju-labs.org" -f "$KEY"
  chmod 600 "$KEY"
  chmod 644 "${KEY}.pub"
else
  echo "SSH key already exists at $KEY (skipping generation)."
fi

# Start agent and add key
eval "$(ssh-agent -s)"
ssh-add "$KEY"

echo
echo "👉 Add this SSH PUBLIC key to GitHub (Settings → SSH and GPG keys):"
echo
cat "${KEY}.pub"
echo
echo "📱 Or scan this QR code to copy it from your phone:"
echo
qrencode -t ansiutf8 < "${KEY}.pub"
echo
echo "✅ After adding, test with: ssh -T git@github.com"
