#!/usr/bin/env python3
"""
check_direwolf.py — Connect to Direwolf's AGW port on localhost:8000 and wait
30 seconds, printing any packets that arrive.  Useful for confirming Direwolf
is running and the AIOC audio is being decoded correctly.

Usage: python3 tools/check_direwolf.py
"""

import signal
import socket
import struct
import sys
import time
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed.  pip install pyyaml")
    sys.exit(1)

CONFIG_FILE = Path(__file__).parent.parent / "config.yaml"

with open(CONFIG_FILE) as f:
    config = yaml.safe_load(f)

MY_CALL = config["callsign"].upper()
SSID    = int(config.get("ssid", 0))
MYCALL  = f"{MY_CALL}-{SSID}" if SSID else MY_CALL

AGW_HOST = "localhost"
AGW_PORT = 8000
TIMEOUT  = 30

AGW_FMT  = "<B3xBxBx10s10sII"
AGW_SIZE = struct.calcsize(AGW_FMT)


def recv_exactly(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("AGW socket closed")
        buf += chunk
    return buf


def read_frame(sock):
    hdr = recv_exactly(sock, AGW_SIZE)
    port, dk, pid, cf, ct, dlen, _ = struct.unpack(AGW_FMT, hdr)
    data = recv_exactly(sock, dlen) if dlen > 0 else b""
    return {
        "data_kind": chr(dk),
        "call_from": cf.rstrip(b"\x00").decode("ascii", errors="replace").strip(),
        "call_to":   ct.rstrip(b"\x00").decode("ascii", errors="replace").strip(),
        "data":      data,
    }


def make_frame(data_kind, call_from="", call_to="", pid=0, data=b""):
    cf = call_from.encode()[:10].ljust(10, b"\x00")
    ct = call_to.encode()[:10].ljust(10, b"\x00")
    hdr = struct.pack(AGW_FMT, 0, ord(data_kind), pid, cf, ct, len(data), 0)
    return hdr + data


def main():
    print("Direwolf AGW Connection Check")
    print(f"  Station : {MYCALL}")
    print(f"  Target  : {AGW_HOST}:{AGW_PORT}")
    print(f"  Timeout : {TIMEOUT}s")
    print()

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT)
        sock.connect((AGW_HOST, AGW_PORT))
    except ConnectionRefusedError:
        print(f"ERROR: Cannot connect to Direwolf AGW on {AGW_HOST}:{AGW_PORT}")
        print()
        print("Possible fixes:")
        print("  sudo systemctl start direwolf")
        print("  sudo systemctl status direwolf")
        print("  journalctl -u direwolf -n 30")
        sys.exit(1)
    except socket.timeout:
        print("ERROR: Connection timed out.")
        sys.exit(1)

    print(f"Connected to Direwolf AGW  ({AGW_HOST}:{AGW_PORT})")

    # Register and enable monitoring
    sock.sendall(make_frame("R", call_from=MYCALL))
    sock.sendall(make_frame("m"))   # monitor all traffic

    print(f"Listening for packets ({TIMEOUT}s)… press Ctrl+C to stop early.")
    print("-" * 60)

    pkt_count = 0
    deadline = time.time() + TIMEOUT

    try:
        while time.time() < deadline:
            remaining = deadline - time.time()
            sock.settimeout(max(1.0, remaining))
            try:
                frame = read_frame(sock)
            except socket.timeout:
                continue

            dk = frame["data_kind"]
            data = frame["data"]

            if dk in ("T", "U", "K") and data:
                text = data.rstrip(b"\x00\r\n").decode("ascii", errors="replace")
                ts = time.strftime("%H:%M:%S")
                if ">" in text and ":" in text:
                    src = text.split(">")[0]
                    print(f"[{ts}]  {src:<12}  {text[:100]}")
                elif frame["call_from"]:
                    print(f"[{ts}]  {frame['call_from']:<12}  {frame['call_to']}:{text[:80]}")
                pkt_count += 1

            elif dk == "G":
                # Version response from Direwolf
                ver = data.decode("ascii", errors="replace").strip("\x00")
                print(f"Direwolf version: {ver}")

    except socket.timeout:
        pass
    except KeyboardInterrupt:
        print()

    print("-" * 60)
    if pkt_count > 0:
        print(f"PASSED — received {pkt_count} packet(s) from Direwolf.")
        print("AGW connection and packet decode are working.")
    else:
        print("No packets received in the listen window.")
        print("This may be normal if the band is quiet; check:")
        print("  - AIOC is plugged in and recognised  (tools/find_aioc.sh)")
        print("  - Direwolf audio levels  (direwolf output in: journalctl -u direwolf -f)")
        print("  - Baofeng is on 144.390 MHz and squelch is open enough to hear packets")

    sock.close()


if __name__ == "__main__":
    main()
