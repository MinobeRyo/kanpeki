import array
import io
import math
import unittest
import wave
from unittest.mock import patch

from kanpeki_audio.analysis import build_report, normalize_transcript, pace_windows, quiet_intervals, read_audio, validate_slides


def wav(parts=(1, 2, 1), rate=16000, channels=1):
    samples = array.array("h")
    for index, seconds in enumerate(parts):
        for at in range(int(seconds * rate)):
            value = int(10000 * math.sin(2 * math.pi * 220 * at / rate)) if index % 2 == 0 else 0
            samples.extend([value] * channels)
    output = io.BytesIO()
    with wave.open(output, "wb") as target:
        target.setnchannels(channels); target.setsampwidth(2); target.setframerate(rate)
        target.writeframes(samples.tobytes())
    return output.getvalue()


class AnalysisTests(unittest.TestCase):
    def test_detects_inserted_quiet_interval_on_original_timeline(self):
        result = quiet_intervals(read_audio(wav()))
        self.assertEqual(result, [{"start": 1.0, "end": 3.0, "duration": 2.0}])

    def test_short_pause_is_not_reported(self):
        self.assertEqual(quiet_intervals(read_audio(wav((1, .5, 1)))), [])

    def test_trailing_quiet_interval_is_kept(self):
        self.assertEqual(quiet_intervals(read_audio(wav((1, 1.5))))[0]["end"], 2.5)

    def test_invalid_and_truncated_wav(self):
        for data in [b"invalid", wav()[:-100], wav(rate=8000), wav(channels=2), wav((.01,))]:
            with self.subTest(length=len(data)), self.assertRaises(ValueError):
                read_audio(data)

    def test_model_absence_does_not_fabricate_metrics(self):
        report = build_report(wav(), [])
        self.assertEqual(report["transcription_status"], "not_configured")
        for key in ["transcript", "pace", "average_characters_per_minute", "filler_candidates"]:
            self.assertIsNone(report[key])
        self.assertEqual(report["quiet_seconds"], 2)
        self.assertEqual(report["slides"], [])

    def test_model_failure_preserves_audio_metrics(self):
        report = build_report(wav(), [], "/nonexistent-whisper", "/nonexistent-model")
        self.assertEqual(report["transcription_status"], "failed")
        self.assertIsNone(report["filler_candidates"])
        self.assertEqual(report["quiet_seconds"], 2)

    def test_slide_returns_are_separate_visits(self):
        report = build_report(wav(), [{"at": 0, "slide": 1}, {"at": 1, "slide": 2}, {"at": 3, "slide": 1}])
        self.assertEqual([s["duration"] for s in report["slides"]], [1, 2, 1])
        self.assertEqual([s["slide"] for s in report["slides"]], [1, 2, 1])

    def test_invalid_slide_clock(self):
        bad = [[{"at": float("nan"), "slide": 1}], [{"at": -1, "slide": 1}], [{"at": 5, "slide": 1}],
               [{"at": 0, "slide": True}], [{"at": 0, "slide": 1}, {"at": 0, "slide": 2}], [None]]
        for events in bad:
            with self.subTest(events=events), self.assertRaises(ValueError):
                validate_slides(events, 4)

    def test_pace_distributes_segments_across_window_boundary(self):
        pace = pace_windows([{"start": 0, "end": 20, "text": "一二三四五六七八九十。"}], 20)
        self.assertEqual([item["characters_per_minute"] for item in pace], [30, 30])

    def test_whisper_milliseconds_normalized_and_clamped(self):
        raw = {"transcription": [{"offsets": {"from": 1000, "to": 9000}, "text": " 説明します。 "}]}
        self.assertEqual(normalize_transcript(raw, 4), [{"start": 1, "end": 4, "text": "説明します。"}])

    def test_candidates_keep_segment_range_not_fake_word_timestamp(self):
        segments = [{"start": 1.0, "end": 3.0, "text": "えー、あの資料です。"}]
        with patch("kanpeki_audio.analysis.transcribe", return_value=segments):
            report = build_report(wav(), [{"at": 0, "slide": 3}], "fixture", "fixture")
        self.assertEqual(len(report["filler_candidates"]), 2)
        self.assertEqual(report["filler_candidates"][0]["start"], 1)
        self.assertEqual(report["filler_candidates"][0]["end"], 3)
        self.assertEqual(report["filler_candidates"][0]["slide"], 3)
        self.assertEqual(report["filler_candidates"][0]["timing"], "segment")

    def test_empty_recognition_is_not_zero_fillers(self):
        with patch("kanpeki_audio.analysis.transcribe", return_value=[]):
            report = build_report(wav(), [], "fixture", "fixture")
        self.assertEqual(report["transcription_status"], "no_speech_recognized")
        self.assertIsNone(report["filler_candidates"])


if __name__ == "__main__":
    unittest.main()
