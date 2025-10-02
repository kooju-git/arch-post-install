#!/usr/bin/env bash
set -euo pipefail

# Installeert: reflector, rsync, yay (from source)
# Past pacman.conf veilig aan binnen [options] en schakelt multilib in.
# => Zorgt dat /etc/pacman.conf eindigt met root:root en mode 644.
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

# --- [options] sectie veilig normaliseren ---
tmp="$(mktemp)"
awk '
  BEGIN{inopt=0; haveColor=0; havePar=0; haveCandy=0}
  /^\[.*\]$/{
    if(inopt){
      if(!haveColor)  print "Color"
      if(!havePar)    print "ParallelDownloads = 5"
      if(!haveCandy)  print "ILoveCandy"
    }
    print
    inopt = ($0=="[options]")
    next
  }
  {
    if(inopt){
      if($0 ~ /^[[:space:]]*#?[[:space:]]*Color([[:space:]]|$)/){ if(!haveColor){ print "Color"; haveColor=1 }; next }
      if($0 ~ /^[[:space:]]*#?[[:space:]]*ParallelDownloads[[:space:]]*=/){ print "ParallelDownloads = 5"; havePar=1; next }
      if($0 ~ /^[[:space:]]*ILoveCandy([[:space:]]|$)/){ haveCandy=1 }
    }
    print
  }
  END{
    if(inopt){
      if(!haveColor)  print "Color"
      if(!havePar)    print "ParallelDownloads = 5"
      if(!haveCandy)  print "ILoveCandy"
    }
  }
' "$PACCONF" > "$tmp"

# Plaats met correcte perms (root:root, 644)
install -m 644 -o root -g root "$tmp" "$PACCONF"
rm -f "$tmp"

# --- multilib inschakelen binnen eigen sectie ---
sed -i -E 's/^[#[:space:]]*\[multilib\]/[multilib]/' "$PACCONF"
sed -i -E '/^\[multilib\]/,/^\[/{s|^[#[:space:]]*Include *= */etc/pacman.d/mirrorlist|Include = /etc/pacman.d/mirrorlist|}' "$PACCONF"

# verzeker juiste perms (mocht sed iets aangepast hebben)
chown root:root "$PACCONF"
chmod 644 "$PACCONF"

# --- resync ---
log "Systeem opnieuw synchroniseren na pacman.conf/mirrorlist wijzigingen…"
pacman -Syu --noconfirm

# --- microcode updates ---
pacman -S intel-ucode --noconfirm
grub-mkconfig -o /boot/grub/grub.cfg

# --- basis packages ---
pacman -S --needed --noconfirm fastfetch alacritty vi nano stow bash-completion gnu-free-fonts noto-fonts ttf-jetbrains-mono firefox

# --- kde ---
pacman -S --needed --noconfirm plasma-meta kde-applications
systemctl enable sddm.service
systemctl start sddm.service

# --- ssh script ---
curl -L -o bootstrap-ssh.sh https://raw.githubusercontent.com/kooju-git/arch-post-install/main/bootstrap-ssh.sh

echo
log "Klaar. Gelieve te rebooten."
