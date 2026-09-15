#!/usr/bin/env python3
"""Analyze an explicit WAV file locally without launching a server."""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from kanpeki_audio.analysis import build_report

parser = argparse.ArgumentParser(description="16kHz mono PCM16 WAVをMac内で分析")
parser.add_argument("wav", type=Path)
parser.add_argument("--whisper-cli")
parser.add_argument("--model")
parser.add_argument("--slides", type=Path, help='[{"at": 0, "slide": 1}, ...] のJSON')
parser.add_argument("--output", type=Path)
args = parser.parse_args()
if bool(args.whisper_cli) != bool(args.model):
    parser.error("--whisper-cli と --model は両方指定してください。")
try:
    events = json.loads(args.slides.read_text()) if args.slides else []
    report = build_report(args.wav.read_bytes(), events, args.whisper_cli, args.model)
except (ValueError, OSError) as error:
    parser.exit(1, f"{error}\n")
output = json.dumps(report, ensure_ascii=False, indent=2)
if args.output:
    args.output.write_text(output + "\n")
    print(f"結果: {args.output}")
else:
    print(output)
