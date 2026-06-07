from argparse import Namespace
import asyncio
from contextlib import redirect_stderr
import io
import tempfile
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from tarteel_realtime.asr_smoke import SmokeAudio
import tarteel_realtime.diagnostics_capture as diagnostics_capture
from tarteel_realtime.diagnostics_capture import (
    DiagnosticCaptureError,
    bearer_token_from_args,
    main,
    merge_trace_records,
    ping_url_from_websocket_url,
    prepare_diagnostic_url,
    reconstruct_asr_windows,
    run_capture,
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
                    "transcript": "sample transcript",
                    "duration_ms": 123,
                    "segments": [
                        {"sequence_number": 0, "start_byte": 1, "end_byte": 4},
                        {"sequence_number": 1, "start_byte": 0, "end_byte": 2},
                    ],
                },
            },
        }]

        windows = reconstruct_asr_windows(envelopes, chunks)

        self.assertEqual(
            windows,
            [
                {
                    "id": 0,
                    "transcript": "sample transcript",
                    "duration_ms": 123,
                    "segments": [
                        {"sequence_number": 0, "start_byte": 1, "end_byte": 4},
                        {"sequence_number": 1, "start_byte": 0, "end_byte": 2},
                    ],
                    "pcm": b"aaabb",
                }
            ],
        )

    def test_reconstruct_asr_windows_rejects_missing_chunk_segments(self):
        envelopes = [{
            "kind": "recitation_trace",
            "event": {"type": "locked"},
            "trace": {
                "sequence_number": 0,
                "asr_window": {
                    "id": 0,
                    "segments": [
                        {"sequence_number": 7, "start_byte": 0, "end_byte": 2},
                    ],
                },
            },
        }]

        with self.assertRaisesRegex(DiagnosticCaptureError, "sequence 7"):
            reconstruct_asr_windows(envelopes, {0: b"aa"})

    def test_reconstruct_asr_windows_rejects_invalid_segment_bounds(self):
        envelopes = [{
            "kind": "recitation_trace",
            "event": {"type": "locked"},
            "trace": {
                "sequence_number": 0,
                "asr_window": {
                    "id": 0,
                    "segments": [
                        {"sequence_number": 0, "start_byte": -1, "end_byte": 2},
                    ],
                },
            },
        }]

        with self.assertRaisesRegex(DiagnosticCaptureError, "byte range"):
            reconstruct_asr_windows(envelopes, {0: b"aa"})

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

    def test_prepare_diagnostic_url_replaces_diagnostics_and_strips_fragment(self):
        self.assertEqual(
            prepare_diagnostic_url(
                "wss://example.test/ws/recitation?diagnostics=0&foo=bar#access_token=secret",
                scope="108",
            ),
            "wss://example.test/ws/recitation?foo=bar&scope=108&diagnostics=1",
        )

    def test_prepare_diagnostic_url_rejects_userinfo_without_leaking_secret(self):
        with self.assertRaises(DiagnosticCaptureError) as context:
            prepare_diagnostic_url(
                "wss://user:pass@example.test/ws/recitation?token=secret",
                scope=None,
            )

        message = str(context.exception)
        self.assertIn("userinfo", message)
        self.assertNotIn("user:pass", message)
        self.assertNotIn("secret", message)

    def test_derives_ping_url_from_websocket_url(self):
        self.assertEqual(
            ping_url_from_websocket_url("wss://example.test/ws/recitation?scope=108"),
            "https://example.test/ping",
        )
        self.assertEqual(
            ping_url_from_websocket_url("ws://127.0.0.1:8000/ws/recitation"),
            "http://127.0.0.1:8000/ping",
        )

    def test_decode_trace_envelope_rejects_non_json_and_non_object(self):
        with self.assertRaisesRegex(DiagnosticCaptureError, "non-JSON"):
            diagnostics_capture.decode_trace_envelope("not json")
        with self.assertRaisesRegex(DiagnosticCaptureError, "non-object"):
            diagnostics_capture.decode_trace_envelope("[]")

    def test_bearer_token_from_args_prefers_environment(self):
        args = Namespace(
            bearer_token="argument-token",
            bearer_token_env="DIAGNOSTIC_TOKEN",
        )
        with patch.dict("os.environ", {"DIAGNOSTIC_TOKEN": "environment-token"}):
            self.assertEqual(
                bearer_token_from_args(args),
                ("environment-token", "environment"),
            )

    def test_bearer_token_from_args_uses_environment_source_when_env_missing(self):
        args = Namespace(
            bearer_token="argument-token",
            bearer_token_env="DIAGNOSTIC_TOKEN",
        )
        with patch.dict("os.environ", {}, clear=True):
            self.assertEqual(bearer_token_from_args(args), (None, "environment"))

    def test_run_capture_rejects_invalid_chunk_ms_before_connecting(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with self.assertRaisesRegex(DiagnosticCaptureError, "chunk-ms"):
                asyncio.run(
                    run_capture(
                        url="ws://127.0.0.1:8000/ws/recitation",
                        audio_path=Path("missing.wav"),
                        chunk_ms=0,
                        scope=None,
                        output_root=Path(tmpdir),
                        raw_sample_rate_hz=16_000,
                        disable_ping=True,
                        bearer_token=None,
                        authorization_source="none",
                    )
                )

    def test_run_capture_rejects_invalid_sample_rate_before_loading_audio(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.object(
                diagnostics_capture,
                "load_replay_audio_file",
            ) as load_audio, self.assertRaisesRegex(DiagnosticCaptureError, "sample-rate"):
                asyncio.run(
                    run_capture(
                        url="ws://127.0.0.1:8000/ws/recitation",
                        audio_path=Path("missing.wav"),
                        chunk_ms=1000,
                        scope=None,
                        output_root=Path(tmpdir),
                        raw_sample_rate_hz=0,
                        disable_ping=True,
                        bearer_token=None,
                        authorization_source="none",
                    )
                )

            load_audio.assert_not_called()

    def test_run_capture_wraps_audio_load_errors(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.object(
                diagnostics_capture,
                "load_replay_audio_file",
                side_effect=OSError("secret path token"),
            ), self.assertRaisesRegex(DiagnosticCaptureError, "Could not load audio") as context:
                asyncio.run(
                    run_capture(
                        url="ws://127.0.0.1:8000/ws/recitation",
                        audio_path=Path("missing.wav"),
                        chunk_ms=1000,
                        scope=None,
                        output_root=Path(tmpdir),
                        raw_sample_rate_hz=16_000,
                        disable_ping=True,
                        bearer_token=None,
                        authorization_source="none",
                    )
                )

        self.assertNotIn("secret", str(context.exception))

    def test_run_capture_rejects_odd_length_pcm_before_connecting(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.object(
                diagnostics_capture,
                "load_replay_audio_file",
                return_value=SmokeAudio(pcm=b"\x00", sample_rate_hz=16_000),
            ), self.assertRaisesRegex(DiagnosticCaptureError, "PCM16"):
                asyncio.run(
                    run_capture(
                        url="ws://127.0.0.1:8000/ws/recitation",
                        audio_path=Path("odd.raw"),
                        chunk_ms=1000,
                        scope=None,
                        output_root=Path(tmpdir),
                        raw_sample_rate_hz=16_000,
                        disable_ping=True,
                        bearer_token=None,
                        authorization_source="none",
                    )
                )

    def test_run_capture_wraps_websocket_errors_without_leaking_url_secrets(self):
        connect_urls = []

        class FailingConnection:
            async def __aenter__(self):
                raise RuntimeError("token=secret")

            async def __aexit__(self, exc_type, exc, traceback):
                return False

        class FakeWebSockets:
            @staticmethod
            def connect(url, **kwargs):
                connect_urls.append(url)
                return FailingConnection()

        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.dict(sys.modules, {"websockets": FakeWebSockets}), patch.object(
                diagnostics_capture,
                "load_replay_audio_file",
                return_value=SmokeAudio(pcm=b"\x00\x00", sample_rate_hz=16_000),
            ), self.assertRaisesRegex(DiagnosticCaptureError, "WebSocket capture failed") as context:
                asyncio.run(
                    run_capture(
                        url="wss://example.test/ws/recitation?token=secret#fragment-secret",
                        audio_path=Path("sample.wav"),
                        chunk_ms=1000,
                        scope=None,
                        output_root=Path(tmpdir),
                        raw_sample_rate_hz=16_000,
                        disable_ping=True,
                        bearer_token=None,
                        authorization_source="none",
                    )
                )

        self.assertEqual(
            connect_urls,
            ["wss://example.test/ws/recitation?token=secret&diagnostics=1"],
        )
        message = str(context.exception)
        self.assertNotIn("secret", message)
        self.assertNotIn("fragment-secret", message)

    def test_run_capture_rejects_empty_audio_before_connecting(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.object(
                diagnostics_capture,
                "load_replay_audio_file",
                return_value=SmokeAudio(pcm=b"", sample_rate_hz=16_000),
            ), self.assertRaisesRegex(DiagnosticCaptureError, "empty audio"):
                asyncio.run(
                    run_capture(
                        url="ws://127.0.0.1:8000/ws/recitation",
                        audio_path=Path("empty.wav"),
                        chunk_ms=1000,
                        scope=None,
                        output_root=Path(tmpdir),
                        raw_sample_rate_hz=16_000,
                        disable_ping=True,
                        bearer_token=None,
                        authorization_source="none",
                    )
                )

    def test_run_capture_starts_replay_clock_after_websocket_connects(self):
        current_time = {"value": 0.0}
        captured_traces = []
        response_count = {"value": 0}

        def fake_monotonic():
            return current_time["value"]

        async def fake_sleep(seconds):
            current_time["value"] += seconds

        class FakeConnection:
            async def __aenter__(self):
                current_time["value"] = 0.7
                return self

            async def __aexit__(self, exc_type, exc, traceback):
                return False

            async def send(self, payload):
                return None

            async def recv(self):
                sequence_number = response_count["value"]
                response_count["value"] += 1
                return (
                    '{"kind":"recitation_trace",'
                    f'"event":{{"type":"locating"}},'
                    f'"trace":{{"sequence_number":{sequence_number},'
                    '"buffer":{"appended":true}}}'
                )

        class FakeWebSockets:
            @staticmethod
            def connect(url, **kwargs):
                return FakeConnection()

        def fake_write_diagnostics_bundle(**kwargs):
            captured_traces.append(kwargs["trace"])
            return SimpleNamespace(index_html_path=Path("/tmp/index.html"))

        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.dict(sys.modules, {"websockets": FakeWebSockets}), patch.object(
                diagnostics_capture,
                "load_replay_audio_file",
                return_value=SmokeAudio(pcm=b"\x00\x00\x01\x00", sample_rate_hz=1),
            ), patch.object(
                diagnostics_capture,
                "write_diagnostics_bundle",
                side_effect=fake_write_diagnostics_bundle,
            ), patch.object(
                diagnostics_capture,
                "monotonic",
                side_effect=fake_monotonic,
            ), patch.object(diagnostics_capture.asyncio, "sleep", side_effect=fake_sleep):
                index_path = asyncio.run(
                    run_capture(
                        url="ws://127.0.0.1:8000/ws/recitation",
                        audio_path=Path("sample.wav"),
                        chunk_ms=1000,
                        scope=None,
                        output_root=Path(tmpdir),
                        raw_sample_rate_hz=16_000,
                        disable_ping=True,
                        bearer_token=None,
                        authorization_source="none",
                    )
                )

        self.assertEqual(index_path, Path("/tmp/index.html"))
        self.assertEqual(captured_traces[0]["chunks"][0]["send_offset_ms"], 0)
        self.assertEqual(captured_traces[0]["metadata"]["ping"], {"enabled": False})

    def test_main_returns_2_for_diagnostic_capture_error_without_traceback(self):
        with patch.object(
            diagnostics_capture,
            "run_capture",
            side_effect=DiagnosticCaptureError("plain diagnostic error"),
        ):
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                exit_code = main(
                    [
                        "--url",
                        "ws://127.0.0.1:8000/ws/recitation",
                        "--audio-path",
                        "sample.wav",
                    ]
                )

        self.assertEqual(exit_code, 2)
        self.assertEqual(stderr.getvalue().strip(), "plain diagnostic error")
        self.assertNotIn("Traceback", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
