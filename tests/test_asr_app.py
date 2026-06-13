import base64
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from fastapi.testclient import TestClient

from tarteel_realtime.asr_app import (
    DEFAULT_QURAN_WHISPER_MODEL_ID,
    AsrAppSettings,
    create_asr_app,
    create_buffered_asr_recognizer_factory,
    create_buffered_asr_recognizer_factories_by_model,
    create_buffered_whisper_recognizer_factory,
    create_lazy_asr_recognizer_factory,
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
        self.assertEqual(settings.asr_backend, "transformers")
        self.assertEqual(settings.model_id, DEFAULT_QURAN_WHISPER_MODEL_ID)
        self.assertEqual(settings.whisper_backend, "transformers")
        self.assertEqual(settings.language, "ar")
        self.assertIsNone(settings.device)
        self.assertIsNone(settings.faster_whisper_compute_type)
        self.assertIsNone(settings.nemo_model_file)
        self.assertEqual(settings.buffering_profile, "stable")
        self.assertEqual(settings.minimum_audio_ms, 4_200)
        self.assertEqual(settings.flush_interval_ms, 4_200)
        self.assertEqual(settings.tail_audio_ms, 0)
        self.assertEqual(settings.speech_end_min_audio_ms, 4_200)
        self.assertFalse(settings.flush_on_speech_end)
        self.assertEqual(settings.minimum_speech_rms, 400)
        self.assertEqual(settings.minimum_frame_rms, 150)
        self.assertFalse(settings.log_transcripts)
        self.assertIsNone(settings.websocket_bearer_token)

    def test_settings_from_env_accepts_backend_overrides(self):
        settings = settings_from_env({
            "TARTEEL_TANZIL_PATH": "/tmp/quran.txt",
            "TARTEEL_MINIMUM_LOCK_WORDS": "2",
            "TARTEEL_WHISPER_MODEL_ID": "local/quran-whisper",
            "TARTEEL_WHISPER_BACKEND": "faster-whisper",
            "TARTEEL_WHISPER_LANGUAGE": "fa",
            "TARTEEL_WHISPER_DEVICE": "cuda:0",
            "TARTEEL_FASTER_WHISPER_COMPUTE_TYPE": "float16",
            "TARTEEL_ASR_MIN_AUDIO_MS": "1000",
            "TARTEEL_ASR_FLUSH_MS": "750",
            "TARTEEL_ASR_TAIL_MS": "250",
            "TARTEEL_ASR_SPEECH_END_MIN_AUDIO_MS": "500",
            "TARTEEL_ASR_FLUSH_ON_SPEECH_END": "1",
            "TARTEEL_ASR_MIN_SPEECH_RMS": "550",
            "TARTEEL_ASR_MIN_FRAME_RMS": "125",
            "TARTEEL_LOG_TRANSCRIPTS": "1",
            "TARTEEL_WS_BEARER_TOKEN": "secret-token",
        })

        self.assertEqual(settings.tanzil_path, Path("/tmp/quran.txt"))
        self.assertEqual(settings.minimum_lock_words, 2)
        self.assertEqual(settings.asr_backend, "faster-whisper")
        self.assertEqual(settings.model_id, "local/quran-whisper")
        self.assertEqual(settings.whisper_backend, "faster-whisper")
        self.assertEqual(settings.language, "fa")
        self.assertEqual(settings.device, "cuda:0")
        self.assertEqual(settings.faster_whisper_compute_type, "float16")
        self.assertEqual(settings.minimum_audio_ms, 1_000)
        self.assertEqual(settings.flush_interval_ms, 750)
        self.assertEqual(settings.tail_audio_ms, 250)
        self.assertEqual(settings.speech_end_min_audio_ms, 500)
        self.assertTrue(settings.flush_on_speech_end)
        self.assertEqual(settings.minimum_speech_rms, 550)
        self.assertEqual(settings.minimum_frame_rms, 125)
        self.assertTrue(settings.log_transcripts)
        self.assertEqual(settings.websocket_bearer_token, "secret-token")

    def test_settings_from_env_accepts_nemo_backend_overrides(self):
        settings = settings_from_env({
            "TARTEEL_ASR_BACKEND": "nemo",
            "TARTEEL_ASR_MODEL_ID": "mohammed/fastconformer-quran-ar",
            "TARTEEL_ASR_DEVICE": "cuda:0",
            "TARTEEL_NEMO_MODEL_FILE": "phase3_full/phase3_full_wer0.0014.nemo",
            "TARTEEL_HF_CACHE_ROOT": "/models/huggingface-cache/hub",
        })

        self.assertEqual(settings.asr_backend, "nemo")
        self.assertEqual(settings.model_id, "mohammed/fastconformer-quran-ar")
        self.assertEqual(settings.device, "cuda:0")
        self.assertEqual(settings.nemo_model_file, "phase3_full/phase3_full_wer0.0014.nemo")
        self.assertEqual(settings.hf_cache_root, Path("/models/huggingface-cache/hub"))
        self.assertEqual(settings.whisper_backend, "transformers")

    def test_settings_from_env_applies_low_latency_buffering_profile(self):
        settings = settings_from_env({
            "TARTEEL_ASR_BUFFERING_PROFILE": "low-latency",
        })

        self.assertEqual(settings.buffering_profile, "low-latency")
        self.assertEqual(settings.minimum_audio_ms, 2_000)
        self.assertEqual(settings.flush_interval_ms, 1_000)
        self.assertEqual(settings.tail_audio_ms, 500)
        self.assertEqual(settings.speech_end_min_audio_ms, 2_000)
        self.assertEqual(settings.minimum_speech_rms, 400)
        self.assertEqual(settings.minimum_frame_rms, 150)

    def test_explicit_asr_window_env_overrides_profile_values(self):
        settings = settings_from_env({
            "TARTEEL_ASR_BUFFERING_PROFILE": "low-latency",
            "TARTEEL_ASR_MIN_AUDIO_MS": "2300",
            "TARTEEL_ASR_FLUSH_MS": "1200",
            "TARTEEL_ASR_TAIL_MS": "400",
            "TARTEEL_ASR_SPEECH_END_MIN_AUDIO_MS": "900",
            "TARTEEL_ASR_FLUSH_ON_SPEECH_END": "1",
        })

        self.assertEqual(settings.buffering_profile, "low-latency")
        self.assertEqual(settings.minimum_audio_ms, 2_300)
        self.assertEqual(settings.flush_interval_ms, 1_200)
        self.assertEqual(settings.tail_audio_ms, 400)
        self.assertEqual(settings.speech_end_min_audio_ms, 900)
        self.assertTrue(settings.flush_on_speech_end)

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

    def test_lazy_asr_factory_selects_nemo_builder(self):
        built_configs = []

        class StubRecognizer:
            def __init__(self, config):
                built_configs.append(config)

            def recognize(self, chunk: AudioChunk) -> RecognitionResult:
                return RecognitionResult(
                    transcript="إنا أعطيناك الكوثر",
                    confidence=0.9,
                    chunk_sequence=chunk.sequence_number,
                    is_final=True,
                )

        factory = create_lazy_asr_recognizer_factory(
            AsrAppSettings(
                tanzil_path=Path("unused.txt"),
                asr_backend="nemo",
                model_id="mohammed/fastconformer-quran-ar",
                nemo_model_file="phase3_full/phase3_full_wer0.0014.nemo",
                device="cuda:0",
            ),
            nemo_recognizer_builder=StubRecognizer,
        )

        recognizer = factory()
        self.assertEqual(built_configs, [])

        result = recognizer.recognize(AudioChunk(0, b"\x00\x00", 16_000))

        self.assertEqual(result.transcript, "إنا أعطيناك الكوثر")
        self.assertEqual(len(built_configs), 1)
        self.assertEqual(built_configs[0].model_id, "mohammed/fastconformer-quran-ar")
        self.assertEqual(built_configs[0].model_file, "phase3_full/phase3_full_wer0.0014.nemo")
        self.assertEqual(built_configs[0].device, "cuda:0")

    def test_buffered_asr_factory_reuses_nemo_model_across_sessions_with_separate_buffers(self):
        built_configs = []
        recognized_pcm = []

        class StubRecognizer:
            def __init__(self, config):
                built_configs.append(config)

            def recognize(self, chunk: AudioChunk) -> RecognitionResult:
                recognized_pcm.append(chunk.pcm)
                return RecognitionResult(
                    transcript="إنا أعطيناك الكوثر",
                    confidence=0.9,
                    chunk_sequence=chunk.sequence_number,
                    is_final=True,
                )

        factory = create_buffered_asr_recognizer_factory(
            AsrAppSettings(
                tanzil_path=Path("unused.txt"),
                asr_backend="nemo",
                model_id="mohammed/fastconformer-quran-ar",
                minimum_audio_ms=2,
                flush_interval_ms=2,
                tail_audio_ms=0,
                minimum_speech_rms=0,
            ),
            nemo_recognizer_builder=StubRecognizer,
        )

        first_session = factory()
        second_session = factory()
        first_session.recognize(AudioChunk(0, b"\x00\x01", 1_000))
        second_session.recognize(AudioChunk(10, b"\x10\x11", 1_000))
        first_session.recognize(AudioChunk(1, b"\x02\x03", 1_000))
        second_session.recognize(AudioChunk(11, b"\x12\x13", 1_000))

        self.assertEqual(len(built_configs), 1)
        self.assertEqual(recognized_pcm, [
            b"\x00\x01\x02\x03",
            b"\x10\x11\x12\x13",
        ])

    def test_buffered_asr_factories_by_model_keep_one_lazy_recognizer_per_slug(self):
        built_nemo_configs = []
        built_whisper_configs = []
        recognize_calls = []

        class StubRecognizer:
            def __init__(self, label):
                self.label = label

            def recognize(self, chunk: AudioChunk) -> RecognitionResult:
                recognize_calls.append((self.label, chunk.sequence_number))
                return RecognitionResult(
                    transcript="مَلِكِ",
                    confidence=0.9,
                    chunk_sequence=chunk.sequence_number,
                    is_final=True,
                )

        def build_nemo(config):
            built_nemo_configs.append(config)
            return StubRecognizer("nemo")

        def build_whisper(config):
            built_whisper_configs.append(config)
            return StubRecognizer("faster-whisper")

        factories = create_buffered_asr_recognizer_factories_by_model(
            {
                "nemo-fastconformer-quran-ar": AsrAppSettings(
                    tanzil_path=Path("unused.txt"),
                    asr_backend="nemo",
                    model_id="mohammed/fastconformer-quran-ar",
                    nemo_model_file="phase3_full/phase3_full_wer0.0014.nemo",
                    minimum_audio_ms=2,
                    flush_interval_ms=2,
                    minimum_speech_rms=0,
                ),
                "faster-whisper-base-ar-quran": AsrAppSettings(
                    tanzil_path=Path("unused.txt"),
                    asr_backend="faster-whisper",
                    whisper_backend="faster-whisper",
                    model_id="OdyAsh/faster-whisper-base-ar-quran",
                    minimum_audio_ms=2,
                    flush_interval_ms=2,
                    minimum_speech_rms=0,
                ),
            },
            nemo_recognizer_builder=build_nemo,
            whisper_recognizer_builder=build_whisper,
        )

        nemo_session_a = factories["nemo-fastconformer-quran-ar"]()
        nemo_session_b = factories["nemo-fastconformer-quran-ar"]()
        whisper_session = factories["faster-whisper-base-ar-quran"]()

        nemo_session_a.recognize(AudioChunk(0, b"\x00\x01", 1_000))
        nemo_session_a.recognize(AudioChunk(1, b"\x00\x02", 1_000))
        nemo_session_b.recognize(AudioChunk(10, b"\x00\x03", 1_000))
        nemo_session_b.recognize(AudioChunk(11, b"\x00\x04", 1_000))
        whisper_session.recognize(AudioChunk(20, b"\x00\x05", 1_000))
        whisper_session.recognize(AudioChunk(21, b"\x00\x06", 1_000))

        self.assertEqual(len(built_nemo_configs), 1)
        self.assertEqual(len(built_whisper_configs), 1)
        self.assertEqual(
            recognize_calls,
            [("nemo", 1), ("nemo", 11), ("faster-whisper", 21)],
        )

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
                minimum_speech_rms=0,
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

    def test_buffered_whisper_factory_reuses_model_across_sessions_with_separate_buffers(self):
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
                minimum_speech_rms=0,
            ),
            recognizer_builder=StubRecognizer,
        )

        first_session = factory()
        second_session = factory()
        first_session.recognize(AudioChunk(0, b"\x00\x01", 1_000))
        second_session.recognize(AudioChunk(10, b"\x10\x11", 1_000))
        first_session.recognize(AudioChunk(1, b"\x02\x03", 1_000))
        second_session.recognize(AudioChunk(11, b"\x12\x13", 1_000))

        self.assertEqual(len(built_configs), 1)
        self.assertEqual(recognized_pcm, [
            b"\x00\x01\x02\x03",
            b"\x10\x11\x12\x13",
        ])

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
