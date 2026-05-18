import unittest

from tarteel_realtime.quran import QuranCorpus, QuranRef
from tarteel_realtime.recognition import AudioChunk, FakeRecognizer, RecognitionResult
from tarteel_realtime.session import RecitationSession, SessionEventType


SAMPLE_TANZIL_LINES = [
    "113|1|قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
    "102|1|بسم الله الرحمن الرحيم ألهاكم التكاثر",
    "102|2|حتى زرتم المقابر",
    "102|3|كلا سوف تعلمون",
    "102|4|ثم كلا سوف تعلمون",
    "102|5|كلا لو تعلمون علم اليقين",
    "102|6|لترون الجحيم",
    "102|7|ثم لترونها عين اليقين",
    "102|8|ثم لتسألن يومئذ عن النعيم",
]


def chunk(sequence_number: int = 0) -> AudioChunk:
    return AudioChunk(
        sequence_number=sequence_number,
        pcm=b"\x00\x01",
        sample_rate_hz=16_000,
    )


class RecitationSessionTests(unittest.TestCase):
    def setUp(self):
        self.corpus = QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES)

    def test_emits_lock_candidate_for_ambiguous_phrase_before_lock(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer(["قُلْ أَعُوذُ بِرَبِّ"]),
            minimum_lock_words=2,
        )

        event = session.handle_chunk(chunk())

        self.assertEqual(event.type, SessionEventType.LOCK_CANDIDATE)
        self.assertEqual(event.reason, "multiple_matches")
        self.assertEqual(
            event.candidate_refs,
            (
                QuranRef(surah=113, ayah=1),
                QuranRef(surah=114, ayah=1),
            ),
        )

    def test_locks_on_unique_phrase_and_tracks_next_expected_word(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
        )

        event = session.handle_chunk(chunk())

        self.assertEqual(event.type, SessionEventType.LOCKED)
        self.assertEqual(event.start_ref, QuranRef(surah=114, ayah=2, word_index=1))
        self.assertEqual(event.ayah_ref, QuranRef(surah=114, ayah=2))
        self.assertEqual(event.next_expected_ref, QuranRef(surah=114, ayah=2, word_index=2))

    def test_emits_progress_after_lock_when_next_chunk_matches(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer(["مَلِكِ", "النَّاسِ"]),
            minimum_lock_words=1,
        )

        session.handle_chunk(chunk(0))
        event = session.handle_chunk(chunk(1))

        self.assertEqual(event.type, SessionEventType.PROGRESS)
        self.assertEqual(event.consumed_words, 1)
        self.assertIsNone(event.next_expected_ref)

    def test_emits_wrong_after_lock_when_next_chunk_mismatches(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer(["مَلِكِ", "الْفَلَقِ"]),
            minimum_lock_words=1,
        )

        session.handle_chunk(chunk(0))
        event = session.handle_chunk(chunk(1))

        self.assertEqual(event.type, SessionEventType.WRONG)
        self.assertEqual(event.expected_ref, QuranRef(surah=114, ayah=2, word_index=2))
        self.assertEqual(event.expected_word, "الناس")
        self.assertEqual(event.recognized_word, "الفلق")
        self.assertEqual(event.reason, "word_mismatch")

    def test_emits_uncertain_after_lock_when_transcript_is_empty(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer(["مَلِكِ", ""]),
            minimum_lock_words=1,
        )

        session.handle_chunk(chunk(0))
        event = session.handle_chunk(chunk(1))

        self.assertEqual(event.type, SessionEventType.UNCERTAIN)
        self.assertEqual(event.reason, "no_recognized_words")
        self.assertEqual(event.next_expected_ref, QuranRef(surah=114, ayah=2, word_index=2))

    def test_emits_waiting_event_before_lock_when_asr_buffer_is_not_ready(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer([
                RecognitionResult(
                    transcript="",
                    confidence=0.0,
                    is_final=False,
                ),
            ]),
            minimum_lock_words=1,
        )

        event = session.handle_chunk(chunk(0))

        self.assertEqual(event.type, SessionEventType.LOCATING)
        self.assertEqual(event.reason, "waiting_for_audio_buffer")
        self.assertEqual(event.chunk_sequence, 0)

    def test_waiting_event_after_lock_preserves_next_expected_word(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer([
                "مَلِكِ",
                RecognitionResult(
                    transcript="",
                    confidence=0.0,
                    is_final=False,
                ),
            ]),
            minimum_lock_words=1,
        )

        session.handle_chunk(chunk(0))
        event = session.handle_chunk(chunk(1))

        self.assertEqual(event.type, SessionEventType.UNCERTAIN)
        self.assertEqual(event.reason, "waiting_for_audio_buffer")
        self.assertEqual(event.next_expected_ref, QuranRef(surah=114, ayah=2, word_index=2))

    def test_emits_locating_when_no_match_before_lock(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer(["كلمة غير موجودة"]),
            minimum_lock_words=2,
        )

        event = session.handle_chunk(chunk())

        self.assertEqual(event.type, SessionEventType.LOCATING)
        self.assertEqual(event.reason, "no_match")

    def test_tolerant_locator_fallback_locks_when_exact_match_fails(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer(["حَتَّى زُرْتُمُ الْمَقَى"]),
            minimum_lock_words=2,
        )

        event = session.handle_chunk(chunk())

        self.assertEqual(event.type, SessionEventType.LOCKED)
        self.assertEqual(event.reason, "tolerant_match")
        self.assertEqual(event.ayah_ref, QuranRef(surah=102, ayah=2))
        self.assertEqual(event.start_ref, QuranRef(surah=102, ayah=2, word_index=1))


if __name__ == "__main__":
    unittest.main()
