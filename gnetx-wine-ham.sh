#!/bin/bash
# ============================================================
#  GNETX Linux — Wine HAM add-on
#  Winlink Express + VARA FM (Wine) + Pat (nativno, povezan na VARA)
#  Ciljna distribucija: Debian 13 (trixie)
#  Callsign: S51DG
# ============================================================
# Zagon:  sudo bash gnetx-wine-ham.sh [mapa_z_installerji]
# Privzeta mapa installerjev: ~/Downloads
#
# Installerje prenesi ročno (verzije in URL-ji se spreminjajo):
#   Winlink Express : https://winlink.org/WinlinkExpress
#   VARA FM         : https://downloads.winlink.org/VARA%20Products/
# Skripta jih poišče po vzorcu imena (zip ali exe).
# ============================================================

set -u

if [[ $EUID -ne 0 ]]; then
  echo "[!] Zaženi kot root: sudo bash $0"
  exit 1
fi

CALLSIGN="S51DG"
GRID="JN76BB"
RUN_USER="${SUDO_USER:-$USER}"
RUN_HOME=$(getent passwd "$RUN_USER" | cut -d: -f6)
SRC_DIR="${1:-$RUN_HOME/Downloads}"
WPREFIX="$RUN_HOME/.wine-winlink"
LOG="/var/log/gnetx-wine-ham.log"

# Opcijsko: če želiš samodejni prenos, vpiši preverjena URL-ja
WINLINK_URL=""
VARAFM_URL=""

say()  { echo -e "\033[0;36m[*]\033[0m $1" | tee -a "$LOG"; }
ok()   { echo -e "\033[0;32m[✓]\033[0m $1" | tee -a "$LOG"; }
warn() { echo -e "\033[1;33m[!]\033[0m $1" | tee -a "$LOG"; }
asuser() { sudo -u "$RUN_USER" env HOME="$RUN_HOME" WINEPREFIX="$WPREFIX" WINEARCH=win32 WINEDEBUG=-all "$@"; }

# --- Arhitektura ---
ARCH=$(dpkg --print-architecture)
if [[ "$ARCH" != "amd64" ]]; then
  warn "Arhitektura $ARCH: Winlink Express in VARA sta x86 Windows programa."
  warn "Na arm64 Wine ne zažene x86 programov brez box64/FEX emulacije."
  warn "Priporočilo: na arm64 uporabi samo nativni Pat (in ARDOP/Direwolf)."
  exit 1
fi

# ============================================================
say "Namestitev Wine (32-bit podpora)"
dpkg --add-architecture i386
apt-get update -y >> "$LOG" 2>&1
apt-get install -y wine wine32 wine64 winetricks cabextract unzip \
  libasound2-plugins pulseaudio-utils >> "$LOG" 2>&1 \
  && ok "Wine nameščen" || { warn "Wine namestitev ni uspela, glej $LOG"; exit 1; }

# ============================================================
say "Ustvarjam ločen 32-bit Wine prefix: $WPREFIX"
asuser wineboot -u >> "$LOG" 2>&1
asuser winetricks -q win7 >> "$LOG" 2>&1
asuser winetricks -q corefonts vb6run pdh_nt4 >> "$LOG" 2>&1 \
  && ok "VARA odvisnosti (vb6run, pdh_nt4)" || warn "Preveri winetricks v $LOG"

say "Nameščam .NET 4.8 (potreben za Winlink Express, traja nekaj minut)"
asuser winetricks -q dotnet48 >> "$LOG" 2>&1 \
  && ok ".NET 4.8 nameščen" || warn ".NET namestitev: poskusi ročno 'winetricks dotnet48' kot $RUN_USER"

# ============================================================
find_installer() {
  # $1 = glob vzorec, išče v SRC_DIR
  find "$SRC_DIR" -maxdepth 1 -iname "$1" 2>/dev/null | sort -V | tail -n1
}

prepare_exe() {
  # sprejme zip ali exe, vrne pot do exe
  local f="$1"
  if [[ "$f" == *.zip || "$f" == *.ZIP ]]; then
    local d="/tmp/gnetx-wine-$(basename "$f" .zip)"
    rm -rf "$d"; mkdir -p "$d"
    unzip -qo "$f" -d "$d"
    find "$d" -iname "*.exe" | head -n1
  else
    echo "$f"
  fi
}

if [[ -n "$WINLINK_URL" ]]; then
  mkdir -p "$SRC_DIR"; wget -q "$WINLINK_URL" -P "$SRC_DIR" && ok "Winlink prenesen"
fi
if [[ -n "$VARAFM_URL" ]]; then
  mkdir -p "$SRC_DIR"; wget -q "$VARAFM_URL" -P "$SRC_DIR" && ok "VARA FM prenesen"
fi

# --- VARA FM ---
say "Iščem VARA FM installer v $SRC_DIR"
VARA_FILE=$(find_installer "*VARA*FM*")
if [[ -n "$VARA_FILE" ]]; then
  VARA_EXE=$(prepare_exe "$VARA_FILE")
  say "Zaganjam VARA FM installer: $VARA_EXE"
  asuser wine "$VARA_EXE" >> "$LOG" 2>&1 && ok "VARA FM nameščen" || warn "VARA FM installer javil napako"
