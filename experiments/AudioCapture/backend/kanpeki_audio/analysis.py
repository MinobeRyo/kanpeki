"""Deterministic metrics. Model results are estimates, never ground truth."""
from __future__ import annotations

import array
import io
import json
import math
import re
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

MAX_DURATION = 15 * 60
SAMPLE_RATE = 16000


def read_audio(data: bytes) -> array.array:
    try:
        with wave.open(io.BytesIO(data), "rb") as source:
            if (source.getnchannels(), source.getsampwidth(), source.getframerate(), source.getcomptype()) != (1, 2, SAMPLE_RATE, "NONE"):
                raise ValueError("16 kHz・モノラル・16 bit PCMのWAVを送信してください。")
            count = source.getnframes()
            if not 1600 <= count <= MAX_DURATION * SAMPLE_RATE:
                raise ValueError("録音は0.1秒以上、15分以内にしてください。")
            raw = source.readframes(count)
            if len(raw) != count * 2:
                raise ValueError("音声ファイルが途中で切れています。")
    except (wave.Error, EOFError) as error:
        raise ValueError("読み取れるPCM WAVではありません。") from error
    samples = array.array("h", raw)
    if sys.byteorder != "little":
        samples.byteswap()
    return samples


def validate_slides(events: list, duration: float) -> list[dict]:
    if not isinstance(events, list) or len(events) > 500:
        raise ValueError("スライド履歴は500件以内の配列にしてください。")
    previous = -1.0
    result = []
    for event in events:
        if not isinstance(event, dict):
            raise ValueError("スライド履歴の形式が不正です。")
        seconds, slide = event.get("at"), event.get("slide")
        if type(seconds) not in (int, float) or not math.isfinite(seconds) or not 0 <= seconds <= duration or seconds <= previous:
            raise ValueError("スライド切替時刻は録音開始を0秒とする昇順の値にしてください。")
        if type(slide) is not int or not 1 <= slide <= 10000:
            raise ValueError("スライド番号が不正です。")
        result.append({"at": float(seconds), "slide": slide})
        previous = seconds
    return result


def quiet_intervals(samples: array.array, threshold_db: float = -40, minimum: float = 1.0) -> list[dict]:
    """Low-energy intervals, NOT semantic silence or speaker detection."""
    intervals, start = [], None
    step = 320  # 20 ms frames, preserving the original audio clock.
    for offset in range(0, len(samples), step):
        frame = samples[offset:offset + step]
        rms = math.sqrt(sum(float(x) * x for x in frame) / len(frame)) / 32768
        quiet = 20 * math.log10(max(rms, 1e-12)) < threshold_db
        if quiet and start is None:
            start = offset / SAMPLE_RATE
        elif not quiet and start is not None:
            end = offset / SAMPLE_RATE
            if end - start >= minimum - 1e-9:
                intervals.append({"start": start, "end": end, "duration": round(end - start, 3)})
            start = None
    end = len(samples) / SAMPLE_RATE
    if start is not None and end - start >= minimum - 1e-9:
        intervals.append({"start": start, "end": end, "duration": round(end - start, 3)})
    return intervals


def normalize_transcript(raw: dict, duration: float) -> list[dict]:
    segments = []
    for segment in raw.get("transcription", []):
        offsets = segment.get("offsets", {})
        start, end = offsets.get("from"), offsets.get("to")
        if type(start) not in (float, int) or type(end) not in (float, int):
            continue
        if not math.isfinite(start) or not math.isfinite(end):
            continue
        start, end = max(0.0, start / 1000), min(duration, end / 1000)
        text = str(segment.get("text", "")).strip()
        if text and end > start:
            segments.append({"start": start, "end": end, "text": text})
    return sorted(segments, key=lambda item: item["start"])


