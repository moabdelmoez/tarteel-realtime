from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import struct
from collections.abc import Callable
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
    VoiceActivity,
)
from tarteel_realtime.session import RecitationSession, SessionEvent, SessionEventType


RECITATION_EVENT_TOPIC = "tarteel.recitation.event"
VOICE_ACTIVITY_TOPIC = "tarteel.voice_activity"
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
        session_id: str | None = None,
        voice_activity_provider: Callable[[], VoiceActivity | None] | None = None,
    ) -> None:
        self._session = RecitationSession(
            corpus=corpus,
            recognizer=recognizer,
            minimum_lock_words=minimum_lock_words,
        )
        self._corpus = corpus
        self._publisher = publisher
        self._sequence_number = 0
        self._session_id = session_id
        self._voice_activity_provider = voice_activity_provider

    async def handle_audio_frame(self, frame: Any) -> None:
        chunk = audio_frame_to_chunk(
            frame,
            sequence_number=self._sequence_number,
            voice_activity=self._latest_voice_activity(),
        )
        self._sequence_number += 1
        event = self._handle_chunk_safely(chunk)
        payload = session_event_to_payload(
            event,
            corpus=self._corpus,
            session_id=self._session_id,
        )
        await self._publisher.publish_data(
            json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            reliable=True,
            topic=RECITATION_EVENT_TOPIC,
        )

    def _handle_chunk_safely(self, chunk: AudioChunk) -> SessionEvent:
        try:
            return self._session.handle_chunk(chunk)
        except Exception:
            logger.exception(
                "livekit_worker asr_error sequence=%s sample_rate_hz=%s pcm_bytes=%s",
                chunk.sequence_number,
                chunk.sample_rate_hz,
                len(chunk.pcm),
            )
            return SessionEvent(
                type=SessionEventType.UNCERTAIN,
                transcript="",
                confidence=0.0,
                chunk_sequence=chunk.sequence_number,
                reason="asr_error",
            )

    def _latest_voice_activity(self) -> VoiceActivity | None:
        if self._voice_activity_provider is None:
            return None
        return self._voice_activity_provider()


def create_livekit_recitation_worker(
    *,
    corpus: QuranCorpus,
    recognizer_factory: Callable[[], SpeechRecognizer],
    publisher: LiveKitDataPublisher,
    minimum_lock_words: int = 3,
    session_id: str | None = None,
    voice_activity_provider: Callable[[], VoiceActivity | None] | None = None,
) -> LiveKitRecitationWorker:
    return LiveKitRecitationWorker(
        corpus=corpus,
        recognizer=recognizer_factory(),
        publisher=publisher,
        minimum_lock_words=minimum_lock_words,
        session_id=session_id,
        voice_activity_provider=voice_activity_provider,
    )


class LiveKitTrackTaskRegistry:
    def __init__(self) -> None:
        self._tasks: dict[str, asyncio.Task] = {}

    @property
    def active_count(self) -> int:
        return len(self._tasks)

    def add(self, track_sid: str, task: asyncio.Task) -> None:
        self.cancel(track_sid)
        self._tasks[track_sid] = task
        task.add_done_callback(lambda _: self._tasks.pop(track_sid, None))

    def cancel(self, track_sid: str) -> None:
        task = self._tasks.pop(track_sid, None)
        if task is not None:
            task.cancel()

    def cancel_all(self) -> None:
        for track_sid in tuple(self._tasks):
            self.cancel(track_sid)


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


def audio_frame_to_chunk(
    frame: Any,
    *,
    sequence_number: int,
    voice_activity: VoiceActivity | None = None,
) -> AudioChunk:
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
        voice_activity=voice_activity,
    )


def voice_activity_from_livekit_data(
    payload: Any,
    *,
    topic: str | None = None,
) -> VoiceActivity | None:
    resolved_topic = topic if topic is not None else getattr(payload, "topic", VOICE_ACTIVITY_TOPIC)
    if resolved_topic != VOICE_ACTIVITY_TOPIC:
        return None
    payload = getattr(payload, "data", payload)
    try:
        raw = json.loads(payload.decode("utf-8") if isinstance(payload, bytes) else payload)
    except (UnicodeDecodeError, json.JSONDecodeError, TypeError):
        return None
    if not isinstance(raw, dict):
        return None
    voice_activity = raw.get("voice_activity")
    if not isinstance(voice_activity, dict):
        return None
    try:
        return VoiceActivity(
            probability=voice_activity.get("probability"),
            is_speech_active=voice_activity.get("is_speech_active"),
            event=voice_activity.get("event"),
        )
    except ValueError:
        return None


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
    recognizer_factory = _recognizer_factory_for_livekit_worker(
        asr_settings,
        fake_transcripts=fake_transcripts,
    )

    room = rtc.Room()
    track_tasks = LiveKitTrackTaskRegistry()
    voice_activity_by_identity: dict[str, VoiceActivity] = {}
    worker_factory: Callable[[str], LiveKitRecitationWorker] | None = None

    @room.on("data_received")
    def on_data_received(data_packet, *args) -> None:
        topic = args[-1] if args and isinstance(args[-1], str) else None
        voice_activity = voice_activity_from_livekit_data(data_packet, topic=topic)
        if voice_activity is None:
            return
        participant = getattr(data_packet, "participant", None)
        if participant is None and args:
            participant = args[0]
        identity = getattr(participant, "identity", None)
        if identity is None:
            return
        voice_activity_by_identity[str(identity)] = voice_activity

    @room.on("track_subscribed")
    def on_track_subscribed(track, publication, participant) -> None:
        if track.kind != rtc.TrackKind.KIND_AUDIO:
            return
        if worker_factory is None:
            logger.warning("livekit_worker received audio track before worker initialization")
            return
        logger.warning(
            "livekit_worker subscribed audio track=%s participant=%s",
            publication.sid,
            participant.identity,
        )
        session_id = str(participant.identity)
        task = asyncio.create_task(_consume_audio_stream(
            rtc.AudioStream(track),
            worker_factory(session_id),
        ))
        track_tasks.add(publication.sid, task)

    @room.on("track_unsubscribed")
    def on_track_unsubscribed(track, publication, participant) -> None:
        track_tasks.cancel(publication.sid)

    token = livekit_token_response(
        settings=settings,
        identity=worker_identity,
        role="worker",
    )["token"]
    await room.connect(settings.url, token)
    worker_factory = lambda session_id: create_livekit_recitation_worker(
        corpus=corpus,
        recognizer_factory=recognizer_factory,
        publisher=room.local_participant,
        minimum_lock_words=asr_settings.minimum_lock_words,
        session_id=session_id,
        voice_activity_provider=lambda session_id=session_id: voice_activity_by_identity.get(session_id),
    )
    logger.warning("livekit_worker connected url=%s room=%s", settings.url, settings.room_name)

    try:
        await asyncio.Event().wait()
    finally:
        track_tasks.cancel_all()
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
