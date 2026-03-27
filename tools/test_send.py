#!/usr/bin/env python3
"""
test_send.py — Call POST /api/send with a test message and print the full JSON response.

Reads callsign and partner_callsign from config.yaml and sends to the partner.

Usage: python3 tools/test_send.py [optional message text]
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
PARTNER = config.get("partner_callsign", "").upper()

if not PARTNER:
    print("ERROR: partner_callsign not set in config.yaml")
    sys.exit(1)

MSG = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else f"Test from {MY_CALL} — system check"

if len(MSG) > 67:
    print(f"ERROR: message length {len(MSG)} exceeds 67-char APRS limit")
    sys.exit(1)

BASE_URL = "http://localhost:5000"

print(f"APRS Send Test")
print(f"  From   : {MY_CALL}")
print(f"  To     : {PARTNER}")
print(f"  Message: {MSG}")
print()

try:
    resp = requests.post(
        f"{BASE_URL}/api/send",
        json={"to": PARTNER, "message": MSG},
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

if resp.ok and data.get("status") == "sent":
    print()
    print(f"Message sent OK — message_id: {data.get('message_id')}")
    print("Check http://localhost:5000 → My Messages panel for the outgoing entry.")
else:
    print()
    print("Send FAILED — check that Direwolf is running and connected.")
    sys.exit(1)
