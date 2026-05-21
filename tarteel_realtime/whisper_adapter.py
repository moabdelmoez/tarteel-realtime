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
    backend: str = "transformers"
    compute_type: str | None = None


class WhisperRecognizer:
    def __init__(self, *, backend: WhisperBackend, config: WhisperConfig) -> None:
        self._backend = backend
        self._config = config

    @classmethod
    def from_config(cls, config: WhisperConfig) -> WhisperRecognizer:
        backend = config.backend.strip().lower().replace("_", "-")
        if backend == "transformers":
            return cls.from_transformers(config)
        if backend == "faster-whisper":
            return cls.from_faster_whisper(config)
        raise ValueError(f"unsupported Whisper backend: {config.backend}")

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

    @classmethod
    def from_faster_whisper(
        cls,
        config: WhisperConfig,
        *,
        model_factory=None,
    ) -> WhisperRecognizer:
        if model_factory is None:
            try:
                from faster_whisper import WhisperModel as model_factory
            except ModuleNotFoundError as exc:
                raise WhisperBackendMissing(
                    "Install faster-whisper to use WhisperRecognizer.from_faster_whisper()."
                ) from exc

        backend = FasterWhisperBackend(
            model_factory=model_factory,
            config=config,
        )
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

        def inputs() -> dict[str, Any]:
            return {
                "raw": np.array(samples, dtype=np.float32),
                "sampling_rate": sample_rate_hz,
            }

        try:
            result = self._pipeline(inputs(), generate_kwargs={"language": language})
        except ValueError as exc:
            if not _is_outdated_generation_config_error(exc):
                raise
            result = self._pipeline(inputs(), generate_kwargs={})
        return {
            "text": result.get("text", ""),
            "confidence": result.get("confidence", 0.0),
            "is_final": True,
        }


class FasterWhisperBackend:
    _WHISPER_SAMPLE_RATE_HZ = 16_000

    def __init__(self, *, model_factory, config: WhisperConfig) -> None:
        self._model = model_factory(
            config.model_id,
            **_faster_whisper_model_kwargs(config),
        )

    def transcribe(self, *, samples: list[float], sample_rate_hz: int, language: str) -> dict[str, Any]:
        import numpy as np

        whisper_samples = _resample_to_whisper_rate(
            samples,
            sample_rate_hz=sample_rate_hz,
        )
        segments, info = self._model.transcribe(
            np.array(whisper_samples, dtype=np.float32),
            language=language,
            beam_size=5,
            vad_filter=False,
            condition_on_previous_text=False,
        )
        text = " ".join(
            segment_text
            for segment_text in (
                str(segment.text).strip()
                for segment in segments
            )
            if segment_text
        )
        return {
            "text": text,
            "confidence": float(getattr(info, "language_probability", 0.0) or 0.0),
            "is_final": True,
        }


def _is_outdated_generation_config_error(exc: ValueError) -> bool:
    message = str(exc)
    return (
        "generation config is outdated" in message
        and "language" in message
    )


def _faster_whisper_model_kwargs(config: WhisperConfig) -> dict[str, Any]:
    kwargs: dict[str, Any] = {}
    if config.device is not None:
        device, device_index = _faster_whisper_device(config.device)
        kwargs["device"] = device
        if device_index is not None:
            kwargs["device_index"] = device_index
    if config.compute_type:
        kwargs["compute_type"] = config.compute_type
    return kwargs


def _faster_whisper_device(device: str | int) -> tuple[str, int | None]:
    if isinstance(device, int):
        return "cuda", device

    normalized = device.strip()
    if ":" not in normalized:
        return normalized, None

    device_name, index_text = normalized.split(":", maxsplit=1)
    try:
        return device_name, int(index_text)
    except ValueError:
        return normalized, None


def _resample_to_whisper_rate(
    samples: list[float],
    *,
    sample_rate_hz: int,
) -> list[float]:
    whisper_rate = FasterWhisperBackend._WHISPER_SAMPLE_RATE_HZ
    if sample_rate_hz == whisper_rate or not samples:
        return samples
    if sample_rate_hz <= 0:
        raise ValueError("sample_rate_hz must be positive")

    output_length = max(1, round(len(samples) * whisper_rate / sample_rate_hz))
    if output_length == 1:
        return [samples[0]]

    step = sample_rate_hz / whisper_rate
    last_index = len(samples) - 1
    resampled: list[float] = []
    for output_index in range(output_length):
        position = output_index * step
        left_index = min(int(position), last_index)
        right_index = min(left_index + 1, last_index)
        fraction = position - left_index
        left = samples[left_index]
        right = samples[right_index]
        resampled.append(left + (right - left) * fraction)
    return resampled
