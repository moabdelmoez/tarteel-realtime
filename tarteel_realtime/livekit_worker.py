from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import struct
from typing import Any, Protocol

from tarteel_realtime.api import session_event_to_payload
from tarteel_realtime.asr_app import (
    create_buffered_whisper_recognizer_factory,
    settings_from_env as asr_settings_from_env,
)
from tarteel_realtime.livekit_tokens import (
    LiveKitDependencyMissing,
    LiveKitSettings,
    livekit_settings_from_env,
    livekit_token_response,
)
from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recognition import (
    AudioChunk,
    FakeRecognizer,
    RecognitionResult,
    RecognizerScriptExhausted,
    SpeechRecognizer,
)
from tarteel_realtime.session import RecitationSession


RECITATION_EVENT_TOPIC = "tarteel.recitation.event"
FAKE_TRANSCRIPTS_ENV = "TARTEEL_LIVEKIT_FAKE_TRANSCRIPTS"

logger = logging.getLogger(__name__)


class LiveKitDataPublisher(Protocol):
    async def publish_data(
        self,
        payload: bytes | str,
        *,
        reliable: bool = True,
        topic: str = "",
    ) -> None:
        """Publish a LiveKit data packet."""


class LiveKitRecitationWorker:
    def __init__(
        self,
        *,
        corpus: QuranCorpus,
        recognizer: SpeechRecognizer,
        publisher: LiveKitDataPublisher,
        minimum_lock_words: int = 3,
    ) -> None:
        self._session = RecitationSession(
            corpus=corpus,
            recognizer=recognizer,
            minimum_lock_words=minimum_lock_words,
        )
        self._corpus = corpus
        self._publisher = publisher
        self._sequence_number = 0

    async def handle_audio_frame(self, frame: Any) -> None:
        chunk = audio_frame_to_chunk(
            frame,
            sequence_number=self._sequence_number,
        )
        self._sequence_number += 1
        event = self._session.handle_chunk(chunk)
        payload = session_event_to_payload(event, corpus=self._corpus)
        await self._publisher.publish_data(
            json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            reliable=True,
            topic=RECITATION_EVENT_TOPIC,
        )


class RepeatingFakeRecognizer:
    def __init__(self, transcripts: list[str]) -> None:
        self._recognizer = FakeRecognizer(transcripts)
        self._fallback_transcript = transcripts[-1]

    def recognize(self, chunk: AudioChunk) -> RecognitionResult:
        try:
            return self._recognizer.recognize(chunk)
        except RecognizerScriptExhausted:
            return RecognitionResult(
                transcript=self._fallback_transcript,
                confidence=1.0,
            )


def audio_frame_to_chunk(frame: Any, *, sequence_number: int) -> AudioChunk:
    sample_rate = int(frame.sample_rate)
    channel_count = int(frame.num_channels)
    samples_per_channel = int(frame.samples_per_channel)
    if channel_count <= 0:
        raise ValueError("audio frame must have at least one channel")

    samples = _frame_int16_samples(frame)
    expected_samples = samples_per_channel * channel_count
    if len(samples) < expected_samples:
        raise ValueError("audio frame has fewer samples than its metadata declares")
    samples = samples[:expected_samples]

    if channel_count == 1:
        mono_samples = samples
    else:
        mono_samples = [
            _clamp_int16(round(sum(samples[offset:offset + channel_count]) / channel_count))
            for offset in range(0, expected_samples, channel_count)
        ]

    return AudioChunk(
        sequence_number=sequence_number,
        pcm=struct.pack(f"<{len(mono_samples)}h", *mono_samples),
        sample_rate_hz=sample_rate,
    )


async def run_livekit_worker(
    *,
    livekit_settings: LiveKitSettings | None = None,
    worker_identity: str = "tarteel-backend-worker",
    fake_transcripts: list[str] | None = None,
) -> None:
    try:
        from livekit import rtc
    except ModuleNotFoundError as exc:
        raise LiveKitDependencyMissing(
            "Install livekit and livekit-api to run the LiveKit recitation worker."
        ) from exc

    settings = livekit_settings or livekit_settings_from_env()
    asr_settings = asr_settings_from_env()
    corpus = QuranCorpus.from_tanzil_file(asr_settings.tanzil_path)
    recognizer = _recognizer_factory_for_livekit_worker(
        asr_settings,
        fake_transcripts=fake_transcripts,
    )()

    room = rtc.Room()
    tasks: set[asyncio.Task] = set()
    worker: LiveKitRecitationWorker | None = None

    @room.on("track_subscribed")
    def on_track_subscribed(track, publication, participant) -> None:
        if track.kind != rtc.TrackKind.KIND_AUDIO:
            return
        if worker is None:
            logger.warning("livekit_worker received audio track before worker initialization")
            return
        logger.warning(
            "livekit_worker subscribed audio track=%s participant=%s",
            publication.sid,
            participant.identity,
        )
        task = asyncio.create_task(_consume_audio_stream(rtc.AudioStream(track), worker))
        tasks.add(task)
        task.add_done_callback(tasks.discard)

    token = livekit_token_response(
        settings=settings,
        identity=worker_identity,
        role="worker",
    )["token"]
    await room.connect(settings.url, token)
    worker = LiveKitRecitationWorker(
        corpus=corpus,
        recognizer=recognizer,
        publisher=room.local_participant,
        minimum_lock_words=asr_settings.minimum_lock_words,
    )
    logger.warning("livekit_worker connected url=%s room=%s", settings.url, settings.room_name)

    try:
        await asyncio.Event().wait()
    finally:
        for task in tasks:
            task.cancel()
        await room.disconnect()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the LiveKit recitation worker.")
    parser.add_argument("--identity", default=os.environ.get("TARTEEL_LIVEKIT_WORKER_IDENTITY", "tarteel-backend-worker"))
    parser.add_argument(
        "--fake-transcript",
        action="append",
        default=None,
        help="Use a deterministic transcript for local LiveKit transport smoke tests. Can be passed more than once.",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.WARNING)
    asyncio.run(run_livekit_worker(
        worker_identity=args.identity,
        fake_transcripts=args.fake_transcript,
    ))
    return 0


async def _consume_audio_stream(audio_stream: Any, worker: LiveKitRecitationWorker) -> None:
    async for audio_event in audio_stream:
        frame = getattr(audio_event, "frame", audio_event)
        await worker.handle_audio_frame(frame)


def _frame_int16_samples(frame: Any) -> list[int]:
    data = frame.data
    if isinstance(data, memoryview):
        view = data if data.format == "h" else data.cast("h")
        return [int(sample) for sample in view]
    return [int(sample) for sample in data]


def _clamp_int16(value: int) -> int:
    return max(-32768, min(32767, value))


def _recognizer_factory_for_livekit_worker(
    asr_settings,
    *,
    fake_transcripts: list[str] | None = None,
):
    transcripts = fake_transcripts
    if transcripts is None:
        transcripts = fake_transcripts_from_env()
    if transcripts:
        return lambda: RepeatingFakeRecognizer(transcripts)
    return create_buffered_whisper_recognizer_factory(asr_settings)


def fake_transcripts_from_env(env: dict[str, str] | None = None) -> list[str]:
    values = os.environ if env is None else env
    raw_script = values.get(FAKE_TRANSCRIPTS_ENV, "")
    return [
        transcript.strip()
        for transcript in raw_script.split("|")
        if transcript.strip()
    ]


if __name__ == "__main__":
    raise SystemExit(main())
