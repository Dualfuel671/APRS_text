#!/usr/bin/env python3
"""
check_audio.py — Synthesize a short test phrase with Piper and play it via aplay.
Confirms TTS works and audio routes to the correct output device before going RF.

Usage: python3 tools/check_audio.py
"""

import os
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed.  pip install pyyaml")
    sys.exit(1)

CONFIG_FILE = Path(__file__).parent.parent / "config.yaml"

with open(CONFIG_FILE) as f:
    config = yaml.safe_load(f)

CALLSIGN   = config["callsign"].upper()
MODEL_NAME = config["tts"]["model"]
AUDIO_DEV  = config["tts"].get("audio_device", "default")

PIPER_BIN  = os.path.expanduser("~/piper/piper")
MODEL_PATH = os.path.expanduser(f"~/piper/voices/{MODEL_NAME}.onnx")
WAV_PATH   = "/tmp/aprs_tts_check.wav"

NATO = {
    "A":"Alpha","B":"Bravo","C":"Charlie","D":"Delta","E":"Echo",
    "F":"Foxtrot","G":"Golf","H":"Hotel","I":"India","J":"Juliet",
    "K":"Kilo","L":"Lima","M":"Mike","N":"November","O":"Oscar",
    "P":"Papa","Q":"Quebec","R":"Romeo","S":"Sierra","T":"Tango",
    "U":"Uniform","V":"Victor","W":"Whiskey","X":"X-ray","Y":"Yankee","Z":"Zulu",
}
call_speech = " ".join(NATO.get(c, c) if c.isalpha() else c for c in CALLSIGN if c.isalnum())
TEST_TEXT = f"Audio check. {call_speech} station. Text to speech is working correctly."

print("APRS Audio / TTS Check")
print(f"  Callsign   : {CALLSIGN}")
print(f"  Piper      : {PIPER_BIN}")
print(f"  Model      : {MODEL_PATH}")
print(f"  Audio dev  : {AUDIO_DEV}")
print(f"  Text       : {TEST_TEXT}")
print()

# Check Piper binary
if not os.path.isfile(PIPER_BIN):
    print(f"ERROR: Piper binary not found at {PIPER_BIN}")
    print("Run setup/install.sh first.")
    sys.exit(1)

# Check model file
if not os.path.isfile(MODEL_PATH):
    print(f"ERROR: Voice model not found at {MODEL_PATH}")
    print("Run setup/install.sh first.")
    sys.exit(1)

print("Synthesizing speech with Piper...")
result = subprocess.run(
    [PIPER_BIN, "--model", MODEL_PATH, "--output_file", WAV_PATH],
    input=TEST_TEXT.encode(),
    capture_output=True,
    timeout=30,
)

if result.returncode != 0:
    print(f"ERROR: Piper failed (exit {result.returncode})")
    print(result.stderr.decode(errors="replace"))
    sys.exit(1)

wav_size = os.path.getsize(WAV_PATH)
print(f"Synthesis OK — WAV size: {wav_size} bytes")
print("Playing audio...")

play_cmd = ["aplay", WAV_PATH] if AUDIO_DEV == "default" else ["aplay", "-D", AUDIO_DEV, WAV_PATH]
play_result = subprocess.run(play_cmd, capture_output=True, timeout=30)

if play_result.returncode != 0:
    print(f"ERROR: aplay failed (exit {play_result.returncode})")
    print(play_result.stderr.decode(errors="replace"))
    print()
    print("Possible fixes:")
    print("  - Check that the correct audio device is set in config.yaml  tts.audio_device")
    print("  - List available devices: aplay -L")
    print("  - Make sure your user is in the audio group: groups $USER")
    sys.exit(1)

print()
print("Audio check PASSED — TTS and speaker output are working correctly.")
