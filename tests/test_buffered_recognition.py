import unittest
import struct

from tarteel_realtime.buffered_recognition import BufferedRecognitionConfig, BufferedRecognizer
from tarteel_realtime.recognition import AudioChunk, RecognitionResult, VoiceActivity


def chunk(sequence_number: int, pcm: bytes, sample_rate_hz: int = 1_000) -> AudioChunk:
    return AudioChunk(
        sequence_number=sequence_number,
        pcm=pcm,
        sample_rate_hz=sample_rate_hz,
    )


class RecordingRecognizer:
    def __init__(self):
        self.chunks = []

    def recognize(self, audio_chunk: AudioChunk) -> RecognitionResult:
        self.chunks.append(audio_chunk)
        return RecognitionResult(
            transcript=f"flush-{len(self.chunks)}",
            confidence=0.8,
            chunk_sequence=audio_chunk.sequence_number,
            is_final=True,
        )


class BufferedRecognizerTests(unittest.TestCase):
    def test_waits_until_minimum_audio_before_calling_inner_recognizer(self):
        inner = RecordingRecognizer()
        recognizer = BufferedRecognizer(
            inner,
            config=BufferedRecognitionConfig(
                minimum_audio_ms=3,
                flush_interval_ms=3,
                tail_audio_ms=1,
            ),
        )

        first = recognizer.recognize(chunk(0, b"aa"))
        second = recognizer.recognize(chunk(1, b"bb"))
        third = recognizer.recognize(chunk(2, b"cc"))

        self.assertEqual(first.transcript, "")
        self.assertEqual(first.confidence, 0.0)
        self.assertFalse(first.is_final)
        self.assertEqual(second.transcript, "")
        self.assertEqual(third.transcript, "flush-1")
        self.assertEqual(third.chunk_sequence, 2)
        self.assertEqual([recorded.pcm for recorded in inner.chunks], [b"aabbcc"])

    def test_keeps_tail_audio_after_flush_for_next_window(self):
        inner = RecordingRecognizer()
        recognizer = BufferedRecognizer(
            inner,
            config=BufferedRecognitionConfig(
                minimum_audio_ms=3,
                flush_interval_ms=3,
                tail_audio_ms=1,
            ),
        )

        recognizer.recognize(chunk(0, b"aa"))
        recognizer.recognize(chunk(1, b"bb"))
        recognizer.recognize(chunk(2, b"cc"))
        recognizer.recognize(chunk(3, b"dd"))
        recognizer.recognize(chunk(4, b"ee"))
        result = recognizer.recognize(chunk(5, b"ff"))

        self.assertEqual(result.transcript, "flush-2")
        self.assertEqual([recorded.pcm for recorded in inner.chunks], [
            b"aabbcc",
            b"ccddeeff",
        ])

    def test_empty_audio_chunk_waits_without_calling_inner_recognizer(self):
        inner = RecordingRecognizer()
        recognizer = BufferedRecognizer(
            inner,
            config=BufferedRecognitionConfig(
                minimum_audio_ms=1,
                flush_interval_ms=1,
                tail_audio_ms=0,
            ),
        )

        result = recognizer.recognize(chunk(0, b""))

        self.assertEqual(result.transcript, "")
        self.assertEqual(inner.chunks, [])

    def test_skips_quiet_windows_until_speech_energy_is_present(self):
        inner = RecordingRecognizer()
        recognizer = BufferedRecognizer(
            inner,
            config=BufferedRecognitionConfig(
                minimum_audio_ms=2,
                flush_interval_ms=2,
                tail_audio_ms=0,
            ),
        )

        quiet = recognizer.recognize(chunk(0, b"\x00\x00\x00\x00"))
        loud_pcm = struct.pack("<hh", 1000, -1000)
        loud = recognizer.recognize(chunk(1, loud_pcm))

        self.assertEqual(quiet.transcript, "")
        self.assertEqual(quiet.confidence, 0.0)
        self.assertFalse(quiet.is_final)
        self.assertEqual(loud.transcript, "flush-1")
        self.assertEqual([recorded.pcm for recorded in inner.chunks], [loud_pcm])

    def test_flushes_on_vad_speech_end_after_minimum_audio_before_interval(self):
        inner = RecordingRecognizer()
        recognizer = BufferedRecognizer(
            inner,
            config=BufferedRecognitionConfig(
                minimum_audio_ms=4,
                flush_interval_ms=10,
                tail_audio_ms=0,
            ),
        )

        recognizer.recognize(chunk(0, struct.pack("<hh", 1000, -1000)))
        waiting = recognizer.recognize(chunk(1, b"\x00\x00"))
        result = recognizer.recognize(AudioChunk(
            sequence_number=2,
            pcm=struct.pack("<h", 1000),
            sample_rate_hz=1_000,
            voice_activity=VoiceActivity(
                probability=0.1,
                is_speech_active=False,
                event="speech_end",
            ),
        ))

        self.assertEqual(waiting.transcript, "")
        self.assertEqual(result.transcript, "flush-1")
        self.assertEqual(result.chunk_sequence, 2)
        self.assertEqual([recorded.pcm for recorded in inner.chunks], [
            struct.pack("<hhhh", 1000, -1000, 0, 1000),
        ])

    def test_logs_buffer_diagnostics_without_audio_content(self):
        inner = RecordingRecognizer()
        recognizer = BufferedRecognizer(
            inner,
            config=BufferedRecognitionConfig(
                minimum_audio_ms=3,
                flush_interval_ms=3,
                tail_audio_ms=0,
            ),
        )

        with self.assertLogs("tarteel_realtime.buffered_recognition", level="INFO") as logs:
            recognizer.recognize(chunk(0, b"aa"))
            recognizer.recognize(chunk(1, b"bb"))
            recognizer.recognize(chunk(2, b"cc"))

        joined_logs = "\n".join(logs.output)
        self.assertIn("buffered_ms=1", joined_logs)
        self.assertIn("buffered_ms=3", joined_logs)
        self.assertIn("action=wait", joined_logs)
        self.assertIn("action=flush", joined_logs)


if __name__ == "__main__":
    unittest.main()
