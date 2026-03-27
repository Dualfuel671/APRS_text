#!/usr/bin/env bash
# APRS Station install script — idempotent, works on Linux Mint x86_64 and RPi OS aarch64
# Usage: bash setup/install.sh    (run from aprs_station/ project root)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$SCRIPT_DIR/install.log"
ARCH=$(uname -m)
CURRENT_USER="$USER"
HOME_DIR="$HOME"

# Tee all output to log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "APRS Station Install — $(date)"
echo "User: $CURRENT_USER | Arch: $ARCH | Project: $PROJECT_DIR"
echo "========================================"

cd "$PROJECT_DIR"

# ── 1. System packages ────────────────────────────────────────────────────────
echo ""
echo "── 1. Installing system packages ────────────────────────────────────────"
sudo apt-get update -qq

sudo apt-get install -y \
    direwolf \
    python3-pip \
    python3-venv \
    python3-yaml \
    alsa-utils \
    wget curl sox jq libsndfile1

# Install Chromium — only needed for kiosk mode; non-fatal if unavailable.
# On Ubuntu 24.04+, chromium-browser is a snap stub so we try the plain
# 'chromium' package from universe, then warn if neither installs.
echo "Checking for Chromium browser..."
if command -v chromium-browser &>/dev/null || command -v chromium &>/dev/null; then
    echo "  Chromium already installed — skipping."
elif sudo apt-get install -y chromium 2>/dev/null; then
    echo "  Installed chromium."
elif sudo apt-get install -y chromium-browser 2>/dev/null; then
    echo "  Installed chromium-browser."
else
    echo "  WARNING: Could not install Chromium via apt."
    echo "  For kiosk mode (KE8DUO RPi) install it manually."
    echo "  For this desktop (KE8DCJ) you can open localhost:5000 in any browser — continuing."
fi

# ── 2. Python virtual environment ─────────────────────────────────────────────
echo ""
echo "── 2. Python virtual environment ────────────────────────────────────────"
if [ ! -d "$HOME_DIR/aprs_env" ]; then
    python3 -m venv "$HOME_DIR/aprs_env"
    echo "Created venv at ~/aprs_env"
else
    echo "venv already exists — skipping creation"
fi

source "$HOME_DIR/aprs_env/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet flask flask-socketio aprslib pydub pyyaml requests
echo "Python packages installed."

# ── 3. Piper TTS — arch-aware install ────────────────────────────────────────
echo ""
echo "── 3. Installing Piper TTS ($ARCH) ──────────────────────────────────────"
PIPER_TAG="2023.11.14-2"
if [ "$ARCH" = "x86_64" ]; then
    PIPER_URL="https://github.com/rhasspy/piper/releases/download/${PIPER_TAG}/piper_linux_x86_64.tar.gz"
elif [ "$ARCH" = "aarch64" ]; then
    PIPER_URL="https://github.com/rhasspy/piper/releases/download/${PIPER_TAG}/piper_linux_aarch64.tar.gz"
else
    echo "ERROR: Unsupported architecture: $ARCH"
    exit 1
fi

mkdir -p "$HOME_DIR/piper/voices"

if [ ! -f "$HOME_DIR/piper/piper" ]; then
    echo "Downloading Piper binary from $PIPER_URL ..."
    rm -f /tmp/piper.tar.gz
    wget -O /tmp/piper.tar.gz "$PIPER_URL"
    # tarball contains piper/ prefix; strip it so files land directly in ~/piper/
    tar -xzf /tmp/piper.tar.gz -C "$HOME_DIR/piper/" --strip-components=1
    chmod +x "$HOME_DIR/piper/piper"
    echo "Piper binary installed."
else
    echo "Piper binary already installed — skipping."
fi

VOICE_BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium"
VOICE_ONNX="$HOME_DIR/piper/voices/en_US-lessac-medium.onnx"
VOICE_JSON="$HOME_DIR/piper/voices/en_US-lessac-medium.onnx.json"

if [ ! -f "$VOICE_ONNX" ]; then
    echo "Downloading Piper voice model..."
    wget -O "$VOICE_ONNX" "${VOICE_BASE}/en_US-lessac-medium.onnx"
    wget -O "$VOICE_JSON" "${VOICE_BASE}/en_US-lessac-medium.onnx.json"
    echo "Voice model installed."
else
    echo "Voice model already installed — skipping."
