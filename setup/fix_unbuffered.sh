#!/usr/bin/env bash
# Adds PYTHONUNBUFFERED=1 to aprs_station.service so that print()
# statements appear immediately in journalctl instead of being held
# in Python's stdout buffer.
set -e

PROJECT_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
CURRENT_USER="$(stat -c '%U' "$PROJECT_DIR")"
HOME_DIR="$(eval echo ~$CURRENT_USER)"

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

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
echo "aprs_station.service updated — python -u + PYTHONUNBUFFERED=1"
echo "Run: sudo systemctl restart aprs_station"
