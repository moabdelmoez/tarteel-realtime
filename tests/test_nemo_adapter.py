import unittest
import wave
from unittest.mock import patch

from tarteel_realtime.diagnostics import (
    DiagnosticTraceCollector,
    diagnostic_asr_context,
)
from tarteel_realtime.nemo_adapter import (
    NemoBackendMissing,
    NemoConfig,
    NemoRecognizer,
    NemoTranscribeBackend,
)
from tarteel_realtime.recognition import AudioChunk


class FakeNemoBackend:
    def __init__(self, transcript="إنا أعطيناك الكوثر", confidence=0.91, is_final=True):
        self.calls = []
        self._transcript = transcript
        self._confidence = confidence
        self._is_final = is_final

    def transcribe(self, *, samples, sample_rate_hz):
        self.calls.append({
            "samples": samples,
            "sample_rate_hz": sample_rate_hz,
        })
        return {
            "text": self._transcript,
            "confidence": self._confidence,
            "is_final": self._is_final,
        }


class NemoRecognizerTests(unittest.TestCase):
    def test_recognizes_audio_chunk_with_injected_backend(self):
        backend = FakeNemoBackend()
        recognizer = NemoRecognizer(
            backend=backend,
            config=NemoConfig(model_id="mohammed/fastconformer-quran-ar"),
        )

        result = recognizer.recognize(AudioChunk(
            sequence_number=7,
            pcm=b"\x00\x40\x00\xc0",
            sample_rate_hz=16_000,
        ))

        self.assertEqual(result.transcript, "إنا أعطيناك الكوثر")
        self.assertEqual(result.normalized_transcript, "انا اعطيناك الكوثر")
        self.assertEqual(result.confidence, 0.91)
        self.assertEqual(result.chunk_sequence, 7)
        self.assertTrue(result.is_final)
        self.assertEqual(backend.calls, [{
            "samples": [0.5, -0.5],
            "sample_rate_hz": 16_000,
        }])

    def test_uses_safe_defaults_when_backend_omits_optional_fields(self):
        class MinimalBackend:
            def transcribe(self, *, samples, sample_rate_hz):
                return {"text": "فصل لربك وانحر"}

        recognizer = NemoRecognizer(
            backend=MinimalBackend(),
            config=NemoConfig(model_id="mohammed/fastconformer-quran-ar"),
        )

        result = recognizer.recognize(AudioChunk(
            sequence_number=2,
            pcm=b"\x00\x00",
            sample_rate_hz=16_000,
        ))

        self.assertEqual(result.transcript, "فصل لربك وانحر")
        self.assertEqual(result.confidence, 0.0)
        self.assertTrue(result.is_final)

    def test_records_inference_timing_in_diagnostic_context(self):
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
        recognizer = NemoRecognizer(
            backend=FakeNemoBackend(),
            config=NemoConfig(model_id="mohammed/fastconformer-quran-ar"),
        )

        with diagnostic_asr_context(collector, window_id):
            recognizer.recognize(AudioChunk(0, b"\x00\x01", 16_000))

        envelope = collector.envelope({"type": "locked"})
        self.assertIsInstance(
            envelope["trace"]["asr_window"]["asr_inference_ms"],
            int,
        )

    def test_from_pretrained_raises_clear_error_when_dependency_missing(self):
        def missing_model_factory(*args, **kwargs):
            raise ModuleNotFoundError("No module named 'nemo'")

        with self.assertRaisesRegex(NemoBackendMissing, "nemo_toolkit"):
            NemoRecognizer.from_pretrained(
                NemoConfig(model_id="mohammed/fastconformer-quran-ar"),
                model_factory=missing_model_factory,
            )


