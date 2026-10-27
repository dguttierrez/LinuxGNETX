# GNETX Linux — Celoten vodič za izgradnjo distribucije

> Debian-based · Kernel 7.0.6 · LXDE (ročen zagon) · x86_64 + arm64

---

## Kazalo

1. [Zahteve in priprava okolja](#1-zahteve-in-priprava-okolja)
2. [Struktura projekta](#2-struktura-projekta)
3. [Konfiguracija live-build](#3-konfiguracija-live-build)
4. [Kompajlanje kernela 7.0.6](#4-kompajlanje-kernela-706)
5. [Paketni seznam — minimalen + LXDE](#5-paketni-seznam)
6. [Branding — logotip, GRUB, Plymouth](#6-branding)
7. [LXDE — ročen zagon (brez autostart)](#7-lxde--ročen-zagon)
8. [OS identifikacija](#8-os-identifikacija)
9. [Build za x86_64](#9-build-za-x86_64)
10. [Build za arm64](#10-build-za-arm64)
11. [Testiranje z QEMU](#11-testiranje-z-qemu)
12. [Distribucija ISO](#12-distribucija-iso)

---

## 1. Zahteve in priprava okolja

### Build stroj
- Debian 12 (Bookworm) ali Ubuntu 24.04
- Vsaj 40 GB prostega diska
- Vsaj 8 GB RAM
- Za cross-compile arm64: dodatni `gcc-aarch64-linux-gnu`

### Namestitev orodij

```bash
sudo apt update
sudo apt install -y \
  live-build \
  debootstrap \
  squashfs-tools \
  xorriso \
  grub-pc-bin \
  grub-efi-amd64-bin \
  mtools \
  isolinux \
  syslinux-common \
  bc \
  bison \
  flex \
  libelf-dev \
  libssl-dev \
  libncurses-dev \
  gcc \
  make \
  dpkg-dev \
  git \
  wget \
  gcc-aarch64-linux-gnu \
  binutils-aarch64-linux-gnu \
  plymouth \
  plymouth-themes
```

> **Opomba — `grub-efi-arm64-bin`:** ta paket ni vedno na voljo na amd64 build stroju, ker je del arm64 arhitekture in zahteva dodan "foreign" arhitekturni seznam. Če buildaš arm64 ISO na amd64 stroju, ga dodaj posebej:
> ```bash
> sudo dpkg --add-architecture arm64
> sudo apt update
> sudo apt install -y grub-efi-arm64-bin
> ```
> Če tudi to javi napako, je najbolj zanesljivo arm64 build poganjati neposredno na arm64 stroju (ali VM), kjer je paket nativno na voljo.
>
> **Opomba — `dpkg-dev`:** ta paket vsebuje orodja za `make bindeb-pkg` (poglavje 4). Brez njega ukaz javi napako, da ne najde `dpkg-buildpackage`.

---

## 2. Struktura projekta

### 2.1 Ustvarjanje osnovnih map

```bash
# Ustvari koren repozitorija in pojdi vanj
mkdir -p gnetx
cd gnetx

mkdir -p build-x86/config
mkdir -p build-arm64/config
mkdir -p kernel/build-x86
mkdir -p kernel/build-arm64
mkdir -p branding/plymouth
```

`lb config` (poglavje 3) nato sam ustvari preostale podmape znotraj `config/` (package-lists, includes.chroot, hooks, bootloaders). `branding/` služi kot "master" izvor grafik, od koder jih kopiraš v `build-x86/config/includes.chroot/...` in `build-arm64/config/includes.chroot/...`.

### 2.2 Pregled strukture

```
gnetx/
├── build-x86/              # live-build konfig za x86_64
│   └── config/
│       ├── package-lists/
│       │   └── gnetx.list.chroot
│       ├── includes.chroot/
│       │   ├── etc/
│       │   │   ├── os-release
│       │   │   ├── issue
│       │   │   └── issue.net
│       │   ├── usr/share/plymouth/themes/gnetx/
│       │   └── usr/share/pixmaps/
│       ├── hooks/normal/
│       │   ├── 0010-kernel.hook.chroot
│       │   └── 0020-lxde-noauto.hook.chroot
│       └── bootloaders/grub-pc/
│           └── live-theme/
│               ├── theme.txt
│               └── gnetx-grub.png
├── build-arm64/            # live-build konfig za arm64
│   └── config/             # (enaka struktura)
├── kernel/                 # kernel source + build
│   ├── linux-7.0.6/
│   ├── build-x86/
│   └── build-arm64/
└── branding/               # originalne grafike
    ├── logo.svg
    ├── grub-bg.png
    └── plymouth/
```

---

## 3. Konfiguracija live-build

### x86_64

```bash
mkdir -p gnetx/build-x86 && cd gnetx/build-x86

lb config \
  --distribution bookworm \
  --architectures amd64 \
  --linux-flavours none \
  --bootappend-live "boot=live components quiet splash" \
  --iso-volume "GNETX" \
  --iso-publisher "GNETX Project" \
  --iso-application "GNETX Linux" \
  --memtest none \
  --firmware-binary false \
  --firmware-chroot false
```

### arm64

```bash
mkdir -p gnetx/build-arm64 && cd gnetx/build-arm64

lb config \
  --distribution bookworm \
  --architectures arm64 \
  --linux-flavours none \
  --bootappend-live "boot=live components quiet splash" \
  --iso-volume "GNETX-ARM64" \
  --iso-publisher "GNETX Project" \
  --iso-application "GNETX Linux arm64" \
  --memtest none \
  --firmware-binary false \
  --firmware-chroot false
```

---

## 4. Kompajlanje kernela 7.0.6

### Prenos izvorne kode

```bash
cd gnetx/kernel
wget https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.0.6.tar.xz
tar xf linux-7.0.6.tar.xz
```

### Build za x86_64

```bash
mkdir build-x86 && cd build-x86

make -C ../linux-7.0.6 O=$(pwd) x86_64_defconfig

# Prilagoditve za minimalen sistem
make menuconfig
# Priporočene nastavitve:
#   General setup -> Default hostname: gnetx
#   Processor type -> x86-64
#   Device Drivers -> Graphics -> DRM (za LXDE)

make -j$(nproc) bzImage modules

# Pakiranje v .deb format
make -j$(nproc) bindeb-pkg LOCALVERSION=-gnetx
# Nastanejo: linux-image-7.0.6-gnetx_*.deb, linux-headers-*.deb
```

> **Pozor:** `bindeb-pkg` zgradi `.deb` pakete **eno mapo nad** `O=$(pwd)` izhodnim direktorijem — torej ne v `build-x86/`, ampak v `kernel/` (nadrejena mapa). To velja za oba builda (x86 in arm64). Upoštevaj to pri kopiranju v naslednjem koraku.

### Build za arm64 (cross-compile)

```bash
mkdir gnetx/kernel/build-arm64 && cd gnetx/kernel/build-arm64

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

make -C ../linux-7.0.6 O=$(pwd) defconfig

make -j$(nproc) Image.gz modules dtbs

# Pakiranje (nastane v gnetx/kernel/, NE v build-arm64/)
make -j$(nproc) bindeb-pkg LOCALVERSION=-gnetx-arm64
```

### Kopiranje kernel .deb v live-build

`.deb` paketi so po buildu v `gnetx/kernel/` (ne v `kernel/build-x86/` ali `kernel/build-arm64/`):

```bash
# x86_64
cp gnetx/kernel/linux-image-7.0.6-gnetx_*.deb \
   gnetx/build-x86/config/packages.chroot/

# arm64
cp gnetx/kernel/linux-image-7.0.6-gnetx-arm64_*.deb \
   gnetx/build-arm64/config/packages.chroot/
```

---

## 5. Paketni seznam

### `config/package-lists/gnetx.list.chroot`

```
# Osnova
systemd
systemd-sysv
bash
coreutils
util-linux
procps
grep
sed
gawk
findutils

# Omrežje
network-manager
wpasupplicant
iproute2
iputils-ping
wget
curl
openssh-client

# Datotečni sistem
e2fsprogs
dosfstools
ntfs-3g

# Grafično okolje — LXDE
xorg
xserver-xorg
xserver-xorg-video-all
xinit
openbox
lxde-core
lxde-common
lxpanel
pcmanfm
lxappearance
lxterm
lxtask

# Orodja
vim
nano
htop
git
zip
unzip
gzip
bzip2

# Plymouth (boot splash)
plymouth
plymouth-themes

# LXDE dodatki
mousepad
gpicview
```

---

## 6. Branding

### 6.1 GRUB tema

Celotno poglavje 6 se izvaja znotraj `live-build` konfiguracije — torej iz `gnetx/build-x86/` (za arm64 build ponovi enako v `gnetx/build-arm64/`). Najprej se postavi tja:

```bash
cd gnetx/build-x86
mkdir -p config/bootloaders/grub-pc/live-theme
```

#### `config/bootloaders/grub-pc/live-theme/theme.txt`

```
# GNETX GRUB Theme
title-text: ""
desktop-color: "#0D1F3C"
desktop-image: "background.png"

+ boot_menu {
  left = 25%
  top = 40%
  width = 50%
  height = 30%
  item_color = "#4FA3FF"
  item_height = 36
  item_font = "DejaVu Sans Regular 14"
  selected_item_color = "#FFFFFF"
  selected_item_font = "DejaVu Sans Bold 14"
  selected_background = "#1A3A6B"
  item_padding = 10
  scrollbar = false
}

+ label {
  top = 10%
  left = 50%
  align = "center"
  color = "#FFFFFF"
  font = "DejaVu Sans Bold 28"
  text = "GNETX Linux"
}

+ label {
  top = 18%
  left = 50%
  align = "center"
  color = "#4FA3FF"
  font = "DejaVu Sans Regular 14"
  text = "Kernel 7.0.6 | Debian-based"
}

+ progress_bar {
  id = "__timeout__"
  left = 25%
  top = 75%
  width = 50%
  height = 6
  fg_color = "#2A7FE8"
  bg_color = "#1A3A6B"
  border_color = "#4FA3FF"
  text = ""
}
```

#### GRUB ozadje

Ustvari PNG `background.png` (1920×1080) z logotipom. Primer z ImageMagick:

```bash
convert -size 1920x1080 \
  -background '#0D1F3C' \
  -fill '#1A3A6B' \
  -draw "polygon 960,200 1110,283 1110,450 960,533 810,450 810,283" \
  -fill '#2A7FE8' \
  -pointsize 72 \
  -gravity center \
  -annotate +0-200 'GNETX' \
  config/bootloaders/grub-pc/live-theme/background.png
```

### 6.2 Plymouth boot splash

```bash
mkdir -p config/includes.chroot/usr/share/plymouth/themes/gnetx
```

#### `gnetx.plymouth`

```ini
[Plymouth Theme]
Name=GNETX
Description=GNETX Linux boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/gnetx
ScriptFile=/usr/share/plymouth/themes/gnetx/gnetx.script
```

#### `gnetx.script`

```javascript
// GNETX Plymouth script
Window.SetBackgroundTopColor(0.051, 0.122, 0.235);   // #0D1F3C
Window.SetBackgroundBottomColor(0.024, 0.094, 0.165);

logo_image = Image("logo.png");
logo_sprite = Sprite(logo_image);

screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
logo_x = screen_width / 2 - logo_image.GetWidth() / 2;
logo_y = screen_height / 2 - logo_image.GetHeight() / 2 - 40;

logo_sprite.SetX(logo_x);
logo_sprite.SetY(logo_y);

// Besedilo
text_image = Image.Text("GNETX Linux", 1.0, 1.0, 1.0, 1, "Sans Bold 20");
text_sprite = Sprite(text_image);
text_sprite.SetX(screen_width / 2 - text_image.GetWidth() / 2);
text_sprite.SetY(logo_y + logo_image.GetHeight() + 20);

// Progress bar
progress_box = Sprite();
progress_box.SetX(screen_width / 2 - 150);
progress_box.SetY(screen_height * 0.75);

progress = 0;
fun progress_callback(duration, progress) {
  bar = Image.Text("", 0.165, 0.5, 0.91, 1, "Sans 1");
  bar_width = Math.Int(300 * progress);
  if (bar_width > 0) {
    bar = bar.Scale(bar_width, 6);
  }
  progress_box.SetImage(bar);
}

Plymouth.SetBootProgressFunction(progress_callback);
```

### 6.3 Hook za namestitev Plymouth teme

#### `config/hooks/normal/0030-plymouth.hook.chroot`

```bash
#!/bin/bash
set -e

# Nastavi GNETX kot privzeto Plymouth temo
update-alternatives --install \
  /usr/share/plymouth/themes/default.plymouth \
  default.plymouth \
  /usr/share/plymouth/themes/gnetx/gnetx.plymouth 200

update-alternatives --set default.plymouth \
  /usr/share/plymouth/themes/gnetx/gnetx.plymouth

# Regeneriraj initramfs
update-initramfs -u
```

```bash
chmod +x config/hooks/normal/0030-plymouth.hook.chroot
```

---

## 7. LXDE — ročen zagon

LXDE se **ne zaganja avtomatično** ob bootu. Sistem se zažene v konzolo (TTY). Uporabnik sam zagene grafično okolje z ukazom `startx`.

### 7.1 Onemogoči display manager

#### `config/hooks/normal/0020-lxde-noauto.hook.chroot`

```bash
#!/bin/bash
set -e

# Odstrani/onemogoči display managerje če so prisotni
systemctl disable lightdm 2>/dev/null || true
systemctl disable gdm3 2>/dev/null || true
systemctl disable sddm 2>/dev/null || true

# Nastavi multi-user.target kot privzeti (brez GUI)
systemctl set-default multi-user.target

echo "LXDE autostart je onemogočen. Za zagon GUI vtipkaj: startx"
```

```bash
chmod +x config/hooks/normal/0020-lxde-noauto.hook.chroot
```

### 7.2 Konfiguracija .xinitrc za LXDE

#### `config/includes.chroot/etc/skel/.xinitrc`

```bash
#!/bin/bash
# GNETX — zagon LXDE z ukazom startx
exec startlxde
```

### 7.3 MOTD z navodilom za zagon GUI

#### `config/includes.chroot/etc/motd`

```
╔══════════════════════════════════════════════════════╗
║          GNETX Linux | Kernel 7.0.6                 ║
║          Debian-based | Minimal System              ║
╠══════════════════════════════════════════════════════╣
║  Za zagon grafičnega okolja LXDE vtipkaj:           ║
║                                                      ║
║    startx                                            ║
║                                                      ║
║  Dokumentacija: https://gnetx.example.com           ║
╚══════════════════════════════════════════════════════╝
```

---

## 8. OS identifikacija

#### `config/includes.chroot/etc/os-release`

```ini
NAME="GNETX Linux"
VERSION="1.0"
ID=gnetx
ID_LIKE=debian
PRETTY_NAME="GNETX Linux 1.0 (Kernel 7.0.6)"
VERSION_ID="1.0"
HOME_URL="https://gnetx.example.com"
SUPPORT_URL="https://gnetx.example.com/support"
BUG_REPORT_URL="https://gnetx.example.com/bugs"
BUILD_ID="gnetx-1.0-20260514"
VARIANT="Minimal"
ANSI_COLOR="1;34"
```

#### `config/includes.chroot/etc/issue`

```
GNETX Linux 1.0 \n \l
```

#### `config/includes.chroot/etc/issue.net`

```
GNETX Linux 1.0
```

### Hook za kernel namestitev

#### `config/hooks/normal/0010-kernel.hook.chroot`

```bash
#!/bin/bash
set -e

# Namesti custom kernel .deb (je bil kopiran v packages.chroot/)
# live-build ga namesti samodejno iz config/packages.chroot/

# Onemogoči privzete Debian kernele
apt-get remove --purge -y linux-image-amd64 linux-image-arm64 2>/dev/null || true

# Posodobi GRUB
update-grub
```

```bash
chmod +x config/hooks/normal/0010-kernel.hook.chroot
```

---

## 9. Build za x86_64

```bash
cd gnetx/build-x86

# Preveri da so kernel .deb paketi na mestu
ls config/packages.chroot/linux-image-7.0.6-gnetx_*.deb

# Zaženi build (traja 30-90 min odvisno od stroja)
sudo lb build 2>&1 | tee ../build-x86.log

# Rezultat
ls -lh live-image-amd64.hybrid.iso
```

### Čiščenje med ponovitvami

```bash
# Počisti vse (full rebuild)
sudo lb clean --all

# Počisti samo binarno (hitrejše)
sudo lb clean --binary
```

---

## 10. Build za arm64

```bash
cd gnetx/build-arm64

ls config/packages.chroot/linux-image-7.0.6-gnetx-arm64_*.deb

sudo lb build 2>&1 | tee ../build-arm64.log

ls -lh live-image-arm64.hybrid.iso
```

### Opomba za arm64

Za zagon na fizičnem arm64 (npr. Raspberry Pi 4/5, Ampere, AWS Graviton) potrebuješ:
- UEFI firmware (EDK2/TianoCore za RPi) **ali**
- U-Boot z EFI podporo

Za RPi 4/5 dodaj v `config/package-lists/gnetx.list.chroot`:
```
raspi-firmware
u-boot-rpi
```

---

## 11. Testiranje z QEMU

### x86_64

```bash
# Namesti QEMU
sudo apt install -y qemu-system-x86

# Zagon (BIOS)
qemu-system-x86_64 \
  -cdrom gnetx/build-x86/live-image-amd64.hybrid.iso \
  -m 2G \
  -smp 2 \
  -enable-kvm \
  -vga virtio \
  -display gtk

# Zagon (UEFI)
sudo apt install -y ovmf
qemu-system-x86_64 \
  -cdrom gnetx/build-x86/live-image-amd64.hybrid.iso \
  -bios /usr/share/ovmf/OVMF.fd \
  -m 2G \
  -smp 2 \
  -enable-kvm \
  -vga virtio
```

### arm64

```bash
sudo apt install -y qemu-system-arm qemu-efi-aarch64

qemu-system-aarch64 \
  -machine virt \
  -cpu cortex-a72 \
  -smp 2 \
  -m 2G \
  -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -cdrom gnetx/build-arm64/live-image-arm64.hybrid.iso \
  -nographic
```

---

## 12. Distribucija ISO

### Preverjanje integritete

```bash
# SHA256 checksumi
sha256sum gnetx/build-x86/live-image-amd64.hybrid.iso > GNETX-1.0-x86_64.sha256
sha256sum gnetx/build-arm64/live-image-arm64.hybrid.iso > GNETX-1.0-arm64.sha256
```

### Zapis na USB

```bash
# Poišči disk (POZOR: zamenjaj /dev/sdX z ustreznim!)
lsblk

# Zapis x86_64
sudo dd if=gnetx/build-x86/live-image-amd64.hybrid.iso \
        of=/dev/sdX \
        bs=4M \
        status=progress \
        oflag=sync

# Zapis arm64
sudo dd if=gnetx/build-arm64/live-image-arm64.hybrid.iso \
        of=/dev/sdX \
        bs=4M \
        status=progress \
        oflag=sync
```

### Preimenovanje za distribucijo

```bash
cp gnetx/build-x86/live-image-amd64.hybrid.iso   GNETX-1.0-x86_64.iso
cp gnetx/build-arm64/live-image-arm64.hybrid.iso  GNETX-1.0-arm64.iso
```

---

## Povzetek toka

```
Kernel source (7.0.6)
    ↓ make bindeb-pkg  (x86 + arm64)
Kernel .deb paketi
    ↓ config/packages.chroot/
live-build config
    ├── package-lists (minimalen + LXDE)
    ├── hooks (kernel, LXDE noauto, Plymouth)
    ├── includes.chroot (os-release, motd, xinitrc)
    └── bootloaders (GRUB tema)
    ↓ sudo lb build
GNETX-1.0-x86_64.iso
GNETX-1.0-arm64.iso
```

---

*GNETX Linux — build vodič v1.0 | Datum: 14. maj 2026*
