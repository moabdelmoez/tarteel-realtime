from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Protocol

from tarteel_realtime.quran import normalize_arabic


@dataclass(frozen=True)
class AudioChunk:
    sequence_number: int
    pcm: bytes
    sample_rate_hz: int

    def __post_init__(self) -> None:
        if self.sequence_number < 0:
            raise ValueError("sequence_number must be non-negative")
        if self.sample_rate_hz <= 0:
            raise ValueError("sample_rate_hz must be positive")


@dataclass(frozen=True)
class RecognitionResult:
    transcript: str
    confidence: float
    chunk_sequence: int | None = None
    is_final: bool = False

    @property
    def normalized_transcript(self) -> str:
        return normalize_arabic(self.transcript)


class SpeechRecognizer(Protocol):
    def recognize(self, chunk: AudioChunk) -> RecognitionResult:
        """Recognize one rolling audio chunk."""


class RecognizerScriptExhausted(RuntimeError):
    pass


class FakeRecognizer:
    def __init__(self, script: list[str | RecognitionResult]) -> None:
        self._script = tuple(script)
        self._index = 0

    def recognize(self, chunk: AudioChunk) -> RecognitionResult:
        if self._index >= len(self._script):
            raise RecognizerScriptExhausted("fake recognizer script is exhausted")

        next_item = self._script[self._index]
        self._index += 1

        if isinstance(next_item, RecognitionResult):
            return replace(next_item, chunk_sequence=chunk.sequence_number)

        return RecognitionResult(
            transcript=next_item,
            confidence=1.0,
            chunk_sequence=chunk.sequence_number,
        )
