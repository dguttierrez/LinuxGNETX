#!/bin/bash
# ============================================================
#  GNETX Linux — Post-install skript
#  HAM radio orodja + Varnostna orodja
#  Ciljna distribucija: Debian 13 (trixie)
#  Avtor: GNETX Project | S51DG
#  Datum: 2026-10-28
# ============================================================
# Zagon: sudo bash gnetx-postinstall.sh
# ============================================================

set -e

# --- Zaznaj Debian codename (za backports fallback ipd.) ---
DEBIAN_CODENAME=$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-trixie}")

# --- Barve za izpis ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Preveri root ---
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[!] Ta skript mora teči kot root. Uporabi: sudo bash $0${NC}"
  exit 1
fi

# --- Spremenljivke ---
LOGFILE="/var/log/gnetx-postinstall.log"
INSTALL_USER="${SUDO_USER:-$USER}"
INSTALL_HOME=$(eval echo "~$INSTALL_USER")

log() { echo -e "$1" | tee -a "$LOGFILE"; }
section() { log "\n${CYAN}${BOLD}══════════════════════════════════════════${NC}"; log "${CYAN}${BOLD}  $1${NC}"; log "${CYAN}${BOLD}══════════════════════════════════════════${NC}"; }
ok()      { log "${GREEN}[✓]${NC} $1"; }
warn()    { log "${YELLOW}[!]${NC} $1"; }
err()     { log "${RED}[✗]${NC} $1"; }
info()    { log "${BLUE}[i]${NC} $1"; }

# --- Meni za izbiro ---
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       GNETX Post-Install Setup           ║"
echo "  ║   HAM Radio + Security Tools             ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "Kaj želiš namestiti?\n"
echo "  [1] Samo HAM radio orodja"
echo "  [2] Samo varnostna orodja"
echo "  [3] Vse (HAM + Security)"
echo "  [4] Izhod"
echo ""
read -rp "Izbira [1-4]: " CHOICE

case $CHOICE in
  1) DO_HAM=1; DO_SEC=0 ;;
  2) DO_HAM=0; DO_SEC=1 ;;
  3) DO_HAM=1; DO_SEC=1 ;;
  4) echo "Izhod."; exit 0 ;;
  *) echo -e "${RED}Neveljavna izbira.${NC}"; exit 1 ;;
esac

mkdir -p "$(dirname $LOGFILE)"
log "=== GNETX post-install started: $(date) ==="
info "Nameščam za uporabnika: $INSTALL_USER (home: $INSTALL_HOME)"

# ============================================================
# OSNOVA — skupna za oba
# ============================================================
section "Posodabljanje sistema"
apt-get update -y >> "$LOGFILE" 2>&1 && ok "apt update" || err "apt update failed"
apt-get upgrade -y >> "$LOGFILE" 2>&1 && ok "apt upgrade" || warn "apt upgrade — preveri log"

apt-get install -y \
  build-essential \
  git \
  wget \
  curl \
  python3 \
  python3-pip \
  python3-venv \
  libusb-1.0-0-dev \
  cmake \
  pkg-config \
  usbutils \
  >> "$LOGFILE" 2>&1 && ok "Osnovna orodja nameščena"

# ============================================================
# HAM RADIO ORODJA
# ============================================================
if [[ $DO_HAM -eq 1 ]]; then

section "HAM Radio — Hamlib (rig control)"
apt-get install -y \
  hamlib-utils \
  libhamlib-dev \
  libhamlib4 \
  >> "$LOGFILE" 2>&1 && ok "Hamlib nameščen" || err "Hamlib — napaka"

section "HAM Radio — WSJT-X (FT8, FT4, WSPR, JT65...)"
# WSJT-X iz Debian repota
apt-get install -y wsjtx >> "$LOGFILE" 2>&1 \
  && ok "WSJT-X nameščen" \
  || {
    warn "WSJT-X ni v glavnem repoju — poskušam iz ${DEBIAN_CODENAME}-backports"
    echo "deb http://deb.debian.org/debian ${DEBIAN_CODENAME}-backports main" \
      > /etc/apt/sources.list.d/backports.list
    apt-get update -y >> "$LOGFILE" 2>&1
    apt-get install -y -t "${DEBIAN_CODENAME}-backports" wsjtx >> "$LOGFILE" 2>&1 \
      && ok "WSJT-X nameščen iz backports" \
      || warn "WSJT-X ni dostopen — namesti ročno iz https://wsjt.sourceforge.io"
  }

section "HAM Radio — Fldigi (digitalni modusi: PSK31, RTTY, Olivia...)"
apt-get install -y \
  fldigi \
  flrig \
  flmsg \
  flamp \
  >> "$LOGFILE" 2>&1 && ok "Fldigi suite nameščena" || err "Fldigi — napaka"