fi

# ── 4. AIOC udev rules ────────────────────────────────────────────────────────
echo ""
echo "── 4. Installing AIOC udev rules ────────────────────────────────────────"
UDEV_FILE="/etc/udev/rules.d/99-aioc.rules"
if [ ! -f "$UDEV_FILE" ]; then
    sudo tee "$UDEV_FILE" > /dev/null << 'EOF'
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="7388", SYMLINK+="aioc_hid", MODE="0666"
SUBSYSTEM=="sound", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="7388", ENV{ID_MODEL}="AIOC"
EOF
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    echo "udev rules installed."
else
    echo "udev rules already installed — skipping."
fi

# Add user to groups
sudo usermod -aG dialout,audio "$CURRENT_USER"
echo "User $CURRENT_USER added to dialout and audio groups."

# ── 5. APRS-IS passcode ───────────────────────────────────────────────────────
echo ""
echo "── 5. Calculating APRS-IS passcode ──────────────────────────────────────"
python3 "$SCRIPT_DIR/calculate_passcode.py"

# ── 6. Generate Direwolf config ───────────────────────────────────────────────
echo ""
echo "── 6. Generating config/direwolf.conf ───────────────────────────────────"
mkdir -p "$PROJECT_DIR/config"
python3 - << PYEOF
import yaml, os, sys
sys.path.insert(0, '$PROJECT_DIR')

with open('$PROJECT_DIR/config.yaml') as f:
    cfg = yaml.safe_load(f)

callsign = cfg['callsign'].upper()
ssid = cfg.get('ssid', 0)
mycall = f"{callsign}-{ssid}" if ssid else callsign
adevice = cfg['direwolf']['adevice']
ptt_device = cfg['direwolf']['ptt_device']

conf = f"""ADEVICE {adevice}
CHANNEL 0
MYCALL {mycall}
MODEM 1200
PTT HID {ptt_device}
AGWPORT 8000
KISSPORT 8001
"""

with open('$PROJECT_DIR/config/direwolf.conf', 'w') as f:
    f.write(conf)
print(f"Written config/direwolf.conf for {mycall}")
PYEOF

# ── 7. Systemd services ───────────────────────────────────────────────────────
echo ""
echo "── 7. Installing systemd services ───────────────────────────────────────"

sudo tee /etc/systemd/system/direwolf.service > /dev/null << EOF
[Unit]
Description=Direwolf APRS TNC
After=sound.target

[Service]
User=$CURRENT_USER
ExecStart=/usr/bin/direwolf -c $PROJECT_DIR/config/direwolf.conf -t 0
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/aprs_station.service > /dev/null << EOF
[Unit]
Description=APRS Station Web Server
After=direwolf.service network.target

[Service]
User=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$HOME_DIR/aprs_env/bin/python $PROJECT_DIR/aprs_router.py
Restart=on-failure
RestartSec=5
Environment=HOME=$HOME_DIR

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable direwolf aprs_station
echo "systemd services installed and enabled."

# ── 8. Kiosk autostart (RPi / kiosk_mode: true only) ─────────────────────────
echo ""
echo "── 8. Kiosk autostart ───────────────────────────────────────────────────"
KIOSK_MODE=$(python3 -c "import yaml; cfg=yaml.safe_load(open('config.yaml')); print(cfg.get('kiosk_mode', False))")

if [ "$KIOSK_MODE" = "True" ]; then
    mkdir -p "$HOME_DIR/.config/autostart"
    cat > "$HOME_DIR/.config/autostart/aprs_kiosk.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=APRS Kiosk
Exec=chromium-browser --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble http://localhost:5000
EOF
    echo "Kiosk autostart created."
else
    echo "kiosk_mode is false — skipping kiosk autostart."
    echo "Open http://localhost:5000 manually in your browser."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "Install complete — $(date)"
echo ""
echo "Next steps:"
echo "  1. Run: bash tools/find_aioc.sh       (confirm AIOC device paths)"
echo "  2. Run: python3 tools/check_audio.py  (test TTS + speakers)"
echo "  3. Run: python3 tools/check_direwolf.py (verify AGW connection)"
echo "  4. sudo systemctl start direwolf aprs_station"
echo "  5. Open http://localhost:5000"
echo "  NOTE: Log out and back in for group changes (dialout/audio) to take effect."
echo "========================================"
