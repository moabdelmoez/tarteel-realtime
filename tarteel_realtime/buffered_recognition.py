from __future__ import annotations

from dataclasses import dataclass
import logging
import math
import struct
from time import monotonic

from tarteel_realtime.diagnostics import (
    BUFFER_ACTION_APPEND_WAIT_FLUSH_INTERVAL,
    BUFFER_ACTION_APPEND_WAIT_MIN_AUDIO,
    BUFFER_ACTION_DROP_VAD_OR_RMS,
    BUFFER_ACTION_DROP_QUIET_BUFFER,
    BUFFER_ACTION_FLUSH_ASR,
    BUFFER_ACTION_RESET_SAMPLE_RATE,
    diagnostic_asr_context,
)
from tarteel_realtime.recognition import AudioChunk, RecognitionResult, SpeechRecognizer


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class BufferedRecognitionConfig:
    minimum_audio_ms: int = 4_200
    flush_interval_ms: int = 4_200
    tail_audio_ms: int = 0
    minimum_speech_rms: int = 400
    minimum_frame_rms: int = 150

    def __post_init__(self) -> None:
        if self.minimum_audio_ms <= 0:
            raise ValueError("minimum_audio_ms must be positive")
        if self.flush_interval_ms <= 0:
            raise ValueError("flush_interval_ms must be positive")
        if self.tail_audio_ms < 0:
            raise ValueError("tail_audio_ms must be non-negative")
        if self.minimum_speech_rms < 0:
            raise ValueError("minimum_speech_rms must be non-negative")
        if self.minimum_frame_rms < 0:
            raise ValueError("minimum_frame_rms must be non-negative")


@dataclass(frozen=True)
class BufferedAudioSegment:
    sequence_number: int
    start_byte: int
    end_byte: int

    def to_payload(self) -> dict[str, int]:
        return {
            "sequence_number": self.sequence_number,
            "start_byte": self.start_byte,
            "end_byte": self.end_byte,
        }


DEFAULT_BUFFERING_PROFILE = "stable"
LOW_LATENCY_BUFFERING_PROFILE = "low-latency"

_BUFFERING_PROFILE_CONFIGS = {
    DEFAULT_BUFFERING_PROFILE: BufferedRecognitionConfig(),
    LOW_LATENCY_BUFFERING_PROFILE: BufferedRecognitionConfig(
        minimum_audio_ms=2_000,
        flush_interval_ms=1_000,
        tail_audio_ms=500,
        minimum_speech_rms=400,
        minimum_frame_rms=150,
    ),
}


def normalize_buffering_profile_name(value: str) -> str:
    profile = value.strip().lower().replace("_", "-")
    if profile not in _BUFFERING_PROFILE_CONFIGS:
        allowed = ", ".join(sorted(_BUFFERING_PROFILE_CONFIGS))
        raise ValueError(f"unknown ASR buffering profile {value!r}; expected one of: {allowed}")
    return profile


def buffering_profile_config(value: str) -> BufferedRecognitionConfig:
    return _BUFFERING_PROFILE_CONFIGS[normalize_buffering_profile_name(value)]