class NemoTranscribeBackendTests(unittest.TestCase):
    def test_from_pretrained_loads_model_and_moves_to_device(self):
        class FakeModel:
            def __init__(self):
                self.to_calls = []
                self.eval_called = False

            def to(self, device):
                self.to_calls.append(device)
                return self

            def eval(self):
                self.eval_called = True
                return self

        model = FakeModel()
        factory_calls = []

        def model_factory(model_id):
            factory_calls.append(model_id)
            return model

        backend = NemoTranscribeBackend.from_pretrained(
            NemoConfig(
                model_id="mohammed/fastconformer-quran-ar",
                device="cuda:0",
                batch_size=2,
            ),
            model_factory=model_factory,
        )

        self.assertIs(backend.model, model)
        self.assertEqual(factory_calls, ["mohammed/fastconformer-quran-ar"])
        self.assertEqual(model.to_calls, ["cuda:0"])
        self.assertTrue(model.eval_called)

    def test_from_pretrained_restores_nested_nemo_file_from_huggingface_snapshot(self):
        class FakeModel:
            def __init__(self):
                self.eval_called = False

            def eval(self):
                self.eval_called = True
                return self

        model = FakeModel()
        snapshot_calls = []
        restore_calls = []

        def snapshot_downloader(*, repo_id, cache_dir):
            snapshot_calls.append({
                "repo_id": repo_id,
                "cache_dir": cache_dir,
            })
            return "/cache/snapshots/60973918"

        def restore_factory(*, restore_path):
            restore_calls.append(restore_path)
            return model

        backend = NemoTranscribeBackend.from_pretrained(
            NemoConfig(
                model_id="mohammed/fastconformer-quran-ar",
                model_file="phase3_full/phase3_full_wer0.0014.nemo",
                cache_dir="/models/huggingface-cache/hub",
            ),
            snapshot_downloader=snapshot_downloader,
            restore_factory=restore_factory,
        )

        self.assertIs(backend.model, model)
        self.assertEqual(snapshot_calls, [{
            "repo_id": "mohammed/fastconformer-quran-ar",
            "cache_dir": "/models/huggingface-cache/hub",
        }])
        self.assertEqual(
            restore_calls,
            ["/cache/snapshots/60973918/phase3_full/phase3_full_wer0.0014.nemo"],
        )
        self.assertTrue(model.eval_called)

    def test_transcribe_writes_temp_wav_and_parses_hypothesis_text(self):
        class Hypothesis:
            text = "إن شانئك هو الأبتر"

        class FakeModel:
            def __init__(self):
                self.calls = []

            def transcribe(self, inputs, *, batch_size):
                with wave.open(inputs[0], "rb") as wav_file:
                    self.calls.append({
                        "channels": wav_file.getnchannels(),
                        "sample_width": wav_file.getsampwidth(),
                        "sample_rate": wav_file.getframerate(),
                        "frames": wav_file.getnframes(),
                        "batch_size": batch_size,
                    })
                return [Hypothesis()]

        model = FakeModel()
        backend = NemoTranscribeBackend(
            model=model,
            config=NemoConfig(
                model_id="mohammed/fastconformer-quran-ar",
                batch_size=3,
            ),
        )

        payload = backend.transcribe(
            samples=[0.0, 0.5, -0.5],
            sample_rate_hz=16_000,
        )

        self.assertEqual(model.calls, [{
            "channels": 1,
            "sample_width": 2,
            "sample_rate": 16_000,
            "frames": 3,
            "batch_size": 3,
        }])
        self.assertEqual(payload, {
            "text": "إن شانئك هو الأبتر",
            "confidence": 0.0,
            "is_final": True,
        })

    def test_from_pretrained_imports_nemo_when_no_factory_is_injected(self):
        with patch.dict("sys.modules", {"nemo": None}):
            with self.assertRaisesRegex(NemoBackendMissing, "nemo_toolkit"):
                NemoTranscribeBackend.from_pretrained(
                    NemoConfig(model_id="mohammed/fastconformer-quran-ar"),
                )


if __name__ == "__main__":
    unittest.main()
