import struct
import unittest

from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recognition import AudioChunk, FakeRecognizer
from tarteel_realtime.recitation_stream import RecitationStream


SAMPLE_TANZIL_LINES = [
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
]


def chunk(sequence_number: int = 0, pcm: bytes = b"\x00\x01") -> AudioChunk:
    return AudioChunk(
        sequence_number=sequence_number,
        pcm=pcm,
        sample_rate_hz=16_000,
    )


class FailingRecognizer:
    def recognize(self, audio_chunk: AudioChunk):
        raise RuntimeError("CUDA error: device-side assert triggered")


class RecitationStreamTests(unittest.TestCase):
    def test_process_chunk_returns_event_payload_and_diagnostics(self):
        stream = RecitationStream(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer=FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
        )

        result = stream.process_chunk(chunk(pcm=struct.pack("<hh", 1000, -1000)))

        self.assertEqual(result.event.type.value, "locked")
        self.assertEqual(result.payload["type"], "locked")
        self.assertNotIn("session_id", result.payload)
        self.assertEqual(result.payload["ayah_ref"], "114:2")
        self.assertEqual(result.payload["ayah_text"], "مَلِكِ النَّاسِ")
        self.assertEqual(result.diagnostics.sequence_number, 0)
        self.assertEqual(result.diagnostics.pcm_bytes, 4)
        self.assertEqual(result.diagnostics.sample_rate_hz, 16_000)
        self.assertEqual(result.diagnostics.pcm_rms, 1000)
        self.assertEqual(result.diagnostics.pcm_peak, 1000)
        self.assertEqual(result.diagnostics.event_type, "locked")
        self.assertEqual(result.diagnostics.reason, "unique_match")
        self.assertEqual(result.diagnostics.ayah_ref, "114:2")
        self.assertEqual(result.diagnostics.transcript_chars, 6)
        self.assertEqual(result.diagnostics.transcript_text, "<redacted>")

    def test_process_chunk_can_include_transcript_text_in_diagnostics(self):
        stream = RecitationStream(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer=FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
            log_transcripts=True,
        )

        result = stream.process_chunk(chunk())

        self.assertEqual(result.diagnostics.transcript_text, "مَلِكِ")

    def test_process_chunk_surfaces_asr_errors_as_uncertain_events(self):
        stream = RecitationStream(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer=FailingRecognizer(),
            minimum_lock_words=1,
        )

        result = stream.process_chunk(chunk(sequence_number=3))

        self.assertEqual(result.event.type.value, "uncertain")
        self.assertEqual(result.event.reason, "asr_error")
        self.assertEqual(result.event.chunk_sequence, 3)
        self.assertEqual(result.payload["type"], "uncertain")
        self.assertEqual(result.payload["reason"], "asr_error")
        self.assertEqual(result.payload["chunk_sequence"], 3)
        self.assertEqual(result.diagnostics.event_type, "uncertain")
        self.assertEqual(result.diagnostics.reason, "asr_error")


if __name__ == "__main__":
    unittest.main()
