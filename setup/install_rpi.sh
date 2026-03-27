#!/usr/bin/env bash
# =============================================================================
# APRS Station — Raspberry Pi OS Bullseye (aarch64) Installer
# Callsigns: KE8DCJ / KE8DUO  |  Hardware: Baofeng UV-5R + AIOC (NA6D)
# Target: RPi 3B+ running Raspberry Pi OS Bullseye 64-bit
#
# Usage (run as your normal user, NOT root):
#   cd /path/to/APRS_transfer
#   bash setup/install_rpi.sh
#
# Key differences from the Linux Mint installer (install.sh):
#   - Bullseye uses PulseAudio, not PipeWire/WirePlumber.
#     AIOC exclusion is handled via a PULSE_IGNORE udev rule (step 4).
#   - Piper binary is piper_linux_aarch64.tar.gz
#   - chromium-browser is available in RPi OS repos (not a snap)
#   - SupplementaryGroups=audio dialout in direwolf.service
# =============================================================================

set -euo pipefail

# ── Sanity checks ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Do not run as root. Run as your normal user — sudo is called internally."
    exit 1
fi

ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "WARNING: This script targets aarch64 (RPi OS Bullseye 64-bit)."
    echo "         Detected arch: $ARCH"
    echo "         For x86_64 Linux Mint, use setup/install.sh instead."
    read -rp "Continue anyway? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] || exit 1
fi

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")"   # APRS_transfer root
INSTALL_DIR="$HOME/APRS"
LOG_FILE="$SOURCE_DIR/install_rpi.log"
CURRENT_USER="$USER"
HOME_DIR="$HOME"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "APRS Station RPi Install — $(date)"
echo "User: $CURRENT_USER  |  Arch: $ARCH"
echo "Source: $SOURCE_DIR"
echo "Install to: $INSTALL_DIR"
echo "========================================"

# ── Step 0: Copy project to ~/APRS ───────────────────────────────────────────
echo ""
echo "── 0. Installing project files to ~/APRS ───────────────────────────────"

if [ -d "$INSTALL_DIR" ]; then
    echo "  $INSTALL_DIR already exists."
    echo "  To clean re-install: rm -rf ~/APRS  then re-run this script."
    echo "  Continuing with existing directory — not overwriting your files."
else
    mkdir -p "$INSTALL_DIR"
    rsync -a --exclude='install_rpi.log' --exclude='install.log' \
          "$SOURCE_DIR/" "$INSTALL_DIR/"
    echo "  Project files copied to $INSTALL_DIR"
fi

PROJECT_DIR="$INSTALL_DIR"

# ── Step 1: System packages ───────────────────────────────────────────────────
echo ""
echo "── 1. System packages ──────────────────────────────────────────────────"

sudo apt-get update -qq

sudo apt-get install -y \
    direwolf \
    python3-pip \
    python3-venv \
    python3-yaml \
    alsa-utils \
    wget curl sox jq libsndfile1 rsync

# chromium-browser is in RPi OS repos (not a snap — works fine on Bullseye)
if command -v chromium-browser &>/dev/null; then
    echo "  chromium-browser already installed."
else
    sudo apt-get install -y chromium-browser && echo "  chromium-browser installed."
fi

# ── Step 2: Python virtual environment ───────────────────────────────────────
echo ""
echo "── 2. Python virtual environment ───────────────────────────────────────"

PYTHON_VER=$(python3 --version)
echo "  System Python: $PYTHON_VER"

if [ ! -d "$HOME_DIR/aprs_env" ]; then
    python3 -m venv "$HOME_DIR/aprs_env"
    echo "  Created ~/aprs_env"
else
    echo "  ~/aprs_env already exists — skipping creation"
fi

source "$HOME_DIR/aprs_env/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet flask flask-socketio aprslib pydub pyyaml requests
echo "  Python packages installed: flask flask-socketio aprslib pydub pyyaml requests"

# ── Step 3: Piper TTS (aarch64) ───────────────────────────────────────────────
echo ""
echo "── 3. Piper TTS (aarch64) ──────────────────────────────────────────────"

PIPER_TAG="2023.11.14-2"
PIPER_URL="https://github.com/rhasspy/piper/releases/download/${PIPER_TAG}/piper_linux_aarch64.tar.gz"

mkdir -p "$HOME_DIR/piper/voices"

