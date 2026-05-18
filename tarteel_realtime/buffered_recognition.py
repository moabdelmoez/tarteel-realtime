from __future__ import annotations

from dataclasses import dataclass
import logging

from tarteel_realtime.recognition import AudioChunk, RecognitionResult, SpeechRecognizer


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class BufferedRecognitionConfig:
    minimum_audio_ms: int = 2_000
    flush_interval_ms: int = 1_500
    tail_audio_ms: int = 500

    def __post_init__(self) -> None:
        if self.minimum_audio_ms <= 0:
            raise ValueError("minimum_audio_ms must be positive")
        if self.flush_interval_ms <= 0:
            raise ValueError("flush_interval_ms must be positive")
        if self.tail_audio_ms < 0:
            raise ValueError("tail_audio_ms must be non-negative")


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
        self._sample_rate_hz: int | None = None
        self._bytes_since_flush = 0

    def recognize(self, chunk: AudioChunk) -> RecognitionResult:
        if chunk.pcm:
            self._append(chunk)
        if not self._ready_to_flush():
            logger.warning(
                "buffered_recognizer sequence=%s incoming_bytes=%s sample_rate_hz=%s "
                "buffered_ms=%s unflushed_ms=%s action=wait",
                chunk.sequence_number,
                len(chunk.pcm),
                chunk.sample_rate_hz,
                self._buffered_ms,
                self._unflushed_ms,
            )
            return _waiting_result(chunk.sequence_number)

        logger.warning(
            "buffered_recognizer sequence=%s incoming_bytes=%s sample_rate_hz=%s "
            "buffered_ms=%s unflushed_ms=%s action=flush",
            chunk.sequence_number,
            len(chunk.pcm),
            chunk.sample_rate_hz,
            self._buffered_ms,
            self._unflushed_ms,
        )
        result = self._recognizer.recognize(AudioChunk(
            sequence_number=chunk.sequence_number,
            pcm=bytes(self._buffer),
            sample_rate_hz=self._sample_rate_hz or chunk.sample_rate_hz,
        ))
        self._keep_tail()
        self._bytes_since_flush = 0
        return result

    def _append(self, chunk: AudioChunk) -> None:
        if self._sample_rate_hz is None:
            self._sample_rate_hz = chunk.sample_rate_hz
        elif self._sample_rate_hz != chunk.sample_rate_hz:
            self._buffer.clear()
            self._bytes_since_flush = 0
            self._sample_rate_hz = chunk.sample_rate_hz

        self._buffer.extend(chunk.pcm)
        self._bytes_since_flush += len(chunk.pcm)

    def _ready_to_flush(self) -> bool:
        if self._sample_rate_hz is None:
            return False
        return (
            self._buffered_ms >= self._config.minimum_audio_ms
            and self._unflushed_ms >= self._config.flush_interval_ms
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
            return
        del self._buffer[:-tail_bytes]


def _waiting_result(sequence_number: int) -> RecognitionResult:
    return RecognitionResult(
        transcript="",
        confidence=0.0,
        chunk_sequence=sequence_number,
        is_final=False,
    )


def _pcm_bytes_to_ms(byte_count: int, *, sample_rate_hz: int) -> int:
    bytes_per_sample = 2
    return byte_count * 1_000 // (sample_rate_hz * bytes_per_sample)


def _ms_to_pcm_bytes(duration_ms: int, *, sample_rate_hz: int) -> int:
    bytes_per_sample = 2
    return duration_ms * sample_rate_hz * bytes_per_sample // 1_000
