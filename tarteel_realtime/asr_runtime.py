from __future__ import annotations

import os
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path
from threading import Lock
from time import monotonic

from tarteel_realtime.buffered_recognition import (
    DEFAULT_BUFFERING_PROFILE,
    BufferedRecognitionConfig,
    BufferedRecognizer,
    buffering_profile_config,
    normalize_buffering_profile_name,
)
from tarteel_realtime.diagnostics import current_diagnostic_context
from tarteel_realtime.quran_data import DEFAULT_TANZIL_PATH
from tarteel_realtime.recognition import AudioChunk, RecognitionResult, SpeechRecognizer
from tarteel_realtime.whisper_adapter import WhisperConfig, WhisperRecognizer


DEFAULT_QURAN_WHISPER_MODEL_ID = "basharalrfooh/whisper-small-quran"
DEFAULT_HF_CACHE_ROOT = Path("/runpod-volume/huggingface-cache/hub")


@dataclass(frozen=True)
class AsrRuntimeSettings:
    tanzil_path: Path = DEFAULT_TANZIL_PATH
    minimum_lock_words: int = 3
    model_id: str = DEFAULT_QURAN_WHISPER_MODEL_ID
    whisper_backend: str = "transformers"
    language: str = "ar"
    device: str | int | None = None
    faster_whisper_compute_type: str | None = None
    buffering_profile: str = DEFAULT_BUFFERING_PROFILE
    minimum_audio_ms: int = 4_200
    flush_interval_ms: int = 4_200
    tail_audio_ms: int = 0
    minimum_speech_rms: int = 400
    minimum_frame_rms: int = 150
    log_transcripts: bool = False
    websocket_bearer_token: str | None = None


class LazyRecognizer:
    def __init__(self, recognizer_factory: Callable[[], SpeechRecognizer]) -> None:
        self._recognizer_factory = recognizer_factory
        self._recognizer: SpeechRecognizer | None = None
        self._lock = Lock()

    def recognize(self, chunk: AudioChunk) -> RecognitionResult:
        if self._recognizer is None:
            with self._lock:
                if self._recognizer is None:
                    start = monotonic()
                    self._recognizer = self._recognizer_factory()
                    duration_ms = int(round((monotonic() - start) * 1_000))
                    context = current_diagnostic_context()
                    if context is not None:
                        context.collector.record_recognizer_init(
                            context.window_id,
                            duration_ms=duration_ms,
                        )
        return self._recognizer.recognize(chunk)


def settings_from_env(env: Mapping[str, str] | None = None) -> AsrRuntimeSettings:
    values = os.environ if env is None else env
    buffering_profile = normalize_buffering_profile_name(
        values.get("TARTEEL_ASR_BUFFERING_PROFILE") or DEFAULT_BUFFERING_PROFILE
    )
    profile_config = buffering_profile_config(buffering_profile)
    return AsrRuntimeSettings(
        tanzil_path=Path(values.get("TARTEEL_TANZIL_PATH", str(DEFAULT_TANZIL_PATH))),
        minimum_lock_words=int(values.get("TARTEEL_MINIMUM_LOCK_WORDS", "3")),
        model_id=resolve_cached_huggingface_model_id(
            values.get("TARTEEL_WHISPER_MODEL_ID", DEFAULT_QURAN_WHISPER_MODEL_ID),
            cache_root=Path(values.get("TARTEEL_HF_CACHE_ROOT", str(DEFAULT_HF_CACHE_ROOT))),
        ),
        whisper_backend=_whisper_backend(values.get("TARTEEL_WHISPER_BACKEND", "transformers")),
        language=values.get("TARTEEL_WHISPER_LANGUAGE", "ar"),
        device=_optional_env(values, "TARTEEL_WHISPER_DEVICE"),
        faster_whisper_compute_type=_optional_env(values, "TARTEEL_FASTER_WHISPER_COMPUTE_TYPE"),
        buffering_profile=buffering_profile,
        minimum_audio_ms=int(values.get("TARTEEL_ASR_MIN_AUDIO_MS", str(profile_config.minimum_audio_ms))),
        flush_interval_ms=int(values.get("TARTEEL_ASR_FLUSH_MS", str(profile_config.flush_interval_ms))),
        tail_audio_ms=int(values.get("TARTEEL_ASR_TAIL_MS", str(profile_config.tail_audio_ms))),
        minimum_speech_rms=int(values.get("TARTEEL_ASR_MIN_SPEECH_RMS", str(profile_config.minimum_speech_rms))),
        minimum_frame_rms=int(values.get("TARTEEL_ASR_MIN_FRAME_RMS", str(profile_config.minimum_frame_rms))),
        log_transcripts=_env_bool(values, "TARTEEL_LOG_TRANSCRIPTS"),
        websocket_bearer_token=_optional_env(values, "TARTEEL_WS_BEARER_TOKEN"),
    )


def create_lazy_whisper_recognizer_factory(
    settings: AsrRuntimeSettings,
    *,
    recognizer_builder: Callable[[WhisperConfig], SpeechRecognizer] | None = None,
) -> Callable[[], SpeechRecognizer]:
    builder = recognizer_builder or WhisperRecognizer.from_config
    config = WhisperConfig(
        model_id=settings.model_id,
        language=settings.language,
        device=settings.device,
        backend=settings.whisper_backend,
        compute_type=settings.faster_whisper_compute_type,
    )

    shared_recognizer = LazyRecognizer(lambda: builder(config))

    def create_recognizer() -> SpeechRecognizer:
        return shared_recognizer

    return create_recognizer


def create_buffered_whisper_recognizer_factory(
    settings: AsrRuntimeSettings,
    *,
    recognizer_builder: Callable[[WhisperConfig], SpeechRecognizer] | None = None,
) -> Callable[[], SpeechRecognizer]:
    lazy_factory = create_lazy_whisper_recognizer_factory(
        settings,
        recognizer_builder=recognizer_builder,
    )
    buffer_config = BufferedRecognitionConfig(
        minimum_audio_ms=settings.minimum_audio_ms,
        flush_interval_ms=settings.flush_interval_ms,
        tail_audio_ms=settings.tail_audio_ms,
        minimum_speech_rms=settings.minimum_speech_rms,
        minimum_frame_rms=settings.minimum_frame_rms,
    )

    def create_recognizer() -> SpeechRecognizer:
        return BufferedRecognizer(lazy_factory(), config=buffer_config)

    return create_recognizer


def _optional_env(values: Mapping[str, str], key: str) -> str | None:
    value = values.get(key)
    if not value:
        return None
    return value


def _whisper_backend(value: str) -> str:
    return value.strip().lower().replace("_", "-")


def _env_bool(values: Mapping[str, str], key: str) -> bool:
    return values.get(key, "").strip().lower() in {"1", "true", "yes", "on"}


def resolve_cached_huggingface_model_id(
    model_id: str,
    *,
    cache_root: Path = DEFAULT_HF_CACHE_ROOT,
) -> str:
    if "/" not in model_id:
        return model_id
    if Path(model_id).exists():
        return model_id

    org, name = model_id.split("/", 1)
    model_root = cache_root / f"models--{org}--{name}"
    refs_main = model_root / "refs" / "main"
    snapshots_dir = model_root / "snapshots"

    if refs_main.is_file():
        snapshot_hash = refs_main.read_text(encoding="utf-8").strip()
        candidate = snapshots_dir / snapshot_hash
        if candidate.is_dir():
            return str(candidate)

    if snapshots_dir.is_dir():
        snapshots = sorted(path for path in snapshots_dir.iterdir() if path.is_dir())
        if snapshots:
            return str(snapshots[0])

    return model_id
