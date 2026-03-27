#!/usr/bin/env python3
"""
test_receive.py — Inject a fake inbound APRS message to test the full pipeline:
AGW decode → DB → TTS → WebSocket → UI

Reads config.yaml to determine this station's callsign and the partner callsign,
then injects a message as if received from the partner station.

Usage: python3 tools/test_receive.py
"""

import socket
import struct
import sys
import time
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML required.  pip install pyyaml")
    sys.exit(1)

CONFIG_FILE = Path(__file__).parent.parent / "config.yaml"

with open(CONFIG_FILE) as f:
    config = yaml.safe_load(f)

MY_CALL    = config["callsign"].upper()
PARTNER    = config.get("partner_callsign", "KE8DUO").upper()
MY_SSID    = int(config.get("ssid", 0))
MYCALL     = f"{MY_CALL}-{MY_SSID}" if MY_SSID else MY_CALL

# Build a realistic APRS message packet
# :ADDRESSEE :message text{msgNo
addressee_padded = MYCALL[:9].ljust(9)
MSG_NO    = "T01"
MSG_TEXT  = f"Test message from {PARTNER} - pipeline check"
INFO      = f":{addressee_padded}:{MSG_TEXT}{{{MSG_NO}"

# Full TNC2 packet string
PACKET    = f"{PARTNER}>APRS,WIDE1-1:{INFO}"

AGW_FMT   = "<B3xBxBx10s10sII"
AGW_SIZE  = struct.calcsize(AGW_FMT)   # 36

AGW_HOST  = "localhost"
AGW_PORT  = 8000


def make_frame(data_kind, call_from="", call_to="", pid=0, data=b""):
    cf = call_from.encode()[:10].ljust(10, b"\x00")
    ct = call_to.encode()[:10].ljust(10, b"\x00")
    hdr = struct.pack(AGW_FMT, 0, ord(data_kind), pid, cf, ct, len(data), 0)
    return hdr + data


def main():
    print(f"APRS Receive Test")
    print(f"  This station : {MYCALL}")
    print(f"  Partner      : {PARTNER}")
    print(f"  Packet       : {PACKET}")
    print()

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect((AGW_HOST, AGW_PORT))
        print(f"Connected to Direwolf AGW {AGW_HOST}:{AGW_PORT}")
    except ConnectionRefusedError:
        print(f"ERROR: Could not connect to Direwolf AGW on {AGW_HOST}:{AGW_PORT}")
        print("Make sure direwolf.service is running: sudo systemctl start direwolf")
        sys.exit(1)

    # Register our callsign (as the "receiving" callsign)
    sock.sendall(make_frame("R", call_from=MYCALL))
    time.sleep(0.3)

    # Inject the fake packet as a 'T' (UI) frame from the partner
    # DataKind 'T' = inject received data frame (Direwolf will route it internally)
    # We send it as if it came from PARTNER
    data = PACKET.encode("ascii")
    frame = make_frame("T",
                       call_from=PARTNER,
                       call_to="APRS",
                       pid=0xF0,
                       data=data)
    sock.sendall(frame)
    print(f"Injected packet: {PACKET}")
    print()
    print("Expected results:")
    print(f"  1. Piper TTS should speak: 'APRS message from {spell_call(PARTNER)}. {MSG_TEXT}'")
    print(f"  2. My Messages panel in UI should show the message (unread, highlighted)")
    print(f"  3. An ACK packet should appear in the packet stream")
    print()
    print("Check: open http://localhost:5000 in your browser.")

    time.sleep(1)
    sock.close()


def spell_call(call):
    NATO = {"A":"Alpha","B":"Bravo","C":"Charlie","D":"Delta","E":"Echo",
            "F":"Foxtrot","G":"Golf","H":"Hotel","I":"India","J":"Juliet",
            "K":"Kilo","L":"Lima","M":"Mike","N":"November","O":"Oscar",
            "P":"Papa","Q":"Quebec","R":"Romeo","S":"Sierra","T":"Tango",
            "U":"Uniform","V":"Victor","W":"Whiskey","X":"X-ray","Y":"Yankee","Z":"Zulu"}
    call = call.split("-")[0].upper()
    return " ".join(NATO.get(c, c) if c.isalpha() else c for c in call if c.isalnum())


if __name__ == "__main__":
    main()