section "HAM Radio — Direwolf (APRS TNC softver)"
apt-get install -y direwolf >> "$LOGFILE" 2>&1 \
  && ok "Direwolf nameščen" \
  || {
    warn "Direwolf ni v repotu — gradim iz izvora"
    cd /tmp
    git clone https://github.com/wb2osz/direwolf.git >> "$LOGFILE" 2>&1
    cd direwolf
    mkdir build && cd build
    cmake .. >> "$LOGFILE" 2>&1
    make -j$(nproc) >> "$LOGFILE" 2>&1
    make install >> "$LOGFILE" 2>&1
    ok "Direwolf zgrajen iz izvora"
    cd /tmp && rm -rf direwolf
  }

section "HAM Radio — GQRX + SDR (Software Defined Radio)"
apt-get install -y \
  gqrx-sdr \
  rtl-sdr \
  gr-osmosdr \
  gnuradio \
  cubicsdr \
  >> "$LOGFILE" 2>&1 && ok "SDR orodja nameščena" || err "SDR — napaka"

# RTL-SDR udev pravila
if ! grep -q "rtl-sdr" /etc/udev/rules.d/rtl-sdr.rules 2>/dev/null; then
  cat > /etc/udev/rules.d/rtl-sdr.rules << 'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", GROUP="plugdev", MODE="0666", SYMLINK+="rtl_sdr"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", GROUP="plugdev", MODE="0666", SYMLINK+="rtl_sdr"
EOF
  udevadm control --reload-rules
  ok "RTL-SDR udev pravila dodana"
fi

# Dodaj uporabnika v plugdev skupino
usermod -aG plugdev "$INSTALL_USER" && ok "Uporabnik $INSTALL_USER dodan v plugdev"

section "HAM Radio — PAT Winlink (radio email)"
PAT_VER="0.15.0"
PAT_ARCH="amd64"
if [[ "$(uname -m)" == "aarch64" ]]; then PAT_ARCH="arm64"; fi
PAT_DEB="pat_${PAT_VER}_linux_${PAT_ARCH}.deb"
PAT_URL="https://github.com/la5nta/pat/releases/download/v${PAT_VER}/${PAT_DEB}"

wget -q "$PAT_URL" -O "/tmp/${PAT_DEB}" >> "$LOGFILE" 2>&1 \
  && dpkg -i "/tmp/${PAT_DEB}" >> "$LOGFILE" 2>&1 \
  && ok "PAT Winlink nameščen (v${PAT_VER})" \
  || warn "PAT — prenesi ročno: https://github.com/la5nta/pat/releases"

rm -f "/tmp/${PAT_DEB}"

section "HAM Radio — CHIRP (programiranje radiev)"
apt-get install -y chirp >> "$LOGFILE" 2>&1 \
  && ok "CHIRP nameščen" \
  || {
    warn "CHIRP iz apt ni dostopen — nameščam pip verzijo"
    pip3 install chirp --break-system-packages >> "$LOGFILE" 2>&1 \
      && ok "CHIRP (pip) nameščen" \
      || warn "CHIRP — namesti ročno iz https://chirp.danplanet.com"
  }

section "HAM Radio — JS8Call (slaba signalna digitalna komunikacija)"
warn "JS8Call ni v Debian repotu. Prenesi .deb ročno z:"
warn "  http://js8call.com/download/"
info "Po prenosu: sudo dpkg -i js8call_*.deb"

section "HAM Radio — APRS konfiguracija (Direwolf)"
DIREWOLF_CONF="$INSTALL_HOME/.config/direwolf.conf"
mkdir -p "$INSTALL_HOME/.config"
if [[ ! -f "$DIREWOLF_CONF" ]]; then
  cat > "$DIREWOLF_CONF" << 'EOF'
# Direwolf APRS konfiguracija za GNETX / S51DG
# Prilagodi MYCALL, ADEVICE in PBEACON po potrebi

MYCALL S51DG-9
MODEM 1200
ADEVICE plughw:0,0

# APRS iGate (odkomentiraj za iGate)
# IGSERVER euro.aprs2.net
# IGLOGIN S51DG-9 <passcode>

# APRS beacon (odkomentiraj in prilagodi)
# PBEACON delay=1 every=30 symbol="/" lat=46.05 long=14.51 \
#   comment="GNETX APRS | S51DG | JN76BB"

# Filtriranje (odkomentiraj za lokalni filter)
# FILTER IG 0 r/46.05/14.51/50
EOF
  chown "$INSTALL_USER:$INSTALL_USER" "$DIREWOLF_CONF"
  ok "Direwolf template config ustvarjen: $DIREWOLF_CONF"
fi

section "HAM Radio — systemd storitev za Direwolf"
cat > /etc/systemd/system/direwolf.service << EOF
[Unit]
Description=Direwolf APRS TNC
After=network.target sound.target

