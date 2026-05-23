from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
import re
import unicodedata


_LETTER_NORMALIZATION = str.maketrans(
    {
        "ٱ": "ا",
        "أ": "ا",
        "إ": "ا",
        "آ": "ا",
        "ى": "ي",
        "ؤ": "و",
        "ئ": "ي",
        "ة": "ه",
    }
)


@dataclass(frozen=True, order=True)
class QuranRef:
    surah: int
    ayah: int
    word_index: int | None = None

    def __post_init__(self) -> None:
        if self.surah < 1:
            raise ValueError("surah must be positive")
        if self.ayah < 1:
            raise ValueError("ayah must be positive")
        if self.word_index is not None and self.word_index < 1:
            raise ValueError("word_index must be positive")

    def __str__(self) -> str:
        if self.word_index is None:
            return f"{self.surah}:{self.ayah}"
        return f"{self.surah}:{self.ayah}:{self.word_index}"


@dataclass(frozen=True)
class QuranWord:
    ref: QuranRef
    text: str
    normalized_text: str


@dataclass(frozen=True)
class QuranAyah:
    ref: QuranRef
    text: str
    normalized_text: str
    words: tuple[QuranWord, ...]


def normalize_arabic(text: str) -> str:
    without_marks = "".join(
        char
        for char in text
        if char != "\u0640" and unicodedata.category(char) != "Mn"
    )
    normalized_letters = without_marks.translate(_LETTER_NORMALIZATION)
    return re.sub(r"\s+", " ", normalized_letters).strip()


class QuranCorpus:
    def __init__(self, ayahs: tuple[QuranAyah, ...]) -> None:
        self._ordered_ayahs = ayahs
        self._ayahs = {ayah.ref: ayah for ayah in ayahs}
        self._words = {
            word.ref: word
            for ayah in ayahs
            for word in ayah.words
        }

    @classmethod
    def from_tanzil_lines(cls, lines: list[str]) -> QuranCorpus:
        ayahs: list[QuranAyah] = []

        for line_number, raw_line in enumerate(lines, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            parts = line.split("|", maxsplit=2)
            if len(parts) != 3:
                raise ValueError(f"malformed Tanzil row at line {line_number}")

            surah_text, ayah_text, text = parts
            try:
                surah = int(surah_text)
                ayah = int(ayah_text)
            except ValueError as exc:
                raise ValueError(f"malformed Tanzil row at line {line_number}") from exc

            ref = QuranRef(surah=surah, ayah=ayah)
            words_list: list[QuranWord] = []
            for word in text.split():
                normalized_word = normalize_arabic(word)
                if not normalized_word:
                    continue
                words_list.append(
                    QuranWord(
                        ref=QuranRef(
                            surah=surah,
                            ayah=ayah,
                            word_index=len(words_list) + 1,
                        ),
                        text=word,
                        normalized_text=normalized_word,
                    )
                )
            words = tuple(words_list)
            ayahs.append(
                QuranAyah(
                    ref=ref,
                    text=text,
                    normalized_text=normalize_arabic(text),
                    words=words,
                )
            )

        return cls(tuple(ayahs))

    @classmethod
    def from_tanzil_file(cls, path: str | Path) -> QuranCorpus:
        tanzil_path = Path(path)
        if not tanzil_path.exists():
            raise FileNotFoundError(f"Tanzil file not found: {tanzil_path}")
        return cls.from_tanzil_lines(
            tanzil_path.read_text(encoding="utf-8").splitlines()
        )

    def get_ayah(self, ref: QuranRef) -> QuranAyah:
        ayah_ref = QuranRef(surah=ref.surah, ayah=ref.ayah)
        return self._ayahs[ayah_ref]

    def words_for_ayah(self, ref: QuranRef) -> tuple[QuranWord, ...]:
        return self.get_ayah(ref).words

    def get_word(self, ref: QuranRef) -> QuranWord:
        if ref.word_index is None:
            raise ValueError("word reference must include word_index")
        return self._words[ref]

    def ayahs(self) -> tuple[QuranAyah, ...]:
        return self._ordered_ayahs

    def filter_surahs(self, surahs: Iterable[int]) -> QuranCorpus:
        selected_surahs = set(surahs)
        return QuranCorpus(tuple(
            ayah
            for ayah in self._ordered_ayahs
            if ayah.ref.surah in selected_surahs
        ))
