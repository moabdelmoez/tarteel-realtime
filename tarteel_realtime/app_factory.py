from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from fastapi import FastAPI

from tarteel_realtime.api import create_app
from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recognition import SpeechRecognizer


@dataclass(frozen=True)
class AppSettings:
    tanzil_path: Path
    minimum_lock_words: int = 3
    log_transcripts: bool = False
    websocket_bearer_token: str | None = None


def create_configured_app(
    settings: AppSettings,
    *,
    recognizer_factory: Callable[[], SpeechRecognizer],
) -> FastAPI:
    return create_app(
        corpus=QuranCorpus.from_tanzil_file(settings.tanzil_path),
        recognizer_factory=recognizer_factory,
        minimum_lock_words=settings.minimum_lock_words,
        log_transcripts=settings.log_transcripts,
        websocket_bearer_token=settings.websocket_bearer_token,
    )