if [ ! -f "$HOME_DIR/piper/piper" ]; then
    echo "  Downloading Piper binary (aarch64)..."
    wget -q --show-progress -O /tmp/piper.tar.gz "$PIPER_URL"
    tar -xzf /tmp/piper.tar.gz -C "$HOME_DIR/piper/" --strip-components=1
    chmod +x "$HOME_DIR/piper/piper"
    rm -f /tmp/piper.tar.gz
    echo "  Piper binary installed at ~/piper/piper"
else
    echo "  Piper binary already present — skipping."
fi

VOICE_BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium"
VOICE_ONNX="$HOME_DIR/piper/voices/en_US-lessac-medium.onnx"
VOICE_JSON="$HOME_DIR/piper/voices/en_US-lessac-medium.onnx.json"

if [ ! -f "$VOICE_ONNX" ]; then
    echo "  Downloading voice model (en_US-lessac-medium)..."
    wget -q --show-progress -O "$VOICE_ONNX" "${VOICE_BASE}/en_US-lessac-medium.onnx"
    wget -q --show-progress -O "$VOICE_JSON" "${VOICE_BASE}/en_US-lessac-medium.onnx.json"
    echo "  Voice model installed."
else
    echo "  Voice model already present — skipping."
fi

# ── Step 4: AIOC udev rule + PulseAudio exclusion ────────────────────────────
# RPi OS Bullseye uses PulseAudio (not PipeWire/WirePlumber).
# PULSE_IGNORE=1 on the sound subsystem rule tells PulseAudio to leave the
# AIOC alone, so Direwolf gets exclusive ALSA access to plughw:1,0.
# The hidraw rule creates the stable /dev/aioc_hid symlink for PTT.
echo ""
echo "── 4. AIOC udev rule + PulseAudio exclusion ────────────────────────────"

cat > /tmp/_aioc_udev_rpi.sh << 'AIOC_UDEV'
#!/usr/bin/env bash
set -e
cat > /etc/udev/rules.d/99-aioc.rules << 'EOF'
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="7388", SYMLINK+="aioc_hid", MODE="0666"
SUBSYSTEM=="sound",  ATTRS{idVendor}=="1209", ATTRS{idProduct}=="7388", ENV{PULSE_IGNORE}="1", ENV{ID_MODEL}="AIOC"
EOF
udevadm control --reload-rules
udevadm trigger
echo "  udev rule installed."
echo "  PULSE_IGNORE=1 prevents PulseAudio from claiming the AIOC."
echo "  /dev/aioc_hid symlink will be created on plug-in."
AIOC_UDEV
sudo bash /tmp/_aioc_udev_rpi.sh
rm -f /tmp/_aioc_udev_rpi.sh

# ── Step 5: APRS-IS passcode ──────────────────────────────────────────────────
echo ""
echo "── 5. APRS-IS passcode ─────────────────────────────────────────────────"
source "$HOME_DIR/aprs_env/bin/activate"
python3 "$PROJECT_DIR/setup/calculate_passcode.py"

# ── Step 6: Direwolf config ───────────────────────────────────────────────────
echo ""
echo "── 6. Generating config/direwolf.conf ──────────────────────────────────"
mkdir -p "$PROJECT_DIR/config"

source "$HOME_DIR/aprs_env/bin/activate"
python3 - << PYEOF
import yaml

with open('$PROJECT_DIR/config.yaml') as f:
    cfg = yaml.safe_load(f)

callsign = cfg['callsign'].upper()
ssid = cfg.get('ssid', 0)
mycall = f"{callsign}-{ssid}" if ssid else callsign
adevice = cfg['direwolf']['adevice']

conf = (
    f"ADEVICE {adevice}\n"
    f"CHANNEL 0\n"
    f"MYCALL {mycall}\n"
    f"MODEM 1200\n"
    f"PTT CM108 /dev/aioc_hid\n"
    f"AGWPORT 8000\n"
    f"KISSPORT 8001\n"
)

with open('$PROJECT_DIR/config/direwolf.conf', 'w') as f:
    f.write(conf)

print(f"  Written config/direwolf.conf")
print(f"    MYCALL  : {mycall}")
print(f"    ADEVICE : {adevice}")
print(f"    PTT     : CM108 /dev/aioc_hid")
PYEOF

# ── Step 7: Systemd services ──────────────────────────────────────────────────
echo ""
echo "── 7. Systemd services ─────────────────────────────────────────────────"

