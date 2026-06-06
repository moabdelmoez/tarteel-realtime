import struct
import unittest

from tarteel_realtime.buffered_recognition import (
    BufferedRecognitionConfig,
    BufferedRecognizer,
)
from tarteel_realtime.diagnostics import BUFFER_ACTION_FLUSH_ASR
from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recognition import AudioChunk, FakeRecognizer, RecognitionResult
from tarteel_realtime.recitation_stream import RecitationStream


SAMPLE_TANZIL_LINES = [
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
]


def chunk(
    sequence_number: int = 0,
    pcm: bytes = b"\x00\x01",
    sample_rate_hz: int = 16_000,
) -> AudioChunk:
    return AudioChunk(
        sequence_number=sequence_number,
        pcm=pcm,
        sample_rate_hz=sample_rate_hz,
    )


class FailingRecognizer:
    def recognize(self, audio_chunk: AudioChunk):
        raise RuntimeError("CUDA error: device-side assert triggered")


class RecordingRecognizer:
    def __init__(self):
        self.chunks = []

    def recognize(self, audio_chunk: AudioChunk):
        self.chunks.append(audio_chunk)
        return RecognitionResult(
            transcript="مَلِكِ",
            confidence=0.9,
            chunk_sequence=audio_chunk.sequence_number,
            is_final=True,
        )


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

    def test_process_chunk_can_return_diagnostic_envelope(self):
        stream = RecitationStream(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer=FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
            diagnostics_enabled=True,
        )

        result = stream.process_chunk(chunk(0, pcm=struct.pack("<h", 1000)))

        self.assertEqual(result.payload["type"], "locked")
        self.assertIsNotNone(result.diagnostic_envelope)
        self.assertEqual(result.diagnostic_envelope["kind"], "recitation_trace")
        self.assertEqual(result.diagnostic_envelope["event"], result.payload)
        self.assertEqual(result.diagnostic_envelope["trace"]["sequence_number"], 0)
        self.assertEqual(result.diagnostic_envelope["trace"]["audio"]["pcm_bytes"], 2)

    def test_diagnostic_collector_reaches_buffered_recognizer(self):
        inner = RecordingRecognizer()
        stream = RecitationStream(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer=BufferedRecognizer(
                inner,
                config=BufferedRecognitionConfig(
                    minimum_audio_ms=2,
                    flush_interval_ms=2,
                    tail_audio_ms=0,
                    minimum_frame_rms=0,
                ),
            ),
            minimum_lock_words=1,
            diagnostics_enabled=True,
        )

        stream.process_chunk(
            chunk(0, pcm=struct.pack("<h", 1000), sample_rate_hz=1_000)
        )
        result = stream.process_chunk(
            chunk(1, pcm=struct.pack("<h", -1000), sample_rate_hz=1_000)
        )

        self.assertEqual(result.payload["type"], "locked")
        self.assertEqual(
            result.diagnostic_envelope["trace"]["buffer"]["action"],
            BUFFER_ACTION_FLUSH_ASR,
        )
        self.assertEqual(
            result.diagnostic_envelope["trace"]["asr_window"]["segments"],
            [
                {"sequence_number": 0, "start_byte": 0, "end_byte": 2},
                {"sequence_number": 1, "start_byte": 0, "end_byte": 2},
            ],
        )
        self.assertEqual([recorded.pcm for recorded in inner.chunks], [
            struct.pack("<h", 1000) + struct.pack("<h", -1000),
        ])

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
