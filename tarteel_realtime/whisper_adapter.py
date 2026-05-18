from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol

from tarteel_realtime.audio import pcm16le_to_float_samples
from tarteel_realtime.recognition import AudioChunk, RecognitionResult


class WhisperBackend(Protocol):
    def transcribe(self, *, samples: list[float], sample_rate_hz: int, language: str) -> dict[str, Any]:
        """Return a Whisper-like transcription payload."""


class WhisperBackendMissing(ImportError):
    pass


@dataclass(frozen=True)
class WhisperConfig:
    model_id: str
    language: str = "ar"
    device: str | int | None = None


class WhisperRecognizer:
    def __init__(self, *, backend: WhisperBackend, config: WhisperConfig) -> None:
        self._backend = backend
        self._config = config

    @classmethod
    def from_transformers(
        cls,
        config: WhisperConfig,
        *,
        pipeline_factory=None,
    ) -> WhisperRecognizer:
        if pipeline_factory is None:
            try:
                from transformers import pipeline as pipeline_factory
            except ModuleNotFoundError as exc:
                raise WhisperBackendMissing(
                    "Install transformers/torch to use WhisperRecognizer.from_transformers()."
                ) from exc

        try:
            backend = TransformersWhisperBackend(
                pipeline_factory=pipeline_factory,
                config=config,
            )
        except ModuleNotFoundError as exc:
            raise WhisperBackendMissing(
                "Install transformers/torch to use WhisperRecognizer.from_transformers()."
            ) from exc
        return cls(backend=backend, config=config)

    def recognize(self, chunk: AudioChunk) -> RecognitionResult:
        payload = self._backend.transcribe(
            samples=pcm16le_to_float_samples(chunk.pcm),
            sample_rate_hz=chunk.sample_rate_hz,
            language=self._config.language,
        )
        return RecognitionResult(
            transcript=str(payload["text"]),
            confidence=float(payload.get("confidence", 0.0)),
            chunk_sequence=chunk.sequence_number,
            is_final=bool(payload.get("is_final", False)),
        )


class TransformersWhisperBackend:
    def __init__(self, *, pipeline_factory, config: WhisperConfig) -> None:
        kwargs: dict[str, Any] = {
            "task": "automatic-speech-recognition",
            "model": config.model_id,
        }
        if config.device is not None:
            kwargs["device"] = config.device
        self._pipeline = pipeline_factory(**kwargs)

    def transcribe(self, *, samples: list[float], sample_rate_hz: int, language: str) -> dict[str, Any]:
        import numpy as np

        result = self._pipeline({
            "raw": np.array(samples, dtype=np.float32),
            "sampling_rate": sample_rate_hz,
        }, generate_kwargs={"language": language})
        return {
            "text": result.get("text", ""),
            "confidence": result.get("confidence", 0.0),
            "is_final": True,
        }
