from __future__ import annotations

import base64
from collections.abc import Callable
import logging
import math
import struct
from typing import Any

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect

from tarteel_realtime.livekit_tokens import (
    LiveKitConfigurationError,
    LiveKitDependencyMissing,
    LiveKitSettings,
    LiveKitTokenBuilder,
    livekit_settings_from_env,
    livekit_token_response,
)
from tarteel_realtime.quran import QuranCorpus, QuranRef
from tarteel_realtime.recognition import AudioChunk, SpeechRecognizer, VoiceActivity
from tarteel_realtime.session import RecitationSession, SessionEvent


logger = logging.getLogger(__name__)


def create_app(
    *,
    corpus: QuranCorpus,
    recognizer_factory: Callable[[], SpeechRecognizer],
    minimum_lock_words: int = 3,
    log_transcripts: bool = False,
    livekit_settings: LiveKitSettings | None = None,
    livekit_token_builder: LiveKitTokenBuilder | None = None,
) -> FastAPI:
    app = FastAPI(title="Tarteel Realtime MVP")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/livekit/recitation-token")
    def livekit_recitation_token(
        identity: str | None = None,
        role: str = "client",
    ) -> dict[str, str]:
        try:
            return livekit_token_response(
                settings=livekit_settings or livekit_settings_from_env(),
                identity=identity,
                role=role,
                token_builder=livekit_token_builder,
            )
        except LiveKitConfigurationError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except LiveKitDependencyMissing as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc

    @app.websocket("/ws/recitation")
    async def recitation_socket(websocket: WebSocket) -> None:
        await websocket.accept()
        session = RecitationSession(
            corpus=corpus,
            recognizer=recognizer_factory(),
            minimum_lock_words=minimum_lock_words,
        )

        try:
            while True:
                payload = await websocket.receive_json()
                chunk = _audio_chunk_from_payload(payload)
                event = session.handle_chunk(chunk)
                rms, peak = _pcm_level_stats(chunk.pcm)
                logger.warning(
                    "recitation_chunk sequence=%s pcm_bytes=%s sample_rate_hz=%s "
                    "approx_audio_ms=%s pcm_rms=%s pcm_peak=%s event_type=%s "
                    "reason=%s ayah_ref=%s transcript_chars=%s transcript_text=%s",
                    chunk.sequence_number,
                    len(chunk.pcm),
                    chunk.sample_rate_hz,
                    _pcm_bytes_to_ms(len(chunk.pcm), sample_rate_hz=chunk.sample_rate_hz),
                    rms,
                    peak,
                    event.type.value,
                    event.reason,
                    _ref_to_string(event.ayah_ref),
                    len(event.transcript),
                    event.transcript if log_transcripts else "<redacted>",
                )
                await websocket.send_json(_event_to_payload(event, corpus=corpus))
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


def session_event_to_payload(
    event: SessionEvent,
    *,
    corpus: QuranCorpus,
    session_id: str | None = None,
) -> dict[str, Any]:
    return {
        "type": event.type.value,
        "transcript": event.transcript,
        "confidence": event.confidence,
        "chunk_sequence": event.chunk_sequence,
        "reason": event.reason,
        "session_id": session_id,
        "candidate_refs": [_ref_to_string(ref) for ref in event.candidate_refs],
        "ayah_text": _ayah_text_for_event(event, corpus=corpus),
        "ayah_ref": _ref_to_string(event.ayah_ref),
        "start_ref": _ref_to_string(event.start_ref),
        "next_expected_ref": _ref_to_string(event.next_expected_ref),
        "consumed_words": event.consumed_words,
        "expected_ref": _ref_to_string(event.expected_ref),
        "expected_word": event.expected_word,
        "recognized_word": event.recognized_word,
    }


def _event_to_payload(event: SessionEvent, *, corpus: QuranCorpus) -> dict[str, Any]:
    return session_event_to_payload(event, corpus=corpus)


def _ayah_text_for_event(event: SessionEvent, *, corpus: QuranCorpus) -> str | None:
    ref = event.ayah_ref or event.start_ref
    if ref is None:
        return None
    return corpus.get_ayah(ref).text


def _ref_to_string(ref: QuranRef | None) -> str | None:
    if ref is None:
        return None
    return str(ref)


def _pcm_bytes_to_ms(byte_count: int, *, sample_rate_hz: int) -> int:
    bytes_per_sample = 2
    return byte_count * 1_000 // (sample_rate_hz * bytes_per_sample)


def _pcm_level_stats(pcm: bytes) -> tuple[int, int]:
    sample_count = len(pcm) // 2
    if sample_count == 0:
        return 0, 0

    peak = 0
    square_sum = 0
    pcm_samples = pcm[: sample_count * 2]
    for (sample,) in struct.iter_unpack("<h", pcm_samples):
        magnitude = abs(sample)
        peak = max(peak, magnitude)
        square_sum += sample * sample

    rms = int(round(math.sqrt(square_sum / sample_count)))
    return rms, peak
