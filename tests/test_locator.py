import unittest

from tarteel_realtime.locator import LocatorStatus, QuranLocator
from tarteel_realtime.quran import QuranCorpus, QuranRef


SAMPLE_TANZIL_LINES = [
    "1|1|بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
    "1|2|الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ",
    "113|1|قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
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

    def test_empty_transcript_is_uncertain(self):
        decision = self.locator.locate("")

        self.assertEqual(decision.status, LocatorStatus.NOT_FOUND)
        self.assertEqual(decision.reason, "no_recognized_words")
        self.assertEqual(decision.candidates, ())


if __name__ == "__main__":
    unittest.main()
