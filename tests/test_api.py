import base64
import struct
import unittest

from fastapi.testclient import TestClient

from tarteel_realtime.api import create_app
from tarteel_realtime.livekit_tokens import LiveKitTokenRequest
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

    def test_livekit_recitation_token_endpoint_returns_local_dev_join_token(self):
        token_requests = []

        class RecordingTokenBuilder:
            def build(self, request: LiveKitTokenRequest) -> str:
                token_requests.append(request)
                return "signed-dev-token"

        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer([]),
            livekit_token_builder=RecordingTokenBuilder(),
        )

        response = TestClient(app).get(
            "/livekit/recitation-token",
            params={"identity": "ios-simulator", "role": "client"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {
            "url": "ws://127.0.0.1:7880",
            "room": "tarteel-local-recitation",
            "identity": "ios-simulator",
            "role": "client",
            "token": "signed-dev-token",
        })
        self.assertEqual(token_requests[0].identity, "ios-simulator")
        self.assertEqual(token_requests[0].role, "client")
        self.assertTrue(token_requests[0].can_publish)


if __name__ == "__main__":
    unittest.main()
