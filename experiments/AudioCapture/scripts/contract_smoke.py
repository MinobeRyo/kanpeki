#!/usr/bin/env python3
"""Run the app's real Swift HTTP client against a temporary local backend.

Pass a test WAV explicitly. This does not access a microphone.
"""
import argparse
import secrets
import subprocess
import sys
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
from kanpeki_audio.server import AudioServer, JobStore

parser = argparse.ArgumentParser()
parser.add_argument("wav", type=Path)
parser.add_argument("--whisper-cli")
parser.add_argument("--model")
args = parser.parse_args()
if bool(args.whisper_cli) != bool(args.model):
    parser.error("--whisper-cli と --model は両方指定してください。")
build = ROOT / ".build"
build.mkdir(exist_ok=True)
binary = build / "contract-smoke"
subprocess.run(["swiftc", "-swift-version", "5", str(ROOT / "ios/KanpekiAudio/AudioAPI.swift"), str(ROOT / "scripts/contract_smoke.swift"), "-o", str(binary)], check=True)
token = secrets.token_urlsafe(24)
store = JobStore(args.whisper_cli, args.model)
server = AudioServer(("127.0.0.1", 0), token, store)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    result = subprocess.run([str(binary), f"http://127.0.0.1:{server.server_port}", token, str(args.wav.resolve())], timeout=600)
finally:
    server.shutdown(); server.server_close(); thread.join(); store.executor.shutdown()
sys.exit(result.returncode)
