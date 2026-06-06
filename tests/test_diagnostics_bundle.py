import json
import struct
import tempfile
from pathlib import Path
import unittest
import wave

from tarteel_realtime.diagnostics_bundle import (
    build_waveform_peaks,
    scrub_url,
    write_diagnostics_bundle,
)


class DiagnosticsBundleTests(unittest.TestCase):
    def test_scrubs_url_query_values(self):
        self.assertEqual(
            scrub_url("wss://example.test/ws/recitation?scope=108&token=secret"),
            "wss://example.test/ws/recitation?scope=108&token=%3Credacted%3E",
        )

    def test_builds_waveform_min_max_peaks(self):
        pcm = struct.pack("<hhhh", -1000, 500, -200, 1200)

        peaks = build_waveform_peaks(pcm, bucket_samples=2)

        self.assertEqual(
            peaks,
            [
                {"min": -0.0305, "max": 0.0153},
                {"min": -0.0061, "max": 0.0366},
            ],
        )

    def test_writes_bundle_files_and_inlines_trace_json(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            output_root = Path(tmpdir)
            raw_pcm = struct.pack("<hhhh", 1000, -1000, 500, -500)
            trace = {
                "metadata": {
                    "backend_url": "wss://example.test/ws/recitation",
                    "authorization_used": True,
                },
                "chunks": [],
                "asr_windows": [],
                "audio_artifacts": {},
                "raw_backend_envelopes": [],
            }

            bundle = write_diagnostics_bundle(
                output_root=output_root,
                session_slug="20260606T143012Z-108001-scope-108",
                trace=trace,
                raw_audio_pcm=raw_pcm,
                sample_rate_hz=16_000,
                asr_input_segments=[],
                asr_windows=[],
            )

            self.assertTrue((bundle.path / "index.html").is_file())
            self.assertTrue((bundle.path / "trace.json").is_file())
            self.assertTrue((bundle.path / "raw-mic.wav").is_file())
            self.assertTrue((bundle.path / "asr-input.wav").is_file())
            self.assertTrue((bundle.path / "assets" / "diagnostics.css").is_file())
            self.assertTrue((bundle.path / "assets" / "diagnostics.js").is_file())
            self.assertTrue((bundle.path / "asr-windows").is_dir())

            html = (bundle.path / "index.html").read_text(encoding="utf-8")
            self.assertIn('<script type="application/json" id="trace-data">', html)
            self.assertIn("Visual Diagnostics", html)

            with wave.open(str(bundle.path / "raw-mic.wav"), "rb") as wav_file:
                self.assertEqual(wav_file.getnchannels(), 1)
                self.assertEqual(wav_file.getsampwidth(), 2)
                self.assertEqual(wav_file.getframerate(), 16_000)
                self.assertEqual(wav_file.getnframes(), 4)

            trace_json = json.loads(bundle.trace_json_path.read_text(encoding="utf-8"))
            self.assertEqual(
                trace_json["audio_artifacts"]["raw_mic"]["filename"],
                "raw-mic.wav",
            )
            self.assertEqual(
                trace_json["audio_artifacts"]["asr_input"]["filename"],
                "asr-input.wav",
            )

    def test_writes_asr_window_audio_and_normalizes_trace(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            window_pcm = struct.pack("<hhhh", -1000, 500, -200, 1200)

            bundle = write_diagnostics_bundle(
                output_root=Path(tmpdir),
                session_slug="session",
                trace={"metadata": {}, "chunks": []},
                raw_audio_pcm=b"",
                sample_rate_hz=16_000,
                asr_input_segments=[{"pcm": window_pcm[:4]}, {"pcm": window_pcm[4:]}],
                asr_windows=[
                    {
                        "id": 3,
                        "pcm": window_pcm,
                        "triggering_sequence_number": 9,
                        "transcript": "sample transcript",
                    }
                ],
            )

            self.assertTrue(
                (bundle.path / "asr-windows" / "asr-window-003.wav").is_file()
            )

            trace_json = json.loads(bundle.trace_json_path.read_text(encoding="utf-8"))
            self.assertEqual(
                trace_json["asr_windows"],
                [
                    {
                        "id": 3,
                        "filename": "asr-windows/asr-window-003.wav",
                        "triggering_sequence_number": 9,
                        "transcript": "sample transcript",
                        "waveform_peaks": [
                            {"min": -0.0305, "max": 0.0366},
                        ],
                    }
                ],
            )
            self.assertEqual(
                trace_json["audio_artifacts"]["asr_input"]["waveform_peaks"],
                [{"min": -0.0305, "max": 0.0366}],
            )

    def test_duplicate_session_slug_creates_unique_directory(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            output_root = Path(tmpdir)

            first = write_diagnostics_bundle(
                output_root=output_root,
                session_slug="session",
                trace={},
                raw_audio_pcm=struct.pack("<h", 1),
                sample_rate_hz=16_000,
                asr_input_segments=[],
                asr_windows=[],
            )
            second = write_diagnostics_bundle(
                output_root=output_root,
                session_slug="session",
                trace={},
                raw_audio_pcm=struct.pack("<h", 2),
                sample_rate_hz=16_000,
                asr_input_segments=[],
                asr_windows=[],
            )

            self.assertEqual(first.path, output_root / "session")
            self.assertEqual(second.path, output_root / "session-2")
            self.assertTrue((first.path / "trace.json").is_file())
            self.assertTrue((second.path / "trace.json").is_file())


if __name__ == "__main__":
    unittest.main()
