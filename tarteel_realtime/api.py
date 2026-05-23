from __future__ import annotations

import base64
from collections.abc import Callable
import logging
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recitation_scope import parse_recitation_scope
from tarteel_realtime.recognition import AudioChunk, SpeechRecognizer, VoiceActivity
from tarteel_realtime.recitation_stream import (
    RecitationStream,
    log_recitation_diagnostics,
)


logger = logging.getLogger(__name__)


def create_app(
    *,
    corpus: QuranCorpus,
    recognizer_factory: Callable[[], SpeechRecognizer],
    minimum_lock_words: int = 3,
    log_transcripts: bool = False,
) -> FastAPI:
    app = FastAPI(title="Tarteel Realtime MVP")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.websocket("/ws/recitation")
    async def recitation_socket(websocket: WebSocket) -> None:
        try:
            recitation_scope = parse_recitation_scope(
                websocket.query_params.get("scope"),
                corpus=corpus,
            )
        except ValueError as exc:
            await websocket.close(code=1008, reason=str(exc))
            return

        await websocket.accept()
        stream = RecitationStream(
            corpus=corpus,
            recognizer=recognizer_factory(),
            minimum_lock_words=minimum_lock_words,
            log_transcripts=log_transcripts,
            recitation_scope=recitation_scope,
        )

        try:
            while True:
                payload = await websocket.receive_json()
                chunk = _audio_chunk_from_payload(payload)
                result = stream.process_chunk(chunk)
                log_recitation_diagnostics(
                    result.diagnostics,
                    target_logger=logger,
                )
                await websocket.send_json(result.payload)
        except WebSocketDisconnect:
            return

    return app


def _audio_chunk_from_payload(payload: dict[str, Any]) -> AudioChunk:
    return AudioChunk(
        sequence_number=int(payload["sequence_number"]),
        pcm=base64.b64decode(payload["pcm_base64"]),
        sample_rate_hz=int(payload["sample_rate_hz"]),
        voice_activity=_voice_activity_from_payload(payload.get("voice_activity")),
    )


def _voice_activity_from_payload(payload: Any) -> VoiceActivity | None:
    if payload is None:
        return None
    if not isinstance(payload, dict):
        raise ValueError("voice_activity must be an object")
    return VoiceActivity(
        probability=(
            None
            if payload.get("probability") is None
            else float(payload["probability"])
        ),
        is_speech_active=(
            None
            if payload.get("is_speech_active") is None
            else bool(payload["is_speech_active"])
        ),
        event=payload.get("event"),
    )
