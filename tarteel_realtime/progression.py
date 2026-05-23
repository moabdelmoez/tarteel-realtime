from __future__ import annotations

from tarteel_realtime.alignment import AlignmentDecision, AlignmentStatus
from tarteel_realtime.locator import LocatorCandidate
from tarteel_realtime.quran import QuranCorpus, QuranRef


class RecitationProgression:
    def __init__(self, corpus: QuranCorpus) -> None:
        self._corpus = corpus
        self.next_expected_ref: QuranRef | None = None
        self.progress_anchor_ref: QuranRef | None = None
        self._ordered_miss_count = 0
        ordered_ayah_refs = tuple(ayah.ref for ayah in corpus.ayahs())
        self._next_ayah_refs = {
            current_ref: next_ref
            for current_ref, next_ref in zip(ordered_ayah_refs, ordered_ayah_refs[1:])
        }

    def mark_initial_lock(
        self,
        *,
        ayah_ref: QuranRef,
        alignment_decision: AlignmentDecision,
    ) -> QuranRef | None:
        self._ordered_miss_count = 0
        self.next_expected_ref = self._next_ref_after_initial_lock(
            alignment_decision
        )
        self.progress_anchor_ref = self._progress_ref_after(
            ayah_ref,
            self.next_expected_ref,
        )
        return self.next_expected_ref

    def mark_alignment_progress(
        self,
        *,
        current_ref: QuranRef,
        next_expected_ref: QuranRef | None,
    ) -> QuranRef | None:
        self.next_expected_ref = next_expected_ref
        self.progress_anchor_ref = self._progress_ref_after(
            current_ref,
            self.next_expected_ref,
        )
        return self.next_expected_ref

    def mark_candidate_match(self, candidate: LocatorCandidate) -> QuranRef | None:
        self._ordered_miss_count = 0
        self.next_expected_ref = self._next_ref_after_match(candidate)
        self.progress_anchor_ref = self._progress_ref_after(
            candidate.ayah_ref,
            self.next_expected_ref,
        )
        return self.next_expected_ref

    def ordered_allowed_ayah_refs(self) -> tuple[QuranRef, ...]:
        if self.next_expected_ref is None:
            if self.progress_anchor_ref is None:
                return ()
            return (ayah_ref(self.progress_anchor_ref),)

        current_ayah_ref = ayah_ref(self.next_expected_ref)
        next_ayah_ref = self._next_ayah_refs.get(current_ayah_ref)
        if next_ayah_ref is None:
            return (current_ayah_ref,)
        return (current_ayah_ref, next_ayah_ref)

    def expected_ordered_start_ref(self) -> QuranRef | None:
        ref = self.next_expected_ref or self.progress_anchor_ref
        if ref is None:
            return None
        if ref.word_index is not None:
            return ref
        return QuranRef(surah=ref.surah, ayah=ref.ayah, word_index=1)

    def record_ordered_miss(self) -> int:
        self._ordered_miss_count += 1
        return self._ordered_miss_count

    def _progress_ref_after(
        self,
        current_ref: QuranRef,
        next_expected_ref: QuranRef | None,
    ) -> QuranRef | None:
        if next_expected_ref is not None:
            return next_expected_ref
        return self._next_ayah_refs.get(ayah_ref(current_ref))

    def _next_ref_after_initial_lock(
        self,
        alignment_decision: AlignmentDecision,
    ) -> QuranRef | None:
        if alignment_decision.next_expected_ref is not None:
            return alignment_decision.next_expected_ref
        if (
            alignment_decision.status == AlignmentStatus.WRONG
            and alignment_decision.expected_ref is not None
        ):
            return alignment_decision.expected_ref
        return None

    def _next_ref_after_match(self, candidate: LocatorCandidate) -> QuranRef | None:
        start_word_index = candidate.start_ref.word_index
        if start_word_index is None:
            raise ValueError("candidate start reference must include word_index")
        next_word_index = start_word_index + candidate.matched_words
        ayah_words = self._corpus.words_for_ayah(candidate.ayah_ref)
        if next_word_index > len(ayah_words):
            return None
        return QuranRef(
            surah=candidate.ayah_ref.surah,
            ayah=candidate.ayah_ref.ayah,
            word_index=next_word_index,
        )


def ayah_ref(ref: QuranRef) -> QuranRef:
    return QuranRef(surah=ref.surah, ayah=ref.ayah)
