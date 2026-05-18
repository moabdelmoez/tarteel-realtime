import unittest

from tarteel_realtime.alignment import AlignmentStatus, QuranAligner
from tarteel_realtime.quran import QuranCorpus, QuranRef


SAMPLE_TANZIL_LINES = [
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
]


class QuranAlignerTests(unittest.TestCase):
    def setUp(self):
        self.corpus = QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES)
        self.aligner = QuranAligner(self.corpus)

    def test_marks_matching_partial_recitation_as_correct(self):
        decision = self.aligner.evaluate_from(
            QuranRef(surah=114, ayah=1, word_index=1),
            "قُلْ أَعُوذُ",
        )

        self.assertEqual(decision.status, AlignmentStatus.CORRECT)
        self.assertEqual(decision.consumed_words, 2)
        self.assertEqual(decision.next_expected_ref, QuranRef(surah=114, ayah=1, word_index=3))

    def test_marks_wrong_word_as_wrong(self):
        decision = self.aligner.evaluate_from(
            QuranRef(surah=114, ayah=1, word_index=1),
            "قُلْ أَعُوذُ بِرَبِّ الفلق",
        )

        self.assertEqual(decision.status, AlignmentStatus.WRONG)
        self.assertEqual(decision.expected_ref, QuranRef(surah=114, ayah=1, word_index=4))
        self.assertEqual(decision.expected_word, "الناس")
        self.assertEqual(decision.recognized_word, "الفلق")
        self.assertEqual(decision.reason, "word_mismatch")

    def test_marks_skipped_expected_word_as_wrong(self):
        decision = self.aligner.evaluate_from(
            QuranRef(surah=114, ayah=1, word_index=1),
            "قُلْ بِرَبِّ النَّاسِ",
        )

        self.assertEqual(decision.status, AlignmentStatus.WRONG)
        self.assertEqual(decision.expected_ref, QuranRef(surah=114, ayah=1, word_index=2))
        self.assertEqual(decision.expected_word, "اعوذ")
        self.assertEqual(decision.recognized_word, "برب")
        self.assertEqual(decision.reason, "skipped_word")

    def test_marks_uncorrected_extra_word_as_wrong(self):
        decision = self.aligner.evaluate_from(
            QuranRef(surah=114, ayah=1, word_index=1),
            "قُلْ يا أَعُوذُ",
        )

        self.assertEqual(decision.status, AlignmentStatus.WRONG)
        self.assertEqual(decision.expected_ref, QuranRef(surah=114, ayah=1, word_index=2))
        self.assertEqual(decision.expected_word, "اعوذ")
        self.assertEqual(decision.recognized_word, "يا")
        self.assertEqual(decision.reason, "extra_word")

    def test_marks_empty_or_silent_transcript_as_uncertain(self):
        decision = self.aligner.evaluate_from(
            QuranRef(surah=114, ayah=1, word_index=1),
            "",
        )

        self.assertEqual(decision.status, AlignmentStatus.UNCERTAIN)
        self.assertEqual(decision.reason, "no_recognized_words")

    def test_allows_immediate_repetition_without_advancing(self):
        decision = self.aligner.evaluate_from(
            QuranRef(surah=114, ayah=1, word_index=1),
            "قُلْ قُلْ أَعُوذُ",
        )

        self.assertEqual(decision.status, AlignmentStatus.CORRECT)
        self.assertEqual(decision.consumed_words, 2)
        self.assertEqual(decision.next_expected_ref, QuranRef(surah=114, ayah=1, word_index=3))

    def test_allows_one_immediate_self_correction(self):
        decision = self.aligner.evaluate_from(
            QuranRef(surah=114, ayah=1, word_index=1),
            "قُلْ أَعُوذُ بالملك بِرَبِّ النَّاسِ",
        )

        self.assertEqual(decision.status, AlignmentStatus.CORRECT)
        self.assertEqual(decision.consumed_words, 4)
        self.assertEqual(decision.corrections, ("بالملك",))


if __name__ == "__main__":
    unittest.main()
