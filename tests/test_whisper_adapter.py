import unittest
from unittest.mock import patch

from tarteel_realtime.diagnostics import (
    DiagnosticTraceCollector,
    diagnostic_asr_context,
)
from tarteel_realtime.recognition import AudioChunk
from tarteel_realtime.whisper_adapter import (
    FasterWhisperBackend,
    TransformersWhisperBackend,
    WhisperBackendMissing,
    WhisperConfig,
    WhisperRecognizer,
    _resample_to_whisper_rate,
)


class FakeWhisperBackend:
    def __init__(self, transcript="مَلِكِ النَّاسِ", confidence=0.82, is_final=True):
        self.calls = []
        self._transcript = transcript
        self._confidence = confidence
        self._is_final = is_final

    def transcribe(self, *, samples, sample_rate_hz, language):
        self.calls.append({
            "samples": samples,
            "sample_rate_hz": sample_rate_hz,
            "language": language,
        })
        return {
            "text": self._transcript,
            "confidence": self._confidence,
            "is_final": self._is_final,
        }


class WhisperRecognizerTests(unittest.TestCase):
    def test_recognizes_audio_chunk_with_injected_backend(self):
        backend = FakeWhisperBackend()
        recognizer = WhisperRecognizer(
            backend=backend,
            config=WhisperConfig(model_id="test/quran-whisper", language="ar"),
        )

        result = recognizer.recognize(AudioChunk(
            sequence_number=4,
            pcm=b"\x00\x01",
            sample_rate_hz=16_000,
        ))

        self.assertEqual(result.transcript, "مَلِكِ النَّاسِ")
        self.assertEqual(result.normalized_transcript, "ملك الناس")
        self.assertEqual(result.confidence, 0.82)
        self.assertEqual(result.chunk_sequence, 4)
        self.assertTrue(result.is_final)
        self.assertEqual(backend.calls, [{
            "samples": [0.0078125],
            "sample_rate_hz": 16_000,
            "language": "ar",
        }])

    def test_uses_safe_defaults_when_backend_omits_optional_fields(self):
        class MinimalBackend:
            def transcribe(self, *, samples, sample_rate_hz, language):
                return {"text": "النَّاسِ"}

        recognizer = WhisperRecognizer(
            backend=MinimalBackend(),
            config=WhisperConfig(model_id="test/quran-whisper"),
        )

        result = recognizer.recognize(AudioChunk(
            sequence_number=1,
            pcm=b"\x00\x00",
            sample_rate_hz=16_000,
        ))

        self.assertEqual(result.transcript, "النَّاسِ")
        self.assertEqual(result.confidence, 0.0)
        self.assertFalse(result.is_final)

    def test_whisper_recognizer_records_inference_timing_in_diagnostic_context(self):
        class StaticBackend:
            def transcribe(self, *, samples, sample_rate_hz, language):
                return {"text": "مَلِكِ", "confidence": 0.7, "is_final": True}

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
        recognizer = WhisperRecognizer(
            backend=StaticBackend(),
            config=WhisperConfig(model_id="fake"),
        )

        with diagnostic_asr_context(collector, window_id):
            recognizer.recognize(AudioChunk(0, b"\x00\x01", 16_000))

        envelope = collector.envelope({"type": "locked"})
        self.assertIsInstance(
            envelope["trace"]["asr_window"]["asr_inference_ms"],
            int,
        )

    def test_from_transformers_raises_clear_error_when_dependency_missing(self):
        def missing_pipeline_factory(*args, **kwargs):
            raise ModuleNotFoundError("No module named 'transformers'")

        with self.assertRaisesRegex(WhisperBackendMissing, "transformers"):
            WhisperRecognizer.from_transformers(
                WhisperConfig(model_id="test/quran-whisper"),
                pipeline_factory=missing_pipeline_factory,
            )

    def test_transformers_backend_sends_numpy_array_to_pipeline(self):
        class FakeNumpy:
            float32 = "float32"

            def array(self, values, *, dtype):
                return {"kind": "ndarray", "values": values, "dtype": dtype}

        class RecordingPipeline:
            def __init__(self):
                self.calls = []

            def __call__(self, inputs, *, generate_kwargs):
                self.calls.append((inputs, generate_kwargs))
                return {"text": "مَلِكِ النَّاسِ"}

        pipeline = RecordingPipeline()

        with patch.dict("sys.modules", {"numpy": FakeNumpy()}):
            backend = TransformersWhisperBackend(
                pipeline_factory=lambda **kwargs: pipeline,
                config=WhisperConfig(model_id="test/quran-whisper"),
            )
            backend.transcribe(samples=[0.0, 0.5], sample_rate_hz=16_000, language="ar")

        inputs, generate_kwargs = pipeline.calls[0]
        self.assertEqual(inputs["raw"], {
            "kind": "ndarray",
            "values": [0.0, 0.5],
            "dtype": "float32",
        })
        self.assertEqual(inputs["sampling_rate"], 16_000)
        self.assertEqual(generate_kwargs, {"language": "ar"})

    def test_transformers_backend_retries_without_language_for_outdated_generation_config(self):
        class FakeNumpy:
            float32 = "float32"

            def array(self, values, *, dtype):
                return {"kind": "ndarray", "values": values, "dtype": dtype}

        class OutdatedGenerationConfigPipeline:
            def __init__(self):
                self.calls = []

            def __call__(self, inputs, *, generate_kwargs):
                self.calls.append((inputs, generate_kwargs))
                if len(self.calls) == 1:
                    inputs.pop("raw")
                    raise ValueError(
                        "The generation config is outdated and is thus not "
                        "compatible with the `language` argument to `generate`."
                    )
                return {"text": "أَلْهَاكُمُ التَّكَاثُرُ"}

        pipeline = OutdatedGenerationConfigPipeline()

        with patch.dict("sys.modules", {"numpy": FakeNumpy()}):
            backend = TransformersWhisperBackend(
                pipeline_factory=lambda **kwargs: pipeline,
                config=WhisperConfig(model_id="test/quran-whisper"),
            )
            payload = backend.transcribe(samples=[0.0], sample_rate_hz=16_000, language="ar")

        self.assertEqual(payload["text"], "أَلْهَاكُمُ التَّكَاثُرُ")
        self.assertEqual(pipeline.calls[0][1], {"language": "ar"})
        self.assertEqual(pipeline.calls[1][1], {})
        self.assertIn("raw", pipeline.calls[1][0])

    def test_faster_whisper_backend_loads_ctranslate_model_and_transcribes_array(self):
        class FakeNumpy:
            float32 = "float32"

            def array(self, values, *, dtype):
                return {
                    "kind": "ndarray",
                    "values": values,
                    "dtype": dtype,
                }

        class Segment:
            def __init__(self, text):
                self.text = text

        class Info:
            language_probability = 0.97

        class FakeModel:
            def __init__(self):
                self.calls = []

            def transcribe(self, audio, **kwargs):
                self.calls.append((audio, kwargs))
                return [Segment(" مَلِكِ "), Segment("النَّاسِ")], Info()

        model = FakeModel()
        factory_calls = []

        def model_factory(model_id, **kwargs):
            factory_calls.append((model_id, kwargs))
            return model

        with patch.dict("sys.modules", {"numpy": FakeNumpy()}):
            backend = FasterWhisperBackend(
                model_factory=model_factory,
                config=WhisperConfig(
                    model_id="OdyAsh/faster-whisper-base-ar-quran",
                    device="cuda:0",
                    compute_type="float16",
                ),
            )
            payload = backend.transcribe(
                samples=[0.0, 0.5],
                sample_rate_hz=16_000,
                language="ar",
            )

        self.assertEqual(factory_calls, [(
            "OdyAsh/faster-whisper-base-ar-quran",
            {
                "device": "cuda",
                "device_index": 0,
                "compute_type": "float16",
            },
        )])
        audio, kwargs = model.calls[0]
        self.assertEqual(audio, {
            "kind": "ndarray",
            "values": [0.0, 0.5],
            "dtype": "float32",
        })
        self.assertEqual(kwargs["language"], "ar")
        self.assertEqual(kwargs["beam_size"], 5)
        self.assertFalse(kwargs["vad_filter"])
        self.assertFalse(kwargs["condition_on_previous_text"])
        self.assertEqual(payload, {
            "text": "مَلِكِ النَّاسِ",
            "confidence": 0.97,
            "is_final": True,
        })

    def test_resamples_transport_rate_audio_to_whisper_rate(self):
        samples = [0.0, 1.0, 0.0, -1.0, 0.0, 1.0]

        resampled = _resample_to_whisper_rate(samples, sample_rate_hz=48_000)

        self.assertEqual(len(resampled), 2)
        self.assertEqual(resampled[0], 0.0)
        self.assertEqual(resampled[1], -1.0)

    def test_from_config_selects_faster_whisper_backend(self):
        config = WhisperConfig(
            model_id="OdyAsh/faster-whisper-base-ar-quran",
            backend="faster-whisper",
        )

        with patch.object(WhisperRecognizer, "from_faster_whisper") as faster_builder:
            WhisperRecognizer.from_config(config)

        faster_builder.assert_called_once_with(config)


if __name__ == "__main__":
    unittest.main()
