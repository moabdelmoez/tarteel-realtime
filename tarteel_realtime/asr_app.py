from __future__ import annotations

import os
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path

from fastapi import FastAPI

from tarteel_realtime.app_factory import AppSettings, create_configured_app
from tarteel_realtime.buffered_recognition import BufferedRecognitionConfig, BufferedRecognizer
from tarteel_realtime.quran_data import DEFAULT_TANZIL_PATH
from tarteel_realtime.recognition import AudioChunk, RecognitionResult, SpeechRecognizer
from tarteel_realtime.whisper_adapter import WhisperConfig, WhisperRecognizer


DEFAULT_QURAN_WHISPER_MODEL_ID = "basharalrfooh/whisper-small-quran"


@dataclass(frozen=True)
class AsrAppSettings:
    tanzil_path: Path = DEFAULT_TANZIL_PATH
    minimum_lock_words: int = 3
    model_id: str = DEFAULT_QURAN_WHISPER_MODEL_ID
    language: str = "ar"
    device: str | int | None = None
    minimum_audio_ms: int = 2_000
    flush_interval_ms: int = 1_500
    tail_audio_ms: int = 500


class LazyRecognizer:
    def __init__(self, recognizer_factory: Callable[[], SpeechRecognizer]) -> None:
        self._recognizer_factory = recognizer_factory
        self._recognizer: SpeechRecognizer | None = None

    def recognize(self, chunk: AudioChunk) -> RecognitionResult:
        if self._recognizer is None:
            self._recognizer = self._recognizer_factory()
        return self._recognizer.recognize(chunk)


def settings_from_env(env: Mapping[str, str] | None = None) -> AsrAppSettings:
    values = os.environ if env is None else env
    return AsrAppSettings(
        tanzil_path=Path(values.get("TARTEEL_TANZIL_PATH", str(DEFAULT_TANZIL_PATH))),
        minimum_lock_words=int(values.get("TARTEEL_MINIMUM_LOCK_WORDS", "3")),
        model_id=values.get("TARTEEL_WHISPER_MODEL_ID", DEFAULT_QURAN_WHISPER_MODEL_ID),
        language=values.get("TARTEEL_WHISPER_LANGUAGE", "ar"),
        device=_optional_env(values, "TARTEEL_WHISPER_DEVICE"),
        minimum_audio_ms=int(values.get("TARTEEL_ASR_MIN_AUDIO_MS", "2000")),
        flush_interval_ms=int(values.get("TARTEEL_ASR_FLUSH_MS", "1500")),
        tail_audio_ms=int(values.get("TARTEEL_ASR_TAIL_MS", "500")),
    )


def create_lazy_whisper_recognizer_factory(
    settings: AsrAppSettings,
    *,
    recognizer_builder: Callable[[WhisperConfig], SpeechRecognizer] | None = None,
) -> Callable[[], SpeechRecognizer]:
    builder = recognizer_builder or WhisperRecognizer.from_transformers
    config = WhisperConfig(
        model_id=settings.model_id,
        language=settings.language,
        device=settings.device,
    )

    def create_recognizer() -> SpeechRecognizer:
        return LazyRecognizer(lambda: builder(config))

    return create_recognizer


def create_buffered_whisper_recognizer_factory(
    settings: AsrAppSettings,
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
    )

    def create_recognizer() -> SpeechRecognizer:
        return BufferedRecognizer(lazy_factory(), config=buffer_config)

    return create_recognizer


def create_asr_app(
    settings: AsrAppSettings,
    *,
    recognizer_factory: Callable[[], SpeechRecognizer] | None = None,
) -> FastAPI:
    return create_configured_app(
        AppSettings(
            tanzil_path=settings.tanzil_path,
            minimum_lock_words=settings.minimum_lock_words,
        ),
        recognizer_factory=recognizer_factory or create_buffered_whisper_recognizer_factory(settings),
    )


def create_app_from_env() -> FastAPI:
    return create_asr_app(settings_from_env())


def _optional_env(values: Mapping[str, str], key: str) -> str | None:
    value = values.get(key)
    if not value:
        return None
    return value
