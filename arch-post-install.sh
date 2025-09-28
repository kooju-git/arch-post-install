#!/usr/bin/env bash
set -euo pipefail

# Tools
sudo pacman -Syu --noconfirm git stow openssh

# Ensure ~/.ssh exists with safe perms
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

KEY="$HOME/.ssh/id_ed25519"

# Generate key only if missing (will PROMPT for passphrase)
if [[ ! -f "$KEY" ]]; then
  ssh-keygen -t ed25519 -C "kooju-git@kooju-labs.org" -f "$KEY"
  chmod 600 "$KEY"
  chmod 644 "${KEY}.pub"
else
  echo "SSH key already exists at $KEY (skipping generation)."
fi

# Start agent and add the key (prompts for passphrase once)
eval "$(ssh-agent -s)"
ssh-add "$KEY"

echo
echo "Add this SSH PUBLIC key to GitHub (Settings → SSH and GPG keys):"
echo
cat "${KEY}.pub"
echo
echo "Test after adding: ssh -T git@github.com"
