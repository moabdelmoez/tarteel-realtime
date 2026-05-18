from __future__ import annotations

from tarteel_realtime.quran import QuranCorpus


MVP_SURAH_NUMBERS = (1, *range(78, 115))


def mvp_corpus(corpus: QuranCorpus) -> QuranCorpus:
    return corpus.filter_surahs(MVP_SURAH_NUMBERS)