class BufferedRecognizer:
    def __init__(
        self,
        recognizer: SpeechRecognizer,
        *,
        config: BufferedRecognitionConfig = BufferedRecognitionConfig(),
    ) -> None:
        self._recognizer = recognizer
        self._config = config
        self._buffer = bytearray()
        self._segments: list[BufferedAudioSegment] = []
        self._sample_rate_hz: int | None = None
        self._bytes_since_flush = 0

    def recognize(
        self,
        chunk: AudioChunk,
        *,
        diagnostic_collector=None,
    ) -> RecognitionResult:
        incoming_rms = _pcm_rms(chunk.pcm) if chunk.pcm else 0
        buffered_ms_before = self._buffered_ms
        appended_segments: list[BufferedAudioSegment] = []
        sample_rate_reset = False
        if chunk.pcm:
            if self._should_buffer_chunk(chunk, incoming_rms=incoming_rms):
                sample_rate_reset = self._reset_sample_rate_if_needed(chunk)
                appended_segments = self._append(chunk)
            else:
                _record_buffer_action(
                    diagnostic_collector,
                    chunk=chunk,
                    action=BUFFER_ACTION_DROP_VAD_OR_RMS,
                    incoming_rms=incoming_rms,
                    buffered_ms_before=buffered_ms_before,
                    buffered_ms_after=self._buffered_ms,
                    unflushed_ms_after=self._unflushed_ms,
                    appended=False,
                    appended_segments=[],
                )
                logger.warning(
                    "buffered_recognizer sequence=%s incoming_bytes=%s sample_rate_hz=%s "
                    "buffered_ms=%s unflushed_ms=%s incoming_rms=%s action=wait_vad",
                    chunk.sequence_number,
                    len(chunk.pcm),
                    chunk.sample_rate_hz,
                    self._buffered_ms,
                    self._unflushed_ms,
                    incoming_rms,
                )
                return _waiting_result(chunk.sequence_number)
        if not self._ready_to_flush(chunk):
            if appended_segments:
                action = _wait_action_for_buffer_state(
                    sample_rate_reset=sample_rate_reset,
                    buffered_ms=self._buffered_ms,
                    minimum_audio_ms=self._config.minimum_audio_ms,
                )
                _record_buffer_action(
                    diagnostic_collector,
                    chunk=chunk,
                    action=action,
                    incoming_rms=incoming_rms,
                    buffered_ms_before=buffered_ms_before,
                    buffered_ms_after=self._buffered_ms,
                    unflushed_ms_after=self._unflushed_ms,
                    appended=True,
                    appended_segments=appended_segments,
                )
            logger.warning(
                "buffered_recognizer sequence=%s incoming_bytes=%s sample_rate_hz=%s "
                "buffered_ms=%s unflushed_ms=%s incoming_rms=%s action=wait",
                chunk.sequence_number,
                len(chunk.pcm),
                chunk.sample_rate_hz,
                self._buffered_ms,
                self._unflushed_ms,
                incoming_rms,
            )
            return _waiting_result(chunk.sequence_number)

        buffered_rms = _pcm_rms(bytes(self._buffer))
        if buffered_rms < self._config.minimum_speech_rms:
            _record_buffer_action(
                diagnostic_collector,
                chunk=chunk,
                action=BUFFER_ACTION_DROP_QUIET_BUFFER,
                incoming_rms=incoming_rms,
                buffered_ms_before=buffered_ms_before,
                buffered_ms_after=self._buffered_ms,
                unflushed_ms_after=self._unflushed_ms,
                appended=bool(appended_segments),
                appended_segments=appended_segments,
            )
            logger.warning(
                "buffered_recognizer sequence=%s incoming_bytes=%s sample_rate_hz=%s "
                "buffered_ms=%s unflushed_ms=%s buffered_rms=%s action=wait_quiet",
                chunk.sequence_number,
                len(chunk.pcm),
                chunk.sample_rate_hz,
                self._buffered_ms,
                self._unflushed_ms,
                buffered_rms,
            )
            self._buffer.clear()
            self._segments.clear()
            self._bytes_since_flush = 0
            return _waiting_result(chunk.sequence_number)

        logger.warning(
            "buffered_recognizer sequence=%s incoming_bytes=%s sample_rate_hz=%s "
            "buffered_ms=%s unflushed_ms=%s buffered_rms=%s action=flush",
            chunk.sequence_number,
            len(chunk.pcm),
            chunk.sample_rate_hz,
            self._buffered_ms,
            self._unflushed_ms,
            buffered_rms,
        )

        _record_buffer_action(
            diagnostic_collector,
            chunk=chunk,
            action=(
                BUFFER_ACTION_RESET_SAMPLE_RATE
                if sample_rate_reset
                else BUFFER_ACTION_FLUSH_ASR
            ),
            incoming_rms=incoming_rms,
            buffered_ms_before=buffered_ms_before,
            buffered_ms_after=self._buffered_ms,
            unflushed_ms_after=self._unflushed_ms,
            appended=bool(appended_segments),
            appended_segments=appended_segments,
        )
        window_id = None
        if diagnostic_collector is not None:
            window_id = diagnostic_collector.begin_asr_window(
                triggering_sequence_number=chunk.sequence_number,
                segments=[segment.to_payload() for segment in self._segments],
                audio_ms=self._buffered_ms,
                pcm_bytes=len(self._buffer),
                buffered_rms=buffered_rms,
                tail_audio_ms=self._config.tail_audio_ms,
            )

        start = monotonic()
        asr_chunk = AudioChunk(
            sequence_number=chunk.sequence_number,
            pcm=bytes(self._buffer),
            sample_rate_hz=self._sample_rate_hz or chunk.sample_rate_hz,
        )
        if diagnostic_collector is not None and window_id is not None:
            with diagnostic_asr_context(diagnostic_collector, window_id):
                result = self._recognizer.recognize(asr_chunk)
        else:
            result = self._recognizer.recognize(asr_chunk)
        total_ms = int(round((monotonic() - start) * 1_000))
        if diagnostic_collector is not None and window_id is not None:
            diagnostic_collector.finish_asr_window(
                window_id,
                transcript=result.transcript,
                confidence=result.confidence,
                is_final=result.is_final,
                total_duration_ms=total_ms,
            )
        self._keep_tail()
        self._bytes_since_flush = 0
        return result

    def _should_buffer_chunk(self, chunk: AudioChunk, *, incoming_rms: int) -> bool:
        if self._config.minimum_frame_rms == 0:
            return True
        if chunk.voice_activity is not None:
            if chunk.voice_activity.is_speech_active is True:
                return True
            if chunk.voice_activity.event == "speech_start":
                return True
        return incoming_rms >= self._config.minimum_frame_rms

    def _append(self, chunk: AudioChunk) -> list[BufferedAudioSegment]:
        if self._sample_rate_hz is None:
            self._sample_rate_hz = chunk.sample_rate_hz

        self._buffer.extend(chunk.pcm)
        segment = BufferedAudioSegment(
            sequence_number=chunk.sequence_number,
            start_byte=0,
            end_byte=len(chunk.pcm),
        )
        self._segments.append(segment)
        self._bytes_since_flush += len(chunk.pcm)
        return [segment]

    def _reset_sample_rate_if_needed(self, chunk: AudioChunk) -> bool:
        if self._sample_rate_hz is None:
            return False
        if self._sample_rate_hz == chunk.sample_rate_hz:
            return False
        self._buffer.clear()
        self._segments.clear()
        self._bytes_since_flush = 0
        self._sample_rate_hz = chunk.sample_rate_hz
        return True

    def _ready_to_flush(self, chunk: AudioChunk) -> bool:
        if self._sample_rate_hz is None:
            return False
        if self._buffered_ms < self._config.minimum_audio_ms:
            return False
        return (
            self._unflushed_ms >= self._config.flush_interval_ms
            or _is_vad_speech_end(chunk)
        )

    @property
    def _buffered_ms(self) -> int:
        return _pcm_bytes_to_ms(len(self._buffer), sample_rate_hz=self._sample_rate_hz or 1)

    @property
    def _unflushed_ms(self) -> int:
        return _pcm_bytes_to_ms(self._bytes_since_flush, sample_rate_hz=self._sample_rate_hz or 1)

    def _keep_tail(self) -> None:
        tail_bytes = _ms_to_pcm_bytes(
            self._config.tail_audio_ms,
            sample_rate_hz=self._sample_rate_hz or 1,
        )
        if tail_bytes == 0:
            self._buffer.clear()
            self._segments.clear()
            return
        del self._buffer[:-tail_bytes]
        self._trim_segments_to_tail(tail_bytes)

    def _trim_segments_to_tail(self, tail_bytes: int) -> None:
        if tail_bytes == 0:
            self._segments.clear()
            return
        remaining = tail_bytes
        kept: list[BufferedAudioSegment] = []
        for segment in reversed(self._segments):
            segment_length = segment.end_byte - segment.start_byte
            if remaining <= 0:
                break
            if segment_length <= remaining:
                kept.append(segment)
                remaining -= segment_length
                continue
            kept.append(BufferedAudioSegment(
                sequence_number=segment.sequence_number,
                start_byte=segment.end_byte - remaining,
                end_byte=segment.end_byte,
            ))
            remaining = 0
        self._segments = list(reversed(kept))


