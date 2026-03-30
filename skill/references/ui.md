# UI Reference

Single-page app — `templates/index.html`.  No build step; all JS is inline
vanilla ES6.  Socket.IO client is served locally from `/static/socket.io.min.js`
(Flask-SocketIO 5.x intercepts the CDN path `/socket.io/`).

---

## Layout

```
┌─────────────────────────────────────────────────────────┐
│  STATUS BAR: callsign · freq · Direwolf● · APRS-IS● · uptime · 🔊 Test Audio │
├───────────────────────┬─────────────────────────────────┤
│  SEND MESSAGE         │                                 │
│  ┌─────────────────┐  │  LIVE PACKET STREAM             │
│  │ To: [callsign]  │  │  time  source  type  RF/IS  sum │
│  │ Msg: [textarea] │  │  ...                            │
│  │ [   SEND   ]    │  │                                 │
│  └─────────────────┘  │                                 │
├───────────────────────┤                                 │
│  MY MESSAGES          │                                 │
│  (newest on top)      │                                 │
│  ▶ KE8DUO→KE8DCJ  IN  │                                 │
│  ◀ KE8DCJ→KE8DUO OUT  │                                 │
│    [Cancel Retry]     │                                 │
└───────────────────────┴─────────────────────────────────┘
```

---

## Color Palette (verified against CSS)

### CSS Variables

| Variable | Hex | Used for |
|----------|-----|---------|
| `--bg` | `#0d1117` | Page background |
| `--surface` | `#161b22` | Status bar, send panel |
| `--border` | `#30363d` | All borders |
| `--text` | `#c9d1d9` | Body text |
| `--muted` | `#8b949e` | Labels, timestamps, dim text |
| `--accent` | `#58a6ff` | Callsign, inbound message border, links |
| `--green` | `#3fb950` | Direwolf connected, outbound border, ACK status |
| `--red` | `#f85149` | Errors, disconnected, No ACK status |
| `--orange` | `#d29922` | Weather type, Cancel Retry button |
| `--yellow` | `#e3b341` | APRS-IS connecting dot |
| `--blue-dim` | `#1c2a3f` | Unread message row background |
| `--green-dim` | `#112518` | (defined, not currently used in UI) |

### Packet Type Badges

| Type | Background | Text |
|------|-----------|------|
| `position` | `#0d1e40` | `#79b8ff` (light blue) |
| `message` | `#0d2e18` | `#3fb950` (green) |
| `weather` | `#2e200d` | `#d29922` (orange) |
| `status` | `#1e1e2e` | `#c084fc` (purple) |
| `object` | `#1e2e2e` | `#67e8f9` (cyan) |
| other | `#1e1e1e` | `#8b949e` (muted) |

### Origin Badges (RF / IS)

| Origin | Background | Text |
|--------|-----------|------|
| RF | `#0d2e18` | `#4ade80` (bright green) |
| Internet (IS) | `#1a1a2e` | `#94a3b8` (slate) |

### Message Row Left Border

| Direction | Color |
|-----------|-------|
| IN | `--accent` (`#58a6ff`) |
| OUT | `--green` (`#3fb950`) |

Unread IN rows get `background: --blue-dim` (`#1c2a3f`).

### Message Status Indicators (after retry resolves)

| Status | Color | Label |
|--------|-------|-------|
| `acked` | `--green` (`#3fb950`) | ✓ ACK'd |
| `failed` | `--red` (`#f85149`) | ✗ No ACK |
| `cancelled` | `--muted` (`#8b949e`) | ⊘ Cancelled |

---

## SocketIO Events

### Server → Client

| Event | Payload | Trigger |
|-------|---------|---------|
| `status` | `{direwolf, aprs_is, callsign, frequency, partner, uptime}` | Connect / disconnect / 5 s poll |
| `packet` | `{source, type, summary, raw, origin, timestamp}` | Any decoded packet |
| `message` | `{from_call, to_call, text, direction, timestamp, id}` | Inbound or outbound APRS message |
| `message_status` | `{id, status}` | ACK received, max retries hit, or retry cancelled |

`message.id` is the APRS message_id string (e.g. `"001"`) for socket events.
`message.id` is the **DB row integer** for messages loaded from `/api/messages`.
These are different things — see the ID duality note below.

### Client → Server (REST, not WebSocket)

All sends are plain `fetch()` calls — no client-to-server Socket.IO events.

---

## Message ID Duality

This is a known gotcha.  There are two IDs for messages:

| ID | Type | Source | Used for |
|----|------|--------|---------|
| DB row `id` | Integer | SQLite AUTOINCREMENT | `POST /api/ack/<id>` (mark read) |
| APRS `message_id` | String `"001"`–`"999"` | `_next_msg_id()` | Retry queue key, `message_status` events |

When the UI loads messages from `/api/messages`, both are available:
`m.id` (DB row) and `m.message_id` (APRS id).  The `addMessage()` function
stores `data-id` (DB row) and `data-mid` (APRS id) as separate attributes on
the message row element.

The Cancel Retry button uses `data-mid` to call `/api/cancel_retry/<msg_id>`.
The mark-read click handler uses `data-id` to call `/api/ack/<id>`.

---

## Cancel Retry Button — Implementation Summary

Added 2026-03-30.  Orange button inline in the outbound message header row,
visible only while the message is in `_pending_acks`.

**Flow:**
1. Message sent → server emits `message` event with `direction: "OUT"` → UI
   calls `addMessage(msg, isPending=true)` → button rendered, `pendingRetries`
   Set updated.
2. Page reload → UI calls `GET /api/pending_retries` alongside
   `GET /api/messages` → pending message_ids restored → buttons re-rendered.
3. Button click → `POST /api/cancel_retry/<mid>` → server pops from
   `_pending_acks`, emits `message_status {id, status: "cancelled"}` →
   `message_status` handler removes button, inserts `⊘ Cancelled` span.
4. Same `message_status` handler handles `acked` and `failed` the same way.

The fetch response from cancel is not used for UI state — only the socket event
drives the visual change.

---

## Chromium Kiosk Launch (RPi / KE8DUO)

```bash
chromium-browser --kiosk --noerrdialogs --disable-infobars \
  --app=http://localhost:5000
```

Triggered via `kiosk_mode: true` in `config.yaml`.  Only relevant on the
Raspberry Pi station with an attached display.
