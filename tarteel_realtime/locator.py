from __future__ import annotations

from collections.abc import Iterable

from tarteel_realtime.locator_matching import LocatorSearchScope, QuranCandidateFinder
from tarteel_realtime.locator_types import (
    LocatorCandidate,
    LocatorDecision,
    LocatorStatus,
)
from tarteel_realtime.quran import QuranCorpus, QuranRef, normalize_arabic


class QuranLocator:
    def __init__(self, corpus: QuranCorpus, minimum_lock_words: int = 3) -> None:
        if minimum_lock_words < 1:
            raise ValueError("minimum_lock_words must be positive")
        self._minimum_lock_words = minimum_lock_words
        self._candidate_finder = QuranCandidateFinder(corpus)

    def locate(
        self,
        recognized_text: str,
        *,
        preferred_ref: QuranRef | None = None,
        allowed_ayah_refs: Iterable[QuranRef] | None = None,
        minimum_start_ref: QuranRef | None = None,
    ) -> LocatorDecision:
        recognized_words = normalize_arabic(recognized_text).split()
        if not recognized_words:
            return LocatorDecision(
                status=LocatorStatus.NOT_FOUND,
                reason="no_recognized_words",
            )

        candidates = self._candidate_finder.exact_candidates(
            recognized_words,
            scope=LocatorSearchScope.from_refs(
                preferred_ref=preferred_ref,
                allowed_ayah_refs=allowed_ayah_refs,
                minimum_start_ref=minimum_start_ref,
            ),
        )
        return self._decision_from_candidates(
            candidates,
            recognized_word_count=len(recognized_words),
            locked_reason="unique_match",
        )

    def locate_recitation(
        self,
        recognized_text: str,
        *,
        preferred_ref: QuranRef | None = None,
        allowed_ayah_refs: Iterable[QuranRef] | None = None,
        minimum_start_ref: QuranRef | None = None,
    ) -> LocatorDecision:
        decision = self.locate(
            recognized_text,
            preferred_ref=preferred_ref,
            allowed_ayah_refs=allowed_ayah_refs,
            minimum_start_ref=minimum_start_ref,
        )
        if decision.status != LocatorStatus.NOT_FOUND:
            return decision
        return self.locate_tolerant(
            recognized_text,
            preferred_ref=preferred_ref,
            allowed_ayah_refs=allowed_ayah_refs,
            minimum_start_ref=minimum_start_ref,
        )

    def locate_tolerant(
        self,
        recognized_text: str,
        *,
        preferred_ref: QuranRef | None = None,
        allowed_ayah_refs: Iterable[QuranRef] | None = None,
        minimum_start_ref: QuranRef | None = None,
    ) -> LocatorDecision:
        recognized_words = normalize_arabic(recognized_text).split()
        if not recognized_words:
            return LocatorDecision(
                status=LocatorStatus.NOT_FOUND,
                reason="no_recognized_words",
            )

        scope = LocatorSearchScope.from_refs(
            preferred_ref=preferred_ref,
            allowed_ayah_refs=allowed_ayah_refs,
            minimum_start_ref=minimum_start_ref,
        )
        candidates = self._candidate_finder.tolerant_candidates(
            recognized_words,
            scope=scope,
        )
        reason = "tolerant_match"
        if not candidates:
            candidates = self._candidate_finder.tolerant_span_candidates(
                recognized_words,
                scope=scope,
                minimum_lock_words=self._minimum_lock_words,
            )
            reason = "tolerant_span_match"

        return self._decision_from_candidates(
            candidates,
            recognized_word_count=len(recognized_words),
            locked_reason=reason,
        )

    def _decision_from_candidates(
        self,
        candidates: tuple[LocatorCandidate, ...],
        *,
        recognized_word_count: int,
        locked_reason: str,
    ) -> LocatorDecision:
        if not candidates:
            return LocatorDecision(
                status=LocatorStatus.NOT_FOUND,
                reason="no_match",
            )

        if recognized_word_count < self._minimum_lock_words:
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
            reason=locked_reason,
        )