cat > /tmp/_aprs_svc_rpi.sh << SVCEOF
#!/usr/bin/env bash
set -e

cat > /etc/systemd/system/direwolf.service << 'EOF'
[Unit]
Description=Direwolf APRS TNC
After=sound.target

[Service]
User=${CURRENT_USER}
SupplementaryGroups=audio dialout
ExecStart=/usr/bin/direwolf -c ${PROJECT_DIR}/config/direwolf.conf -t 0
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/aprs_station.service << 'EOF'
[Unit]
Description=APRS Station Web Server
After=direwolf.service network.target

[Service]
User=${CURRENT_USER}
WorkingDirectory=${PROJECT_DIR}
ExecStart=${HOME_DIR}/aprs_env/bin/python ${PROJECT_DIR}/aprs_router.py
Restart=on-failure
RestartSec=5
Environment=HOME=${HOME_DIR}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable direwolf aprs_station
echo "  Services installed and enabled."
SVCEOF
sudo bash /tmp/_aprs_svc_rpi.sh
rm -f /tmp/_aprs_svc_rpi.sh

sudo usermod -aG dialout,audio "$CURRENT_USER"
echo "  User $CURRENT_USER added to: dialout audio"

# ── Step 8: Kiosk autostart ───────────────────────────────────────────────────
echo ""
echo "── 8. Kiosk autostart ──────────────────────────────────────────────────"
source "$HOME_DIR/aprs_env/bin/activate"
KIOSK_MODE=$(python3 -c "
import yaml
with open('$PROJECT_DIR/config.yaml') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('kiosk_mode', False))
" 2>/dev/null || echo "False")

if [ "$KIOSK_MODE" = "True" ]; then
    mkdir -p "$HOME_DIR/.config/autostart"
    cat > "$HOME_DIR/.config/autostart/aprs_kiosk.desktop" << 'KIOSK_EOF'
[Desktop Entry]
Type=Application
Name=APRS Kiosk
Exec=chromium-browser --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble http://localhost:5000
KIOSK_EOF
    echo "  Kiosk autostart created: ~/.config/autostart/aprs_kiosk.desktop"
    echo "  Chromium will open fullscreen to localhost:5000 on next login."
else
    echo "  kiosk_mode is false — set to true in config.yaml to enable."
    echo "  Open http://localhost:5000 in any browser."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "RPi Install complete — $(date)"
echo ""
echo "NEXT STEPS (in order):"
echo ""
echo "  1.  LOG OUT and log back in"
echo "      (required for dialout/audio group changes)"
echo ""
echo "  2.  Plug in the AIOC USB cable"
echo ""
echo "  3.  Confirm device paths:"
echo "        bash $PROJECT_DIR/tools/find_aioc.sh"
echo "      If ALSA card number differs from plughw:1,0, update config.yaml"
echo "      then re-generate: python3 $PROJECT_DIR/setup/calculate_passcode.py"
echo "      and re-run this script (skips completed steps)."
echo ""
echo "  4.  Test TTS:"
echo "        source ~/aprs_env/bin/activate"
echo "        python3 $PROJECT_DIR/tools/check_audio.py"
echo ""
echo "  5.  Start Direwolf:"
echo "        sudo systemctl start direwolf"
echo "        journalctl -u direwolf -f"
echo ""
echo "  6.  Verify packet decode:"
echo "        source ~/aprs_env/bin/activate"
echo "        python3 $PROJECT_DIR/tools/check_direwolf.py"
echo ""
echo "  7.  Start web server:"
echo "        sudo systemctl start aprs_station"
echo ""
echo "  8.  Open browser: http://localhost:5000"
echo "      (or http://<rpi-ip>:5000 from another device on the network)"
echo ""
echo "── HARDWARE NOTES ──────────────────────────────────────────────────────"
echo ""
echo "  FERRITE CHOKE: Wrap 2-3 turns of the AIOC USB cable through a ferrite"
echo "  core. Without it, RF on TX couples into USB → Direwolf crash + radio"
echo "  stays keyed until cable is unplugged."
echo ""
echo "  AUDIO on RPi 3B+: The onboard bcm2835 audio is card 0."
echo "  The AIOC should appear as card 1 (plughw:1,0)."
echo "  Run tools/find_aioc.sh to confirm."
echo ""
echo "Log saved to: $LOG_FILE"
echo "========================================"
