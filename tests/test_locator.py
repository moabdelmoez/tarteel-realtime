import unittest
from pathlib import Path

import tarteel_realtime.locator_matching as locator_matching_module
from tarteel_realtime.locator import LocatorStatus, QuranLocator
from tarteel_realtime.quran import QuranCorpus, QuranRef


SAMPLE_TANZIL_LINES = [
    "1|1|بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
    "1|2|الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ",
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


class QuranLocatorTests(unittest.TestCase):
    def setUp(self):
        self.corpus = QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES)
        self.locator = QuranLocator(self.corpus, minimum_lock_words=2)

    def test_locks_onto_unique_ayah_start_phrase(self):
        decision = self.locator.locate("مَلِكِ النَّاسِ")

        self.assertEqual(decision.status, LocatorStatus.LOCKED)
        self.assertEqual(decision.reason, "unique_match")
        self.assertEqual(decision.best.ayah_ref, QuranRef(surah=114, ayah=2))
        self.assertEqual(decision.best.start_ref, QuranRef(surah=114, ayah=2, word_index=1))
        self.assertEqual(decision.best.matched_words, 2)

    def test_locks_onto_phrase_that_starts_inside_an_ayah(self):
        decision = self.locator.locate("أَعُوذُ بِرَبِّ النَّاسِ")

        self.assertEqual(decision.status, LocatorStatus.LOCKED)
        self.assertEqual(decision.best.ayah_ref, QuranRef(surah=114, ayah=1))
        self.assertEqual(decision.best.start_ref, QuranRef(surah=114, ayah=1, word_index=2))
        self.assertEqual(decision.best.matched_words, 3)

    def test_returns_ranked_candidates_for_repeated_phrase(self):
        decision = self.locator.locate("قُلْ أَعُوذُ بِرَبِّ")

        self.assertEqual(decision.status, LocatorStatus.AMBIGUOUS)
        self.assertEqual(decision.reason, "multiple_matches")
        self.assertEqual(
            [candidate.ayah_ref for candidate in decision.candidates],
            [
                QuranRef(surah=113, ayah=1),
                QuranRef(surah=114, ayah=1),
            ],
        )
        self.assertTrue(all(candidate.matched_words == 3 for candidate in decision.candidates))

    def test_short_phrase_is_ambiguous_even_when_unique(self):
        decision = self.locator.locate("مَلِكِ")

        self.assertEqual(decision.status, LocatorStatus.AMBIGUOUS)
        self.assertEqual(decision.reason, "insufficient_context")
        self.assertEqual(decision.best.ayah_ref, QuranRef(surah=114, ayah=2))
        self.assertEqual(decision.best.matched_words, 1)

    def test_returns_not_found_when_no_words_match(self):
        decision = self.locator.locate("كلمة غير موجودة")

        self.assertEqual(decision.status, LocatorStatus.NOT_FOUND)
        self.assertEqual(decision.reason, "no_match")
        self.assertEqual(decision.candidates, ())

    def test_locate_recitation_uses_exact_match_before_tolerant_fallback(self):
        exact_decision = self.locator.locate_recitation("مَلِكِ النَّاسِ")
        tolerant_decision = self.locator.locate_recitation("حَتَّى زُرْتُمُ الْمَقَى")

        self.assertEqual(exact_decision.status, LocatorStatus.LOCKED)
        self.assertEqual(exact_decision.reason, "unique_match")
        self.assertEqual(exact_decision.best.ayah_ref, QuranRef(surah=114, ayah=2))
        self.assertEqual(tolerant_decision.status, LocatorStatus.LOCKED)
        self.assertEqual(tolerant_decision.reason, "tolerant_match")
        self.assertEqual(tolerant_decision.best.ayah_ref, QuranRef(surah=102, ayah=2))

    def test_empty_transcript_is_uncertain(self):
        decision = self.locator.locate("")

        self.assertEqual(decision.status, LocatorStatus.NOT_FOUND)
        self.assertEqual(decision.reason, "no_recognized_words")
        self.assertEqual(decision.candidates, ())

    def test_tolerant_locator_handles_truncated_surah_102_words(self):
        decision = self.locator.locate_tolerant("حَتَّى زُرْتُمُ الْمَقَى")

        self.assertEqual(decision.status, LocatorStatus.LOCKED)
        self.assertEqual(decision.reason, "tolerant_match")
        self.assertEqual(decision.best.ayah_ref, QuranRef(surah=102, ayah=2))
        self.assertEqual(decision.best.start_ref, QuranRef(surah=102, ayah=2, word_index=1))

    def test_tolerant_locator_handles_short_surah_102_asr_substitutions(self):
        cases = [
            ("كَلَّا سَوْفَ تَعْلَى", QuranRef(surah=102, ayah=3), QuranRef(surah=102, ayah=3, word_index=1)),
            ("إِلَّا سَوْفَ تَعْلَمُونَ", QuranRef(surah=102, ayah=3), QuranRef(surah=102, ayah=3, word_index=1)),
            ("عَلَّمُونَ عِلْمَ الْيَقِينِ", QuranRef(surah=102, ayah=5), QuranRef(surah=102, ayah=5, word_index=3)),
            ("وَأُنَّهَا عَيْنَ الْيَقِينِ", QuranRef(surah=102, ayah=7), QuranRef(surah=102, ayah=7, word_index=2)),
            ("ثُمَّ لَتُسْأَلُونَ", QuranRef(surah=102, ayah=8), QuranRef(surah=102, ayah=8, word_index=1)),
        ]

        for transcript, ayah_ref, start_ref in cases:
            with self.subTest(transcript=transcript):
                decision = self.locator.locate_tolerant(transcript)

                self.assertEqual(decision.status, LocatorStatus.LOCKED)
                self.assertEqual(decision.reason, "tolerant_match")
                self.assertEqual(decision.best.ayah_ref, ayah_ref)
                self.assertEqual(decision.best.start_ref, start_ref)

    def test_tolerant_locator_recovers_valid_phrase_inside_noisy_asr_window(self):
        decision = self.locator.locate_tolerant("فكلا سوف تعلمون كلا لو")

        self.assertEqual(decision.status, LocatorStatus.LOCKED)
        self.assertEqual(decision.reason, "tolerant_span_match")
        self.assertEqual(decision.best.ayah_ref, QuranRef(surah=102, ayah=3))
        self.assertEqual(decision.best.start_ref, QuranRef(surah=102, ayah=3, word_index=1))
        self.assertGreaterEqual(decision.best.matched_words, 3)

    def test_tolerant_locator_uses_rapidfuzz_backend(self):
        source = Path(locator_matching_module.__file__).read_text(encoding="utf-8")

        self.assertIn("rapidfuzz", source)
        self.assertNotIn("SequenceMatcher", source)

    def test_tolerant_locator_recovers_clipped_surah_98_fragment(self):
        decision = self.locator.locate_tolerant(
            "مِنْ أَهْلِ الْكِتَابِ الم مُنفَكِينَ حَتَّى تَأْتِيَهُمُ الْبَيِّنَةِ"
        )

        self.assertEqual(decision.status, LocatorStatus.LOCKED)
        self.assertEqual(decision.reason, "tolerant_match")
        self.assertEqual(decision.best.ayah_ref, QuranRef(surah=98, ayah=1))
        self.assertEqual(decision.best.start_ref, QuranRef(surah=98, ayah=1, word_index=9))

    def test_exact_locator_prefers_progression_for_repeated_phrase(self):
        decision = self.locator.locate(
            "كَلَّا سَوْفَ تَعْلَمُونَ",
            preferred_ref=QuranRef(surah=102, ayah=4),
        )

        self.assertEqual(decision.status, LocatorStatus.LOCKED)
        self.assertEqual(decision.best.ayah_ref, QuranRef(surah=102, ayah=4))
        self.assertEqual(decision.best.start_ref, QuranRef(surah=102, ayah=4, word_index=2))

    def test_tolerant_locator_prefers_progression_for_repeated_phrase(self):
        decision = self.locator.locate_tolerant(
            "إِلَّا سَوْفَ تَعْلَمُونَ",
            preferred_ref=QuranRef(surah=102, ayah=4),
        )

        self.assertEqual(decision.status, LocatorStatus.LOCKED)
        self.assertEqual(decision.best.ayah_ref, QuranRef(surah=102, ayah=4))
        self.assertEqual(decision.best.start_ref, QuranRef(surah=102, ayah=4, word_index=2))

    def test_tolerant_locator_recovers_short_clipped_fragment_only_with_progression(self):
        cold_decision = self.locator.locate_tolerant("ثُمَّ لَتَرَى")
        progressed_decision = self.locator.locate_tolerant(
            "ثُمَّ لَتَرَى",
            preferred_ref=QuranRef(surah=102, ayah=7),
        )

        self.assertEqual(cold_decision.status, LocatorStatus.NOT_FOUND)
        self.assertEqual(progressed_decision.status, LocatorStatus.LOCKED)
        self.assertEqual(progressed_decision.reason, "tolerant_match")
        self.assertEqual(progressed_decision.best.ayah_ref, QuranRef(surah=102, ayah=7))
        self.assertEqual(progressed_decision.best.start_ref, QuranRef(surah=102, ayah=7, word_index=1))

    def test_locator_can_be_scoped_to_ordered_ayahs_after_lock(self):
        decision = self.locator.locate(
            "مَلِكِ النَّاسِ",
            allowed_ayah_refs=(QuranRef(surah=102, ayah=4),),
        )

        self.assertEqual(decision.status, LocatorStatus.NOT_FOUND)
        self.assertEqual(decision.reason, "no_match")

    def test_tolerant_locator_scoped_to_surah_98_does_not_jump_to_unrelated_ayah(self):
        decision = self.locator.locate_tolerant(
            "مَلِكِ النَّاسِ",
            allowed_ayah_refs=(QuranRef(surah=98, ayah=3),),
        )

        self.assertEqual(decision.status, LocatorStatus.NOT_FOUND)
        self.assertEqual(decision.reason, "no_match")


if __name__ == "__main__":
    unittest.main()
