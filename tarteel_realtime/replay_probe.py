from __future__ import annotations

import argparse
import asyncio
from collections import Counter
from dataclasses import dataclass
import json
import os
from pathlib import Path
import struct
from time import monotonic
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
import wave

from tarteel_realtime.asr_smoke import SmokeAudio, load_audio_file
from tarteel_realtime.ws_client import (
    build_chunk_payload,
    split_pcm_audio,
    websocket_connect_kwargs,
)


WAITING_REASON = "waiting_for_audio_buffer"


@dataclass(frozen=True)
class TimedEvent:
    event: dict[str, Any]
    elapsed_ms: int


@dataclass(frozen=True)
class ReplayProbeResult:
    url: str
    audio_path: str
    chunk_ms: int | None
    connect_ms: int
    total_ms: int
    timed_events: tuple[TimedEvent, ...]


def load_replay_audio_file(audio_path: Path, *, raw_sample_rate_hz: int) -> SmokeAudio:
    if audio_path.suffix.lower() != ".wav":
        return load_audio_file(audio_path, raw_sample_rate_hz=raw_sample_rate_hz)

    with wave.open(str(audio_path), "rb") as wav_file:
        channel_count = wav_file.getnchannels()
        if channel_count < 1:
            raise ValueError("WAV input must have at least one channel.")
        if wav_file.getsampwidth() != 2:
            raise ValueError("WAV input must use 16-bit PCM samples.")
        if wav_file.getcomptype() != "NONE":
            raise ValueError("WAV input must be uncompressed PCM audio.")

        frames = wav_file.readframes(wav_file.getnframes())
        if channel_count == 1:
            return SmokeAudio(
                pcm=frames,
                sample_rate_hz=wav_file.getframerate(),
            )
        return SmokeAudio(
            pcm=_downmix_pcm16le_to_mono(frames, channel_count=channel_count),
            sample_rate_hz=wav_file.getframerate(),
        )


def _downmix_pcm16le_to_mono(pcm: bytes, *, channel_count: int) -> bytes:
    sample_width = 2
    frame_width = channel_count * sample_width
    whole_frames = len(pcm) // frame_width
    if whole_frames == 0:
        return b""

    frames = struct.iter_unpack(
        f"<{channel_count}h",
        pcm[:whole_frames * frame_width],
    )
    mono_samples = [
        round(sum(frame) / channel_count)
        for frame in frames
    ]
    return struct.pack(f"<{len(mono_samples)}h", *mono_samples)


def url_with_scope(url: str, scope: str | None) -> str:
    if not scope:
        return url

    parts = urlsplit(url)
    query_items = [
        (name, value)
        for name, value in parse_qsl(parts.query, keep_blank_values=True)
        if name != "scope"
    ]
    query_items.append(("scope", scope))
    return urlunsplit((
        parts.scheme,
        parts.netloc,
        parts.path,
        urlencode(query_items),
        parts.fragment,
    ))


def url_with_asr_model(url: str, asr_model: str | None) -> str:
    if not asr_model:
        return url

    parts = urlsplit(url)
    query_items = [
        (name, value)
        for name, value in parse_qsl(parts.query, keep_blank_values=True)
        if name != "asr_model"
    ]
    query_items.append(("asr_model", asr_model))
    return urlunsplit((
        parts.scheme,
        parts.netloc,
        parts.path,
        urlencode(query_items),
        parts.fragment,
    ))


