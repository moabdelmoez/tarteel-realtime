import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tarteel_realtime.asr_runtime import (
    DEFAULT_QURAN_WHISPER_MODEL_ID,
    AsrRuntimeSettings,
    LazyRecognizer,
    create_buffered_whisper_recognizer_factory,
    create_lazy_whisper_recognizer_factory,
    settings_from_env,
)
from tarteel_realtime.diagnostics import (
    DiagnosticTraceCollector,
    diagnostic_asr_context,
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

    def test_settings_from_env_applies_low_latency_buffering_profile(self):
        settings = settings_from_env({
            "TARTEEL_ASR_BUFFERING_PROFILE": "low-latency",
        })

        self.assertEqual(settings.buffering_profile, "low-latency")
        self.assertEqual(settings.minimum_audio_ms, 2_000)
        self.assertEqual(settings.flush_interval_ms, 1_000)
        self.assertEqual(settings.tail_audio_ms, 500)
        self.assertEqual(settings.speech_end_min_audio_ms, 2_000)
        self.assertFalse(settings.flush_on_speech_end)
        self.assertEqual(settings.minimum_speech_rms, 400)
        self.assertEqual(settings.minimum_frame_rms, 150)

    def test_settings_from_env_uses_runpod_cached_huggingface_snapshot_when_available(self):
        with TemporaryDirectory() as directory:
            cache_root = Path(directory)
            model_root = cache_root / "models--OdyAsh--faster-whisper-base-ar-quran"
            snapshot = model_root / "snapshots" / "abc123"
            snapshot.mkdir(parents=True)
            (model_root / "refs").mkdir()
            (model_root / "refs" / "main").write_text("abc123", encoding="utf-8")

            settings = settings_from_env({
                "TARTEEL_WHISPER_MODEL_ID": "OdyAsh/faster-whisper-base-ar-quran",
                "TARTEEL_HF_CACHE_ROOT": str(cache_root),
            })

        self.assertEqual(settings.model_id, str(snapshot))

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

    def test_lazy_recognizer_records_cold_start_timing_in_diagnostic_context(self):
        calls = []

        class StaticRecognizer:
            def recognize(self, chunk: AudioChunk) -> RecognitionResult:
                return RecognitionResult(
                    transcript="ready",
                    confidence=1.0,
                    chunk_sequence=chunk.sequence_number,
                    is_final=True,
                )

        collector = DiagnosticTraceCollector(clock=lambda: 1.0)
        collector.begin_chunk(
            sequence_number=0,
            pcm_bytes=2,
            sample_rate_hz=16_000,
            voice_activity=None,
        )
        window_id = collector.begin_asr_window(
            triggering_sequence_number=0,
            segments=[{"sequence_number": 0, "start_byte": 0, "end_byte": 2}],
            audio_ms=1,
            pcm_bytes=2,
            buffered_rms=1000,
            tail_audio_ms=0,
        )
        recognizer = LazyRecognizer(lambda: calls.append("build") or StaticRecognizer())

        with diagnostic_asr_context(collector, window_id):
            recognizer.recognize(AudioChunk(0, b"\x00\x01", 16_000))

        envelope = collector.envelope({"type": "locked"})
        self.assertEqual(calls, ["build"])
        self.assertTrue(envelope["trace"]["asr_window"]["cold_start"])
        self.assertIsInstance(
            envelope["trace"]["asr_window"]["recognizer_init_ms"],
            int,
        )

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
