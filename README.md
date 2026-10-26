# GNETX Linux

Minimalna Debian-based Linux distribucija s customiziranim kernelom, LXDE grafičnim okoljem (brez avtomatičnega zagona) in post-install skriptami za HAM radio ter varnostna orodja.

- **Baza:** Debian (bookworm)
- **Kernel:** 7.0.6
- **Arhitekturi:** x86_64, arm64
- **Grafično okolje:** LXDE (zagon ročno, ukaz `startx`)
- **Avtor:** Davor Guttierrez (S51DG) — [gsistemi.net](https://gsistemi.net)

---

## Struktura repozitorija

```
.
├── README.md                    # ta datoteka
├── GNETX-build-guide.md         # celoten vodič za izgradnjo distribucije
├── gnetx-postinstall.sh         # post-install: HAM radio + security orodja
├── gnetx-wine-ham.sh            # dodatek: Winlink Express + VARA FM (Wine)
├── build-x86/                   # live-build konfiguracija za x86_64
├── build-arm64/                 # live-build konfiguracija za arm64
├── kernel/                      # kernel 7.0.6 source + build direktoriji
└── branding/                    # logotip, GRUB tema, Plymouth tema
```

---

## Hiter začetek

### 1. Izgradnja ISO

Celoten postopek (priprava okolja, kernel build, live-build config, branding, build za obe arhitekturi, testiranje v QEMU) je opisan v [`GNETX-build-guide.md`](GNETX-build-guide.md).

```bash
cd build-x86
sudo lb build
```

### 2. Post-install — HAM radio in varnostna orodja

Po namestitvi sistema zaženi:

```bash
sudo bash gnetx-postinstall.sh
```

Skripta vpraša, ali želiš namestiti HAM radio orodja, security orodja ali oboje. Pokrije Hamlib, WSJT-X, Fldigi, Direwolf (APRS), GQRX/RTL-SDR, PAT Winlink, CHIRP ter Nmap, Wireshark, Metasploit, Aircrack-ng, forenzična orodja in drugo.

> **Znana omejitev:** nekateri paketi (`airodump-ng`, `maltego`, `openvas`, `metasploit-framework` ipd.) niso vedno na voljo v standardnem Debian repozitoriju — če `apt-get` del odpove, preveri log `/var/log/gnetx-postinstall.log`.

### 3. Dodatek — Winlink Express in VARA FM prek Wine

```bash
sudo bash gnetx-wine-ham.sh [pot_do_installerjev]
```

Namesti Wine (32-bit prefix), poišče installerje Winlink Express in VARA FM v `~/Downloads` (ali podani mapi) in ju namesti. Pat (nativen, nameščen v koraku 2) se z VARA FM poveže prek TCP — navodila se zapišejo v `~/gnetx-projects/ham/pat-vara-navodila.txt`.

> Deluje samo na **x86_64** — Winlink Express in VARA sta Windows x86 programa, na arm64 brez emulacije (box64/FEX) ne tečeta.

---

## Branding

Logotip, GRUB tema in Plymouth boot splash so v `branding/`. Barvna paleta: `#0D1F3C` (temno modra), `#2A7FE8` (akcentna modra), `#4FA3FF` (svetla modra).

---

## Testiranje

```bash
qemu-system-x86_64 -cdrom build-x86/live-image-amd64.hybrid.iso -m 2G -enable-kvm
qemu-system-aarch64 -machine virt -cpu cortex-a72 -m 2G \
  -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -cdrom build-arm64/live-image-arm64.hybrid.iso -nographic
```

---

## Licenca

TODO — določi licenco pred javno objavo repozitorija.

## Kontakt

Davor Guttierrez · S51DG · JN76BB · [gsistemi.net](https://gsistemi.net)
