import json
import struct
import tempfile
from pathlib import Path
import unittest

from tarteel_realtime.asr_smoke import SmokeAudio
from tarteel_realtime.diagnostics_capture import (
    DiagnosticCaptureError,
    merge_trace_records,
    reconstruct_asr_windows,
    session_slug,
    validate_trace_envelope,
)


class DiagnosticsCaptureTests(unittest.TestCase):
    def test_session_slug_uses_timestamp_audio_name_and_scope(self):
        self.assertEqual(
            session_slug(
                timestamp_utc="20260606T143012Z",
                audio_path=Path("fixtures/local_audio/108001.wav"),
                scope="108",
            ),
            "20260606T143012Z-108001-scope-108",
        )

    def test_validate_trace_envelope_rejects_plain_event_payload(self):
        with self.assertRaises(DiagnosticCaptureError) as context:
            validate_trace_envelope({"type": "locked"})

        self.assertIn("diagnostics-enabled backend", str(context.exception))

    def test_reconstructs_asr_window_audio_from_backend_segments(self):
        chunks = {
            0: b"aaaa",
            1: b"bbbb",
        }
        envelopes = [{
            "kind": "recitation_trace",
            "event": {"type": "locked"},
            "trace": {
                "sequence_number": 1,
                "asr_window": {
                    "id": 0,
                    "segments": [
                        {"sequence_number": 0, "start_byte": 1, "end_byte": 4},
                        {"sequence_number": 1, "start_byte": 0, "end_byte": 2},
                    ],
                },
            },
        }]

        windows = reconstruct_asr_windows(envelopes, chunks)

        self.assertEqual(windows, [{"id": 0, "pcm": b"aaabb"}])

    def test_merges_client_timing_with_backend_trace(self):
        envelopes = [{
            "kind": "recitation_trace",
            "event": {"type": "locating", "reason": "waiting_for_audio_buffer"},
            "trace": {"sequence_number": 0, "buffer": {"action": "append_wait_min_audio"}},
        }]
        client_chunks = [{
            "sequence_number": 0,
            "capture_offset_ms": 0,
            "send_offset_ms": 2,
            "receive_offset_ms": 20,
            "roundtrip_ms": 18,
            "pcm_bytes": 32000,
            "sample_rate_hz": 16000,
        }]

        trace = merge_trace_records(
            metadata={"scope": "108"},
            envelopes=envelopes,
            client_chunks=client_chunks,
        )

        self.assertEqual(trace["metadata"]["scope"], "108")
        self.assertEqual(trace["chunks"][0]["sequence_number"], 0)
        self.assertEqual(trace["chunks"][0]["roundtrip_ms"], 18)
        self.assertEqual(trace["raw_backend_envelopes"], envelopes)


if __name__ == "__main__":
    unittest.main()
