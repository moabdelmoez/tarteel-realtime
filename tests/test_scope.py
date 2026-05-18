import unittest

from tarteel_realtime.quran import QuranCorpus, QuranRef
from tarteel_realtime.scope import MVP_SURAH_NUMBERS, mvp_corpus


class MvpScopeTests(unittest.TestCase):
    def test_mvp_surah_numbers_are_fatihah_plus_juz_amma(self):
        self.assertEqual(MVP_SURAH_NUMBERS[0], 1)
        self.assertEqual(MVP_SURAH_NUMBERS[1], 78)
        self.assertEqual(MVP_SURAH_NUMBERS[-1], 114)
        self.assertEqual(len(MVP_SURAH_NUMBERS), 38)

    def test_mvp_corpus_filters_to_fatihah_and_juz_amma(self):
        corpus = QuranCorpus.from_tanzil_lines([
            "1|1|بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
            "2|1|الم",
            "77|1|وَالْمُرْسَلَاتِ عُرْفًا",
            "78|1|عَمَّ يَتَسَاءَلُونَ",
            "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
        ])

        scoped = mvp_corpus(corpus)

        self.assertEqual(
            [ayah.ref for ayah in scoped.ayahs()],
            [
                QuranRef(surah=1, ayah=1),
                QuranRef(surah=78, ayah=1),
                QuranRef(surah=114, ayah=1),
            ],
        )


if __name__ == "__main__":
    unittest.main()
