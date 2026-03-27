# KE8DCJ / KE8DUO APRS Station

A dual-station APRS messaging system built on Direwolf, Flask, and Piper TTS.
Lets two licensed amateur radio operators exchange APRS messages over 144.390 MHz
using inexpensive Baofeng UV-5R handhelds and the AIOC (All-In-One-Cable) USB interface.

**Stations:**
- **KE8DCJ** — Linux Mint x86_64 desktop, Calumet MI
- **KE8DUO** — Raspberry Pi 3B+ aarch64, remote location

Both stations run identical code; only `config.yaml` differs.

---

## Hardware Required

| Item | Notes |
|------|-------|
| Baofeng UV-5R (or compatible) | Set to 144.390 MHz, APRS frequency |
| [AIOC (NA6D)](https://github.com/skuep/AIOC) | USB-C audio + PTT interface, VID 1209 / PID 7388 |
| Ferrite choke on AIOC USB cable | **Required** — prevents RF coupling during TX from crashing Direwolf |
| Linux Mint 21+ x86_64 **or** RPi OS Bullseye 64-bit | Installer auto-detects architecture |
| Internet connection (for install only) | Downloads Piper TTS binary + voice model |

---

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/Dualfuel671/APRS_text.git
cd APRS_text
```

### 2. Create your config file

```bash
cp config.yaml.example config.yaml
```

Edit `config.yaml`:
- Set your `callsign` and `partner_callsign`
- Set `aprs_is.filter` to your coordinates (see comments in the file)
- Leave `passcode` blank — the installer calculates it

### 3. Run the installer

```bash
bash setup/install.sh
```

The installer is idempotent — safe to re-run. It will skip steps that are already complete.

### 4. Log out and back in

Required for `dialout` and `audio` group membership to take effect.

### 5. Plug in the AIOC and confirm device paths

```bash
bash tools/find_aioc.sh
```

Update `config.yaml → direwolf.adevice` if the ALSA card number differs from `plughw:1,0`.

### 6. Start the services

```bash
sudo systemctl start direwolf aprs_station
```

### 7. Open the UI

Navigate to **http://localhost:5000** in any browser.

---

## Configuring config.yaml

| Key | Description |
|-----|-------------|
| `callsign` | Your FCC callsign (no SSID) |
| `ssid` | 0 = home station, 9 = mobile |
| `partner_callsign` | The other station's callsign |
| `aprs_is.filter` | `r/LAT/LON/RADIUS_KM` — area to pull packets from APRS-IS |
| `direwolf.adevice` | ALSA device for the AIOC — run `find_aioc.sh` to confirm |
| `direwolf.ptt_device` | Always `/dev/aioc_hid` — the stable udev symlink |
| `tts.audio_device` | `default` for system speakers/earbuds |
| `kiosk_mode` | `true` to auto-launch Chromium fullscreen on boot (RPi only) |

> **config.yaml is excluded from version control** (contains your APRS-IS passcode).
> Use `config.yaml.example` as the template.

---

## Service Management

```bash
# Status
sudo systemctl status direwolf aprs_station

# Start / stop / restart
sudo systemctl start   direwolf aprs_station
sudo systemctl stop    direwolf aprs_station
sudo systemctl restart direwolf aprs_station

# Live logs
journalctl -u direwolf     -f
journalctl -u aprs_station -f

# Enable / disable auto-start at boot
sudo systemctl enable  direwolf aprs_station
sudo systemctl disable direwolf aprs_station
```

---

## Browser UI

Open **http://localhost:5000**

| Panel | Description |
|-------|-------------|
| Status bar | Callsign, frequency, Direwolf connected (green/red), APRS-IS connected, uptime |
| Send Message | Type a destination callsign and message (max 67 chars), press SEND |
| My Messages | Inbound and outbound APRS messages; click an inbound message to mark read |
| Live Packet Stream | All packets in real time with RF (green) / IS (gray) origin badges |

---

## Tools

All tools run from the project root with the venv active:

```bash
source ~/aprs_env/bin/activate
```

| Tool | Usage | Description |
|------|-------|-------------|
| `tools/find_aioc.sh` | `bash tools/find_aioc.sh` | Detects AIOC ALSA card number and `/dev/hidrawN` path. Prints the exact strings to paste into `config.yaml`. |
| `tools/check_audio.py` | `python3 tools/check_audio.py` | Synthesizes a test phrase with Piper TTS and plays it. Confirms TTS and speaker output are working before going RF. |
| `tools/check_direwolf.py` | `python3 tools/check_direwolf.py` | Connects to Direwolf AGW port 8000 and listens for 30 seconds. Confirms Direwolf is running and decoding packets from the air. |
| `tools/test_send.py` | `python3 tools/test_send.py` | Sends a test APRS message to `partner_callsign` via the web API. Confirms TX pipeline is working end-to-end. |
| `tools/test_receive.py` | `python3 tools/test_receive.py` | Injects a fake inbound message as if from the partner station. Tests the full RX pipeline: AGW → DB → TTS → WebSocket → UI. |

---

## Architecture

```
Baofeng UV-5R
     │ audio + PTT
   AIOC (USB-C)
     │ plughw:1,0  /dev/aioc_hid
   Direwolf
     │ AGW :8000 (RX monitor)
     │ KISS :8001 (TX only)
   aprs_router.py (Flask + Socket.IO :5000)
     │
     ├── SQLite  data/aprs_log.db
     ├── Piper TTS  ~/piper/piper
     └── Browser UI  localhost:5000
           │
        APRS-IS (secondary RX feed)
        rotate.aprs2.net:14580
```

**Key design decisions:**
- TX uses KISS port 8001 exclusively — AGW `T` frames are rejected by Direwolf's monitoring connection
- `socket.io.min.js` is served locally from `/static/` — Flask-SocketIO 5.x intercepts the `/socket.io/` CDN path
- `PTT CM108 /dev/aioc_hid` — always the udev symlink, never `/dev/hidrawN` (number changes at each boot)
- WirePlumber exclusion rule prevents PipeWire from claiming the AIOC before Direwolf starts

---

## Known Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| Radio stays keyed after TX | RF couples into USB cable → Direwolf EPIPE crash | **Ferrite choke on AIOC USB cable** (hardware fix, solved) |
| "Device or resource busy" on Direwolf start | PipeWire grabbed AIOC | Confirm `~/.config/wireplumber/main.lua.d/50-aioc-reserve.lua` exists, then log out/in |
| `/dev/aioc_hid` missing after plug-in | udev rule not loaded | `sudo udevadm control --reload-rules && sudo udevadm trigger`, then replug |
| Packets show "IS" not "RF" in UI | TX packets return via APRS-IS iGate (normal with short antenna) | Install a proper 144 MHz antenna (1/4-wave or j-pole) |

---

## For KE8DUO (Raspberry Pi 3B+ aarch64)

Same codebase — only `config.yaml` differs:

```yaml
callsign: KE8DUO
ssid: 0
partner_callsign: KE8DCJ
kiosk_mode: true   # if using an attached display
```

The installer detects `aarch64` and downloads the correct Piper binary automatically.

---

## License

For licensed amateur radio operators. Not for commercial use.