[Service]
User=$INSTALL_USER
ExecStart=/usr/bin/direwolf -c $DIREWOLF_CONF -t 0
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
ok "Direwolf systemd servis ustvarjen (ni avtomatično omogočen)"
info "Za zagon: sudo systemctl enable --now direwolf"

fi  # konec HAM sekcije

# ============================================================
# VARNOSTNA ORODJA
# ============================================================
if [[ $DO_SEC -eq 1 ]]; then

section "Security — Mrežna orodja"
apt-get install -y \
  nmap \
  masscan \
  netcat-openbsd \
  tcpdump \
  wireshark \
  tshark \
  net-tools \
  traceroute \
  dnsutils \
  whois \
  arp-scan \
  >> "$LOGFILE" 2>&1 && ok "Mrežna orodja nameščena"

# Wireshark brez roota
usermod -aG wireshark "$INSTALL_USER" 2>/dev/null && ok "Uporabnik dodan v wireshark skupino" || true

section "Security — Web testiranje"
apt-get install -y \
  nikto \
  gobuster \
  dirb \
  wfuzz \
  sqlmap \
  curl \
  >> "$LOGFILE" 2>&1 && ok "Web orodja nameščena"

section "Security — Gesla in kriptografija"
apt-get install -y \
  john \
  hashcat \
  hydra \
  medusa \
  gpg \
  openssl \
  >> "$LOGFILE" 2>&1 && ok "Password/crypto orodja nameščena"

section "Security — Recon in OSINT"
apt-get install -y \
  maltego \
  recon-ng \
  theHarvester \
  dnsrecon \
  fierce \
  >> "$LOGFILE" 2>&1 \
  || {
    warn "Nekatera recon orodja niso v repotu — nameščam via pip"
    pip3 install theHarvester recon-ng --break-system-packages >> "$LOGFILE" 2>&1 \
      && ok "theHarvester, recon-ng (pip)" || warn "Pip recon orodja — preveri ročno"
  }

section "Security — Exploit orodja"
apt-get install -y \
  metasploit-framework \
  >> "$LOGFILE" 2>&1 \
  || {
    warn "Metasploit ni v standardnem repotu — nameščam iz uradnega vira"
    curl -s https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb \
      > /tmp/msfinstall 2>/dev/null \
      && chmod +x /tmp/msfinstall \
      && /tmp/msfinstall >> "$LOGFILE" 2>&1 \
      && ok "Metasploit nameščen" \
      || warn "Metasploit — namesti ročno: https://docs.metasploit.com"
    rm -f /tmp/msfinstall
  }

section "Security — Wireless testiranje"
apt-get install -y \
  aircrack-ng \
  airodump-ng \
  kismet \
  bettercap \
  >> "$LOGFILE" 2>&1 && ok "Wireless orodja nameščena"

# Monitor mode udev
if ! grep -q "80211" /etc/udev/rules.d/70-wifi-monitor.rules 2>/dev/null; then
  cat > /etc/udev/rules.d/70-wifi-monitor.rules << 'EOF'
SUBSYSTEM=="net", ACTION=="add", ATTR{type}=="1", KERNEL=="wlan*", RUN+="/sbin/iw dev %k set power_save off"
EOF
  udevadm control --reload-rules
  ok "WiFi monitor mode udev pravila dodana"
fi

section "Security — Vulnerability scanning"
apt-get install -y \
  openvas \
  >> "$LOGFILE" 2>&1 \
  || {
    warn "OpenVAS ni dostopen — nameščam Lynis kot alternativo"
    apt-get install -y lynis >> "$LOGFILE" 2>&1 \
      && ok "Lynis nameščen" || warn "Lynis — napaka"
  }

apt-get install -y \
  chkrootkit \
  rkhunter \
  >> "$LOGFILE" 2>&1 && ok "Rootkit scanner nameščen"

section "Security — Forenzika"
apt-get install -y \
  binwalk \
  foremost \
  testdisk \
  sleuthkit \
  autopsy \
  hexedit \
  xxd \
  strings \
  file \
  >> "$LOGFILE" 2>&1 && ok "Forenzična orodja nameščena"

section "Security — Proxy in MITM"
apt-get install -y \
  mitmproxy \
  proxychains4 \
  tor \
  torsocks \
  >> "$LOGFILE" 2>&1 && ok "Proxy orodja nameščena"

section "Security — Dodatni scannerji in orodja"
apt-get install -y \
  enum4linux \
  nbtscan \
  snmp \
  onesixtyone \
  smbclient \
  >> "$LOGFILE" 2>&1 && ok "SMB/SNMP orodja nameščena"

# Namestitev pip orodij
section "Security — Python security orodja (pip)"
pip3 install --break-system-packages \
  impacket \
  scapy \
  pwntools \
  requests \
  >> "$LOGFILE" 2>&1 && ok "Python security paketi nameščeni"

