from __future__ import annotations

from dataclasses import dataclass
from difflib import SequenceMatcher
from enum import StrEnum

from tarteel_realtime.quran import QuranCorpus, QuranRef, normalize_arabic


class LocatorStatus(StrEnum):
    LOCKED = "locked"
    AMBIGUOUS = "ambiguous"
    NOT_FOUND = "not_found"


@dataclass(frozen=True)
class LocatorCandidate:
    ayah_ref: QuranRef
    start_ref: QuranRef
    matched_words: int
    score: float


@dataclass(frozen=True)
class LocatorDecision:
    status: LocatorStatus
    candidates: tuple[LocatorCandidate, ...] = ()
    reason: str | None = None

    @property
    def best(self) -> LocatorCandidate | None:
        if not self.candidates:
            return None
        return self.candidates[0]


class QuranLocator:
    _TOLERANT_WORD_THRESHOLD = 0.60
    _TOLERANT_AVERAGE_THRESHOLD = 0.72
    _AYAH_START_BONUS = 0.01

    def __init__(self, corpus: QuranCorpus, minimum_lock_words: int = 3) -> None:
        if minimum_lock_words < 1:
            raise ValueError("minimum_lock_words must be positive")
        self._corpus = corpus
        self._minimum_lock_words = minimum_lock_words

    def locate(self, recognized_text: str) -> LocatorDecision:
        recognized_words = normalize_arabic(recognized_text).split()
        if not recognized_words:
            return LocatorDecision(
                status=LocatorStatus.NOT_FOUND,
                reason="no_recognized_words",
            )

        candidates = self._find_candidates(recognized_words)
        if not candidates:
            return LocatorDecision(
                status=LocatorStatus.NOT_FOUND,
                reason="no_match",
            )

        if len(recognized_words) < self._minimum_lock_words:
            return LocatorDecision(
                status=LocatorStatus.AMBIGUOUS,
                candidates=candidates,
                reason="insufficient_context",
            )

        top_score = candidates[0].score
        tied_top_candidates = tuple(
            candidate for candidate in candidates if candidate.score == top_score
        )
        if len(tied_top_candidates) > 1:
            return LocatorDecision(
                status=LocatorStatus.AMBIGUOUS,
                candidates=tied_top_candidates,
                reason="multiple_matches",
            )

        return LocatorDecision(
            status=LocatorStatus.LOCKED,
            candidates=(candidates[0],),
            reason="unique_match",
        )

    def locate_tolerant(self, recognized_text: str) -> LocatorDecision:
        recognized_words = normalize_arabic(recognized_text).split()
        if not recognized_words:
            return LocatorDecision(
                status=LocatorStatus.NOT_FOUND,
                reason="no_recognized_words",
            )

        candidates = self._find_tolerant_candidates(recognized_words)
        if not candidates:
            return LocatorDecision(
                status=LocatorStatus.NOT_FOUND,
                reason="no_match",
            )

        if len(recognized_words) < self._minimum_lock_words:
            return LocatorDecision(
                status=LocatorStatus.AMBIGUOUS,
                candidates=candidates,
                reason="insufficient_context",
            )

        top_score = candidates[0].score
        tied_top_candidates = tuple(
            candidate for candidate in candidates if candidate.score == top_score
        )
        if len(tied_top_candidates) > 1:
            return LocatorDecision(
                status=LocatorStatus.AMBIGUOUS,
                candidates=tied_top_candidates,
                reason="multiple_matches",
            )

        return LocatorDecision(
            status=LocatorStatus.LOCKED,
            candidates=(candidates[0],),
            reason="tolerant_match",
        )

    def _find_candidates(self, recognized_words: list[str]) -> tuple[LocatorCandidate, ...]:
        candidates: list[LocatorCandidate] = []
        recognized_length = len(recognized_words)

        for ayah in self._corpus.ayahs():
            ayah_words = [word.normalized_text for word in ayah.words]
            for start_index in range(0, len(ayah_words) - recognized_length + 1):
                candidate_words = ayah_words[start_index:start_index + recognized_length]
                if candidate_words != recognized_words:
                    continue

                start_ref = ayah.words[start_index].ref
                candidates.append(
                    LocatorCandidate(
                        ayah_ref=ayah.ref,
                        start_ref=start_ref,
                        matched_words=recognized_length,
                        score=float(recognized_length),
                    )
                )

        return tuple(
            sorted(
                candidates,
                key=lambda candidate: (
                    -candidate.score,
                    candidate.ayah_ref.surah,
                    candidate.ayah_ref.ayah,
                    candidate.start_ref.word_index or 0,
                ),
            )
        )

    def _find_tolerant_candidates(
        self,
        recognized_words: list[str],
    ) -> tuple[LocatorCandidate, ...]:
        candidates: list[LocatorCandidate] = []
        recognized_length = len(recognized_words)

        for ayah in self._corpus.ayahs():
            ayah_words = [word.normalized_text for word in ayah.words]
            for start_index in range(0, len(ayah_words) - recognized_length + 1):
                candidate_words = ayah_words[start_index:start_index + recognized_length]
                similarities = tuple(
                    _word_similarity(recognized_word, candidate_word)
                    for recognized_word, candidate_word in zip(
                        recognized_words,
                        candidate_words,
                    )
                )
                if any(
                    similarity < self._TOLERANT_WORD_THRESHOLD
                    for similarity in similarities
                ):
                    continue

                average_similarity = sum(similarities) / recognized_length
                if average_similarity < self._TOLERANT_AVERAGE_THRESHOLD:
                    continue

                start_ref = ayah.words[start_index].ref
                ayah_start_bonus = (
                    self._AYAH_START_BONUS
                    if start_ref.word_index == 1
                    else 0.0
                )
                candidates.append(
                    LocatorCandidate(
                        ayah_ref=ayah.ref,
                        start_ref=start_ref,
                        matched_words=recognized_length,
                        score=sum(similarities) + ayah_start_bonus,
                    )
                )

        return tuple(
            sorted(
                candidates,
                key=lambda candidate: (
                    -candidate.score,
                    candidate.ayah_ref.surah,
                    candidate.ayah_ref.ayah,
                    candidate.start_ref.word_index or 0,
                ),
            )
        )


def _word_similarity(recognized_word: str, candidate_word: str) -> float:
    if recognized_word == candidate_word:
        return 1.0
    return SequenceMatcher(None, recognized_word, candidate_word).ratio()