async def run_probe(
    *,
    url: str,
    audio: SmokeAudio,
    audio_path: str,
    chunk_ms: int | None,
    disable_ping: bool,
    authorization_token: str | None = None,
    send_speech_end: bool = False,
) -> ReplayProbeResult:
    import websockets

    start = monotonic()
    timed_events: list[TimedEvent] = []
    async with websockets.connect(
        url,
        **websocket_connect_kwargs(
            disable_ping=disable_ping,
            authorization_token=authorization_token,
        ),
    ) as websocket:
        connected = monotonic()
        chunks = split_pcm_audio(audio, chunk_duration_ms=chunk_ms)
        for sequence_number, pcm in enumerate(chunks):
            await websocket.send(json.dumps(build_chunk_payload(
                sequence_number=sequence_number,
                pcm=pcm,
                sample_rate_hz=audio.sample_rate_hz,
            )))
            event = json.loads(await websocket.recv())
            timed_events.append(TimedEvent(
                event=event,
                elapsed_ms=_elapsed_ms(start),
            ))
        if send_speech_end:
            await websocket.send(json.dumps(build_chunk_payload(
                sequence_number=len(chunks),
                pcm=b"",
                sample_rate_hz=audio.sample_rate_hz,
                voice_activity={
                    "probability": 0.0,
                    "is_speech_active": False,
                    "event": "speech_end",
                },
            )))
            event = json.loads(await websocket.recv())
            timed_events.append(TimedEvent(
                event=event,
                elapsed_ms=_elapsed_ms(start),
            ))
    return ReplayProbeResult(
        url=url,
        audio_path=audio_path,
        chunk_ms=chunk_ms,
        connect_ms=_duration_ms(start, connected),
        total_ms=_elapsed_ms(start),
        timed_events=tuple(timed_events),
    )


def summarize_probe_result(
    result: ReplayProbeResult,
    *,
    include_events: bool = False,
) -> dict[str, Any]:
    events = [timed.event for timed in result.timed_events]
    type_counts = Counter(str(event.get("type", "")) for event in events)
    first_event = result.timed_events[0] if result.timed_events else None
    first_non_wait = next(
        (
            timed
            for timed in result.timed_events
            if timed.event.get("reason") != WAITING_REASON
        ),
        None,
    )
    first_lock = next((event for event in events if event.get("type") == "locked"), None)
    first_progress = next((event for event in events if event.get("type") == "progress"), None)

    summary: dict[str, Any] = {
        "url": result.url,
        "audio_path": result.audio_path,
        "chunk_ms": result.chunk_ms,
        "connect_ms": result.connect_ms,
        "total_ms": result.total_ms,
        "event_count": len(events),
        "event_type_counts": dict(sorted(type_counts.items())),
        "first_event_ms": None if first_event is None else first_event.elapsed_ms,
        "first_non_wait_event_ms": None if first_non_wait is None else first_non_wait.elapsed_ms,
        "first_non_wait_event_type": None if first_non_wait is None else first_non_wait.event.get("type"),
        "first_non_wait_reason": None if first_non_wait is None else first_non_wait.event.get("reason"),
        "first_lock_ref": None if first_lock is None else first_lock.get("ayah_ref"),
        "first_progress_next_expected_ref": (
            None if first_progress is None else first_progress.get("next_expected_ref")
        ),
    }
    if include_events:
        summary["events"] = events
        summary["event_timings_ms"] = [timed.elapsed_ms for timed in result.timed_events]
    return summary


def format_summary(summary: dict[str, Any]) -> str:
    return json.dumps(summary, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _duration_ms(start: float, end: float) -> int:
    return int(round((end - start) * 1_000))


def _elapsed_ms(start: float) -> int:
    return _duration_ms(start, monotonic())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Replay one audio file and summarize WebSocket ASR endpoint behavior.")
    parser.add_argument("--url", required=True)
    parser.add_argument("--audio-path", type=Path, required=True)
    parser.add_argument("--sample-rate", type=int, default=16_000)
    parser.add_argument("--chunk-ms", type=int, default=1_000)
    parser.add_argument("--scope", default=None)
    parser.add_argument("--bearer-token", default=None)
    parser.add_argument("--bearer-token-env", default=None)
    parser.add_argument("--asr-model", default=None)
    parser.add_argument("--disable-ping", action="store_true")
    parser.add_argument("--include-events", action="store_true")
    parser.add_argument("--send-speech-end", action="store_true")
    args = parser.parse_args(argv)

    audio = load_replay_audio_file(args.audio_path, raw_sample_rate_hz=args.sample_rate)
    url = url_with_asr_model(url_with_scope(args.url, args.scope), args.asr_model)
    bearer_token = args.bearer_token
    if args.bearer_token_env:
        bearer_token = os.environ.get(args.bearer_token_env)
    result = asyncio.run(run_probe(
        url=url,
        audio=audio,
        audio_path=str(args.audio_path),
        chunk_ms=args.chunk_ms,
        disable_ping=args.disable_ping,
        authorization_token=bearer_token,
        send_speech_end=args.send_speech_end,
    ))
    print(format_summary(summarize_probe_result(
        result,
        include_events=args.include_events,
    )))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
