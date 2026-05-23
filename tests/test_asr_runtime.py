import unittest
from pathlib import Path

from tarteel_realtime.asr_runtime import (
    DEFAULT_QURAN_WHISPER_MODEL_ID,
    AsrRuntimeSettings,
    create_buffered_whisper_recognizer_factory,
    create_lazy_whisper_recognizer_factory,
    settings_from_env,
)
from tarteel_realtime.recognition import AudioChunk, RecognitionResult


class AsrRuntimeTests(unittest.TestCase):
    def test_settings_from_env_uses_safe_defaults(self):
        settings = settings_from_env({})

        self.assertEqual(settings.tanzil_path, Path("data/tanzil/quran-simple-clean.txt"))
        self.assertEqual(settings.minimum_lock_words, 3)
        self.assertEqual(settings.model_id, DEFAULT_QURAN_WHISPER_MODEL_ID)
        self.assertEqual(settings.whisper_backend, "transformers")
        self.assertEqual(settings.language, "ar")
        self.assertIsNone(settings.device)
        self.assertEqual(settings.minimum_audio_ms, 4_200)
        self.assertEqual(settings.flush_interval_ms, 4_200)
        self.assertEqual(settings.tail_audio_ms, 0)
        self.assertEqual(settings.minimum_speech_rms, 400)
        self.assertEqual(settings.minimum_frame_rms, 150)
        self.assertFalse(settings.log_transcripts)

    def test_lazy_factory_defers_model_build_until_first_audio_chunk(self):
        built = []

        class StubRecognizer:
            def __init__(self, config):
                built.append(config)

            def recognize(self, chunk: AudioChunk) -> RecognitionResult:
                return RecognitionResult(
                    transcript="مَلِكِ",
                    confidence=0.9,
                    chunk_sequence=chunk.sequence_number,
                    is_final=True,
                )

        factory = create_lazy_whisper_recognizer_factory(
            AsrRuntimeSettings(
                tanzil_path=Path("unused.txt"),
                model_id="local/quran-whisper",
            ),
            recognizer_builder=StubRecognizer,
        )

        recognizer = factory()
        self.assertEqual(built, [])
        recognizer.recognize(AudioChunk(0, b"\x00\x00", 16_000))
        self.assertEqual(len(built), 1)

    def test_buffered_factory_wraps_lazy_recognizer(self):
        built = []
        recognized = []

        class StubRecognizer:
            def __init__(self, config):
                built.append(config)

            def recognize(self, chunk: AudioChunk) -> RecognitionResult:
                recognized.append(chunk.pcm)
                return RecognitionResult(
                    transcript="مَلِكِ",
                    confidence=0.9,
                    chunk_sequence=chunk.sequence_number,
                    is_final=True,
                )

        factory = create_buffered_whisper_recognizer_factory(
            AsrRuntimeSettings(
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
        flushed = recognizer.recognize(AudioChunk(1, b"\x02\x03", 1_000))

        self.assertEqual(waiting.transcript, "")
        self.assertEqual(waiting.confidence, 0.0)
        self.assertEqual(flushed.transcript, "مَلِكِ")
        self.assertEqual(len(built), 1)
        self.assertEqual(recognized, [b"\x00\x01\x02\x03"])


if __name__ == "__main__":
    unittest.main()
