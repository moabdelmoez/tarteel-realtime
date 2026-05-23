import unittest

from tarteel_realtime.quran import QuranCorpus, QuranRef
from tarteel_realtime.recitation_scope import parse_recitation_scope


SAMPLE_TANZIL_LINES = [
    "4|1|يا أيها الناس اتقوا ربكم",
    "4|2|وآتوا اليتامى أموالهم",
    "4|3|وإن خفتم ألا تقسطوا",
    "108|1|إنا أعطيناك الكوثر",
    "108|2|فصل لربك وانحر",
    "108|3|إن شانئك هو الأبتر",
]


class RecitationScopeTests(unittest.TestCase):
    def setUp(self):
        self.corpus = QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES)

    def test_parses_surah_scope_to_all_ayah_refs_in_that_surah(self):
        scope = parse_recitation_scope("108", corpus=self.corpus)

        self.assertIsNotNone(scope)
        self.assertEqual(
            scope.allowed_ayah_refs,
            (
                QuranRef(surah=108, ayah=1),
                QuranRef(surah=108, ayah=2),
                QuranRef(surah=108, ayah=3),
            ),
        )

    def test_parses_same_surah_ayah_range(self):
        scope = parse_recitation_scope("4:1-3", corpus=self.corpus)

        self.assertIsNotNone(scope)
        self.assertEqual(
            scope.allowed_ayah_refs,
            (
                QuranRef(surah=4, ayah=1),
                QuranRef(surah=4, ayah=2),
                QuranRef(surah=4, ayah=3),
            ),
        )

    def test_rejects_scope_that_is_not_in_the_loaded_corpus(self):
        with self.assertRaisesRegex(ValueError, "unknown recitation scope"):
            parse_recitation_scope("5", corpus=self.corpus)


if __name__ == "__main__":
    unittest.main()
