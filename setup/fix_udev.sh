#!/usr/bin/env bash
set -e

cat > /etc/udev/rules.d/99-aioc.rules << 'EOF'
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="7388", SYMLINK+="aioc_hid", GROUP="audio", MODE="0660"
SUBSYSTEM=="sound", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="7388", ENV{ID_MODEL}="AIOC"
EOF

udevadm control --reload-rules
udevadm trigger --subsystem-match=hidraw
sleep 1
ls -l /dev/hidraw3
echo "Done. hidraw3 should now be root:audio 0660"
