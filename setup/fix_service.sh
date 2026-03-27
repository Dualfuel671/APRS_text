#!/usr/bin/env bash
set -e

cat > /etc/systemd/system/direwolf.service << 'EOF'
[Unit]
Description=Direwolf APRS TNC
After=sound.target

[Service]
User=dell
SupplementaryGroups=audio dialout
ExecStart=/usr/bin/direwolf -c /home/dell/APRS/config/direwolf.conf -t 0
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
echo "direwolf.service fixed"
systemctl status direwolf --no-pager -l
