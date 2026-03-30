# SQLite Reference

Database file: `data/aprs_log.db`
Created by `init_db()` in `aprs_router.py`.
Each thread gets its own connection via `threading.local()` (`get_db()`).

---

## Table: packets

Stores every decoded packet received from Direwolf AGW or APRS-IS.

```sql
CREATE TABLE IF NOT EXISTS packets (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    received_at   DATETIME DEFAULT CURRENT_TIMESTAMP,
    source        TEXT,
    destination   TEXT,
    packet_type   TEXT,
    raw           TEXT,
    parsed_json   TEXT
);
```

| Column | Description |
|--------|-------------|
| `source` | Originating callsign (from APRS packet) |
| `destination` | Destination field (e.g. `APRS`, `APZ001`) |
| `packet_type` | `position`, `message`, `weather`, `status`, `object`, `other` |
| `raw` | Full TNC2-format string |
| `parsed_json` | JSON from `aprslib.parse()` — may be `{}` if parse failed |

---

## Table: messages

Stores APRS messages only (type `message`), both inbound and outbound.

```sql
CREATE TABLE IF NOT EXISTS messages (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    received_at   DATETIME DEFAULT CURRENT_TIMESTAMP,
    direction     TEXT CHECK(direction IN ('IN','OUT')),
    from_call     TEXT,
    to_call       TEXT,
    message_text  TEXT,
    message_id    TEXT,
    acknowledged  INTEGER DEFAULT 0,
    read          INTEGER DEFAULT 0
);
```

| Column | Description |
|--------|-------------|
| `direction` | `IN` = received, `OUT` = sent |
| `message_id` | APRS message number (e.g. `"001"`) — 3-digit zero-padded string |
| `acknowledged` | **Always 0** — not currently written; ACK state is in-memory only |
| `read` | `1` after user clicks the inbound message row in the UI |

### Important: retry state is NOT in the database

Retry tracking lives entirely in the `_pending_acks` in-memory dict in
`aprs_router.py`.  If the service restarts, all pending retry state is lost.
The UI recovers by calling `GET /api/pending_retries` on page load.

There is **no `retries` column** in the schema.

---

## Common Queries

```sql
-- Last 20 packets
SELECT received_at, source, packet_type, raw
FROM packets ORDER BY id DESC LIMIT 20;

-- All messages, newest first
SELECT received_at, direction, from_call, to_call, message_text, message_id
FROM messages ORDER BY id DESC;

-- Unread inbound messages
SELECT * FROM messages WHERE direction='IN' AND read=0;

-- Outbound messages that were never ACK'd
-- (acknowledged is always 0, so check message_id existence instead)
SELECT * FROM messages WHERE direction='OUT';
```

---

## WAL Mode

For better concurrent read performance (UI polling while AGW thread writes),
enable WAL mode once:

```bash
sqlite3 data/aprs_log.db "PRAGMA journal_mode=WAL;"
```

This is not set automatically by the code — apply manually if needed.
