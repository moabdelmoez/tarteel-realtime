import base64
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from fastapi.testclient import TestClient

from tarteel_realtime.asr_app import (
    DEFAULT_QURAN_WHISPER_MODEL_ID,
    AsrAppSettings,
    create_asr_app,
    create_buffered_whisper_recognizer_factory,
    create_lazy_whisper_recognizer_factory,
    settings_from_env,
)
from tarteel_realtime.recognition import AudioChunk, FakeRecognizer, RecognitionResult


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


class AsrAppTests(unittest.TestCase):
    def test_settings_from_env_uses_safe_defaults(self):
        settings = settings_from_env({})

        self.assertEqual(settings.tanzil_path, Path("data/tanzil/quran-simple-clean.txt"))
        self.assertEqual(settings.minimum_lock_words, 3)
        self.assertEqual(settings.model_id, DEFAULT_QURAN_WHISPER_MODEL_ID)
        self.assertEqual(settings.language, "ar")
        self.assertIsNone(settings.device)
        self.assertEqual(settings.minimum_audio_ms, 2_000)
        self.assertEqual(settings.flush_interval_ms, 1_500)
        self.assertEqual(settings.tail_audio_ms, 500)

    def test_settings_from_env_accepts_backend_overrides(self):
        settings = settings_from_env({
            "TARTEEL_TANZIL_PATH": "/tmp/quran.txt",
            "TARTEEL_MINIMUM_LOCK_WORDS": "2",
            "TARTEEL_WHISPER_MODEL_ID": "local/quran-whisper",
            "TARTEEL_WHISPER_LANGUAGE": "fa",
            "TARTEEL_WHISPER_DEVICE": "cuda:0",
            "TARTEEL_ASR_MIN_AUDIO_MS": "1000",
            "TARTEEL_ASR_FLUSH_MS": "750",
            "TARTEEL_ASR_TAIL_MS": "250",
        })

        self.assertEqual(settings.tanzil_path, Path("/tmp/quran.txt"))
        self.assertEqual(settings.minimum_lock_words, 2)
        self.assertEqual(settings.model_id, "local/quran-whisper")
        self.assertEqual(settings.language, "fa")
        self.assertEqual(settings.device, "cuda:0")
        self.assertEqual(settings.minimum_audio_ms, 1_000)
        self.assertEqual(settings.flush_interval_ms, 750)
        self.assertEqual(settings.tail_audio_ms, 250)

    def test_lazy_whisper_factory_defers_model_creation_until_first_audio_chunk(self):
        built_configs = []

        class StubRecognizer:
            def __init__(self, config):
                built_configs.append(config)

            def recognize(self, chunk: AudioChunk) -> RecognitionResult:
                return RecognitionResult(
                    transcript="مَلِكِ",
                    confidence=0.9,
                    chunk_sequence=chunk.sequence_number,
                    is_final=True,
                )

        factory = create_lazy_whisper_recognizer_factory(
            AsrAppSettings(
                tanzil_path=Path("unused.txt"),
                model_id="local/quran-whisper",
                language="ar",
                device="cuda:0",
            ),
            recognizer_builder=StubRecognizer,
        )

        recognizer = factory()
        self.assertEqual(built_configs, [])

        first = recognizer.recognize(AudioChunk(0, b"\x00\x00", 16_000))
        second = recognizer.recognize(AudioChunk(1, b"\x00\x00", 16_000))

        self.assertEqual(first.transcript, "مَلِكِ")
        self.assertEqual(second.chunk_sequence, 1)
        self.assertEqual(len(built_configs), 1)
        self.assertEqual(built_configs[0].model_id, "local/quran-whisper")
        self.assertEqual(built_configs[0].language, "ar")
        self.assertEqual(built_configs[0].device, "cuda:0")

    def test_buffered_whisper_factory_waits_for_enough_audio_before_model_call(self):
        built_configs = []
        recognized_pcm = []

        class StubRecognizer:
            def __init__(self, config):
                built_configs.append(config)

            def recognize(self, chunk: AudioChunk) -> RecognitionResult:
                recognized_pcm.append(chunk.pcm)
                return RecognitionResult(
                    transcript="مَلِكِ",
                    confidence=0.9,
                    chunk_sequence=chunk.sequence_number,
                    is_final=True,
                )

        factory = create_buffered_whisper_recognizer_factory(
            AsrAppSettings(
                tanzil_path=Path("unused.txt"),
                model_id="local/quran-whisper",
                minimum_audio_ms=2,
                flush_interval_ms=2,
                tail_audio_ms=0,
            ),
            recognizer_builder=StubRecognizer,
        )

        recognizer = factory()
        waiting = recognizer.recognize(AudioChunk(0, b"\x00\x01", 1_000))
        recognized = recognizer.recognize(AudioChunk(1, b"\x02\x03", 1_000))

        self.assertEqual(waiting.transcript, "")
        self.assertEqual(waiting.confidence, 0.0)
        self.assertEqual(recognized.transcript, "مَلِكِ")
        self.assertEqual(len(built_configs), 1)
        self.assertEqual(recognized_pcm, [b"\x00\x01\x02\x03"])

    def test_create_asr_app_uses_same_websocket_contract_with_injected_recognizer(self):
        with TemporaryDirectory() as directory:
            tanzil_path = Path(directory) / "quran-simple-clean.txt"
            tanzil_path.write_text(SAMPLE_TANZIL_TEXT, encoding="utf-8")
            app = create_asr_app(
                AsrAppSettings(
                    tanzil_path=tanzil_path,
                    minimum_lock_words=1,
                    model_id="not-used-in-test",
                ),
                recognizer_factory=lambda: FakeRecognizer(["مَلِكِ"]),
            )

            client = TestClient(app)
            with client.websocket_connect("/ws/recitation") as websocket:
                websocket.send_json(chunk_payload(0))
                locked = websocket.receive_json()

        self.assertEqual(locked["type"], "locked")
        self.assertEqual(locked["start_ref"], "114:2:1")


if __name__ == "__main__":
    unittest.main()
