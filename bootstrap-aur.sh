#!/usr/bin/env bash
set -euo pipefail

# ---- Instellingen / Flags ----------------------------------------------------

YAY_REPO="https://aur.archlinux.org/yay.git"
PACCONF="/etc/pacman.conf"
PACCONF_BAK="/etc/pacman.conf.$(date +%Y%m%d-%H%M%S).bak"

MIRRORLIST="/etc/pacman.d/mirrorlist"
MIRRORLIST_BAK="/etc/pacman.d/mirrorlist.$(date +%Y%m%d-%H%M%S).bak"

CHAOTIC_KEY="3056513887B78AEB"
CHAOTIC_KEYRING_URL="https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst"
CHAOTIC_MIRRORLIST_URL="https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst"

INSTALL_YAY=false
ENABLE_CHAOTIC=false
UPDATE_MIRROR=false

usage() {
  cat <<EOF
Gebruik: sudo $0 [opties]

Opties:
  -y, --install-yay     Installeer 'yay' uit AUR (from source)
  -c, --enable-chaotic  Schakel Chaotic-AUR in (key, keyring, mirrorlist, repo)
  -m, --update-mirror   Update mirrorlist
  -h, --help            Toon deze hulp

Standaard wordt de mirrorlist geüpdatet (5 snelste) en pacman.conf "clean" herschreven.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--install-yay) INSTALL_YAY=true; shift ;;
    -c|--enable-chaotic) ENABLE_CHAOTIC=true; shift ;;
    -m|--update-mirror) UPDATE_MIRROR=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Onbekende optie: $1"; usage; exit 2 ;;
  esac
done

# ---- Helpers ----------------------------------------------------------------

log()  { printf '\033[1;32m[info]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Run dit script met sudo/root."
    exit 1
  fi
}

get_build_user_or_die() {
  # Nodig als we yay gaan bouwen
  if [[ "${INSTALL_YAY}" == true ]]; then
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
      echo "$SUDO_USER"
      return 0
    fi
    err "Voor het bouwen van yay is een niet-root gebruiker nodig (SUDO_USER ontbreekt). Run met: sudo $0"
    exit 1
  fi
  echo ""  # niet gebruikt
}

clean_tmp() {
  [[ -n "${1:-}" && -e "$1" ]] && rm -f "$1" || true
}

# ---- Start ------------------------------------------------------------------

require_root
BUILD_USER="$(get_build_user_or_die)"

log "Pacman database bijwerken en systeem upgraden…"
pacman -Syu --noconfirm

log "Benodigdheden installeren (git, base-devel, go, reflector, rsync)…"
pacman -S --needed --noconfirm git base-devel go reflector rsync

# ---- Optioneel: yay bouwen/installen ----------------------------------------
if [[ "${INSTALL_YAY}" == true ]]; then
  if ! command -v yay >/dev/null 2>&1; then
    log "yay niet gevonden; bouwen uit AUR…"
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
else
  log "Installatie van yay overgeslagen (geen --install-yay)."
fi

# ---- Optioneel: Chaotic-AUR key/keyring/mirrorlist --------------------------
if [[ "${ENABLE_CHAOTIC}" == true ]]; then
  pacman-key --init
  # Key
  if ! pacman-key --list-keys "$CHAOTIC_KEY" >/dev/null 2>&1; then
    log "Chaotic AUR key importeren en lokaal tekenen…"
    pacman-key --recv-key "$CHAOTIC_KEY" --keyserver keyserver.ubuntu.com
    pacman-key --lsign-key "$CHAOTIC_KEY"
  else
    log "Chaotic AUR key reeds aanwezig."
  fi

  # Pakketten
  if ! pacman -Qi chaotic-keyring >/dev/null 2>&1; then
    log "chaotic-keyring installeren…"
    pacman -U --noconfirm "$CHAOTIC_KEYRING_URL"
  else
    log "chaotic-keyring is al geïnstalleerd."
  fi
  if ! pacman -Qi chaotic-mirrorlist >/dev/null 2>&1; then
    log "chaotic-mirrorlist installeren…"
    pacman -U --noconfirm "$CHAOTIC_MIRRORLIST_URL"
  else
    log "chaotic-mirrorlist is al geïnstalleerd."
  fi
else
  log "Chaotic-AUR configuratie overgeslagen (geen --enable-chaotic)."
fi

# ---- pacman.conf "clean" herschrijven ---------------------------------------
log "pacman.conf backuppen -> $PACCONF_BAK"
cp -a "$PACCONF" "$PACCONF_BAK"

tmp_stripped="$(mktemp)"
tmp_norm_opt="$(mktemp)"
tmp_multilib="$(mktemp)"
tmp_final="$(mktemp)"

