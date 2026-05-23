from __future__ import annotations

from dataclasses import dataclass

from tarteel_realtime.alignment import AlignmentStatus, QuranAligner
from tarteel_realtime.locator import (
    LocatorCandidate,
    LocatorDecision,
    LocatorStatus,
    QuranLocator,
)
from tarteel_realtime.progression import RecitationProgression, ayah_ref
from tarteel_realtime.quran import QuranCorpus, QuranRef, normalize_arabic
from tarteel_realtime.recognition import RecognitionResult
from tarteel_realtime.session_events import (
    SessionEvent,
    SessionEventType,
    lock_candidate_event,
    locked_event,
    locating_event,
    ordered_candidate_event,
    ordered_guidance_event,
    out_of_order_event,
    progress_event,
    uncertain_event,
    waiting_event,
    wrong_event,
)


class RecitationTransitionPolicy:
    def __init__(
        self,
        *,
        corpus: QuranCorpus,
        minimum_lock_words: int = 3,
    ) -> None:
        self._locator = QuranLocator(corpus, minimum_lock_words=minimum_lock_words)
        self._aligner = QuranAligner(corpus)
        self._progression = RecitationProgression(corpus)
        self._initial_transcript_context = _InitialTranscriptContext()
        self._ordered_transcript_context = _InitialTranscriptContext()
        self._corpus = corpus
        self._has_locked = False

    def handle_recognition(self, recognition: RecognitionResult) -> SessionEvent:
        if _is_waiting_for_audio_buffer(recognition):
            return waiting_event(
                transcript=recognition.transcript,
                confidence=recognition.confidence,
                chunk_sequence=recognition.chunk_sequence,
                has_locked=self._has_locked,
                next_expected_ref=self._progression.next_expected_ref,
            )

        if not self._has_locked:
            return self._handle_initial_location(recognition)

        if self._progression.next_expected_ref is None:
            return self._handle_ayah_boundary(recognition)

        return self._handle_post_lock_alignment(recognition)

    def _handle_initial_location(
        self,
        recognition: RecognitionResult,
    ) -> SessionEvent:
        initial_location = self._recognition_and_decision_for_initial_location(recognition)
        recognition_for_location = initial_location.recognition
        locator_decision = initial_location.decision

        if locator_decision.status == LocatorStatus.NOT_FOUND:
            self._initial_transcript_context.clear()
            return locating_event(
                transcript=recognition.transcript,
                confidence=recognition.confidence,
                chunk_sequence=recognition.chunk_sequence,
                reason=locator_decision.reason,
            )

        if locator_decision.status == LocatorStatus.AMBIGUOUS:
            candidate_refs = tuple(
                candidate.ayah_ref
                for candidate in locator_decision.candidates
            )
            self._initial_transcript_context.remember(
                recognition.transcript,
                candidate_refs=candidate_refs,
            )
            if recognition_for_location.transcript != recognition.transcript:
                self._initial_transcript_context.remember(
                    recognition_for_location.transcript,
                    candidate_refs=candidate_refs,
                )
            return lock_candidate_event(
                transcript=recognition_for_location.transcript,
                confidence=recognition_for_location.confidence,
                chunk_sequence=recognition_for_location.chunk_sequence,
                reason=locator_decision.reason,
                candidate_refs=tuple(
                    candidate.ayah_ref
                    for candidate in locator_decision.candidates
                ),
            )

        locked_candidate = locator_decision.best
        if locked_candidate is None:
            return locating_event(
                transcript=recognition.transcript,
                confidence=recognition.confidence,
                chunk_sequence=recognition.chunk_sequence,
                reason="no_lock_candidate",
            )

        alignment_decision = self._aligner.evaluate_from(
            locked_candidate.start_ref,
            recognition_for_location.transcript,
        )
        self._initial_transcript_context.clear()
        self._ordered_transcript_context.clear()
        self._has_locked = True
        next_expected_ref = self._progression.mark_initial_lock(
            ayah_ref=locked_candidate.ayah_ref,
            alignment_decision=alignment_decision,
        )
        return locked_event(
            transcript=recognition_for_location.transcript,
            confidence=recognition_for_location.confidence,
            chunk_sequence=recognition_for_location.chunk_sequence,
            reason=locator_decision.reason,
            candidate=locked_candidate,
            next_expected_ref=next_expected_ref,
            consumed_words=alignment_decision.consumed_words,
        )

    def _recognition_and_decision_for_initial_location(
        self,
        recognition: RecognitionResult,
    ) -> _InitialLocationResult:
        current_decision = self._locate_initial_recognition(recognition)
        if current_decision.status == LocatorStatus.LOCKED:
            if not _is_tolerant_decision(current_decision):
                return _InitialLocationResult(
                    recognition=recognition,
                    decision=current_decision,
                )
            if (
                not _is_tolerant_span_decision(current_decision)
                and self._initial_context_supports_candidate(current_decision.best)
            ):
                return _InitialLocationResult(
                    recognition=recognition,
                    decision=current_decision,
                )
            return _InitialLocationResult(
                recognition=recognition,
                decision=_confirmation_candidate_decision(current_decision),
            )

        if not self._initial_transcript_context.has_transcript:
            return _InitialLocationResult(
                recognition=recognition,
                decision=current_decision,
            )

        ambiguous_contextual_result: _InitialLocationResult | None = None
        for contextual_recognition in self._initial_transcript_context.combine_all(
            recognition
        ):
            contextual_decision = self._locate_initial_recognition(contextual_recognition)
            if (
                contextual_decision.status == LocatorStatus.LOCKED
                and _current_decision_supports_candidate(
                    current_decision,
                    contextual_decision.best,
                )
                and (
                    not _is_tolerant_decision(contextual_decision)
                    or (
                        not _is_tolerant_span_decision(contextual_decision)
                        and self._initial_context_supports_candidate(contextual_decision.best)
                    )
                )
            ):
                return _InitialLocationResult(
                    recognition=contextual_recognition,
                    decision=contextual_decision,
                )
            if (
                current_decision.status == LocatorStatus.AMBIGUOUS
                and contextual_decision.status == LocatorStatus.AMBIGUOUS
                and ambiguous_contextual_result is None
            ):
                ambiguous_contextual_result = _InitialLocationResult(
                    recognition=contextual_recognition,
                    decision=contextual_decision,
                )

        if ambiguous_contextual_result is not None:
            return ambiguous_contextual_result
        return _InitialLocationResult(
            recognition=recognition,
            decision=current_decision,
        )

    def _initial_context_supports_candidate(
        self,
        candidate: LocatorCandidate | None,
    ) -> bool:
        return self._initial_transcript_context.supports_candidate(candidate)

    def _locate_initial_recognition(
        self,
        recognition: RecognitionResult,
    ) -> LocatorDecision:
        return self._locator.locate_recitation(
            recognition.transcript,
            preferred_ref=self._progression.progress_anchor_ref,
        )

    def _handle_ayah_boundary(
        self,
        recognition: RecognitionResult,
    ) -> SessionEvent:
        recognition_for_location, ordered_decision = (
            self._recognition_and_decision_for_ordered_progression(recognition)
        )
        if (
            ordered_decision.status == LocatorStatus.LOCKED
            and ordered_decision.best is not None
        ):
            return self._event_from_ordered_candidate(
                candidate=ordered_decision.best,
                event_type=SessionEventType.LOCKED,
                transcript=recognition_for_location.transcript,
                confidence=recognition_for_location.confidence,
                chunk_sequence=recognition_for_location.chunk_sequence,
                reason=ordered_decision.reason,
            )
        if ordered_decision.status == LocatorStatus.AMBIGUOUS:
            self._ordered_transcript_context.remember(recognition.transcript)
            if recognition_for_location.transcript != recognition.transcript:
                self._ordered_transcript_context.remember(
                    recognition_for_location.transcript
                )
        return self._ordered_guidance_event(
            transcript=recognition_for_location.transcript,
            confidence=recognition_for_location.confidence,
            chunk_sequence=recognition_for_location.chunk_sequence,
            reason=ordered_decision.reason,
        )

    def _recognition_and_decision_for_ordered_progression(
        self,
        recognition: RecognitionResult,
    ) -> tuple[RecognitionResult, LocatorDecision]:
        current_decision = self._locate_ordered_progression(recognition.transcript)
        if (
            current_decision.status == LocatorStatus.LOCKED
            or not self._ordered_transcript_context.has_transcript
        ):
            return recognition, current_decision

        for contextual_recognition in self._ordered_transcript_context.combine_all(
            recognition
        ):
            contextual_decision = self._locate_ordered_progression(
                contextual_recognition.transcript
            )
            if (
                contextual_decision.status == LocatorStatus.LOCKED
                and _current_decision_supports_candidate(
                    current_decision,
                    contextual_decision.best,
                )
            ):
                return contextual_recognition, contextual_decision

        return recognition, current_decision

    def _handle_post_lock_alignment(
        self,
        recognition: RecognitionResult,
    ) -> SessionEvent:
        current_expected_ref = self._progression.next_expected_ref
        if current_expected_ref is None:
            raise RuntimeError("post-lock alignment requires a next expected ref")

        alignment_decision = self._aligner.evaluate_from(
            current_expected_ref,
            recognition.transcript,
        )

        if alignment_decision.status == AlignmentStatus.CORRECT:
            next_expected_ref = self._progression.mark_alignment_progress(
                current_ref=current_expected_ref,
                next_expected_ref=alignment_decision.next_expected_ref,
            )
            return progress_event(
                transcript=recognition.transcript,
                confidence=recognition.confidence,
                chunk_sequence=recognition.chunk_sequence,
                next_expected_ref=next_expected_ref,
                consumed_words=alignment_decision.consumed_words,
            )

        if alignment_decision.status == AlignmentStatus.UNCERTAIN:
            return uncertain_event(
                transcript=recognition.transcript,
                confidence=recognition.confidence,
                chunk_sequence=recognition.chunk_sequence,
                reason=alignment_decision.reason,
                next_expected_ref=self._progression.next_expected_ref,
            )

        ordered_decision = self._locate_ordered_progression(recognition.transcript)
        if (
            ordered_decision.status == LocatorStatus.LOCKED
            and ordered_decision.best is not None
        ):
            event_type = (
                SessionEventType.LOCKED
                if ayah_ref(ordered_decision.best.ayah_ref) != ayah_ref(current_expected_ref)
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

        return wrong_event(
            transcript=recognition.transcript,
            confidence=recognition.confidence,
            chunk_sequence=recognition.chunk_sequence,
            reason=alignment_decision.reason,
            expected_ref=alignment_decision.expected_ref,
            expected_word=alignment_decision.expected_word,
            recognized_word=alignment_decision.recognized_word,
            consumed_words=alignment_decision.consumed_words,
        )

    def _locate_ordered_progression(self, transcript: str) -> LocatorDecision:
        allowed_ayah_refs = self._progression.ordered_allowed_ayah_refs()
        if not allowed_ayah_refs:
            return LocatorDecision(
                status=LocatorStatus.NOT_FOUND,
                reason="no_ordered_progression",
            )

        return self._locator.locate_recitation(
            transcript,
            preferred_ref=self._progression.progress_anchor_ref,
            allowed_ayah_refs=allowed_ayah_refs,
            minimum_start_ref=self._progression.next_expected_ref,
        )

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
        self._ordered_transcript_context.clear()
        next_expected_ref = self._progression.mark_candidate_match(candidate)
        return ordered_candidate_event(
            event_type=event_type,
            transcript=transcript,
            confidence=confidence,
            chunk_sequence=chunk_sequence,
            reason=reason,
            candidate=candidate,
            next_expected_ref=next_expected_ref,
        )

    def _ordered_guidance_event(
        self,
        *,
        transcript: str,
        confidence: float,
        chunk_sequence: int | None,
        reason: str | None,
    ) -> SessionEvent:
        expected_start_ref = self._progression.expected_ordered_start_ref()
        if expected_start_ref is None:
            return uncertain_event(
                transcript=transcript,
                confidence=confidence,
                chunk_sequence=chunk_sequence,
                reason=reason,
            )

        ordered_miss_count = self._progression.record_ordered_miss()
        expected_word = self._corpus.get_word(expected_start_ref).normalized_text
        if ordered_miss_count >= 2:
            return out_of_order_event(
                transcript=transcript,
                confidence=confidence,
                chunk_sequence=chunk_sequence,
                expected_ref=expected_start_ref,
                expected_word=expected_word,
            )

        return ordered_guidance_event(
            transcript=transcript,
            confidence=confidence,
            chunk_sequence=chunk_sequence,
            expected_start_ref=expected_start_ref,
        )


def _is_waiting_for_audio_buffer(recognition: RecognitionResult) -> bool:
    return (
        recognition.transcript == ""
        and recognition.confidence == 0.0
        and not recognition.is_final
    )


@dataclass(frozen=True)
class _InitialLocationResult:
    recognition: RecognitionResult
    decision: LocatorDecision


@dataclass(frozen=True)
class _InitialTranscriptEntry:
    transcript: str
    candidate_refs: tuple[QuranRef, ...] = ()


class _InitialTranscriptContext:
    _MAX_TRANSCRIPTS = 4

    def __init__(self) -> None:
        self._entries: list[_InitialTranscriptEntry] = []

    @property
    def has_transcript(self) -> bool:
        return bool(self._entries)

    @property
    def transcripts(self) -> tuple[str, ...]:
        return tuple(entry.transcript for entry in self._entries)

    def combine_all(self, recognition: RecognitionResult) -> tuple[RecognitionResult, ...]:
        transcript = recognition.transcript.strip()
        if not transcript:
            return (recognition,)
        return tuple(
            RecognitionResult(
                transcript=_merge_transcripts(previous, transcript),
                confidence=recognition.confidence,
                chunk_sequence=recognition.chunk_sequence,
                is_final=recognition.is_final,
            )
            for previous in self.transcripts
        )

    def remember(
        self,
        transcript: str,
        *,
        candidate_refs: tuple[QuranRef, ...] = (),
    ) -> None:
        transcript = transcript.strip()
        if not transcript:
            return
        self._entries = [
            entry for entry in self._entries if entry.transcript != transcript
        ]
        self._entries.append(
            _InitialTranscriptEntry(
                transcript=transcript,
                candidate_refs=candidate_refs,
            )
        )
        self._entries = self._entries[-self._MAX_TRANSCRIPTS:]

    def supports_candidate(self, candidate: LocatorCandidate | None) -> bool:
        if candidate is None:
            return False
        candidate_ayah_ref = ayah_ref(candidate.ayah_ref)
        return any(
            any(ayah_ref(candidate_ref) == candidate_ayah_ref for candidate_ref in entry.candidate_refs)
            for entry in self._entries
        )

    def clear(self) -> None:
        self._entries = []


def _is_tolerant_decision(decision: LocatorDecision) -> bool:
    return decision.reason in {"tolerant_match", "tolerant_span_match"}


def _is_tolerant_span_decision(decision: LocatorDecision) -> bool:
    return decision.reason == "tolerant_span_match"


def _confirmation_candidate_decision(decision: LocatorDecision) -> LocatorDecision:
    return LocatorDecision(
        status=LocatorStatus.AMBIGUOUS,
        candidates=decision.candidates,
        reason="needs_confirmation",
    )


def _current_decision_supports_candidate(
    current_decision: LocatorDecision,
    candidate: LocatorCandidate | None,
) -> bool:
    if candidate is None:
        return False
    if current_decision.status == LocatorStatus.NOT_FOUND:
        return False
    if current_decision.status == LocatorStatus.LOCKED:
        return (
            current_decision.best is not None
            and ayah_ref(current_decision.best.ayah_ref) == ayah_ref(candidate.ayah_ref)
        )
    return any(
        ayah_ref(current_candidate.ayah_ref) == ayah_ref(candidate.ayah_ref)
        for current_candidate in current_decision.candidates
    )


def _merge_transcripts(previous: str, current: str) -> str:
    previous_words = previous.split()
    current_words = current.split()
    overlap = _overlap_word_count(
        normalize_arabic(previous).split(),
        normalize_arabic(current).split(),
    )
    return " ".join([*previous_words, *current_words[overlap:]]).strip()


def _overlap_word_count(previous_words: list[str], current_words: list[str]) -> int:
    max_overlap = min(len(previous_words), len(current_words))
    for overlap in range(max_overlap, 0, -1):
        if previous_words[-overlap:] == current_words[:overlap]:
            return overlap
    return 0