def transcribe(data: bytes, duration: float, executable: str, model: str) -> list[dict]:
    # Explicit paths only; never downloads a model or falls back to the cloud.
    with tempfile.TemporaryDirectory(prefix="kanpeki-audio-") as folder:
        audio_path = Path(folder) / "input.wav"
        output_path = Path(folder) / "transcript"
        audio_path.write_bytes(data)
        command = [executable, "-m", model, "-f", str(audio_path), "-l", "ja", "-oj", "-of", str(output_path), "-ml", "40"]
        subprocess.run(command, check=True, capture_output=True, timeout=600)
        raw = json.loads(output_path.with_suffix(".json").read_text())
    return normalize_transcript(raw, duration)


def char_count(text: str) -> int:
    return sum(character.isalnum() for character in text)


def pace_windows(segments: list[dict], duration: float, window: float = 15) -> list[dict]:
    """Distribute segment characters by overlap. Within-segment rate is estimated."""
    result = []
    start = 0.0
    while start < duration:
        end = min(start + window, duration)
        count = sum(char_count(s["text"]) * max(0, min(end, s["end"]) - max(start, s["start"])) / (s["end"] - s["start"]) for s in segments)
        result.append({"start": start, "end": end, "characters_per_minute": round(count * 60 / (end - start), 1)})
        start = end
    return result


def slide_at(events: list[dict], at: float) -> int | None:
    return next((event["slide"] for event in reversed(events) if event["at"] <= at), None)


def build_report(data: bytes, slide_events: list, executable: str | None = None, model: str | None = None) -> dict:
    samples = read_audio(data)
    duration = len(samples) / SAMPLE_RATE
    events = validate_slides(slide_events, duration)
    quiet = quiet_intervals(samples)
    warnings = ["低音量区間は -40 dBFS 未満が1秒以上続いた区間です。雑音・マイク距離の影響を受け、沈黙や失敗を断定しません。"]
    transcription_status = "not_configured"
    segments = None
    if executable and model:
        try:
            segments = transcribe(data, duration, executable, model)
            transcription_status = "complete" if segments else "no_speech_recognized"
        except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
            transcription_status = "failed"
            warnings.append("文字起こしに失敗しました。音量と時間の結果のみ表示します。Macのモデル設定を確認してください。")
    else:
        warnings.append("文字起こしモデルが未設定です。話速とフィラー候補は未計測です。")
    if segments is not None:
        warnings.append("話速は認識文字数/分の推定値です。15秒区間への配分は文の長さから推定し、フィラーの位置は認識文の時間範囲で表示します。")
        warnings.append("フィラーは候補です。認識による省略や「あの資料」等の誤検出があります。原文と照合してください。")
    if segments == []:
        warnings.append("発話を認識できませんでした。話速とフィラー候補は未計測です。")
    if not any(samples):
        warnings.append("音声全体がゼロ信号です。マイクや入力経路を確認してください。話者の沈黙とは判断できません。")
    filler_candidates = [] if segments else None
    for segment in segments or []:
        for match in re.finditer(r"え[ーぇ]+|あの[ーう]?|えっと|ええと|その[ーう]", segment["text"]):
            filler_candidates.append({"text": match.group(), "start": segment["start"], "end": segment["end"], "context": segment["text"], "slide": slide_at(events, segment["start"]), "timing": "segment"})
    slides = []
    for index, event in enumerate(events):
        end = events[index + 1]["at"] if index + 1 < len(events) else duration
        slides.append({"slide": event["slide"], "start": event["at"], "end": end, "duration": round(end - event["at"], 3)})
    if not events:
        warnings.append("スライド履歴がないため、スライド別時間は未計測です。")
    return {
        "schema_version": 1, "duration": round(duration, 3),
        "transcription_status": transcription_status,
        "transcript": segments,
        "pace": pace_windows(segments, duration) if segments else None,
        "average_characters_per_minute": round(sum(char_count(s["text"]) for s in segments) * 60 / duration, 1) if segments else None,
        "filler_candidates": filler_candidates,
        "quiet_intervals": quiet, "quiet_seconds": round(sum(i["duration"] for i in quiet), 3),
        "slides": slides, "warnings": warnings,
    }