def _waiting_result(sequence_number: int) -> RecognitionResult:
    return RecognitionResult(
        transcript="",
        confidence=0.0,
        chunk_sequence=sequence_number,
        is_final=False,
    )


def _record_buffer_action(
    diagnostic_collector,
    *,
    chunk: AudioChunk,
    action: str,
    incoming_rms: int,
    buffered_ms_before: int,
    buffered_ms_after: int,
    unflushed_ms_after: int,
    appended: bool,
    appended_segments: list[BufferedAudioSegment],
) -> None:
    if diagnostic_collector is None:
        return
    diagnostic_collector.record_buffer_action(
        sequence_number=chunk.sequence_number,
        action=action,
        incoming_rms=incoming_rms,
        buffered_ms_before=buffered_ms_before,
        buffered_ms_after=buffered_ms_after,
        unflushed_ms_after=unflushed_ms_after,
        appended=appended,
        appended_segments=[segment.to_payload() for segment in appended_segments],
    )


def _wait_action_for_buffer_state(
    *,
    sample_rate_reset: bool,
    buffered_ms: int,
    minimum_audio_ms: int,
) -> str:
    if sample_rate_reset:
        return BUFFER_ACTION_RESET_SAMPLE_RATE
    if buffered_ms < minimum_audio_ms:
        return BUFFER_ACTION_APPEND_WAIT_MIN_AUDIO
    return BUFFER_ACTION_APPEND_WAIT_FLUSH_INTERVAL


def _pcm_bytes_to_ms(byte_count: int, *, sample_rate_hz: int) -> int:
    bytes_per_sample = 2
    return byte_count * 1_000 // (sample_rate_hz * bytes_per_sample)


def _ms_to_pcm_bytes(duration_ms: int, *, sample_rate_hz: int) -> int:
    bytes_per_sample = 2
    return duration_ms * sample_rate_hz * bytes_per_sample // 1_000


def _pcm_rms(pcm: bytes) -> int:
    sample_count = len(pcm) // 2
    if sample_count == 0:
        return 0

    square_sum = 0
    for (sample,) in struct.iter_unpack("<h", pcm[: sample_count * 2]):
        square_sum += sample * sample
    return int(round(math.sqrt(square_sum / sample_count)))


def _is_vad_speech_end(chunk: AudioChunk) -> bool:
    return (
        chunk.voice_activity is not None
        and chunk.voice_activity.event == "speech_end"
    )
