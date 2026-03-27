#!/usr/bin/env python3
"""
Compute the APRS-IS passcode for the callsign in config.yaml and write it back.
Algorithm: hash each pair of characters in the callsign (minus SSID).
"""

import sys
import os
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip3 install pyyaml  or  apt install python3-yaml")
    sys.exit(1)

CONFIG_FILE = Path(__file__).parent.parent / "config.yaml"


def calculate_passcode(callsign: str) -> int:
    """Return the numeric APRS-IS passcode for a given callsign."""
    callsign = callsign.upper().split("-")[0]  # strip SSID
    hash_val = 0x73E2
    i = 0
    while i < len(callsign):
        hash_val ^= ord(callsign[i]) << 8
        if i + 1 < len(callsign):
            hash_val ^= ord(callsign[i + 1])
        i += 2
    return hash_val & 0x7FFF


def main():
    with open(CONFIG_FILE) as f:
        config = yaml.safe_load(f)

    callsign = config.get("callsign", "").strip()
    if not callsign:
        print("ERROR: callsign not set in config.yaml")
        sys.exit(1)

    passcode = calculate_passcode(callsign)
    config["passcode"] = str(passcode)

    with open(CONFIG_FILE, "w") as f:
        yaml.dump(config, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

    print(f"Passcode for {callsign}: {passcode} — written to config.yaml")


if __name__ == "__main__":
    main()
