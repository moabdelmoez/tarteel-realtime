import unittest

from tarteel_realtime.locator_matching import (
    LocatorSearchScope,
    QuranCandidateFinder,
)
from tarteel_realtime.quran import QuranCorpus, QuranRef, normalize_arabic


SAMPLE_TANZIL_LINES = [
    "102|3|كلا سوف تعلمون",
    "102|4|ثم كلا سوف تعلمون",
    "102|5|كلا لو تعلمون علم اليقين",
]


class QuranCandidateFinderTests(unittest.TestCase):
    def setUp(self):
        self.corpus = QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES)
        self.finder = QuranCandidateFinder(self.corpus)

    def test_exact_candidates_apply_allowed_ayah_and_minimum_start_scope(self):
        recognized_words = normalize_arabic("كلا سوف تعلمون").split()
        scope = LocatorSearchScope.from_refs(
            allowed_ayah_refs=[QuranRef(surah=102, ayah=4)],
            minimum_start_ref=QuranRef(surah=102, ayah=4, word_index=2),
        )

        candidates = self.finder.exact_candidates(recognized_words, scope=scope)

        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0].ayah_ref, QuranRef(surah=102, ayah=4))
        self.assertEqual(candidates[0].start_ref, QuranRef(surah=102, ayah=4, word_index=2))

    def test_exact_candidates_apply_preferred_ayah_bonus_for_repeated_phrase(self):
        recognized_words = normalize_arabic("كلا سوف تعلمون").split()
        scope = LocatorSearchScope.from_refs(
            preferred_ref=QuranRef(surah=102, ayah=4, word_index=2),
        )

        candidates = self.finder.exact_candidates(recognized_words, scope=scope)

        self.assertEqual(candidates[0].ayah_ref, QuranRef(surah=102, ayah=4))
        self.assertEqual(candidates[0].start_ref, QuranRef(surah=102, ayah=4, word_index=2))

    def test_tolerant_span_candidates_search_inside_noisy_transcript(self):
        recognized_words = normalize_arabic("فكلا سوف تعلمون كلا لو").split()
        scope = LocatorSearchScope.from_refs()

        candidates = self.finder.tolerant_span_candidates(
            recognized_words,
            scope=scope,
            minimum_lock_words=2,
        )

        self.assertGreaterEqual(len(candidates), 1)
        self.assertEqual(candidates[0].ayah_ref, QuranRef(surah=102, ayah=3))
        self.assertEqual(candidates[0].start_ref, QuranRef(surah=102, ayah=3, word_index=1))


if __name__ == "__main__":
    unittest.main()
