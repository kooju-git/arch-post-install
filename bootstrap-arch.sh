#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# ARCH LINUX BOOTSTRAP SCRIPT
# ==============================================================================
# Purpose:  Full system setup after a fresh Arch install.
# Features: Configures Pacman (Multilib, Chaotic-AUR, ParallelDownloads),
#           updates mirrors, installs Yay, installs KDE Plasma stack,
#           installs specific Chaotic-AUR apps, sets up locales/bootloader.
# Security: Generic script. No personal data or hardcoded credentials.
# Usage:    Run with sudo: sudo ./bootstrap_combined.sh
# ==============================================================================

# --- Configuration Variables ---
PACCONF="/etc/pacman.conf"
PACCONF_BAK="/etc/pacman.conf.$(date +%Y%m%d-%H%M%S).bak"
MIRRORLIST="/etc/pacman.d/mirrorlist"

# Chaotic AUR settings
CHAOTIC_KEY="3056513887B78AEB"
CHAOTIC_KEYRING_URL="https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst"
CHAOTIC_MIRRORLIST_URL="https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst"

# Locale settings
LOCALE_EN="en_US.UTF-8"
LOCALE_BE="nl_BE.UTF-8"

# --- Helper Functions ---
log()  { printf '\033[1;32m[info]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; }

# ==============================================================================
# 1. PRE-FLIGHT CHECKS
# ==============================================================================

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    err "Please run this script with sudo."
    exit 1
fi

# Identify the actual user (for building yay)
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    BUILD_USER="$SUDO_USER"
    log "User detected: $BUILD_USER"
else
    err "No non-root user detected. Do not run this from a root shell, use 'sudo ./script.sh'."
    exit 1
fi

# ==============================================================================
# 2. NETWORK & MIRRORS
# ==============================================================================

log "Updating Pacman database..."
pacman -Sy --noconfirm

log "Installing base dependencies (git, base-devel, reflector)..."
pacman -S --needed --noconfirm git base-devel go reflector rsync

if command -v reflector >/dev/null 2>&1; then
    log "Optimizing mirrorlist (Fastest 5, HTTPS, sorted by rate)..."
    # Backup existing mirrorlist if not already backed up today
    [[ ! -f "${MIRRORLIST}.bak" ]] && cp "$MIRRORLIST" "${MIRRORLIST}.bak"
    
    reflector --protocol https --latest 20 --sort rate --fastest 5 --save "$MIRRORLIST"
else
    warn "Reflector not found. Skipping mirror optimization."
fi

# ==============================================================================
# 3. PACMAN CONFIGURATION (Parallel Downloads, Multilib, Chaotic)
# ==============================================================================
log "Optimizing pacman.conf..."

# Backup pacman.conf
cp -a "$PACCONF" "$PACCONF_BAK"

# Create temp file for the new config
tmp_conf="$(mktemp)"

# Clean comments and empty lines first
sed -E -e 's/^[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$PACCONF" > "$tmp_conf"

# Use awk to enforce: Color, ParallelDownloads, ILoveCandy, and [multilib]
awk '
  BEGIN{inopt=0; haveColor=0; haveCandy=0; havePar=0; in_m=0; done_m=0}
  /^\[options\]/ { print; inopt=1; next }
  /^\[multilib\]/ { if(!done_m){ print "[multilib]"; print "Include = /etc/pacman.d/mirrorlist"; done_m=1 } in_m=1; next }
  /^\[.*\]/ {
    if(inopt){
       if(!haveColor) print "Color";
       if(!havePar)   print "ParallelDownloads = 5";
       if(!haveCandy) print "ILoveCandy";
    }
    inopt=0; in_m=0; print; next
  }
  {
    if(inopt){
      if($0 ~ /Color/){ if(!haveColor){print "Color"; haveColor=1}; next }
      if($0 ~ /ILoveCandy/){ if(!haveCandy){print "ILoveCandy"; haveCandy=1}; next }
      if($0 ~ /ParallelDownloads/){ print "ParallelDownloads = 5"; havePar=1; next }
    }
    if(in_m) next;
    print
  }
  END{
    if(inopt){ if(!haveColor) print "Color"; if(!havePar) print "ParallelDownloads = 5"; if(!haveCandy) print "ILoveCandy"; }
    if(!done_m){ print ""; print "[multilib]"; print "Include = /etc/pacman.d/mirrorlist"; }
  }
' "$tmp_conf" > "${tmp_conf}.2" && mv "${tmp_conf}.2" "$tmp_conf"

# Apply the new config
install -m 0644 -o root -g root "$tmp_conf" "$PACCONF"
rm -f "$tmp_conf"

# Sync to enable Multilib
log "Syncing databases (Multilib enabled)..."
pacman -Syy --noconfirm

# ==============================================================================
# 4. CHAOTIC AUR SETUP
# ==============================================================================
log "Setting up Chaotic-AUR..."

# 1. Keys
pacman-key --init
if ! pacman-key --list-keys "$CHAOTIC_KEY" >/dev/null 2>&1; then
    log "Importing and signing Chaotic-AUR key..."
    pacman-key --recv-key "$CHAOTIC_KEY" --keyserver keyserver.ubuntu.com
    pacman-key --lsign-key "$CHAOTIC_KEY"
fi

# 2. Install Keyring & Mirrorlist
if ! pacman -Qi chaotic-keyring >/dev/null 2>&1; then
    pacman -U --noconfirm "$CHAOTIC_KEYRING_URL" "$CHAOTIC_MIRRORLIST_URL" || warn "Failed to install Chaotic keyring from URL."
fi

# 3. Append [chaotic-aur] to pacman.conf if not present
if ! grep -q "^\[chaotic-aur\]" "$PACCONF"; then
    log "Adding Chaotic-AUR to pacman.conf..."
    cat <<EOF >> "$PACCONF"

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
fi

pacman -Syy --noconfirm

# ==============================================================================
# 5. INSTALL YAY (AUR HELPER)
# ==============================================================================

if ! command -v yay >/dev/null 2>&1; then
    log "Yay not found. Building from source..."
    TMPDIR="$(mktemp -d)"
    chown "$BUILD_USER:$BUILD_USER" "$TMPDIR"
    
    sudo -u "$BUILD_USER" bash -lc "
      set -e
      cd '$TMPDIR'
      git clone 'https://aur.archlinux.org/yay.git'
      cd yay
      makepkg -si --noconfirm
    "
    rm -rf "$TMPDIR"
else
    log "Yay is already installed."
fi

# ==============================================================================
# 6. SOFTWARE INSTALLATION
# ==============================================================================
log "Installing software packages..."

# Microcode & Bootloader
pacman -S --needed --noconfirm intel-ucode
mkdir -p /boot/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Desktop Environment (KDE Plasma)
pacman -S --needed --noconfirm plasma-desktop plasma-wayland-session kwayland-integration breeze sddm sddm-kcm

# System Tools
pacman -S --needed --noconfirm kde-system-settings dolphin konsole networkmanager plasma-nm \
    dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers kimageformats qt6-imageformats

# Desktop Apps
pacman -S --needed --noconfirm kfind gwenview kate ark print-manager libreoffice-fresh mpv alacritty

# Fonts
pacman -S --needed --noconfirm nerd-fonts-noto-sans-mono gnu-free-fonts noto-fonts ttf-jetbrains-mono

# Utilities
pacman -S --needed --noconfirm numlockx vi nano less ntfs-3g dosfstools nfs-utils usbutils bash-completion \
    gparted stow fastfetch veracrypt syncthing

# Flatpak
pacman -S --needed --noconfirm flatpak plasma-discover packagekit-flatpak

# Chaotic AUR Specific Apps
log "Installing Chaotic-AUR applications..."
pacman -S --needed --noconfirm \
    chaotic-aur/preload \
    chaotic-aur/zen-browser-bin \
    chaotic-aur/freetube-bin \
    chaotic-aur/synology-drive

# ==============================================================================
# 7. SYSTEM CONFIGURATION
# ==============================================================================

# Locales
log "Configuring locales..."
sed -i -E "s/^#\s*(${LOCALE_EN//./\\.}\s+UTF-8)/\1/" /etc/locale.gen
sed -i -E "s/^#\s*(${LOCALE_BE//./\\.}\s+UTF-8)/\1/" /etc/locale.gen
locale-gen

localectl set-locale \
  LANG=${LOCALE_EN} \
  LC_MESSAGES=${LOCALE_EN} \
  LC_NUMERIC=${LOCALE_BE} \
  LC_TIME=${LOCALE_BE} \
  LC_MONETARY=${LOCALE_BE} \
  LC_PAPER=${LOCALE_BE} \
  LC_NAME=${LOCALE_BE} \
  LC_ADDRESS=${LOCALE_BE} \
  LC_TELEPHONE=${LOCALE_BE} \
  LC_MEASUREMENT=${LOCALE_BE} \
  LC_IDENTIFICATION=${LOCALE_BE} \
  LC_COLLATE=${LOCALE_BE} \
  LC_CTYPE=${LOCALE_BE}

# SDDM Numlock
if [[ ! -f /etc/sddm.conf.d/10-numlock.conf ]]; then
    mkdir -p /etc/sddm.conf.d
    printf "[General]\nNumlock=on\n" > /etc/sddm.conf.d/10-numlock.conf
fi

# Enable Services
log "Enabling system services..."
systemctl enable sddm.service
systemctl enable NetworkManager.service

# Enable Preload (daemon)
log "Enabling Preload daemon..."
systemctl enable preload.service

# ==============================================================================
# 8. FINISH
# ==============================================================================

echo ""
log "Bootstrap complete!"
log "A reboot is recommended to apply all changes."
