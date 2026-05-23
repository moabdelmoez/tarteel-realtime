from __future__ import annotations

from collections.abc import Callable

from fastapi import FastAPI

from tarteel_realtime.app_factory import AppSettings, create_configured_app
from tarteel_realtime.asr_runtime import (
    AsrRuntimeSettings,
    DEFAULT_QURAN_WHISPER_MODEL_ID,
    create_buffered_whisper_recognizer_factory,
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
        recognizer_factory=recognizer_factory or create_buffered_whisper_recognizer_factory(settings),
    )


def create_app_from_env() -> FastAPI:
    return create_asr_app(settings_from_env())
