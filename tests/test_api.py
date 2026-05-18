import base64
import struct
import unittest

from fastapi.testclient import TestClient

from tarteel_realtime.api import create_app
from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recognition import FakeRecognizer


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


if __name__ == "__main__":
    unittest.main()
