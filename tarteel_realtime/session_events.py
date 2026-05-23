from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from tarteel_realtime.locator import LocatorCandidate
from tarteel_realtime.progression import ayah_ref
from tarteel_realtime.quran import QuranRef


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


def waiting_event(
    *,
    transcript: str,
    confidence: float,
    chunk_sequence: int | None,
    has_locked: bool,
    next_expected_ref: QuranRef | None,
) -> SessionEvent:
    event_type = SessionEventType.UNCERTAIN if has_locked else SessionEventType.LOCATING
    return SessionEvent(
        type=event_type,
        transcript=transcript,
        confidence=confidence,
        chunk_sequence=chunk_sequence,
        reason="waiting_for_audio_buffer",
        next_expected_ref=next_expected_ref,
    )


def locating_event(
    *,
    transcript: str,
    confidence: float,
    chunk_sequence: int | None,
    reason: str | None,
) -> SessionEvent:
    return SessionEvent(
        type=SessionEventType.LOCATING,
        transcript=transcript,
        confidence=confidence,
        chunk_sequence=chunk_sequence,
        reason=reason,
    )


def lock_candidate_event(
    *,
    transcript: str,
    confidence: float,
    chunk_sequence: int | None,
    reason: str | None,
    candidate_refs: tuple[QuranRef, ...],
) -> SessionEvent:
    return SessionEvent(
        type=SessionEventType.LOCK_CANDIDATE,
        transcript=transcript,
        confidence=confidence,
        chunk_sequence=chunk_sequence,
        reason=reason,
        candidate_refs=candidate_refs,
    )


def locked_event(
    *,
    transcript: str,
    confidence: float,
    chunk_sequence: int | None,
    reason: str | None,
    candidate: LocatorCandidate,
    next_expected_ref: QuranRef | None,
    consumed_words: int,
) -> SessionEvent:
    return SessionEvent(
        type=SessionEventType.LOCKED,
        transcript=transcript,
        confidence=confidence,
        chunk_sequence=chunk_sequence,
        reason=reason,
        ayah_ref=candidate.ayah_ref,
        start_ref=candidate.start_ref,
        next_expected_ref=next_expected_ref,
        consumed_words=consumed_words,
    )


def ordered_candidate_event(
    *,
    event_type: SessionEventType,
    transcript: str,
    confidence: float,
    chunk_sequence: int | None,
    reason: str | None,
    candidate: LocatorCandidate,
    next_expected_ref: QuranRef | None,
) -> SessionEvent:
    return SessionEvent(
        type=event_type,
        transcript=transcript,
        confidence=confidence,
        chunk_sequence=chunk_sequence,
        reason=reason,
        ayah_ref=candidate.ayah_ref if event_type == SessionEventType.LOCKED else None,
        start_ref=candidate.start_ref if event_type == SessionEventType.LOCKED else None,
        next_expected_ref=next_expected_ref,
        consumed_words=candidate.matched_words,
    )


def progress_event(
    *,
    transcript: str,
    confidence: float,
    chunk_sequence: int | None,
    next_expected_ref: QuranRef | None,
    consumed_words: int,
    reason: str | None = None,
) -> SessionEvent:
    return SessionEvent(
        type=SessionEventType.PROGRESS,
        transcript=transcript,
        confidence=confidence,
        chunk_sequence=chunk_sequence,
        reason=reason,
        next_expected_ref=next_expected_ref,
        consumed_words=consumed_words,
    )


def uncertain_event(
    *,
    transcript: str,
    confidence: float,
    chunk_sequence: int | None,
    reason: str | None,
    next_expected_ref: QuranRef | None = None,
) -> SessionEvent:
    return SessionEvent(
        type=SessionEventType.UNCERTAIN,
        transcript=transcript,
        confidence=confidence,
        chunk_sequence=chunk_sequence,
        reason=reason,
        next_expected_ref=next_expected_ref,
    )


def wrong_event(
    *,
    transcript: str,
    confidence: float,
    chunk_sequence: int | None,
    reason: str | None,
    expected_ref: QuranRef | None = None,
    expected_word: str | None = None,
    recognized_word: str | None = None,
    consumed_words: int = 0,
) -> SessionEvent:
    return SessionEvent(
        type=SessionEventType.WRONG,
        transcript=transcript,
        confidence=confidence,
        chunk_sequence=chunk_sequence,
        reason=reason,
        expected_ref=expected_ref,
        expected_word=expected_word,
        recognized_word=recognized_word,
        consumed_words=consumed_words,
    )


def ordered_guidance_event(
    *,
    transcript: str,
    confidence: float,
    chunk_sequence: int | None,
    expected_start_ref: QuranRef,
) -> SessionEvent:
    return SessionEvent(
        type=SessionEventType.UNCERTAIN,
        transcript=transcript,
        confidence=confidence,
        chunk_sequence=chunk_sequence,
        reason="expected_ordered_progression",
        ayah_ref=ayah_ref(expected_start_ref),
        start_ref=expected_start_ref,
        next_expected_ref=expected_start_ref,
    )


def out_of_order_event(
    *,
    transcript: str,
    confidence: float,
    chunk_sequence: int | None,
    expected_ref: QuranRef,
    expected_word: str,
) -> SessionEvent:
    return wrong_event(
        transcript=transcript,
        confidence=confidence,
        chunk_sequence=chunk_sequence,
        reason="out_of_order",
        expected_ref=expected_ref,
        expected_word=expected_word,
    )
