#!/usr/bin/env bash
set -e

cat > /etc/systemd/system/direwolf.service << 'EOF'
[Unit]
Description=Direwolf APRS TNC
After=sound.target

[Service]
User=dell
ExecStart=/usr/bin/direwolf -c /home/dell/APRS/config/direwolf.conf -t 0
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
User=dell
WorkingDirectory=/home/dell/APRS
ExecStart=/home/dell/aprs_env/bin/python /home/dell/APRS/aprs_router.py
Restart=on-failure
RestartSec=5
Environment=HOME=/home/dell

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable direwolf aprs_station
systemctl start direwolf
echo ""
systemctl status direwolf --no-pager
