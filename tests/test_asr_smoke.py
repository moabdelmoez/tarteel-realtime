import io
import json
import tempfile
import unittest
import wave
from pathlib import Path

from tarteel_realtime.recognition import RecognitionResult
from tarteel_realtime.whisper_adapter import WhisperBackendMissing


class RecordingRecognizer:
    def __init__(self, result):
        self.result = result
        self.chunks = []

    def recognize(self, chunk):
        self.chunks.append(chunk)
        return self.result


class AsrSmokeCliTests(unittest.TestCase):
    def write_wav(self, path, *, channels=1, sample_width=2, sample_rate=22_050, frames=b"\x00\x00\xff\x7f"):
        with wave.open(str(path), "wb") as wav_file:
            wav_file.setnchannels(channels)
            wav_file.setsampwidth(sample_width)
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(frames)

    def test_transcribes_pcm16_file_and_prints_json_payload(self):
        from tarteel_realtime.asr_smoke import main

        with tempfile.TemporaryDirectory() as temp_dir:
            audio_path = Path(temp_dir) / "sample.pcm16le"
            audio_path.write_bytes(b"\x00\x00\xff\x7f")

            recognizer = RecordingRecognizer(RecognitionResult(
                transcript="مَلِكِ النَّاسِ",
                confidence=0.91,
                is_final=True,
            ))
            seen_configs = []

            def recognizer_factory(config):
                seen_configs.append(config)
                return recognizer

            stdout = io.StringIO()
            exit_code = main(
                [
                    str(audio_path),
                    "--model-id",
                    "test/quran-whisper",
                    "--sample-rate",
                    "8000",
                    "--language",
                    "ar",
                    "--device",
                    "cpu",
                ],
                stdout=stdout,
                recognizer_factory=recognizer_factory,
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(len(recognizer.chunks), 1)
        self.assertEqual(recognizer.chunks[0].pcm, b"\x00\x00\xff\x7f")
        self.assertEqual(recognizer.chunks[0].sample_rate_hz, 8000)
        self.assertEqual(recognizer.chunks[0].sequence_number, 0)
        self.assertEqual(seen_configs[0].model_id, "test/quran-whisper")
        self.assertEqual(seen_configs[0].language, "ar")
        self.assertEqual(seen_configs[0].device, "cpu")

        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["transcript"], "مَلِكِ النَّاسِ")
        self.assertEqual(payload["normalized_transcript"], "ملك الناس")
        self.assertEqual(payload["confidence"], 0.91)
        self.assertEqual(payload["chunk_sequence"], 0)
        self.assertTrue(payload["is_final"])
        self.assertEqual(payload["sample_rate_hz"], 8000)
        self.assertTrue(payload["audio_path"].endswith("sample.pcm16le"))

    def test_transcribes_mono_pcm16_wav_using_embedded_sample_rate(self):
        from tarteel_realtime.asr_smoke import main

        with tempfile.TemporaryDirectory() as temp_dir:
            audio_path = Path(temp_dir) / "sample.wav"
            self.write_wav(audio_path, sample_rate=22_050)

            recognizer = RecordingRecognizer(RecognitionResult(
                transcript="قُلْ أَعُوذُ",
                confidence=0.88,
                is_final=True,
            ))

            stdout = io.StringIO()
            exit_code = main(
                [str(audio_path), "--sample-rate", "8000"],
                stdout=stdout,
                recognizer_factory=lambda config: recognizer,
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(recognizer.chunks[0].pcm, b"\x00\x00\xff\x7f")
        self.assertEqual(recognizer.chunks[0].sample_rate_hz, 22_050)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["sample_rate_hz"], 22_050)
        self.assertTrue(payload["audio_path"].endswith("sample.wav"))

    def test_includes_locator_payload_when_tanzil_path_is_provided(self):
        from tarteel_realtime.asr_smoke import main

        with tempfile.TemporaryDirectory() as temp_dir:
            directory_path = Path(temp_dir)
            audio_path = directory_path / "sample.pcm16le"
            audio_path.write_bytes(b"\x00\x00")
            tanzil_path = directory_path / "quran-simple-clean.txt"
            tanzil_path.write_text(
                "\n".join([
                    "113|1|قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
                    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
                    "114|2|مَلِكِ النَّاسِ",
                ]),
                encoding="utf-8",
            )

            recognizer = RecordingRecognizer(RecognitionResult(
                transcript="مَلِكِ النَّاسِ",
                confidence=0.91,
                is_final=True,
            ))

            stdout = io.StringIO()
            exit_code = main(
                [
                    str(audio_path),
                    "--tanzil-path",
                    str(tanzil_path),
                    "--minimum-lock-words",
                    "2",
                ],
                stdout=stdout,
                recognizer_factory=lambda config: recognizer,
            )

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["locator"]["status"], "locked")
        self.assertEqual(payload["locator"]["reason"], "unique_match")
        self.assertEqual(payload["locator"]["candidates"][0]["ayah_ref"], "114:2")
        self.assertEqual(payload["locator"]["candidates"][0]["start_ref"], "114:2:1")
        self.assertEqual(payload["locator"]["candidates"][0]["matched_words"], 2)

    def test_rejects_stereo_wav_without_traceback(self):
        from tarteel_realtime.asr_smoke import main

        with tempfile.TemporaryDirectory() as temp_dir:
            audio_path = Path(temp_dir) / "stereo.wav"
            self.write_wav(audio_path, channels=2, frames=b"\x00\x00\x00\x00")

            stdout = io.StringIO()
            stderr = io.StringIO()
            exit_code = main(
                [str(audio_path)],
                stdout=stdout,
                stderr=stderr,
                recognizer_factory=lambda config: RecordingRecognizer(RecognitionResult("", 0.0)),
            )

        self.assertEqual(exit_code, 2)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("mono", stderr.getvalue())

    def test_reports_missing_tanzil_path_without_traceback(self):
        from tarteel_realtime.asr_smoke import main

        with tempfile.TemporaryDirectory() as temp_dir:
            audio_path = Path(temp_dir) / "sample.pcm16le"
            audio_path.write_bytes(b"\x00\x00")

            stdout = io.StringIO()
            stderr = io.StringIO()
            exit_code = main(
                [
                    str(audio_path),
                    "--tanzil-path",
                    str(Path(temp_dir) / "missing.txt"),
                ],
                stdout=stdout,
                stderr=stderr,
                recognizer_factory=lambda config: RecordingRecognizer(RecognitionResult("مَلِكِ النَّاسِ", 0.9)),
            )

        self.assertEqual(exit_code, 2)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("Tanzil file not found", stderr.getvalue())

    def test_reports_missing_optional_backend_without_traceback(self):
        from tarteel_realtime.asr_smoke import main

        with tempfile.TemporaryDirectory() as temp_dir:
            audio_path = Path(temp_dir) / "sample.pcm16le"
            audio_path.write_bytes(b"\x00\x00")

            def recognizer_factory(config):
                raise WhisperBackendMissing("Install transformers/torch to run ASR smoke.")

            stdout = io.StringIO()
            stderr = io.StringIO()
            exit_code = main(
                [str(audio_path)],
                stdout=stdout,
                stderr=stderr,
                recognizer_factory=recognizer_factory,
            )

        self.assertEqual(exit_code, 2)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("Install transformers/torch", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