# 1) Verwijder alle commented regels + lege regels
#    (Hou enkel de originele ongecommentarieerde inhoud over)
sed -E -e 's/^[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$PACCONF" > "$tmp_stripped"

# 2) Normaliseer [options]: afdwingen Color, ParallelDownloads=5, ILoveCandy
awk '
  BEGIN{inopt=0; haveColor=0; haveCandy=0; havePar=0}
  /^\[.*\]$/ {
    if(inopt){
      if(!haveColor) print "Color";
      if(!havePar)   print "ParallelDownloads = 5";
      if(!haveCandy) print "ILoveCandy";
    }
    print;
    inopt = ($0=="[options]");
    # reset flags for new [options] if any
    if(inopt){ haveColor=0; haveCandy=0; havePar=0 }
    next
  }
  {
    if(inopt){
      if($0 ~ /^[[:space:]]*Color([[:space:]]|$)/){ if(!haveColor){ print "Color"; haveColor=1 }; next }
      if($0 ~ /^[[:space:]]*ILoveCandy([[:space:]]|$)/){ if(!haveCandy){ print "ILoveCandy"; haveCandy=1 }; next }
      if($0 ~ /^[[:space:]]*ParallelDownloads[[:space:]]*=/){ print "ParallelDownloads = 5"; havePar=1; next }
    }
    print
  }
  END{
    if(inopt){
      if(!haveColor) print "Color";
      if(!havePar)   print "ParallelDownloads = 5";
      if(!haveCandy) print "ILoveCandy";
    }
  }
' "$tmp_stripped" > "$tmp_norm_opt"

# 3) Dwing [multilib] af (exact blok), voeg toe als ontbreekt
awk '
  BEGIN{in_m=0; done=0}
  /^\[multilib\]$/ {
    if(!done){
      print "[multilib]";
      print "Include = /etc/pacman.d/mirrorlist";
      done=1;
    }
    in_m=1; next
  }
  /^\[.*\]$/ {
    if(in_m){ in_m=0 } # voorbij de multilib-sectie
  }
  {
    if(!in_m) print
  }
  END{
    if(!done){
      print "";
      print "[multilib]";
      print "Include = /etc/pacman.d/mirrorlist";
    }
  }
' "$tmp_norm_opt" > "$tmp_multilib"

# 4) Optioneel: [chaotic-aur] afdwingen
if [[ "${ENABLE_CHAOTIC}" == true ]]; then
  log "Chaotic-AUR repo in pacman.conf afdwingen…"
  awk '
    BEGIN{in_c=0; done=0}
    /^\[chaotic-aur\]$/ {
      if(!done){
        print "[chaotic-aur]";
        print "Include = /etc/pacman.d/chaotic-mirrorlist";
        done=1;
      }
      in_c=1; next
    }
    /^\[.*\]$/ {
      if(in_c){ in_c=0 }
    }
    {
      if(!in_c) print
    }
    END{
      if(!done){
        print "";
        print "[chaotic-aur]";
        print "Include = /etc/pacman.d/chaotic-mirrorlist";
      }
    }
  ' "$tmp_multilib" > "$tmp_final"
else
  cp -a "$tmp_multilib" "$tmp_final"
fi

# 5) Vervang pacman.conf en herstel permissies
install -m 0644 -o root -g root "$tmp_final" "$PACCONF"
clean_tmp "$tmp_stripped"
clean_tmp "$tmp_norm_opt"
clean_tmp "$tmp_multilib"
clean_tmp "$tmp_final"

# ---- Mirrorlist updaten met reflector ---------------------------------------
if [[ "${UPDATE_MIRROR}" == true ]]; then
  if command -v reflector >/dev/null 2>&1; then
    log "Mirrorlist backuppen -> $MIRRORLIST_BAK (indien aanwezig)…"
    [[ -f "$MIRRORLIST" ]] && cp -a "$MIRRORLIST" "$MIRRORLIST_BAK" || true
    log "Mirrorlist updaten (5 snelste, https, gesorteerd op snelheid)…"
    reflector --protocol https --latest 20 --sort rate --fastest 5 --save "$MIRRORLIST"
    chown root:root "$MIRRORLIST"
    chmod 0644 "$MIRRORLIST"
  else
    warn "reflector niet gevonden (zou geïnstalleerd moeten zijn). Mirrorlist niet geüpdatet."
  fi
else
  log "Update van mirror overgeslagen (geen --update-mirror)."
fi

# ---- Resync ------------------------------------------------------------------
log "Systeem opnieuw synchroniseren na wijzigingen…"
pacman -Syyu --noconfirm

echo
log "Klaar."
if [[ "${ENABLE_CHAOTIC}" == true ]]; then
  echo "Snelle checks:"
  echo "  grep -A1 '^\[chaotic-aur\]' /etc/pacman.conf"
  echo "  pacman -Sl chaotic-aur | head      # repo zichtbaar?"
fi
