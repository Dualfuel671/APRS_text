#!/usr/bin/env python3
"""
test_receive.py — Inject a fake inbound APRS message to test the full pipeline:
process_packet() → DB → TTS → WebSocket → UI

Posts directly to /api/inject on the running aprs_station web server.
This bypasses AGW entirely — Direwolf does not loop injected AGW frames
back to monitoring connections, so the old AGW-injection approach never
reached process_packet() and produced no TTS, no message, no ACK.

Usage: python3 tools/test_receive.py
"""

import json
import sys
from pathlib import Path

try:
    import requests
except ImportError:
    print("ERROR: requests not installed.  pip install requests")
    sys.exit(1)

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed.  pip install pyyaml")
    sys.exit(1)

CONFIG_FILE = Path(__file__).parent.parent / "config.yaml"

with open(CONFIG_FILE) as f:
    config = yaml.safe_load(f)

MY_CALL = config["callsign"].upper()
PARTNER = config.get("partner_callsign", "KE8DUO").upper()
MY_SSID = int(config.get("ssid", 0))
MYCALL  = f"{MY_CALL}-{MY_SSID}" if MY_SSID else MY_CALL

BASE_URL = "http://localhost:5000"

# Build a realistic APRS message packet addressed to this station
addressee_padded = MYCALL[:9].ljust(9)
MSG_NO   = "T01"
MSG_TEXT = f"Test message from {PARTNER} - pipeline check"
INFO     = f":{addressee_padded}:{MSG_TEXT}{{{MSG_NO}"
PACKET   = f"{PARTNER}>APRS,WIDE1-1:{INFO}"


def spell_call(call):
    NATO = {"A":"Alpha","B":"Bravo","C":"Charlie","D":"Delta","E":"Echo",
            "F":"Foxtrot","G":"Golf","H":"Hotel","I":"India","J":"Juliet",
            "K":"Kilo","L":"Lima","M":"Mike","N":"November","O":"Oscar",
            "P":"Papa","Q":"Quebec","R":"Romeo","S":"Sierra","T":"Tango",
            "U":"Uniform","V":"Victor","W":"Whiskey","X":"X-ray","Y":"Yankee","Z":"Zulu"}
    call = call.split("-")[0].upper()
    return " ".join(NATO.get(c, c) if c.isalpha() else c for c in call if c.isalnum())


print("APRS Receive Pipeline Test")
print(f"  This station : {MYCALL}")
print(f"  Partner      : {PARTNER}")
print(f"  Packet       : {PACKET}")
print()

try:
    resp = requests.post(
        f"{BASE_URL}/api/inject",
        json={"raw": PACKET, "origin": "rf"},
        timeout=10,
    )
except requests.ConnectionError:
    print(f"ERROR: Could not reach {BASE_URL}")
    print("Make sure aprs_station.service is running: sudo systemctl start aprs_station")
    sys.exit(1)

print(f"HTTP {resp.status_code}")
try:
    data = resp.json()
    print(json.dumps(data, indent=2))
except Exception:
    print(resp.text)
    sys.exit(1)

if resp.ok and data.get("status") == "injected":
    print()
    print("Packet injected — check for:")
    print(f"  1. TTS speaks : 'APRS message from {spell_call(PARTNER)}. {MSG_TEXT}'")
    print(f"  2. My Messages panel shows the message (unread / highlighted)")
    print(f"  3. ACK packet appears in the live packet stream")
    print()
    print(f"Open: http://localhost:5000")
else:
    print("Injection FAILED.")
    sys.exit(1)
