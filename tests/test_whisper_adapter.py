import unittest
from unittest.mock import patch

from tarteel_realtime.recognition import AudioChunk
from tarteel_realtime.whisper_adapter import (
    TransformersWhisperBackend,
    WhisperBackendMissing,
    WhisperConfig,
    WhisperRecognizer,
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


if __name__ == "__main__":
    unittest.main()
