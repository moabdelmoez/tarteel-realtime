import unittest

from tarteel_realtime.recognition import (
    AudioChunk,
    FakeRecognizer,
    RecognitionResult,
    RecognizerScriptExhausted,
)


class RecognitionResultTests(unittest.TestCase):
    def test_exposes_normalized_transcript_for_quran_matching(self):
        result = RecognitionResult(
            transcript="مَلِكِ النَّاسِ",
            confidence=0.91,
            chunk_sequence=3,
        )

        self.assertEqual(result.normalized_transcript, "ملك الناس")


class AudioChunkTests(unittest.TestCase):
    def test_rejects_invalid_audio_metadata(self):
        with self.assertRaisesRegex(ValueError, "sequence_number"):
            AudioChunk(sequence_number=-1, pcm=b"\x00", sample_rate_hz=16_000)

        with self.assertRaisesRegex(ValueError, "sample_rate_hz"):
            AudioChunk(sequence_number=0, pcm=b"\x00", sample_rate_hz=0)


class FakeRecognizerTests(unittest.TestCase):
    def test_returns_scripted_transcripts_in_order_with_chunk_metadata(self):
        recognizer = FakeRecognizer([
            "مَلِكِ",
            RecognitionResult(transcript="مَلِكِ النَّاسِ", confidence=0.87),
        ])

        first = recognizer.recognize(AudioChunk(
            sequence_number=10,
            pcm=b"\x00\x01",
            sample_rate_hz=16_000,
        ))
        second = recognizer.recognize(AudioChunk(
            sequence_number=11,
            pcm=b"\x02\x03",
            sample_rate_hz=16_000,
        ))

        self.assertEqual(first.transcript, "مَلِكِ")
        self.assertEqual(first.confidence, 1.0)
        self.assertEqual(first.chunk_sequence, 10)
        self.assertFalse(first.is_final)
        self.assertEqual(second.transcript, "مَلِكِ النَّاسِ")
        self.assertEqual(second.confidence, 0.87)
        self.assertEqual(second.chunk_sequence, 11)

    def test_raises_when_script_is_exhausted(self):
        recognizer = FakeRecognizer(["قُلْ"])
        chunk = AudioChunk(sequence_number=0, pcm=b"\x00", sample_rate_hz=16_000)

        recognizer.recognize(chunk)

        with self.assertRaises(RecognizerScriptExhausted):
            recognizer.recognize(chunk)


if __name__ == "__main__":
    unittest.main()