else
  warn "VARA FM installer ni najden. Prenesi ga v $SRC_DIR in ponovno zaženi skripto."
fi

# --- Winlink Express ---
say "Iščem Winlink Express installer v $SRC_DIR"
WL_FILE=$(find_installer "*Winlink*Express*")
if [[ -n "$WL_FILE" ]]; then
  WL_EXE=$(prepare_exe "$WL_FILE")
  say "Zaganjam Winlink Express installer: $WL_EXE"
  asuser wine "$WL_EXE" >> "$LOG" 2>&1 && ok "Winlink Express nameščen" || warn "Winlink installer javil napako"
else
  warn "Winlink Express installer ni najden. Prenesi ga v $SRC_DIR in ponovno zaženi skripto."
fi

# ============================================================
say "Ustvarjam zaganjalnike"
BIN="/usr/local/bin"

cat > "$BIN/winlink-express" << EOF
#!/bin/bash
export WINEPREFIX="$WPREFIX" WINEARCH=win32 WINEDEBUG=-all
EXE=\$(find "\$WINEPREFIX/drive_c" -iname "RMS Express.exe" 2>/dev/null | head -n1)
[ -z "\$EXE" ] && { echo "Winlink Express ni nameščen v prefixu."; exit 1; }
cd "\$(dirname "\$EXE")" && exec wine "\$EXE" "\$@"
EOF

cat > "$BIN/vara-fm" << EOF
#!/bin/bash
export WINEPREFIX="$WPREFIX" WINEARCH=win32 WINEDEBUG=-all
EXE=\$(find "\$WINEPREFIX/drive_c" -iname "VARAFM.exe" 2>/dev/null | head -n1)
[ -z "\$EXE" ] && { echo "VARA FM ni nameščen v prefixu."; exit 1; }
cd "\$(dirname "\$EXE")" && exec wine "\$EXE" "\$@"
EOF

cat > "$BIN/gnetx-winecfg" << EOF
#!/bin/bash
export WINEPREFIX="$WPREFIX" WINEARCH=win32
exec winecfg
EOF
chmod +x "$BIN/winlink-express" "$BIN/vara-fm" "$BIN/gnetx-winecfg"
ok "Zaganjalniki: winlink-express, vara-fm, gnetx-winecfg"

# .desktop vnosi za LXDE
APPS="$RUN_HOME/.local/share/applications"
mkdir -p "$APPS"
cat > "$APPS/winlink-express.desktop" << EOF
[Desktop Entry]
Name=Winlink Express
Exec=winlink-express
Type=Application
Categories=HamRadio;Network;
Terminal=false
EOF
cat > "$APPS/vara-fm.desktop" << EOF
[Desktop Entry]
Name=VARA FM
Exec=vara-fm
Type=Application
Categories=HamRadio;Network;
Terminal=false
EOF
chown -R "$RUN_USER:$RUN_USER" "$APPS"

# ============================================================
say "Pat: nativna namestitev in povezava na VARA FM"
if ! command -v pat >/dev/null 2>&1; then
  warn "Pat ni nameščen. Zaženi najprej gnetx-postinstall.sh (HAM sekcija)."
else
  ok "Pat najden: $(command -v pat)"
  sudo -u "$RUN_USER" pat configure >/dev/null 2>&1 <<< "" || true
fi

PAT_NOTE="$RUN_HOME/gnetx-projects/ham/pat-vara-navodila.txt"
mkdir -p "$(dirname "$PAT_NOTE")"
cat > "$PAT_NOTE" << EOF
Pat + VARA FM (Wine) — navodila za $CALLSIGN ($GRID)
=====================================================
1. Zaženi VARA FM:        vara-fm
   Settings -> TCP Ports: Command port 8300 (data port 8301 se nastavi sam)
   Settings -> Soundcard: izberi vhod/izhod za radio, PTT po potrebi (CAT/serial/VOX)

2. V ~/.config/pat/config.json dodaj/uredi:
     "varafm": {
       "addr": "localhost:8300",
       "bandwidth": 0
     },
     "mycall": "$CALLSIGN",
     "locator": "$GRID"
   Če imaš VARA FM na drugih vratih, popravi "addr".

3. Povezava:
     pat connect varafm:///NEKI_RMS_CALL
   Spletni vmesnik:  pat http   (http://localhost:8080)

4. Winlink Express in Pat ne smeta hkrati uporabljati istega VARA modema/zvočne kartice.
   Izberi enega.

5. Za HF uporabljaš VARA HF (loči se od VARA FM, ima svoj installer in "varahf" blok v Pat configu).
EOF
chown -R "$RUN_USER:$RUN_USER" "$RUN_HOME/gnetx-projects" 2>/dev/null
ok "Navodila: $PAT_NOTE"

# ============================================================
# Dostop do serijskih portov (CAT/PTT)
usermod -aG dialout,audio "$RUN_USER" && ok "Uporabnik dodan v dialout in audio"

echo ""
say "Končano. Odjavi se in prijavi znova (skupine dialout/audio)."
say "Zagon: startx -> terminal -> vara-fm  /  winlink-express"
say "Log: $LOG"
