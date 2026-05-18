from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from tarteel_realtime.alignment import AlignmentStatus, QuranAligner
from tarteel_realtime.locator import LocatorStatus, QuranLocator
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
        self._next_expected_ref: QuranRef | None = None

    def handle_chunk(self, chunk: AudioChunk) -> SessionEvent:
        recognition = self._recognizer.recognize(chunk)

        if _is_waiting_for_audio_buffer(recognition):
            event_type = (
                SessionEventType.LOCATING
                if self._next_expected_ref is None
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

        if self._next_expected_ref is None:
            locator_decision = self._locator.locate(recognition.transcript)
            if locator_decision.status == LocatorStatus.NOT_FOUND:
                tolerant_decision = self._locator.locate_tolerant(recognition.transcript)
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
            self._next_expected_ref = alignment_decision.next_expected_ref
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

        alignment_decision = self._aligner.evaluate_from(
            self._next_expected_ref,
            recognition.transcript,
        )

        if alignment_decision.status == AlignmentStatus.CORRECT:
            self._next_expected_ref = alignment_decision.next_expected_ref
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


def _is_waiting_for_audio_buffer(recognition) -> bool:
    return (
        recognition.transcript == ""
        and recognition.confidence == 0.0
        and not recognition.is_final
    )
