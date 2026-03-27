#!/usr/bin/env bash
# find_aioc.sh — Detect AIOC (NA6D) sound card and HID device paths.
# Prints the exact strings to paste into config.yaml.

echo "========================================"
echo "AIOC Device Detector"
echo "========================================"

# ── Sound card ────────────────────────────────────────────────────────────────
echo ""
echo "── Searching for AIOC sound card ────────────────────────────────────────"

ADEVICE=""
CARD_NAME=""

# Look in aplay -l for AIOC or cm108 (AIOC appears as cm108 USB audio)
while IFS= read -r line; do
    if echo "$line" | grep -iqE 'aioc|cm108|all-in-one|allinone'; then
        CARD_NUM=$(echo "$line" | grep -oP 'card \K[0-9]+')
        CARD_NAME=$(echo "$line" | grep -oP '(?<=card [0-9]: )[^[]+' | sed 's/[[:space:]]*$//')
        if [ -n "$CARD_NUM" ]; then
            ADEVICE="plughw:$CARD_NUM,0"
            # Also try the name form
            ADEVICE_NAME="plughw:CARD=${CARD_NAME// /},DEV=0"
        fi
    fi
done < <(aplay -l 2>/dev/null)

if [ -n "$ADEVICE" ]; then
    echo "  Found sound card: $CARD_NAME"
    echo ""
    echo "  Add to config.yaml under direwolf:"
    echo "    adevice: \"$ADEVICE_NAME\""
    echo "    (fallback numeric form: \"$ADEVICE\")"
else
    echo "  WARNING: No AIOC / cm108 sound card found in 'aplay -l' output."
    echo "  Make sure the AIOC is plugged in and check with: aplay -l"
fi

# ── ALSA card details ─────────────────────────────────────────────────────────
echo ""
echo "── Full aplay -l output ─────────────────────────────────────────────────"
aplay -l 2>/dev/null || echo "  (aplay not available)"

# ── HID device ───────────────────────────────────────────────────────────────
echo ""
echo "── Searching for AIOC HID device (PTT) ──────────────────────────────────"

HID_DEVICE=""
for dev in /dev/hidraw*; do
    if [ ! -e "$dev" ]; then
        continue
    fi
    # Check vendor/product via sysfs
    SYSFS_PATH=$(udevadm info --query=path --name="$dev" 2>/dev/null)
    if [ -n "$SYSFS_PATH" ]; then
        VENDOR=$(cat "/sys/class/hidraw/$(basename "$dev")/device/uevent" 2>/dev/null | grep -oP '(?<=HID_ID=)[^:]+:[^:]+:[0-9A-Fa-f]+' || true)
        # Alternative: check via udevadm
        INFO=$(udevadm info --name="$dev" 2>/dev/null)
        if echo "$INFO" | grep -q "1209"; then
            if echo "$INFO" | grep -q "7388"; then
                HID_DEVICE="$dev"
                echo "  Found AIOC HID: $dev  (VID=1209 PID=7388)"
            fi
        fi
    fi
done

# Fallback: check /dev/aioc_hid symlink (created by udev rule if installed)
if [ -z "$HID_DEVICE" ] && [ -e "/dev/aioc_hid" ]; then
    HID_DEVICE="/dev/aioc_hid"
    echo "  Found via udev symlink: /dev/aioc_hid -> $(readlink /dev/aioc_hid)"
fi

if [ -n "$HID_DEVICE" ]; then
    echo ""
    echo "  Add to config.yaml under direwolf:"
    echo "    ptt_device: \"$HID_DEVICE\""
else
    echo ""
    echo "  WARNING: No AIOC HID device found in /dev/hidraw*"
    echo "  All /dev/hidraw* devices:"
    ls -la /dev/hidraw* 2>/dev/null || echo "    (none found)"
    echo ""
    echo "  Try: sudo udevadm control --reload-rules && sudo udevadm trigger"
    echo "  Then check: ls -la /dev/hidraw*"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "Summary — paste into config.yaml:"
echo ""
echo "direwolf:"
if [ -n "$ADEVICE_NAME" ]; then
    echo "  adevice: \"$ADEVICE_NAME\""
else
    echo "  adevice: \"plughw:CARD=AIOC,DEV=0\"  # NOT DETECTED — verify manually"
fi
if [ -n "$HID_DEVICE" ]; then
    echo "  ptt_device: \"$HID_DEVICE\""
else
    echo "  ptt_device: \"/dev/hidraw0\"  # NOT DETECTED — verify manually"
fi
echo "========================================"
