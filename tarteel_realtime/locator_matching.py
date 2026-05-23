from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from rapidfuzz import fuzz

from tarteel_realtime.locator_types import LocatorCandidate
from tarteel_realtime.quran import QuranCorpus, QuranRef


@dataclass(frozen=True)
class LocatorScoringConfig:
    tolerant_word_threshold: float = 0.60
    preferred_tolerant_word_threshold: float = 0.54
    tolerant_average_threshold: float = 0.72
    ayah_start_bonus: float = 0.01
    preferred_ayah_bonus: float = 1.0


@dataclass(frozen=True)
class LocatorSearchScope:
    preferred_ref: QuranRef | None = None
    allowed_ayah_refs: frozenset[QuranRef] | None = None
    minimum_start_ref: QuranRef | None = None

    @classmethod
    def from_refs(
        cls,
        *,
        preferred_ref: QuranRef | None = None,
        allowed_ayah_refs: Iterable[QuranRef] | None = None,
        minimum_start_ref: QuranRef | None = None,
    ) -> LocatorSearchScope:
        return cls(
            preferred_ref=preferred_ref,
            allowed_ayah_refs=_ayah_ref_set(allowed_ayah_refs),
            minimum_start_ref=minimum_start_ref,
        )

    def allows_ayah(self, ayah_ref: QuranRef) -> bool:
        if self.allowed_ayah_refs is None:
            return True
        return QuranRef(surah=ayah_ref.surah, ayah=ayah_ref.ayah) in self.allowed_ayah_refs

    def allows_start(self, start_ref: QuranRef) -> bool:
        return not _starts_before_minimum(start_ref, self.minimum_start_ref)

    def is_preferred_ayah(self, ayah_ref: QuranRef) -> bool:
        return (
            self.preferred_ref is not None
            and ayah_ref.surah == self.preferred_ref.surah
            and ayah_ref.ayah == self.preferred_ref.ayah
        )


class QuranCandidateFinder:
    def __init__(
        self,
        corpus: QuranCorpus,
        *,
        scoring: LocatorScoringConfig | None = None,
    ) -> None:
        self._corpus = corpus
        self._scoring = scoring or LocatorScoringConfig()

    def exact_candidates(
        self,
        recognized_words: list[str],
        *,
        scope: LocatorSearchScope,
    ) -> tuple[LocatorCandidate, ...]:
        candidates: list[LocatorCandidate] = []
        recognized_length = len(recognized_words)

        for ayah in self._corpus.ayahs():
            if not scope.allows_ayah(ayah.ref):
                continue
            ayah_words = [word.normalized_text for word in ayah.words]
            for start_index in range(0, len(ayah_words) - recognized_length + 1):
                candidate_words = ayah_words[start_index:start_index + recognized_length]
                if candidate_words != recognized_words:
                    continue

                start_ref = ayah.words[start_index].ref
                if not scope.allows_start(start_ref):
                    continue
                candidates.append(
                    LocatorCandidate(
                        ayah_ref=ayah.ref,
                        start_ref=start_ref,
                        matched_words=recognized_length,
                        score=(
                            float(recognized_length)
                            + self._preferred_ayah_bonus(ayah.ref, scope)
                        ),
                    )
                )

        return sort_candidates(candidates)

    def tolerant_candidates(
        self,
        recognized_words: list[str],
        *,
        scope: LocatorSearchScope,
    ) -> tuple[LocatorCandidate, ...]:
        candidates: list[LocatorCandidate] = []
        recognized_length = len(recognized_words)

        for ayah in self._corpus.ayahs():
            if not scope.allows_ayah(ayah.ref):
                continue
            ayah_words = [word.normalized_text for word in ayah.words]
            for start_index in range(0, len(ayah_words) - recognized_length + 1):
                candidate_words = ayah_words[start_index:start_index + recognized_length]
                similarities = tuple(
                    word_similarity(recognized_word, candidate_word)
                    for recognized_word, candidate_word in zip(
                        recognized_words,
                        candidate_words,
                    )
                )
                word_threshold = (
                    self._scoring.preferred_tolerant_word_threshold
                    if scope.is_preferred_ayah(ayah.ref)
                    else self._scoring.tolerant_word_threshold
                )
                if any(similarity < word_threshold for similarity in similarities):
                    continue

                average_similarity = sum(similarities) / recognized_length
                if average_similarity < self._scoring.tolerant_average_threshold:
                    continue

                start_ref = ayah.words[start_index].ref
                if not scope.allows_start(start_ref):
                    continue
                ayah_start_bonus = (
                    self._scoring.ayah_start_bonus
                    if start_ref.word_index == 1
                    else 0.0
                )
                candidates.append(
                    LocatorCandidate(
                        ayah_ref=ayah.ref,
                        start_ref=start_ref,
                        matched_words=recognized_length,
                        score=(
                            sum(similarities)
                            + ayah_start_bonus
                            + self._preferred_ayah_bonus(ayah.ref, scope)
                        ),
                    )
                )

        return sort_candidates(candidates)

    def tolerant_span_candidates(
        self,
        recognized_words: list[str],
        *,
        scope: LocatorSearchScope,
        minimum_lock_words: int,
    ) -> tuple[LocatorCandidate, ...]:
        if len(recognized_words) <= minimum_lock_words:
            return ()

        candidates: dict[tuple[QuranRef, QuranRef, int], LocatorCandidate] = {}
        for window_length in range(
            len(recognized_words) - 1,
            minimum_lock_words - 1,
            -1,
        ):
            for start_index in range(0, len(recognized_words) - window_length + 1):
                window_words = recognized_words[start_index:start_index + window_length]
                for candidate in self.tolerant_candidates(window_words, scope=scope):
                    key = (
                        candidate.ayah_ref,
                        candidate.start_ref,
                        candidate.matched_words,
                    )
                    existing = candidates.get(key)
                    if existing is None or candidate.score > existing.score:
                        candidates[key] = candidate

        return sort_candidates(candidates.values())

    def _preferred_ayah_bonus(
        self,
        ayah_ref: QuranRef,
        scope: LocatorSearchScope,
    ) -> float:
        if scope.is_preferred_ayah(ayah_ref):
            return self._scoring.preferred_ayah_bonus
        return 0.0


def word_similarity(recognized_word: str, candidate_word: str) -> float:
    if recognized_word == candidate_word:
        return 1.0

    ratio = fuzz.ratio(recognized_word, candidate_word) / 100.0
    if len(recognized_word) == len(candidate_word):
        return ratio

    shorter_length = min(len(recognized_word), len(candidate_word))
    if shorter_length < 3:
        return ratio

    partial_ratio = fuzz.partial_ratio(recognized_word, candidate_word) / 100.0
    if partial_ratio < 0.95:
        return ratio
    return max(ratio, partial_ratio)


def sort_candidates(candidates: Iterable[LocatorCandidate]) -> tuple[LocatorCandidate, ...]:
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


def _ayah_ref_set(ayah_refs: Iterable[QuranRef] | None) -> frozenset[QuranRef] | None:
    if ayah_refs is None:
        return None
    return frozenset(
        QuranRef(surah=ref.surah, ayah=ref.ayah)
        for ref in ayah_refs
    )


def _starts_before_minimum(
    start_ref: QuranRef,
    minimum_start_ref: QuranRef | None,
) -> bool:
    if minimum_start_ref is None:
        return False
    if start_ref.word_index is None or minimum_start_ref.word_index is None:
        return False
    if (
        start_ref.surah != minimum_start_ref.surah
        or start_ref.ayah != minimum_start_ref.ayah
    ):
        return False
    return start_ref.word_index < minimum_start_ref.word_index
