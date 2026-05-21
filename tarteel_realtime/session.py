from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from tarteel_realtime.alignment import AlignmentStatus, QuranAligner
from tarteel_realtime.locator import (
    LocatorCandidate,
    LocatorDecision,
    LocatorStatus,
    QuranLocator,
)
from tarteel_realtime.quran import QuranCorpus, QuranRef
from tarteel_realtime.recognition import AudioChunk, SpeechRecognizer


class SessionEventType(StrEnum):
    LOCATING = "locating"
    LOCK_CANDIDATE = "lock_candidate"
    LOCKED = "locked"
    PROGRESS = "progress"
    WRONG = "wrong"
    UNCERTAIN = "uncertain"


@dataclass(frozen=True)
class SessionEvent:
    type: SessionEventType
    transcript: str
    confidence: float
    chunk_sequence: int | None
    reason: str | None = None
    candidate_refs: tuple[QuranRef, ...] = ()
    ayah_ref: QuranRef | None = None
    start_ref: QuranRef | None = None
    next_expected_ref: QuranRef | None = None
    consumed_words: int = 0
    expected_ref: QuranRef | None = None
    expected_word: str | None = None
    recognized_word: str | None = None


class RecitationSession:
    def __init__(
        self,
        *,
        corpus: QuranCorpus,
        recognizer: SpeechRecognizer,
        minimum_lock_words: int = 3,
    ) -> None:
        self._recognizer = recognizer
        self._locator = QuranLocator(corpus, minimum_lock_words=minimum_lock_words)
        self._aligner = QuranAligner(corpus)
        self._corpus = corpus
        self._has_locked = False
        self._next_expected_ref: QuranRef | None = None
        self._progress_anchor_ref: QuranRef | None = None
        self._ordered_miss_count = 0
        ordered_ayah_refs = tuple(ayah.ref for ayah in corpus.ayahs())
        self._next_ayah_refs = {
            current_ref: next_ref
            for current_ref, next_ref in zip(ordered_ayah_refs, ordered_ayah_refs[1:])
        }

    def handle_chunk(self, chunk: AudioChunk) -> SessionEvent:
        recognition = self._recognizer.recognize(chunk)

        if _is_waiting_for_audio_buffer(recognition):
            event_type = (
                SessionEventType.LOCATING
                if not self._has_locked
                else SessionEventType.UNCERTAIN
            )
            return SessionEvent(
                type=event_type,
                transcript=recognition.transcript,
                confidence=recognition.confidence,
                chunk_sequence=recognition.chunk_sequence,
                reason="waiting_for_audio_buffer",
                next_expected_ref=self._next_expected_ref,
            )

        if not self._has_locked:
            locator_decision = self._locator.locate(
                recognition.transcript,
                preferred_ref=self._progress_anchor_ref,
            )
            if locator_decision.status == LocatorStatus.NOT_FOUND:
                tolerant_decision = self._locator.locate_tolerant(
                    recognition.transcript,
                    preferred_ref=self._progress_anchor_ref,
                )
                if tolerant_decision.status != LocatorStatus.NOT_FOUND:
                    locator_decision = tolerant_decision

            if locator_decision.status == LocatorStatus.NOT_FOUND:
                return SessionEvent(
                    type=SessionEventType.LOCATING,
                    transcript=recognition.transcript,
                    confidence=recognition.confidence,
                    chunk_sequence=recognition.chunk_sequence,
                    reason=locator_decision.reason,
                )

            if locator_decision.status == LocatorStatus.AMBIGUOUS:
                return SessionEvent(
                    type=SessionEventType.LOCK_CANDIDATE,
                    transcript=recognition.transcript,
                    confidence=recognition.confidence,
                    chunk_sequence=recognition.chunk_sequence,
                    reason=locator_decision.reason,
                    candidate_refs=tuple(
                        candidate.ayah_ref
                        for candidate in locator_decision.candidates
                    ),
                )

            locked_candidate = locator_decision.best
            if locked_candidate is None:
                return SessionEvent(
                    type=SessionEventType.LOCATING,
                    transcript=recognition.transcript,
                    confidence=recognition.confidence,
                    chunk_sequence=recognition.chunk_sequence,
                    reason="no_lock_candidate",
                )

            alignment_decision = self._aligner.evaluate_from(
                locked_candidate.start_ref,
                recognition.transcript,
            )
            self._has_locked = True
            self._ordered_miss_count = 0
            self._next_expected_ref = self._next_ref_after_initial_lock(
                alignment_decision
            )
            self._progress_anchor_ref = self._progress_ref_after(
                locked_candidate.ayah_ref,
                self._next_expected_ref,
            )
            return SessionEvent(
                type=SessionEventType.LOCKED,
                transcript=recognition.transcript,
                confidence=recognition.confidence,
                chunk_sequence=recognition.chunk_sequence,
                reason=locator_decision.reason,
                ayah_ref=locked_candidate.ayah_ref,
                start_ref=locked_candidate.start_ref,
                next_expected_ref=self._next_expected_ref,
                consumed_words=alignment_decision.consumed_words,
            )

        if self._next_expected_ref is None:
            ordered_decision = self._locate_ordered_progression(recognition.transcript)
            if (
                ordered_decision.status == LocatorStatus.LOCKED
                and ordered_decision.best is not None
            ):
                return self._event_from_ordered_candidate(
                    candidate=ordered_decision.best,
                    event_type=SessionEventType.LOCKED,
                    transcript=recognition.transcript,
                    confidence=recognition.confidence,
                    chunk_sequence=recognition.chunk_sequence,
                    reason=ordered_decision.reason,
                )
            return self._ordered_guidance_event(
                transcript=recognition.transcript,
                confidence=recognition.confidence,
                chunk_sequence=recognition.chunk_sequence,
                reason=ordered_decision.reason,
            )

        current_expected_ref = self._next_expected_ref
        alignment_decision = self._aligner.evaluate_from(
            current_expected_ref,
            recognition.transcript,
        )

        if alignment_decision.status == AlignmentStatus.CORRECT:
            self._next_expected_ref = alignment_decision.next_expected_ref
            self._progress_anchor_ref = self._progress_ref_after(
                current_expected_ref,
                self._next_expected_ref,
            )
            return SessionEvent(
                type=SessionEventType.PROGRESS,
                transcript=recognition.transcript,
                confidence=recognition.confidence,
                chunk_sequence=recognition.chunk_sequence,
                next_expected_ref=self._next_expected_ref,
                consumed_words=alignment_decision.consumed_words,
            )

        if alignment_decision.status == AlignmentStatus.UNCERTAIN:
            return SessionEvent(
                type=SessionEventType.UNCERTAIN,
                transcript=recognition.transcript,
                confidence=recognition.confidence,
                chunk_sequence=recognition.chunk_sequence,
                reason=alignment_decision.reason,
                next_expected_ref=self._next_expected_ref,
            )

        ordered_decision = self._locate_ordered_progression(recognition.transcript)
        if (
            ordered_decision.status == LocatorStatus.LOCKED
            and ordered_decision.best is not None
        ):
            event_type = (
                SessionEventType.LOCKED
                if _ayah_ref(ordered_decision.best.ayah_ref) != _ayah_ref(current_expected_ref)
                else SessionEventType.PROGRESS
            )
            return self._event_from_ordered_candidate(
                candidate=ordered_decision.best,
                event_type=event_type,
                transcript=recognition.transcript,
                confidence=recognition.confidence,
                chunk_sequence=recognition.chunk_sequence,
                reason="tolerant_progression",
            )

        return SessionEvent(
            type=SessionEventType.WRONG,
            transcript=recognition.transcript,
            confidence=recognition.confidence,
            chunk_sequence=recognition.chunk_sequence,
            reason=alignment_decision.reason,
            expected_ref=alignment_decision.expected_ref,
            expected_word=alignment_decision.expected_word,
            recognized_word=alignment_decision.recognized_word,
            consumed_words=alignment_decision.consumed_words,
        )

    def _progress_ref_after(
        self,
        current_ref: QuranRef,
        next_expected_ref: QuranRef | None,
    ) -> QuranRef | None:
        if next_expected_ref is not None:
            return next_expected_ref
        ayah_ref = QuranRef(surah=current_ref.surah, ayah=current_ref.ayah)
        return self._next_ayah_refs.get(ayah_ref)

    def _next_ref_after_initial_lock(self, alignment_decision) -> QuranRef | None:
        if alignment_decision.next_expected_ref is not None:
            return alignment_decision.next_expected_ref
        if (
            alignment_decision.status == AlignmentStatus.WRONG
            and alignment_decision.expected_ref is not None
        ):
            return alignment_decision.expected_ref
        return None

    def _locate_ordered_progression(self, transcript: str) -> LocatorDecision:
        allowed_ayah_refs = self._ordered_allowed_ayah_refs()
        if not allowed_ayah_refs:
            return LocatorDecision(
                status=LocatorStatus.NOT_FOUND,
                reason="no_ordered_progression",
            )

        locator_decision = self._locator.locate(
            transcript,
            preferred_ref=self._progress_anchor_ref,
            allowed_ayah_refs=allowed_ayah_refs,
            minimum_start_ref=self._next_expected_ref,
        )
        if locator_decision.status != LocatorStatus.NOT_FOUND:
            return locator_decision

        return self._locator.locate_tolerant(
            transcript,
            preferred_ref=self._progress_anchor_ref,
            allowed_ayah_refs=allowed_ayah_refs,
            minimum_start_ref=self._next_expected_ref,
        )

    def _ordered_allowed_ayah_refs(self) -> tuple[QuranRef, ...]:
        if self._next_expected_ref is None:
            if self._progress_anchor_ref is None:
                return ()
            return (_ayah_ref(self._progress_anchor_ref),)

        current_ayah_ref = _ayah_ref(self._next_expected_ref)
        next_ayah_ref = self._next_ayah_refs.get(current_ayah_ref)
        if next_ayah_ref is None:
            return (current_ayah_ref,)
        return (current_ayah_ref, next_ayah_ref)

    def _event_from_ordered_candidate(
        self,
        *,
        candidate: LocatorCandidate,
        event_type: SessionEventType,
        transcript: str,
        confidence: float,
        chunk_sequence: int | None,
        reason: str | None,
    ) -> SessionEvent:
        self._ordered_miss_count = 0
        self._next_expected_ref = self._next_ref_after_match(candidate)
        self._progress_anchor_ref = self._progress_ref_after(
            candidate.ayah_ref,
            self._next_expected_ref,
        )
        return SessionEvent(
            type=event_type,
            transcript=transcript,
            confidence=confidence,
            chunk_sequence=chunk_sequence,
            reason=reason,
            ayah_ref=candidate.ayah_ref if event_type == SessionEventType.LOCKED else None,
            start_ref=candidate.start_ref if event_type == SessionEventType.LOCKED else None,
            next_expected_ref=self._next_expected_ref,
            consumed_words=candidate.matched_words,
        )

    def _ordered_guidance_event(
        self,
        *,
        transcript: str,
        confidence: float,
        chunk_sequence: int | None,
        reason: str | None,
    ) -> SessionEvent:
        expected_start_ref = self._expected_ordered_start_ref()
        if expected_start_ref is None:
            return SessionEvent(
                type=SessionEventType.UNCERTAIN,
                transcript=transcript,
                confidence=confidence,
                chunk_sequence=chunk_sequence,
                reason=reason,
            )

        self._ordered_miss_count += 1
        expected_word = self._corpus.get_word(expected_start_ref).normalized_text
        if self._ordered_miss_count >= 2:
            return SessionEvent(
                type=SessionEventType.WRONG,
                transcript=transcript,
                confidence=confidence,
                chunk_sequence=chunk_sequence,
                reason="out_of_order",
                expected_ref=expected_start_ref,
                expected_word=expected_word,
            )

        return SessionEvent(
            type=SessionEventType.UNCERTAIN,
            transcript=transcript,
            confidence=confidence,
            chunk_sequence=chunk_sequence,
            reason="expected_ordered_progression",
            ayah_ref=_ayah_ref(expected_start_ref),
            start_ref=expected_start_ref,
            next_expected_ref=expected_start_ref,
        )

    def _expected_ordered_start_ref(self) -> QuranRef | None:
        ref = self._next_expected_ref or self._progress_anchor_ref
        if ref is None:
            return None
        if ref.word_index is not None:
            return ref
        return QuranRef(surah=ref.surah, ayah=ref.ayah, word_index=1)

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


def _ayah_ref(ref: QuranRef) -> QuranRef:
    return QuranRef(surah=ref.surah, ayah=ref.ayah)


def _is_waiting_for_audio_buffer(recognition) -> bool:
    return (
        recognition.transcript == ""
        and recognition.confidence == 0.0
        and not recognition.is_final
    )
