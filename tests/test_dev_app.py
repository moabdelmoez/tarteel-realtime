import base64
import unittest

from fastapi.testclient import TestClient

from tarteel_realtime.dev_app import app


def chunk_payload(sequence_number: int) -> dict:
    return {
        "sequence_number": sequence_number,
        "pcm_base64": base64.b64encode(b"\x00\x01").decode("ascii"),
        "sample_rate_hz": 16_000,
    }


class DevAppTests(unittest.TestCase):
    def test_dev_app_is_importable_and_reports_health(self):
        response = TestClient(app).get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_dev_app_has_a_scripted_websocket_recitation_flow(self):
        client = TestClient(app)

        with client.websocket_connect("/ws/recitation") as websocket:
            websocket.send_json(chunk_payload(0))
            locked = websocket.receive_json()

            websocket.send_json(chunk_payload(1))
            wrong = websocket.receive_json()

        self.assertEqual(locked["type"], "locked")
        self.assertEqual(locked["start_ref"], "114:2:1")
        self.assertEqual(wrong["type"], "wrong")
        self.assertEqual(wrong["expected_ref"], "114:2:2")
        self.assertEqual(wrong["recognized_word"], "الفلق")


if __name__ == "__main__":
    unittest.main()
