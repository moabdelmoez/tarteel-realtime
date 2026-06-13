from __future__ import annotations

import base64
from collections.abc import Callable, Mapping
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
    websocket_bearer_token: str | None = None,
    recognizer_factories_by_asr_model: Mapping[str, Callable[[], SpeechRecognizer]] | None = None,
    default_asr_model: str | None = None,
) -> FastAPI:
    app = FastAPI(title="Tarteel Realtime MVP")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/ping")
    def ping() -> dict[str, str]:
        return {"status": "ok"}

    @app.websocket("/ws/recitation")
    async def recitation_socket(websocket: WebSocket) -> None:
        if not _is_authorized_websocket(
            websocket,
            expected_bearer_token=websocket_bearer_token,
        ):
            await websocket.close(code=1008, reason="missing or invalid bearer token")
            return

        try:
            recitation_scope = parse_recitation_scope(
                websocket.query_params.get("scope"),
                corpus=corpus,
            )
        except ValueError as exc:
            await websocket.close(code=1008, reason=str(exc))
            return

        try:
            selected_recognizer_factory = _recognizer_factory_for_asr_model(
                websocket.query_params.get("asr_model"),
                default_factory=recognizer_factory,
                factories_by_asr_model=recognizer_factories_by_asr_model,
                default_asr_model=default_asr_model,
            )
        except ValueError as exc:
            await websocket.close(code=1008, reason=str(exc))
            return

        diagnostics_enabled = websocket.query_params.get("diagnostics") == "1"
        await websocket.accept()
        stream = RecitationStream(
            corpus=corpus,
            recognizer=selected_recognizer_factory(),
            minimum_lock_words=minimum_lock_words,
            log_transcripts=log_transcripts,
            recitation_scope=recitation_scope,
            diagnostics_enabled=diagnostics_enabled,
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
                response_payload = (
                    result.diagnostic_envelope
                    if diagnostics_enabled
                    else result.payload
                )
                await websocket.send_json(response_payload)
        except WebSocketDisconnect:
            return

    return app


def _recognizer_factory_for_asr_model(
    requested_asr_model: str | None,
    *,
    default_factory: Callable[[], SpeechRecognizer],
    factories_by_asr_model: Mapping[str, Callable[[], SpeechRecognizer]] | None,
    default_asr_model: str | None,
) -> Callable[[], SpeechRecognizer]:
    if factories_by_asr_model is None:
        return default_factory

    selected_asr_model = (
        requested_asr_model.strip()
        if requested_asr_model is not None and requested_asr_model.strip()
        else default_asr_model
    )
    if not selected_asr_model or selected_asr_model not in factories_by_asr_model:
        raise ValueError("unsupported asr_model")
    return factories_by_asr_model[selected_asr_model]


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


def _is_authorized_websocket(
    websocket: WebSocket,
    *,
    expected_bearer_token: str | None,
) -> bool:
    if not expected_bearer_token:
        return True

    authorization = websocket.headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    expected_token = expected_bearer_token.strip()
    return (
        scheme.lower() == "bearer"
        and bool(expected_token)
        and token.strip() == expected_token
    )
