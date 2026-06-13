import base64
import struct
import unittest

from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from tarteel_realtime.api import create_app
from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recognition import FakeRecognizer, RecognitionResult


SAMPLE_TANZIL_LINES = [
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
]


def chunk_payload(sequence_number: int, pcm: bytes = b"\x00\x01") -> dict:
    return {
        "sequence_number": sequence_number,
        "pcm_base64": base64.b64encode(pcm).decode("ascii"),
        "sample_rate_hz": 16_000,
    }


class ApiTests(unittest.TestCase):
    def test_health_endpoint_reports_ok(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer([]),
        )

        response = TestClient(app).get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_websocket_streams_session_events_from_audio_chunks(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer(["مَلِكِ", "النَّاسِ"]),
            minimum_lock_words=1,
        )
        client = TestClient(app)

        with client.websocket_connect("/ws/recitation") as websocket:
            websocket.send_json(chunk_payload(0))
            locked = websocket.receive_json()

            websocket.send_json(chunk_payload(1))
            progress = websocket.receive_json()

        self.assertEqual(locked["type"], "locked")
        self.assertEqual(locked["start_ref"], "114:2:1")
        self.assertEqual(locked["ayah_text"], "مَلِكِ النَّاسِ")
        self.assertEqual(locked["next_expected_ref"], "114:2:2")
        self.assertEqual(locked["chunk_sequence"], 0)
        self.assertEqual(progress["type"], "progress")
        self.assertIsNone(progress["next_expected_ref"])
        self.assertEqual(progress["chunk_sequence"], 1)

    def test_diagnostics_query_returns_trace_envelope_without_changing_normal_socket(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
        )
        client = TestClient(app)

        with client.websocket_connect("/ws/recitation") as websocket:
            websocket.send_json(chunk_payload(0))
            normal = websocket.receive_json()

        with client.websocket_connect("/ws/recitation?diagnostics=1") as websocket:
            websocket.send_json(chunk_payload(0))
            diagnostic = websocket.receive_json()

        self.assertEqual(normal["type"], "locked")
        self.assertNotIn("kind", normal)
        self.assertEqual(diagnostic["kind"], "recitation_trace")
        self.assertEqual(diagnostic["event"]["type"], "locked")
        self.assertEqual(diagnostic["event"]["start_ref"], "114:2:1")
        self.assertEqual(diagnostic["trace"]["sequence_number"], 0)
        self.assertEqual(diagnostic["trace"]["audio"]["pcm_bytes"], 2)
        decision = diagnostic["trace"]["decision"]
        self.assertEqual(decision["mode"], "initial_location")
        self.assertEqual(decision["locator"]["status"], "locked")
        self.assertEqual(decision["locator"]["top_candidates"][0]["ayah_ref"], "114:2")

    def test_each_websocket_connection_gets_fresh_recitation_stream(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer(["مَلِكِ", "النَّاسِ"]),
            minimum_lock_words=1,
        )
        client = TestClient(app)

        with client.websocket_connect("/ws/recitation") as first_websocket:
            first_websocket.send_json(chunk_payload(0))
            first_locked = first_websocket.receive_json()

            with client.websocket_connect("/ws/recitation") as second_websocket:
                second_websocket.send_json(chunk_payload(0))
                second_locked = second_websocket.receive_json()

        self.assertEqual(first_locked["type"], "locked")
        self.assertEqual(second_locked["type"], "locked")
        self.assertEqual(first_locked["start_ref"], "114:2:1")
        self.assertEqual(second_locked["start_ref"], "114:2:1")

    def test_websocket_keeps_unscoped_noisy_span_as_candidate(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines([
                "102|3|كلا سوف تعلمون",
                "102|4|ثم كلا سوف تعلمون",
                "102|5|كلا لو تعلمون علم اليقين",
            ]),
            recognizer_factory=lambda: FakeRecognizer([
                "فكلا سوف تعلمون كلا لو",
                "فكلا سوف تعلمون كلا لو",
            ]),
            minimum_lock_words=2,
        )
        client = TestClient(app)

        with client.websocket_connect("/ws/recitation") as websocket:
            websocket.send_json(chunk_payload(0))
            first_candidate = websocket.receive_json()

            websocket.send_json(chunk_payload(1))
            second_candidate = websocket.receive_json()

        self.assertEqual(first_candidate["type"], "lock_candidate")
        self.assertEqual(first_candidate["reason"], "needs_confirmation")
        self.assertEqual(second_candidate["type"], "lock_candidate")
        self.assertEqual(second_candidate["reason"], "needs_confirmation")
        self.assertEqual(second_candidate["candidate_refs"], ["102:3"])

    def test_websocket_scope_query_restricts_initial_location(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines([
                "113|1|قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
                "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
            ]),
            recognizer_factory=lambda: FakeRecognizer(["قُلْ أَعُوذُ بِرَبِّ"]),
            minimum_lock_words=2,
        )
        client = TestClient(app)

        with client.websocket_connect("/ws/recitation?scope=114") as websocket:
            websocket.send_json(chunk_payload(0))
            event = websocket.receive_json()

        self.assertEqual(event["type"], "locked")
        self.assertEqual(event["ayah_ref"], "114:1")
        self.assertEqual(event["start_ref"], "114:1:1")

    def test_websocket_selects_recognizer_factory_by_safe_asr_model_slug(self):
        selected_factories = []

        def nemo_factory():
            selected_factories.append("nemo-fastconformer-quran-ar")
            return FakeRecognizer(["مَلِكِ"])

        def faster_whisper_factory():
            selected_factories.append("faster-whisper-base-ar-quran")
            return FakeRecognizer(["قُلْ أَعُوذُ"])

        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=nemo_factory,
            minimum_lock_words=1,
            recognizer_factories_by_asr_model={
                "nemo-fastconformer-quran-ar": nemo_factory,
                "faster-whisper-base-ar-quran": faster_whisper_factory,
            },
            default_asr_model="nemo-fastconformer-quran-ar",
        )
        client = TestClient(app)

        with client.websocket_connect(
            "/ws/recitation?asr_model=faster-whisper-base-ar-quran"
        ) as websocket:
            websocket.send_json(chunk_payload(0))
            event = websocket.receive_json()

        self.assertEqual(selected_factories, ["faster-whisper-base-ar-quran"])
        self.assertEqual(event["type"], "locked")
        self.assertEqual(event["ayah_ref"], "114:1")

    def test_websocket_uses_default_asr_model_when_query_is_missing(self):
        selected_factories = []

        def nemo_factory():
            selected_factories.append("nemo-fastconformer-quran-ar")
            return FakeRecognizer(["مَلِكِ"])

        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=nemo_factory,
            minimum_lock_words=1,
            recognizer_factories_by_asr_model={
                "nemo-fastconformer-quran-ar": nemo_factory,
            },
            default_asr_model="nemo-fastconformer-quran-ar",
        )
        client = TestClient(app)

        with client.websocket_connect("/ws/recitation") as websocket:
            websocket.send_json(chunk_payload(0))
            event = websocket.receive_json()

        self.assertEqual(selected_factories, ["nemo-fastconformer-quran-ar"])
        self.assertEqual(event["type"], "locked")
        self.assertEqual(event["ayah_ref"], "114:2")

    def test_websocket_rejects_unknown_asr_model_slug(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer(["مَلِكِ"]),
            recognizer_factories_by_asr_model={
                "nemo-fastconformer-quran-ar": lambda: FakeRecognizer(["مَلِكِ"]),
            },
            default_asr_model="nemo-fastconformer-quran-ar",
        )
        client = TestClient(app)

        with self.assertRaises(WebSocketDisconnect) as context:
            with client.websocket_connect("/ws/recitation?asr_model=../../other-model"):
                pass

        self.assertEqual(context.exception.code, 1008)

    def test_websocket_accepts_matching_bearer_token_when_configured(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
            websocket_bearer_token="test-token",
        )
        client = TestClient(app)

        with client.websocket_connect(
            "/ws/recitation",
            headers={"Authorization": "Bearer test-token"},
        ) as websocket:
            websocket.send_json(chunk_payload(0))
            event = websocket.receive_json()

        self.assertEqual(event["type"], "locked")
        self.assertEqual(event["start_ref"], "114:2:1")

    def test_websocket_rejects_missing_bearer_token_when_configured(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
            websocket_bearer_token="test-token",
        )
        client = TestClient(app)

        with self.assertRaises(WebSocketDisconnect) as context:
            with client.websocket_connect("/ws/recitation"):
                pass

        self.assertEqual(context.exception.code, 1008)

    def test_websocket_rejects_wrong_bearer_token_when_configured(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
            websocket_bearer_token="test-token",
        )
        client = TestClient(app)

        with self.assertRaises(WebSocketDisconnect) as context:
            with client.websocket_connect(
                "/ws/recitation",
                headers={"Authorization": "Bearer wrong-token"},
            ):
                pass

        self.assertEqual(context.exception.code, 1008)

    def test_websocket_returns_wrong_event(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer(["مَلِكِ", "الْفَلَقِ"]),
            minimum_lock_words=1,
        )
        client = TestClient(app)

        with client.websocket_connect("/ws/recitation") as websocket:
            websocket.send_json(chunk_payload(0))
            websocket.receive_json()

            websocket.send_json(chunk_payload(1))
            wrong = websocket.receive_json()

        self.assertEqual(wrong["type"], "wrong")
        self.assertEqual(wrong["expected_ref"], "114:2:2")
        self.assertEqual(wrong["expected_word"], "الناس")
        self.assertEqual(wrong["recognized_word"], "الفلق")
        self.assertEqual(wrong["reason"], "word_mismatch")

    def test_websocket_logs_privacy_safe_chunk_diagnostics(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
        )
        client = TestClient(app)

        with self.assertLogs("tarteel_realtime.api", level="INFO") as logs:
            with client.websocket_connect("/ws/recitation") as websocket:
                websocket.send_json(chunk_payload(0))
                websocket.receive_json()

        joined_logs = "\n".join(logs.output)
        self.assertIn("pcm_bytes=2", joined_logs)
        self.assertIn("sample_rate_hz=16000", joined_logs)
        self.assertIn("event_type=locked", joined_logs)
        self.assertIn("ayah_ref=114:2", joined_logs)

    def test_websocket_logs_audio_level_diagnostics(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
        )
        client = TestClient(app)
        pcm = struct.pack("<hh", 1000, -1000)

        with self.assertLogs("tarteel_realtime.api", level="INFO") as logs:
            with client.websocket_connect("/ws/recitation") as websocket:
                websocket.send_json(chunk_payload(0, pcm=pcm))
                websocket.receive_json()

        joined_logs = "\n".join(logs.output)
        self.assertIn("pcm_rms=1000", joined_logs)
        self.assertIn("pcm_peak=1000", joined_logs)
        self.assertIn("transcript_chars=6", joined_logs)

    def test_websocket_transcript_log_content_is_opt_in(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
            log_transcripts=True,
        )
        client = TestClient(app)

        with self.assertLogs("tarteel_realtime.api", level="INFO") as logs:
            with client.websocket_connect("/ws/recitation") as websocket:
                websocket.send_json(chunk_payload(0))
                websocket.receive_json()

        joined_logs = "\n".join(logs.output)
        self.assertIn("transcript_text=مَلِكِ", joined_logs)

    def test_websocket_accepts_vad_metadata_on_audio_chunks(self):
        seen_voice_activity = []

        class RecordingRecognizer:
            def recognize(self, audio_chunk):
                seen_voice_activity.append(audio_chunk.voice_activity)
                return RecognitionResult(
                    transcript="مَلِكِ",
                    confidence=0.9,
                    chunk_sequence=audio_chunk.sequence_number,
                    is_final=True,
                )

        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=RecordingRecognizer,
            minimum_lock_words=1,
        )
        client = TestClient(app)
        payload = chunk_payload(0)
        payload["voice_activity"] = {
            "probability": 0.82,
            "is_speech_active": True,
            "event": "speech_start",
        }

        with client.websocket_connect("/ws/recitation") as websocket:
            websocket.send_json(payload)
            websocket.receive_json()

        self.assertEqual(len(seen_voice_activity), 1)
        self.assertEqual(seen_voice_activity[0].probability, 0.82)
        self.assertTrue(seen_voice_activity[0].is_speech_active)
        self.assertEqual(seen_voice_activity[0].event, "speech_start")

    def test_websocket_returns_uncertain_event_when_recognizer_raises(self):
        class FailingRecognizer:
            def recognize(self, audio_chunk):
                raise RuntimeError("CUDA error: device-side assert triggered")

        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=FailingRecognizer,
            minimum_lock_words=1,
        )
        client = TestClient(app)

        with client.websocket_connect("/ws/recitation") as websocket:
            websocket.send_json(chunk_payload(3))
            event = websocket.receive_json()

        self.assertEqual(event["type"], "uncertain")
        self.assertEqual(event["reason"], "asr_error")
        self.assertEqual(event["chunk_sequence"], 3)


if __name__ == "__main__":
    unittest.main()
