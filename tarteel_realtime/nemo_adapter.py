from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct
from tempfile import NamedTemporaryFile
from time import monotonic
from typing import Any, Protocol
import wave

from tarteel_realtime.audio import pcm16le_to_float_samples
from tarteel_realtime.diagnostics import current_diagnostic_context
from tarteel_realtime.recognition import AudioChunk, RecognitionResult


class NemoBackend(Protocol):
    def transcribe(self, *, samples: list[float], sample_rate_hz: int) -> dict[str, Any]:
        """Return a transcription payload for one buffered audio window."""


class NemoBackendMissing(ImportError):
    pass


@dataclass(frozen=True)
class NemoConfig:
    model_id: str
    model_file: str | None = None
    cache_dir: str | None = None
    device: str | int | None = None
    batch_size: int = 1


class NemoRecognizer:
    def __init__(self, *, backend: NemoBackend, config: NemoConfig) -> None:
        self._backend = backend
        self._config = config

    @classmethod
    def from_pretrained(
        cls,
        config: NemoConfig,
        *,
        model_factory=None,
        restore_factory=None,
        snapshot_downloader=None,
    ) -> NemoRecognizer:
        backend = NemoTranscribeBackend.from_pretrained(
            config,
            model_factory=model_factory,
            restore_factory=restore_factory,
            snapshot_downloader=snapshot_downloader,
        )
        return cls(backend=backend, config=config)

    def recognize(self, chunk: AudioChunk) -> RecognitionResult:
        samples = pcm16le_to_float_samples(chunk.pcm)
        start = monotonic()
        payload = self._backend.transcribe(
            samples=samples,
            sample_rate_hz=chunk.sample_rate_hz,
        )
        duration_ms = int(round((monotonic() - start) * 1_000))
        context = current_diagnostic_context()
        if context is not None:
            context.collector.record_asr_inference(
                context.window_id,
                duration_ms=duration_ms,
            )
        return RecognitionResult(
            transcript=str(payload["text"]),
            confidence=float(payload.get("confidence", 0.0)),
            chunk_sequence=chunk.sequence_number,
            is_final=bool(payload.get("is_final", True)),
        )


class NemoTranscribeBackend:
    def __init__(self, *, model: Any, config: NemoConfig) -> None:
        self.model = model
        self._config = config
        if config.device is not None and hasattr(self.model, "to"):
            self.model = self.model.to(config.device)
        if hasattr(self.model, "eval"):
            self.model.eval()

    @classmethod
    def from_pretrained(
        cls,
        config: NemoConfig,
        *,
        model_factory=None,
        restore_factory=None,
        snapshot_downloader=None,
    ) -> NemoTranscribeBackend:
        needs_nemo_import = (
            (not config.model_file and model_factory is None)
            or (config.model_file and restore_factory is None)
        )
        if needs_nemo_import:
            try:
                import nemo.collections.asr as nemo_asr
            except ModuleNotFoundError as exc:
                raise NemoBackendMissing(
                    "Install nemo_toolkit[asr] to use NemoRecognizer.from_pretrained()."
                ) from exc
            if model_factory is None:
                model_factory = nemo_asr.models.ASRModel.from_pretrained
            if restore_factory is None:
                restore_factory = nemo_asr.models.ASRModel.restore_from

        if config.model_file:
            if snapshot_downloader is None:
                try:
                    from huggingface_hub import snapshot_download
                except ModuleNotFoundError as exc:
                    raise NemoBackendMissing(
                        "Install huggingface_hub to restore a nested NeMo model file from Hugging Face."
                    ) from exc
                snapshot_downloader = snapshot_download

            try:
                snapshot_path = Path(snapshot_downloader(
                    repo_id=config.model_id,
                    cache_dir=config.cache_dir,
                ))
                model_path = snapshot_path / config.model_file
                model = restore_factory(restore_path=str(model_path))
            except ModuleNotFoundError as exc:
                raise NemoBackendMissing(
                    "Install nemo_toolkit[asr] to use NemoRecognizer.from_pretrained()."
                ) from exc
            return cls(model=model, config=config)

        try:
            model = model_factory(config.model_id)
        except ModuleNotFoundError as exc:
            raise NemoBackendMissing(
                "Install nemo_toolkit[asr] to use NemoRecognizer.from_pretrained()."
            ) from exc
        return cls(model=model, config=config)

    def transcribe(self, *, samples: list[float], sample_rate_hz: int) -> dict[str, Any]:
        with NamedTemporaryFile(suffix=".wav") as audio_file:
            _write_pcm16_wav(audio_file.name, samples=samples, sample_rate_hz=sample_rate_hz)
            result = self.model.transcribe(
                [audio_file.name],
                batch_size=self._config.batch_size,
            )
        return _payload_from_transcription_result(result)


def _write_pcm16_wav(path: str, *, samples: list[float], sample_rate_hz: int) -> None:
    pcm = _float_samples_to_pcm16le(samples)
    with wave.open(path, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate_hz)
        wav_file.writeframes(pcm)


def _float_samples_to_pcm16le(samples: list[float]) -> bytes:
    if not samples:
        return b""
    clamped = [
        max(-1.0, min(1.0, sample))
        for sample in samples
    ]
    integers = [
        int(round(sample * 32767.0))
        for sample in clamped
    ]
    return struct.pack(f"<{len(integers)}h", *integers)


def _payload_from_transcription_result(result: Any) -> dict[str, Any]:
    item = _first_transcription_item(result)
    if isinstance(item, dict):
        return {
            "text": item.get("text", ""),
            "confidence": item.get("confidence", 0.0),
            "is_final": item.get("is_final", True),
        }
    return {
        "text": getattr(item, "text", item),
        "confidence": getattr(item, "confidence", 0.0),
        "is_final": getattr(item, "is_final", True),
    }


def _first_transcription_item(result: Any) -> Any:
    if isinstance(result, (list, tuple)):
        if not result:
            return ""
        return result[0]
    return result
