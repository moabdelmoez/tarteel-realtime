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
    "98|1|بسم الله الرحمن الرحيم لم يكن الذين كفروا من أهل الكتاب والمشركين منفكين حتى تأتيهم البينة",
    "98|2|رسول من الله يتلو صحفا مطهرة",
    "98|3|فيها كتب قيمة",
    "98|4|وما تفرق الذين أوتوا الكتاب إلا من بعد ما جاءتهم البينة",
    "98|5|وما أمروا إلا ليعبدوا الله مخلصين له الدين حنفاء ويقيموا الصلاة ويؤتوا الزكاة وذلك دين القيمة",
    "98|6|إن الذين كفروا من أهل الكتاب والمشركين في نار جهنم خالدين فيها أولئك هم شر البرية",
    "98|7|إن الذين آمنوا وعملوا الصالحات أولئك هم خير البرية",
    "98|8|جزاؤهم عند ربهم جنات عدن تجري من تحتها الأنهار خالدين فيها أبدا رضي الله عنهم ورضوا عنه ذلك لمن خشي ربه",
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

    def test_tolerant_locator_fallback_requires_confirmation_then_locks(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer([
                "حَتَّى زُرْتُمُ الْمَقَى",
                "حَتَّى زُرْتُمُ الْمَقَى",
            ]),
            minimum_lock_words=2,
        )

        first_event = session.handle_chunk(chunk(0))
        second_event = session.handle_chunk(chunk(1))

        self.assertEqual(first_event.type, SessionEventType.LOCK_CANDIDATE)
        self.assertEqual(first_event.reason, "needs_confirmation")
        self.assertEqual(first_event.candidate_refs, (QuranRef(surah=102, ayah=2),))
        self.assertEqual(second_event.type, SessionEventType.LOCKED)
        self.assertEqual(second_event.reason, "tolerant_match")
        self.assertEqual(second_event.ayah_ref, QuranRef(surah=102, ayah=2))
        self.assertEqual(second_event.start_ref, QuranRef(surah=102, ayah=2, word_index=1))

    def test_noisy_live_asr_window_requires_confirmation_then_locks_valid_span(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer([
                "فكلا سوف تعلمون كلا لو",
                "فكلا سوف تعلمون كلا لو",
            ]),
            minimum_lock_words=2,
        )

        first_event = session.handle_chunk(chunk(0))
        second_event = session.handle_chunk(chunk(1))

        self.assertEqual(first_event.type, SessionEventType.LOCK_CANDIDATE)
        self.assertEqual(first_event.reason, "needs_confirmation")
        self.assertEqual(first_event.candidate_refs, (QuranRef(surah=102, ayah=3),))
        self.assertEqual(second_event.type, SessionEventType.LOCKED)
        self.assertEqual(second_event.reason, "tolerant_span_match")
        self.assertEqual(second_event.ayah_ref, QuranRef(surah=102, ayah=3))
        self.assertEqual(second_event.start_ref, QuranRef(surah=102, ayah=3, word_index=1))

    def test_low_evidence_tolerant_initial_match_waits_for_confirmation(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer(["مَلِكِ النَّارِ"]),
            minimum_lock_words=2,
        )

        event = session.handle_chunk(chunk())

        self.assertEqual(event.type, SessionEventType.LOCK_CANDIDATE)
        self.assertEqual(event.reason, "needs_confirmation")
        self.assertEqual(event.candidate_refs, (QuranRef(surah=114, ayah=2),))

    def test_progression_prefers_next_ayah_for_repeated_asr_phrase(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer([
                "كَلَّا سَوْفَ تَعْلَى",
                "كَلَّا سَوْفَ تَعْلَى",
                "إِلَّا سَوْفَ تَعْلَمُونَ",
            ]),
            minimum_lock_words=2,
        )

        first_event = session.handle_chunk(chunk(0))
        second_event = session.handle_chunk(chunk(1))
        third_event = session.handle_chunk(chunk(2))

        self.assertEqual(first_event.type, SessionEventType.LOCK_CANDIDATE)
        self.assertEqual(first_event.reason, "needs_confirmation")
        self.assertEqual(second_event.type, SessionEventType.LOCKED)
        self.assertEqual(second_event.ayah_ref, QuranRef(surah=102, ayah=3))
        self.assertEqual(third_event.type, SessionEventType.LOCKED)
        self.assertEqual(third_event.ayah_ref, QuranRef(surah=102, ayah=4))
        self.assertEqual(third_event.start_ref, QuranRef(surah=102, ayah=4, word_index=2))

    def test_progression_recovers_short_clipped_next_ayah_fragment(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer([
                "لَتَرَوُنَّ الْجَحِيمَ",
                "ثُمَّ لَتَرَى",
            ]),
            minimum_lock_words=2,
        )

        first_event = session.handle_chunk(chunk(0))
        second_event = session.handle_chunk(chunk(1))

        self.assertEqual(first_event.type, SessionEventType.LOCKED)
        self.assertEqual(first_event.ayah_ref, QuranRef(surah=102, ayah=6))
        self.assertEqual(second_event.type, SessionEventType.LOCKED)
        self.assertEqual(second_event.reason, "tolerant_match")
        self.assertEqual(second_event.ayah_ref, QuranRef(surah=102, ayah=7))
        self.assertEqual(second_event.start_ref, QuranRef(surah=102, ayah=7, word_index=1))

    def test_after_lock_does_not_relock_to_unrelated_global_match_at_ayah_boundary(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer([
                "لَتَرَوُنَّ الْجَحِيمَ",
                "مَلِكِ النَّاسِ",
                "مَلِكِ النَّاسِ",
            ]),
            minimum_lock_words=2,
        )

        first_event = session.handle_chunk(chunk(0))
        guidance_event = session.handle_chunk(chunk(1))
        out_of_order_event = session.handle_chunk(chunk(2))

        self.assertEqual(first_event.type, SessionEventType.LOCKED)
        self.assertEqual(first_event.ayah_ref, QuranRef(surah=102, ayah=6))
        self.assertEqual(guidance_event.type, SessionEventType.UNCERTAIN)
        self.assertEqual(guidance_event.reason, "expected_ordered_progression")
        self.assertEqual(guidance_event.ayah_ref, QuranRef(surah=102, ayah=7))
        self.assertEqual(guidance_event.next_expected_ref, QuranRef(surah=102, ayah=7, word_index=1))
        self.assertEqual(out_of_order_event.type, SessionEventType.WRONG)
        self.assertEqual(out_of_order_event.reason, "out_of_order")
        self.assertEqual(out_of_order_event.expected_ref, QuranRef(surah=102, ayah=7, word_index=1))
        self.assertEqual(out_of_order_event.expected_word, "ثم")

    def test_after_lock_recovers_tolerant_progress_inside_current_ayah(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer([
                "كَلَّا لَوْ",
                "عَلَّمُونَ عِلْمَ الْيَقِينِ",
            ]),
            minimum_lock_words=2,
        )

        first_event = session.handle_chunk(chunk(0))
        recovered_event = session.handle_chunk(chunk(1))

        self.assertEqual(first_event.type, SessionEventType.LOCKED)
        self.assertEqual(first_event.ayah_ref, QuranRef(surah=102, ayah=5))
        self.assertEqual(first_event.next_expected_ref, QuranRef(surah=102, ayah=5, word_index=3))
        self.assertEqual(recovered_event.type, SessionEventType.PROGRESS)
        self.assertEqual(recovered_event.reason, "tolerant_progression")
        self.assertEqual(recovered_event.next_expected_ref, None)
        self.assertEqual(recovered_event.consumed_words, 3)

    def test_surah_98_progression_recovers_clipped_expected_next_ayah(self):
        session = RecitationSession(
            corpus=self.corpus,
            recognizer=FakeRecognizer([
                "رَسُولٌ مِنَ اللَّهِ يَتْلُو صُحُفًا مُطَهَّرَةً",
                "فِيهَا كِتَابٌ قَيِّمَةٌ",
            ]),
            minimum_lock_words=2,
        )

        first_event = session.handle_chunk(chunk(0))
        second_event = session.handle_chunk(chunk(1))

        self.assertEqual(first_event.type, SessionEventType.LOCKED)
        self.assertEqual(first_event.ayah_ref, QuranRef(surah=98, ayah=2))
        self.assertEqual(second_event.type, SessionEventType.LOCKED)
        self.assertEqual(second_event.reason, "tolerant_match")
        self.assertEqual(second_event.ayah_ref, QuranRef(surah=98, ayah=3))
        self.assertEqual(second_event.start_ref, QuranRef(surah=98, ayah=3, word_index=1))


if __name__ == "__main__":
    unittest.main()
