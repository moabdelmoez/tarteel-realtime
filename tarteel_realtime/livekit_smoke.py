from __future__ import annotations

import argparse
import asyncio
import json
import math
import struct
from typing import Any

from tarteel_realtime.livekit_tokens import (
    LiveKitDependencyMissing,
    livekit_settings_from_env,
    livekit_token_response,
)
from tarteel_realtime.livekit_worker import RECITATION_EVENT_TOPIC


async def run_livekit_audio_smoke(
    *,
    identity: str = "tarteel-livekit-smoke-client",
    duration_ms: int = 800,
    timeout_s: float = 10.0,
) -> dict[str, Any]:
    try:
        from livekit import rtc
    except ModuleNotFoundError as exc:
        raise LiveKitDependencyMissing(
            "Install livekit and livekit-api to run the LiveKit audio smoke."
        ) from exc

    settings = livekit_settings_from_env()
    token = livekit_token_response(
        settings=settings,
        identity=identity,
        role="client",
    )["token"]

    room = rtc.Room()
    received: dict[str, Any] = {}
    event_received = asyncio.Event()

    @room.on("data_received")
    def on_data_received(data_packet) -> None:
        payload = recitation_payload_from_data_packet(data_packet)
        if payload is None:
            return
        received["payload"] = payload
        event_received.set()

    await room.connect(settings.url, token)
    audio_source = rtc.AudioSource(16_000, 1)
    audio_track = rtc.LocalAudioTrack.create_audio_track("recitation-smoke-audio", audio_source)
    await room.local_participant.publish_track(audio_track)

    try:
        await _publish_sine_audio(
            rtc=rtc,
            audio_source=audio_source,
            duration_ms=duration_ms,
            event_received=event_received,
        )
        await asyncio.wait_for(event_received.wait(), timeout=timeout_s)
        return received["payload"]
    finally:
        await audio_source.aclose()
        await room.disconnect()


def recitation_payload_from_data_packet(data_packet) -> dict[str, Any] | None:
    if getattr(data_packet, "topic", "") != RECITATION_EVENT_TOPIC:
        return None
    payload = getattr(data_packet, "data", b"")
    if isinstance(payload, str):
        payload_bytes = payload.encode("utf-8")
    else:
        payload_bytes = bytes(payload)
    return json.loads(payload_bytes.decode("utf-8"))


def sine_pcm16_frame(
    *,
    sample_rate: int = 16_000,
    duration_ms: int = 20,
    frequency_hz: float = 440.0,
    amplitude: int = 3_000,
) -> bytes:
    sample_count = sample_rate * duration_ms // 1_000
    samples = [
        int(amplitude * math.sin(2.0 * math.pi * frequency_hz * index / sample_rate))
        for index in range(sample_count)
    ]
    return struct.pack(f"<{sample_count}h", *samples)


async def _publish_sine_audio(
    *,
    rtc,
    audio_source,
    duration_ms: int,
    event_received: asyncio.Event,
) -> None:
    frame_duration_ms = 20
    sample_rate = 16_000
    samples_per_frame = sample_rate * frame_duration_ms // 1_000
    frame_count = max(1, duration_ms // frame_duration_ms)

    for _ in range(frame_count):
        frame = rtc.AudioFrame(
            data=sine_pcm16_frame(sample_rate=sample_rate, duration_ms=frame_duration_ms),
            sample_rate=sample_rate,
            num_channels=1,
            samples_per_channel=samples_per_frame,
        )
        await audio_source.capture_frame(frame)
        if event_received.is_set():
            return


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Publish synthetic audio to LiveKit and wait for a recitation event."
    )
    parser.add_argument("--identity", default="tarteel-livekit-smoke-client")
    parser.add_argument("--duration-ms", type=int, default=800)
    parser.add_argument("--timeout-s", type=float, default=10.0)
    args = parser.parse_args(argv)

    payload = asyncio.run(run_livekit_audio_smoke(
        identity=args.identity,
        duration_ms=args.duration_ms,
        timeout_s=args.timeout_s,
    ))
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
