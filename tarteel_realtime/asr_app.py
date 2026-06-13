from __future__ import annotations

from collections.abc import Callable, Mapping

from fastapi import FastAPI

from tarteel_realtime.app_factory import AppSettings, create_configured_app
from tarteel_realtime.asr_runtime import (
    AsrRuntimeSettings,
    DEFAULT_QURAN_WHISPER_MODEL_ID,
    create_buffered_asr_recognizer_factories_by_model,
    create_buffered_asr_recognizer_factory,
    create_buffered_whisper_recognizer_factory,
    create_lazy_asr_recognizer_factory,
    create_lazy_whisper_recognizer_factory,
    settings_from_env,
)
from tarteel_realtime.recognition import SpeechRecognizer

# Backward-compatible export for existing imports.
AsrAppSettings = AsrRuntimeSettings


def create_asr_app(
    settings: AsrRuntimeSettings,
    *,
    recognizer_factory: Callable[[], SpeechRecognizer] | None = None,
) -> FastAPI:
    return create_configured_app(
        AppSettings(
            tanzil_path=settings.tanzil_path,
            minimum_lock_words=settings.minimum_lock_words,
            log_transcripts=settings.log_transcripts,
        ),
        recognizer_factory=recognizer_factory or create_buffered_asr_recognizer_factory(settings),
    )


def create_model_selecting_asr_app(
    settings_by_asr_model: Mapping[str, AsrRuntimeSettings],
    *,
    default_asr_model: str,
) -> FastAPI:
    if default_asr_model not in settings_by_asr_model:
        raise ValueError(f"default ASR model is not configured: {default_asr_model}")

    recognizer_factories_by_asr_model = create_buffered_asr_recognizer_factories_by_model(
        settings_by_asr_model,
    )
    default_settings = settings_by_asr_model[default_asr_model]
    return create_configured_app(
        AppSettings(
            tanzil_path=default_settings.tanzil_path,
            minimum_lock_words=default_settings.minimum_lock_words,
            log_transcripts=default_settings.log_transcripts,
            websocket_bearer_token=default_settings.websocket_bearer_token,
        ),
        recognizer_factory=recognizer_factories_by_asr_model[default_asr_model],
        recognizer_factories_by_asr_model=recognizer_factories_by_asr_model,
        default_asr_model=default_asr_model,
    )


def create_app_from_env() -> FastAPI:
    return create_asr_app(settings_from_env())
