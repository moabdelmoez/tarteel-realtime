from pathlib import Path
import unittest

from fastapi.testclient import TestClient

from tests.test_asr_app import SAMPLE_TANZIL_TEXT
from tarteel_realtime.asr_app import AsrAppSettings, create_asr_app
from tarteel_realtime.recognition import FakeRecognizer


REPO_ROOT = Path(__file__).resolve().parents[1]


class RunPodServerlessTests(unittest.TestCase):
    def test_asr_app_exposes_runpod_ping_endpoint(self) -> None:
        tanzil_path = REPO_ROOT / "tests" / "tmp-quran-simple-clean.txt"
        tanzil_path.write_text(SAMPLE_TANZIL_TEXT, encoding="utf-8")
        try:
            app = create_asr_app(
                AsrAppSettings(
                    tanzil_path=tanzil_path,
                    minimum_lock_words=1,
                    model_id="not-used-in-test",
                ),
                recognizer_factory=lambda: FakeRecognizer(["مَلِكِ"]),
            )
            response = TestClient(app).get("/ping")
        finally:
            tanzil_path.unlink()

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_runpod_serverless_start_script_preserves_websocket_asr_entrypoint(self) -> None:
        source = (REPO_ROOT / "scripts" / "runpod_serverless_start.sh").read_text(encoding="utf-8")

        self.assertIn('TARTEEL_WHISPER_BACKEND="${TARTEEL_WHISPER_BACKEND:-faster-whisper}"', source)
        self.assertIn('TARTEEL_WHISPER_DEVICE="${TARTEEL_WHISPER_DEVICE:-cuda:0}"', source)
        self.assertIn('TARTEEL_HF_CACHE_ROOT="${TARTEEL_HF_CACHE_ROOT:-/runpod-volume/huggingface-cache/hub}"', source)
        self.assertIn('TARTEEL_ASR_BUFFERING_PROFILE="${TARTEEL_ASR_BUFFERING_PROFILE:-low-latency}"', source)
        self.assertIn('uvicorn tarteel_realtime.asr_app:create_app_from_env', source)
        self.assertIn('--factory', source)
        self.assertIn('--host 0.0.0.0', source)
        self.assertIn('--port "${PORT:-8000}"', source)

    def test_runpod_serverless_dockerfile_installs_faster_whisper_without_default_test_deps(self) -> None:
        source = (REPO_ROOT / "Dockerfile.runpod-serverless").read_text(encoding="utf-8")

        self.assertIn("scripts/runpod_serverless_start.sh", source)
        self.assertIn("faster-whisper", source)
        self.assertIn("uv sync", source)
        self.assertNotIn("pip install", source)


if __name__ == "__main__":
    unittest.main()
