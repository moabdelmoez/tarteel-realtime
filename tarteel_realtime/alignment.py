from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from tarteel_realtime.quran import QuranCorpus, QuranRef, QuranWord, normalize_arabic


class AlignmentStatus(StrEnum):
    CORRECT = "correct"
    WRONG = "wrong"
    UNCERTAIN = "uncertain"


@dataclass(frozen=True)
class AlignmentDecision:
    status: AlignmentStatus
    consumed_words: int = 0
    next_expected_ref: QuranRef | None = None
    expected_ref: QuranRef | None = None
    expected_word: str | None = None
    recognized_word: str | None = None
    reason: str | None = None
    corrections: tuple[str, ...] = ()


class QuranAligner:
    def __init__(self, corpus: QuranCorpus) -> None:
        self._corpus = corpus

    def evaluate_from(self, start_ref: QuranRef, recognized_text: str) -> AlignmentDecision:
        if start_ref.word_index is None:
            raise ValueError("start reference must include word_index")

        recognized_words = normalize_arabic(recognized_text).split()
        if not recognized_words:
            return AlignmentDecision(
                status=AlignmentStatus.UNCERTAIN,
                next_expected_ref=start_ref,
                reason="no_recognized_words",
            )

        expected_words = self._expected_words_from(start_ref)
        expected_index = 0
        recognized_index = 0
        consumed_words = 0
        last_matched_word: str | None = None
        corrections: list[str] = []

        while recognized_index < len(recognized_words):
            if expected_index >= len(expected_words):
                return AlignmentDecision(
                    status=AlignmentStatus.WRONG,
                    consumed_words=consumed_words,
                    recognized_word=recognized_words[recognized_index],
                    reason="extra_word",
                    corrections=tuple(corrections),
                )

            recognized_word = recognized_words[recognized_index]
            expected_word = expected_words[expected_index]

            if recognized_word == expected_word.normalized_text:
                expected_index += 1
                consumed_words += 1
                last_matched_word = recognized_word
                recognized_index += 1
                continue

            if recognized_word == last_matched_word:
                recognized_index += 1
                continue

            if self._matches_later_expected_word(recognized_word, expected_words, expected_index):
                return self._wrong_decision(
                    reason="skipped_word",
                    expected_word=expected_word,
                    recognized_word=recognized_word,
                    consumed_words=consumed_words,
                    corrections=tuple(corrections),
                )

            next_recognized_word = self._next_recognized_word(recognized_words, recognized_index)
            if consumed_words >= 2 and next_recognized_word == expected_word.normalized_text:
                corrections.append(recognized_word)
                recognized_index += 1
                continue

            reason = "extra_word" if next_recognized_word == expected_word.normalized_text else "word_mismatch"
            return self._wrong_decision(
                reason=reason,
                expected_word=expected_word,
                recognized_word=recognized_word,
                consumed_words=consumed_words,
                corrections=tuple(corrections),
            )

        next_expected_ref = (
            expected_words[expected_index].ref
            if expected_index < len(expected_words)
            else None
        )
        return AlignmentDecision(
            status=AlignmentStatus.CORRECT,
            consumed_words=consumed_words,
            next_expected_ref=next_expected_ref,
            corrections=tuple(corrections),
        )

    def _expected_words_from(self, start_ref: QuranRef) -> tuple[QuranWord, ...]:
        words = self._corpus.words_for_ayah(start_ref)
        return tuple(
            word
            for word in words
            if word.ref.word_index is not None and word.ref.word_index >= start_ref.word_index
        )

    def _matches_later_expected_word(
        self,
        recognized_word: str,
        expected_words: tuple[QuranWord, ...],
        expected_index: int,
    ) -> bool:
        return any(
            recognized_word == word.normalized_text
            for word in expected_words[expected_index + 1:]
        )

    def _wrong_decision(
        self,
        *,
        reason: str,
        expected_word: QuranWord,
        recognized_word: str,
        consumed_words: int,
        corrections: tuple[str, ...],
    ) -> AlignmentDecision:
        return AlignmentDecision(
            status=AlignmentStatus.WRONG,
            consumed_words=consumed_words,
            expected_ref=expected_word.ref,
            expected_word=expected_word.normalized_text,
            recognized_word=recognized_word,
            reason=reason,
            corrections=corrections,
        )

    def _next_recognized_word(
        self,
        recognized_words: list[str],
        recognized_index: int,
    ) -> str | None:
        next_index = recognized_index + 1
        if next_index >= len(recognized_words):
            return None
        return recognized_words[next_index]
