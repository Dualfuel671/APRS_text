# Direwolf Reference

## ALSA Device Selection

Run `tools/find_aioc.sh` to detect the correct card number.  The AIOC always
has USB IDs VID `1209` / PID `7388`.  Typical output:

```
ALSA device : plughw:1,0
HID device  : /dev/hidrawN  →  symlink /dev/aioc_hid
```

Set `direwolf.adevice: plughw:1,0` in `config.yaml` (card number may differ).
**Never hardcode `/dev/hidrawN`** — use the udev symlink `/dev/aioc_hid`.

---

## Typical direwolf.conf

```
ADEVICE plughw:1,0
CHANNEL 0
MYCALL  KE8DCJ
MODEM   1200
PTT     CM108 /dev/aioc_hid
AGWPORT 8000
KISSPORT 8001
```

The `PTT CM108` line uses the HID interface on the AIOC to key the radio.
`AGWPORT` and `KISSPORT` must both be open — AGW for monitoring (RX), KISS for
transmit (TX).

---

## PTT Wiring Options

| Method | Config line | Notes |
|--------|------------|-------|
| VOX | `PTT VOX` | No PTT control; radio must have VOX enabled |
| Serial RTS | `PTT /dev/ttyUSB0 RTS` | Standard serial cable |
| CM108 (AIOC) | `PTT CM108 /dev/aioc_hid` | Used on this project |
| RPi GPIO | `PTT GPIO 25` | Raspberry Pi only |

---

## AGW vs KISS Ports

| Port | Use | Direction |
|------|-----|-----------|
| AGW :8000 | Monitoring — frame types T, U, K | RX only |
| KISS :8001 | Transmit | TX only |

Attempting to send a `T` frame on the AGW monitoring connection is silently
rejected by Direwolf.  All outbound packets in this codebase use KISS.

The AGW reader thread (`_agw_reader`) registers the callsign with frame `R`
and enables monitor mode with frame `m` immediately after connecting.

---

## RF Ingress / Ferrite Choke

Without a ferrite choke on the AIOC USB cable, RF couples into the cable during
PTT and crashes Direwolf with an EPIPE error, leaving the radio keyed.  This is
a **hardware fix** — no software workaround is sufficient.  Wrap 3–5 turns of
the cable through a snap-on ferrite near the AIOC end.

---

## WirePlumber Exclusion

PipeWire / WirePlumber claims the AIOC audio device on login, preventing
Direwolf from opening it.  Fix:

```lua
-- ~/.config/wireplumber/main.lua.d/50-aioc-reserve.lua
rule = {
  matches = { { { "device.name", "equals", "alsa_card.usb-NA6D_AIOC_..." } } },
  apply_properties = { ["device.disabled"] = true },
}
table.insert(alsa_monitor.rules, rule)
```

Log out and back in after creating this file.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| "Device or resource busy" | PipeWire grabbed AIOC | Confirm WirePlumber exclusion rule, log out/in |
| `/dev/aioc_hid` missing | udev rule not loaded | `sudo udevadm control --reload-rules && sudo udevadm trigger`, replug |
| Radio stays keyed after TX | RF couples into USB | Add ferrite choke |
| Direwolf EPIPE crash | Same as above | Same fix |
| AGW connect refused | Direwolf not running | `sudo systemctl start direwolf` |
| Packets decoded but not appearing in UI | AGW frame type mismatch | Check `dk in ("T", "U", "K")` in `_agw_reader` |

Live Direwolf log:
```bash
journalctl -u direwolf -f
```
