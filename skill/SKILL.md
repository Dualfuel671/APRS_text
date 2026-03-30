# APRS Station — Developer Skill File

This file is the top-level reference for anyone (or any AI assistant) picking up
work on the KE8DCJ / KE8DUO APRS station codebase.  Read this first, then follow
the pointers to the reference files for deeper detail.

---

## Stack at a Glance

| Layer | Technology | Notes |
|-------|-----------|-------|
| TNC / modem | Direwolf (systemd service) | AGW :8000 (RX monitor), KISS :8001 (TX only) |
| Backend | Python 3.9+, Flask + Flask-SocketIO | `aprs_router.py` — single file, ~730 lines |
| Database | SQLite (`data/aprs_log.db`) | Thread-local connections; see `references/sqlite.md` |
| TTS | Piper (`~/piper/piper`) | Runs in a background queue worker thread |
| Frontend | Vanilla JS + Socket.IO | Single template `templates/index.html`; no build step |
| APRS-IS | Raw TCP to `rotate.aprs2.net:14580` | Secondary RX feed; optional (`aprs_is.enabled`) |

---

## Station Hardware

| Item | KE8DCJ (x86_64) | KE8DUO (RPi 3B+) |
|------|-----------------|------------------|
| OS | Linux Mint 21+ | RPi OS Bullseye 64-bit |
| Radio | Baofeng UV-5R | Baofeng UV-5R |
| Interface | AIOC (NA6D) USB-C | AIOC (NA6D) USB-C |
| Frequency | 144.390 MHz | 144.390 MHz |
| Kiosk mode | No | Optional (`kiosk_mode: true`) |

**AIOC USB IDs:** VID `1209` / PID `7388`

---

## Critical Design Decisions

### TX via KISS, not AGW
Direwolf's AGW monitoring connection (`T` frames) is **receive-only** — sending
a `T` frame on it is silently rejected.  All outbound packets go through the
KISS port 8001 using raw AX.25 frames built in `_build_ax25_ui()`.

### udev symlink for PTT
Always use `/dev/aioc_hid` (the stable udev symlink), never `/dev/hidrawN`.
The hidraw number changes at every boot.

### WirePlumber must be excluded
Without an exclusion rule, PipeWire/WirePlumber grabs the AIOC audio device
before Direwolf starts, causing Direwolf to fail with "Device or resource busy".
Fix: `~/.config/wireplumber/main.lua.d/50-aioc-reserve.lua`

### Ferrite choke — hardware requirement
RF couples back through the AIOC USB cable during PTT and can crash Direwolf
with an EPIPE error, leaving the radio keyed.  A ferrite choke on the cable is
the only reliable fix (software debounce is not sufficient).

### Socket.IO served locally
Flask-SocketIO 5.x intercepts the `/socket.io/` URL path, breaking CDN loads.
`socket.io.min.js` must be served from `/static/`.

### Piper TTS — two gotchas
1. **Tilde path**: `~/piper/piper` must be resolved with `Path.home()`, not
   passed as a literal string to subprocess (the shell does not expand `~` when
   `shell=False`).
2. **Buffering**: Piper reads from stdin; pass `input=text.encode()` to
   `subprocess.run()` — do not use `communicate()` or a pipe without flushing.

### systemd audio session
The service runs as root but needs access to the user's PulseAudio / PipeWire
session for `aplay`.  The service unit must set:
```
Environment=XDG_RUNTIME_DIR=/run/user/1000
```
(replace `1000` with the actual UID).  Without this, `aplay` fails silently.

---

## Message Retry System

Outbound messages are queued in `_pending_acks` (in-memory dict, keyed by
message_id string e.g. `"001"`).  A background thread (`_retry_worker`) wakes
every 5 s and retransmits any message whose `next_retry` time has passed.

| Parameter | Value |
|-----------|-------|
| Max retries | 5 |
| Retry interval | 30 s |
| Storage | In-memory only — not persisted to SQLite |

When an ACK arrives, `_handle_inbound()` pops the entry and emits
`message_status {id, status: "acked"}` over WebSocket.

The **Cancel Retry** button (added 2026-03-30) calls
`POST /api/cancel_retry/<msg_id>`, which pops the entry and emits
`message_status {id, status: "cancelled"}`.  The UI button is driven entirely
by this socket event — the fetch response is not used for UI state.

`GET /api/pending_retries` returns the current list of pending message_ids so
the UI can restore Cancel Retry buttons after a page reload.

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Serve `index.html` |
| GET | `/api/status` | Direwolf/APRS-IS connected, callsign, uptime |
| GET | `/api/packets` | Last 100 packets from DB |
| GET | `/api/messages` | All messages from DB |
| POST | `/api/send` | Send APRS message `{to, message}` |
| POST | `/api/ack/<int:id>` | Mark inbound message read (DB row id) |
| GET | `/api/pending_retries` | List message_ids in retry queue |
| POST | `/api/cancel_retry/<msg_id>` | Cancel retry for a message |
| POST | `/api/test_tts` | Queue a TTS audio test phrase |
| POST | `/api/inject` | Inject raw TNC2 packet (test tool) |

---

## Reference Files

- [`references/direwolf.md`](references/direwolf.md) — ALSA device selection,
  direwolf.conf, PTT wiring options, troubleshooting
- [`references/sqlite.md`](references/sqlite.md) — Table schemas, common
  queries, WAL mode, retry state note
- [`references/ui.md`](references/ui.md) — Color palette, SocketIO event table,
  layout diagram, retry button implementation, Chromium kiosk command
