import base64
import unittest

from fastapi.testclient import TestClient

from tarteel_realtime.api import create_app
from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recognition import FakeRecognizer


SAMPLE_TANZIL_LINES = [
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
]


def chunk_payload(sequence_number: int) -> dict:
    return {
        "sequence_number": sequence_number,
        "pcm_base64": base64.b64encode(b"\x00\x01").decode("ascii"),
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


if __name__ == "__main__":
    unittest.main()
