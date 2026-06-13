from __future__ import annotations

import argparse
import asyncio
import base64
import json
from pathlib import Path
from typing import Any

from tarteel_realtime.asr_smoke import SmokeAudio, load_audio_file


DEFAULT_WS_URL = "ws://127.0.0.1:8000/ws/recitation"
DEFAULT_SAMPLE_RATE_HZ = 16_000


def build_chunk_payload(
    *,
    sequence_number: int,
    pcm: bytes,
    sample_rate_hz: int,
    voice_activity: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "sequence_number": sequence_number,
        "pcm_base64": base64.b64encode(pcm).decode("ascii"),
        "sample_rate_hz": sample_rate_hz,
    }
    if voice_activity is not None:
        payload["voice_activity"] = voice_activity
    return payload


async def collect_events(
    websocket,
    *,
    chunk_count: int,
    sample_rate_hz: int,
) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for sequence_number in range(chunk_count):
        payload = build_chunk_payload(
            sequence_number=sequence_number,
            pcm=b"\x00\x01",
            sample_rate_hz=sample_rate_hz,
        )
        await websocket.send(json.dumps(payload))
        events.append(json.loads(await websocket.recv()))
    return events


def split_pcm_audio(audio: SmokeAudio, *, chunk_duration_ms: int | None) -> list[bytes]:
    if chunk_duration_ms is None:
        return [audio.pcm]
    if chunk_duration_ms <= 0:
        raise ValueError("chunk_duration_ms must be positive")

    bytes_per_sample = 2
    samples_per_chunk = max(1, audio.sample_rate_hz * chunk_duration_ms // 1_000)
    bytes_per_chunk = samples_per_chunk * bytes_per_sample
    return [
        audio.pcm[offset:offset + bytes_per_chunk]
        for offset in range(0, len(audio.pcm), bytes_per_chunk)
        if audio.pcm[offset:offset + bytes_per_chunk]
    ]


async def collect_audio_events(
    websocket,
    *,
    audio: SmokeAudio,
    chunk_duration_ms: int | None,
    send_speech_end: bool = False,
) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    chunks = split_pcm_audio(audio, chunk_duration_ms=chunk_duration_ms)
    for sequence_number, pcm in enumerate(chunks):
        payload = build_chunk_payload(
            sequence_number=sequence_number,
            pcm=pcm,
            sample_rate_hz=audio.sample_rate_hz,
        )
        await websocket.send(json.dumps(payload))
        events.append(json.loads(await websocket.recv()))
    if send_speech_end:
        payload = build_chunk_payload(
            sequence_number=len(chunks),
            pcm=b"",
            sample_rate_hz=audio.sample_rate_hz,
            voice_activity={
                "probability": 0.0,
                "is_speech_active": False,
                "event": "speech_end",
            },
        )
        await websocket.send(json.dumps(payload))
        events.append(json.loads(await websocket.recv()))
    return events


def format_event(event: dict[str, Any]) -> str:
    return json.dumps(event, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def authorization_headers(*, authorization_token: str | None) -> dict[str, str]:
    if authorization_token is None:
        return {}
    token = authorization_token.strip()
    if not token:
        return {}
    return {"Authorization": f"Bearer {token}"}


def websocket_connect_kwargs(
    *,
    disable_ping: bool,
    authorization_token: str | None = None,
) -> dict[str, Any]:
    kwargs: dict[str, Any] = {}
    if disable_ping:
        kwargs["ping_interval"] = None
        kwargs["ping_timeout"] = None
    headers = authorization_headers(authorization_token=authorization_token)
    if headers:
        kwargs["additional_headers"] = headers
    return kwargs


async def run_client(
    *,
    url: str,
    chunk_count: int,
    sample_rate_hz: int,
    audio: SmokeAudio | None = None,
    chunk_duration_ms: int | None = None,
    disable_ping: bool = False,
    authorization_token: str | None = None,
    send_speech_end: bool = False,
) -> list[dict[str, Any]]:
    import websockets

    async with websockets.connect(
        url,
        **websocket_connect_kwargs(
            disable_ping=disable_ping,
            authorization_token=authorization_token,
        ),
    ) as websocket:
        if audio is not None:
            return await collect_audio_events(
                websocket,
                audio=audio,
                chunk_duration_ms=chunk_duration_ms,
                send_speech_end=send_speech_end,
            )
        return await collect_events(
            websocket,
            chunk_count=chunk_count,
            sample_rate_hz=sample_rate_hz,
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Send dummy audio chunks to the dev WebSocket.")
    parser.add_argument("--url", default=DEFAULT_WS_URL)
    parser.add_argument("--chunks", type=int, default=2)
    parser.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE_HZ)
    parser.add_argument("--audio-path", type=Path, default=None, help="Optional PCM16LE or mono PCM16 WAV file to send.")
    parser.add_argument("--chunk-ms", type=int, default=None, help="Optional chunk size in milliseconds. Defaults to one whole-file chunk for --audio-path.")
    parser.add_argument("--disable-ping", action="store_true", help="Disable WebSocket keepalive pings for long ASR inference windows.")
    parser.add_argument("--bearer-token", default=None, help="Optional WebSocket Authorization bearer token.")
    parser.add_argument("--send-speech-end", action="store_true", help="Send one final empty speech_end VAD marker after audio chunks.")
    args = parser.parse_args(argv)

    audio = None
    if args.audio_path is not None:
        audio = load_audio_file(args.audio_path, raw_sample_rate_hz=args.sample_rate)

    events = asyncio.run(run_client(
        url=args.url,
        chunk_count=args.chunks,
        sample_rate_hz=args.sample_rate,
        audio=audio,
        chunk_duration_ms=args.chunk_ms,
        disable_ping=args.disable_ping,
        authorization_token=args.bearer_token,
        send_speech_end=args.send_speech_end,
    ))
    for event in events:
        print(format_event(event))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
