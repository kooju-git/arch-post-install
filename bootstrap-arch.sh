#!/usr/bin/env bash
set -euo pipefail

# --- self-delete als het script succesvol eindigt ---
# SELF="${BASH_SOURCE[0]:-$0}"
# trap 'status=$?;
#       if (( status == 0 )) && [[ -f "$SELF" && -w "$SELF" && -O "$SELF" ]]; then
#         rm -f -- "$SELF"
#       fi' EXIT

# Installeert: reflector, rsync, yay (from source)
# Installeert micro-code updates
# Installeert basis packages
# Installeert KDE
# Haalt bootstrap-ssh.sh script op

YAY_REPO="https://aur.archlinux.org/yay.git"
PACCONF="/etc/pacman.conf"
BACKUP="/etc/pacman.conf.$(date +%Y%m%d-%H%M%S).bak"

log()  { printf '\033[1;32m[info]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; }

# --- sudo & build user ---
if [[ $EUID -ne 0 && -z "${SUDO_USER:-}" ]]; then err "Run met: sudo $0"; exit 1; fi
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  BUILD_USER="$SUDO_USER"
else
  err "Geen niet-root gebruiker gedetecteerd (SUDO_USER). Start met: sudo $0"; exit 1
fi

# --- updates & basis ---
log "Pacman databases updaten en systeem bijwerken…"
pacman -Syu --noconfirm

log "Benodigdheden installeren (git, base-devel, go, reflector, rsync)…"
pacman -S --needed --noconfirm git base-devel go reflector rsync

# --- yay (from source) ---
if ! command -v yay >/dev/null 2>&1; then
  log "yay niet gevonden; bouwen uit AUR (from source)…"
  TMPDIR="$(mktemp -d)"
  chown "$BUILD_USER:$BUILD_USER" "$TMPDIR"
  sudo -u "$BUILD_USER" bash -lc "
    set -e
    cd '$TMPDIR'
    git clone '$YAY_REPO'
    cd yay
    makepkg -si --noconfirm
  "
  rm -rf "$TMPDIR"
else
  log "yay is al geïnstalleerd: $(yay --version | head -n1)"
fi

# --- mirrorlist optimaliseren ---
log "Mirrorlist optimaliseren met reflector…"
if ! reflector --latest 10 --sort rate --fastest 5 --save /etc/pacman.d/mirrorlist 2>/dev/null; then
  warn "reflector met --fastest faalde; val terug op sort-by-rate"
  reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
fi

# --- pacman.conf backup ---
log "Backup van pacman.conf -> $BACKUP"
cp -a "$PACCONF" "$BACKUP"

# --- resync ---
log "Systeem opnieuw synchroniseren na pacman.conf/mirrorlist wijzigingen…"
pacman -Syu --noconfirm

# --- microcode updates ---
pacman -S intel-ucode --noconfirm
grub-mkconfig -o /boot/grub/grub.cfg

# --- basis packages ---
pacman -S --needed --noconfirm fastfetch alacritty vi nano stow bash-completion gnu-free-fonts noto-fonts ttf-jetbrains-mono firefox htop ntfs-3g dosfstools man

# --- kde ---
pacman -S --needed --noconfirm plasma-meta kde-applications
systemctl enable sddm.service

# --- ssh script ---
curl -L -o bootstrap-ssh.sh https://raw.githubusercontent.com/kooju-git/arch-post-install/main/bootstrap-ssh.sh

echo
log "Klaar. Gelieve te rebooten."
