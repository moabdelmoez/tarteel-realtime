import base64
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from fastapi.testclient import TestClient

from tarteel_realtime.app_factory import AppSettings, create_configured_app
from tarteel_realtime.recognition import FakeRecognizer


SAMPLE_TANZIL_TEXT = "\n".join([
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
])


def chunk_payload(sequence_number: int) -> dict:
    return {
        "sequence_number": sequence_number,
        "pcm_base64": base64.b64encode(b"\x00\x01").decode("ascii"),
        "sample_rate_hz": 16_000,
    }


class AppFactoryTests(unittest.TestCase):
    def test_creates_api_from_local_tanzil_file(self):
        with TemporaryDirectory() as directory:
            tanzil_path = Path(directory) / "quran-simple-clean.txt"
            tanzil_path.write_text(SAMPLE_TANZIL_TEXT, encoding="utf-8")
            app = create_configured_app(
                AppSettings(
                    tanzil_path=tanzil_path,
                    minimum_lock_words=1,
                ),
                recognizer_factory=lambda: FakeRecognizer(["مَلِكِ", "النَّاسِ"]),
            )

            client = TestClient(app)
            health = client.get("/health")
            with client.websocket_connect("/ws/recitation") as websocket:
                websocket.send_json(chunk_payload(0))
                locked = websocket.receive_json()

                websocket.send_json(chunk_payload(1))
                progress = websocket.receive_json()

        self.assertEqual(health.json(), {"status": "ok"})
        self.assertEqual(locked["type"], "locked")
        self.assertEqual(locked["start_ref"], "114:2:1")
        self.assertEqual(progress["type"], "progress")


if __name__ == "__main__":
    unittest.main()
