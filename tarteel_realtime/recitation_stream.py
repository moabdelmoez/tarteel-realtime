from __future__ import annotations

import logging
import math
import struct
from dataclasses import dataclass
from typing import Any

from tarteel_realtime.diagnostics import DiagnosticTraceCollector
from tarteel_realtime.event_payloads import session_event_to_payload
from tarteel_realtime.quran import QuranCorpus, QuranRef
from tarteel_realtime.recitation_scope import RecitationScope
from tarteel_realtime.recognition import AudioChunk, SpeechRecognizer, VoiceActivity
from tarteel_realtime.session import RecitationSession
from tarteel_realtime.session_events import SessionEvent, uncertain_event


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class RecitationChunkDiagnostics:
    sequence_number: int
    pcm_bytes: int
    sample_rate_hz: int
    approx_audio_ms: int
    pcm_rms: int
    pcm_peak: int
    event_type: str
    reason: str | None
    ayah_ref: str | None
    transcript_chars: int
    transcript_text: str


@dataclass(frozen=True)
class RecitationStreamResult:
    event: SessionEvent
    payload: dict[str, Any]
    diagnostics: RecitationChunkDiagnostics
    diagnostic_envelope: dict[str, Any] | None = None


class RecitationStream:
    def __init__(
        self,
        *,
        corpus: QuranCorpus,
        recognizer: SpeechRecognizer,
        minimum_lock_words: int = 3,
        log_transcripts: bool = False,
        recitation_scope: RecitationScope | None = None,
        diagnostics_enabled: bool = False,
    ) -> None:
        self._corpus = corpus
        self._session = RecitationSession(
            corpus=corpus,
            recognizer=recognizer,
            minimum_lock_words=minimum_lock_words,
            recitation_scope=recitation_scope,
        )
        self._log_transcripts = log_transcripts
        self._diagnostic_collector = (
            DiagnosticTraceCollector() if diagnostics_enabled else None
        )

    def process_chunk(self, chunk: AudioChunk) -> RecitationStreamResult:
        diagnostic_collector = self._diagnostic_collector
        if diagnostic_collector is not None:
            diagnostic_collector.begin_chunk(
                sequence_number=chunk.sequence_number,
                pcm_bytes=len(chunk.pcm),
                sample_rate_hz=chunk.sample_rate_hz,
                voice_activity=voice_activity_payload(chunk.voice_activity),
            )

        try:
            event = self._session.handle_chunk(chunk)
        except Exception:
            logger.exception(
                "recitation_stream asr_error sequence=%s sample_rate_hz=%s pcm_bytes=%s",
                chunk.sequence_number,
                chunk.sample_rate_hz,
                len(chunk.pcm),
            )
            event = uncertain_event(
                transcript="",
                confidence=0.0,
                chunk_sequence=chunk.sequence_number,
                reason="asr_error",
            )

        payload = session_event_to_payload(
            event,
            corpus=self._corpus,
        )
        diagnostic_envelope = (
            None
            if diagnostic_collector is None
            else diagnostic_collector.envelope(payload)
        )
        return RecitationStreamResult(
            event=event,
            payload=payload,
            diagnostics=recitation_chunk_diagnostics(
                chunk,
                event,
                log_transcripts=self._log_transcripts,
            ),
            diagnostic_envelope=diagnostic_envelope,
        )


def recitation_chunk_diagnostics(
    chunk: AudioChunk,
    event: SessionEvent,
    *,
    log_transcripts: bool = False,
) -> RecitationChunkDiagnostics:
    rms, peak = pcm_level_stats(chunk.pcm)
    return RecitationChunkDiagnostics(
        sequence_number=chunk.sequence_number,
        pcm_bytes=len(chunk.pcm),
        sample_rate_hz=chunk.sample_rate_hz,
        approx_audio_ms=pcm_bytes_to_ms(
            len(chunk.pcm),
            sample_rate_hz=chunk.sample_rate_hz,
        ),
        pcm_rms=rms,
        pcm_peak=peak,
        event_type=event.type.value,
        reason=event.reason,
        ayah_ref=ref_to_string(event.ayah_ref),
        transcript_chars=len(event.transcript),
        transcript_text=event.transcript if log_transcripts else "<redacted>",
    )


def log_recitation_diagnostics(
    diagnostics: RecitationChunkDiagnostics,
    *,
    target_logger: logging.Logger,
) -> None:
    target_logger.warning(
        "recitation_chunk sequence=%s pcm_bytes=%s sample_rate_hz=%s "
        "approx_audio_ms=%s pcm_rms=%s pcm_peak=%s event_type=%s "
        "reason=%s ayah_ref=%s transcript_chars=%s transcript_text=%s",
        diagnostics.sequence_number,
        diagnostics.pcm_bytes,
        diagnostics.sample_rate_hz,
        diagnostics.approx_audio_ms,
        diagnostics.pcm_rms,
        diagnostics.pcm_peak,
        diagnostics.event_type,
        diagnostics.reason,
        diagnostics.ayah_ref,
        diagnostics.transcript_chars,
        diagnostics.transcript_text,
    )


def ref_to_string(ref: QuranRef | None) -> str | None:
    if ref is None:
        return None
    return str(ref)


def voice_activity_payload(
    voice_activity: VoiceActivity | None,
) -> dict[str, Any] | None:
    if voice_activity is None:
        return None
    return {
        "probability": voice_activity.probability,
        "is_speech_active": voice_activity.is_speech_active,
        "event": voice_activity.event,
    }


def pcm_bytes_to_ms(byte_count: int, *, sample_rate_hz: int) -> int:
    bytes_per_sample = 2
    return byte_count * 1_000 // (sample_rate_hz * bytes_per_sample)


def pcm_level_stats(pcm: bytes) -> tuple[int, int]:
    sample_count = len(pcm) // 2
    if sample_count == 0:
        return 0, 0

    peak = 0
    square_sum = 0
    pcm_samples = pcm[: sample_count * 2]
    for (sample,) in struct.iter_unpack("<h", pcm_samples):
        magnitude = abs(sample)
        peak = max(peak, magnitude)
        square_sum += sample * sample

    rms = int(round(math.sqrt(square_sum / sample_count)))
    return rms, peak