# --- Burp Suite Community ---
section "Security — Burp Suite Community"
BURP_DIR="/opt/burpsuite"
if [[ ! -d "$BURP_DIR" ]]; then
  warn "Burp Suite zahteva ročni prenos."
  info "1. Pojdi na: https://portswigger.net/burp/communitydownload"
  info "2. Prenesi Linux installer"
  info "3. Zaženi: chmod +x burpsuite_community_linux*.sh && sudo ./burpsuite_community_linux*.sh"
else
  ok "Burp Suite že nameščen v $BURP_DIR"
fi

fi  # konec Security sekcije

# ============================================================
# SKUPNA ZAKLJUČNA KONFIGURACIJA
# ============================================================
section "Zaključna konfiguracija"

# Ustvari mape za projekte
mkdir -p "$INSTALL_HOME/gnetx-projects/ham"
mkdir -p "$INSTALL_HOME/gnetx-projects/security"
mkdir -p "$INSTALL_HOME/gnetx-projects/logs"
chown -R "$INSTALL_USER:$INSTALL_USER" "$INSTALL_HOME/gnetx-projects"
ok "Projektne mape ustvarjene v $INSTALL_HOME/gnetx-projects/"

# Bashrc dodatki
BASHRC="$INSTALL_HOME/.bashrc"
if ! grep -q "GNETX aliases" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" << 'EOF'

# ---- GNETX aliases ----
alias ham-start='startx -- -nolisten tcp &'
alias wsjt='wsjtx &'
alias fldigi='fldigi &'
alias gqrx='gqrx &'
alias aprs-start='sudo systemctl start direwolf'
alias aprs-stop='sudo systemctl stop direwolf'
alias aprs-log='journalctl -u direwolf -f'
alias sec-ports='sudo nmap -sS -O'
alias sec-web='nikto -h'
alias myip='curl -s ifconfig.me'
alias listen='sudo netstat -tulpn'
EOF
  ok "Bashrc aliasi dodani"
fi

# Ustvari README v projektni mapi
cat > "$INSTALL_HOME/gnetx-projects/README.md" << EOF
# GNETX — Projektna mapa

## HAM Radio
- Konfiguracije: ~/gnetx-projects/ham/
- Direwolf config: ~/.config/direwolf.conf
- WSJT-X config: ~/.local/share/WSJT-X/
- Fldigi config: ~/.fldigi/

## Security
- Delovni direktorij: ~/gnetx-projects/security/
- Logi: ~/gnetx-projects/logs/

## Koristni ukazi (v terminalu)
    aprs-start       — zaženi Direwolf APRS
    aprs-log         — živi log Direwolfa
    sec-ports <IP>   — hitri nmap scan
    sec-web <URL>    — nikto web scan
    myip             — pokaži zunanji IP
    listen           — seznam odprtih portov

## Callsign: S51DG | Grid: JN76BB | GNETX Linux 1.0
EOF
chown "$INSTALL_USER:$INSTALL_USER" "$INSTALL_HOME/gnetx-projects/README.md"
ok "README ustvarjen"

# ============================================================
# POVZETEK
# ============================================================
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     Namestitev zaključena!               ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

if [[ $DO_HAM -eq 1 ]]; then
  echo -e "${CYAN}HAM Radio orodja:${NC}"
  echo "  ✓ Hamlib       — rig control"
  echo "  ✓ WSJT-X       — FT8/FT4/WSPR"
  echo "  ✓ Fldigi suite — PSK31/RTTY/Olivia"
  echo "  ✓ Direwolf     — APRS TNC"
  echo "  ✓ GQRX + RTL-SDR — software radio"
  echo "  ✓ PAT Winlink  — radio email"
  echo "  ✓ CHIRP        — radio programmer"
  echo "  ℹ JS8Call      — ročen prenos potreben"
  echo ""
fi

if [[ $DO_SEC -eq 1 ]]; then
  echo -e "${CYAN}Security orodja:${NC}"
  echo "  ✓ Nmap/Masscan — port scanning"
  echo "  ✓ Wireshark    — packet capture"
  echo "  ✓ Nikto/SQLMap — web testing"
  echo "  ✓ John/Hashcat — password cracking"
  echo "  ✓ Aircrack-ng  — wireless"
  echo "  ✓ Metasploit   — exploitation"
  echo "  ✓ Binwalk      — forensics"
  echo "  ✓ Scapy/Impacket — Python security"
  echo "  ℹ Burp Suite   — ročen prenos potreben"
  echo ""
fi

echo -e "${YELLOW}Opomba:${NC} Odjavi se in prijavi znova da se skupinske spremembe uveljavijo."
echo -e "${YELLOW}Log:${NC} $LOGFILE"
echo ""
log "=== GNETX post-install ended: $(date) ==="
