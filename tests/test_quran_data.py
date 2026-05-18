import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tarteel_realtime.quran import QuranCorpus, QuranRef, normalize_arabic


SAMPLE_TANZIL_LINES = [
    "# Tanzil sample fixture",
    "1|1|بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
    "1|2|الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ",
    "",
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
]


class QuranRefTests(unittest.TestCase):
    def test_formats_ayah_and_word_references(self):
        self.assertEqual(str(QuranRef(surah=1, ayah=2)), "1:2")
        self.assertEqual(str(QuranRef(surah=114, ayah=1, word_index=3)), "114:1:3")


class ArabicNormalizationTests(unittest.TestCase):
    def test_removes_diacritics_and_normalizes_quranic_letters_for_matching(self):
        self.assertEqual(normalize_arabic("بِسْمِ اللَّهِ"), "بسم الله")
        self.assertEqual(normalize_arabic("ٱلرَّحْمَـٰنِ"), "الرحمن")
        self.assertEqual(normalize_arabic("إِيَّاكَ نَعْبُدُ"), "اياك نعبد")


class QuranCorpusTests(unittest.TestCase):
    def test_loads_tanzil_lines_and_returns_ayah_text_by_reference(self):
        corpus = QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES)

        self.assertEqual(
            corpus.get_ayah(QuranRef(surah=1, ayah=1)).text,
            "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
        )
        self.assertEqual(
            corpus.get_ayah(QuranRef(surah=114, ayah=2)).normalized_text,
            "ملك الناس",
        )

    def test_maps_every_word_to_a_stable_quran_reference(self):
        corpus = QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES)

        words = corpus.words_for_ayah(QuranRef(surah=114, ayah=1))

        self.assertEqual(
            [(word.ref, word.normalized_text) for word in words],
            [
                (QuranRef(surah=114, ayah=1, word_index=1), "قل"),
                (QuranRef(surah=114, ayah=1, word_index=2), "اعوذ"),
                (QuranRef(surah=114, ayah=1, word_index=3), "برب"),
                (QuranRef(surah=114, ayah=1, word_index=4), "الناس"),
            ],
        )

    def test_returns_a_single_word_by_quran_reference(self):
        corpus = QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES)

        word = corpus.get_word(QuranRef(surah=1, ayah=1, word_index=2))

        self.assertEqual(word.text, "اللَّهِ")
        self.assertEqual(word.normalized_text, "الله")

    def test_rejects_malformed_tanzil_rows_with_line_context(self):
        with self.assertRaisesRegex(ValueError, "line 2"):
            QuranCorpus.from_tanzil_lines([
                "1|1|بِسْمِ اللَّهِ",
                "this is not a Tanzil row",
            ])

    def test_loads_tanzil_text_from_utf8_file(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "quran-simple-clean.txt"
            path.write_text("\n".join(SAMPLE_TANZIL_LINES), encoding="utf-8")

            corpus = QuranCorpus.from_tanzil_file(path)

        self.assertEqual(
            corpus.get_ayah(QuranRef(surah=114, ayah=1)).normalized_text,
            "قل اعوذ برب الناس",
        )

    def test_missing_tanzil_file_raises_clear_error(self):
        with self.assertRaisesRegex(FileNotFoundError, "Tanzil file not found"):
            QuranCorpus.from_tanzil_file(Path("missing-tanzil-file.txt"))

    def test_filters_to_selected_surahs_without_mutating_original_corpus(self):
        corpus = QuranCorpus.from_tanzil_lines([
            "1|1|بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
            "2|1|الم",
            "78|1|عَمَّ يَتَسَاءَلُونَ",
            "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
        ])

        filtered = corpus.filter_surahs({1, 78, 114})

        self.assertEqual(
            [ayah.ref for ayah in filtered.ayahs()],
            [
                QuranRef(surah=1, ayah=1),
                QuranRef(surah=78, ayah=1),
                QuranRef(surah=114, ayah=1),
            ],
        )
        self.assertEqual(len(corpus.ayahs()), 4)


if __name__ == "__main__":
    unittest.main()
