#!/usr/bin/env bash
# Adds XDG_RUNTIME_DIR to aprs_station.service so that aplay can reach
# PipeWire/PulseAudio from within the systemd service context.
# Without this, aplay with 'default' device fails silently because the
# user audio session socket is not visible to system services.
set -e

PROJECT_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
CURRENT_USER="$(stat -c '%U' "$PROJECT_DIR")"
HOME_DIR="$(eval echo ~$CURRENT_USER)"
USER_UID="$(id -u $CURRENT_USER)"

cat > /etc/systemd/system/aprs_station.service << EOF
[Unit]
Description=APRS Station Web Server
After=direwolf.service network.target

[Service]
User=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$HOME_DIR/aprs_env/bin/python -u $PROJECT_DIR/aprs_router.py
Restart=on-failure
RestartSec=5
Environment=HOME=$HOME_DIR
Environment=PYTHONUNBUFFERED=1
Environment=XDG_RUNTIME_DIR=/run/user/$USER_UID

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl restart aprs_station
echo "aprs_station.service updated with XDG_RUNTIME_DIR=/run/user/$USER_UID"
echo "Service restarted."
