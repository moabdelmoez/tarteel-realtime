import asyncio
import json
import struct
import unittest
from types import SimpleNamespace

import tarteel_realtime.livekit_worker as livekit_worker_module
from tarteel_realtime.livekit_smoke import (
    recitation_payload_from_data_packet,
    sine_pcm16_frame,
)
from tarteel_realtime.livekit_worker import (
    FAKE_TRANSCRIPTS_ENV,
    RECITATION_EVENT_TOPIC,
    VOICE_ACTIVITY_TOPIC,
    LiveKitRecitationWorker,
    LiveKitTrackTaskRegistry,
    RepeatingFakeRecognizer,
    audio_frame_to_chunk,
    create_livekit_recitation_worker,
    fake_transcripts_from_env,
    voice_activity_from_livekit_data,
    _recognizer_factory_for_livekit_worker,
)
from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recognition import FakeRecognizer
from tarteel_realtime.recognition import AudioChunk


SAMPLE_TANZIL_LINES = [
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
]


class FakeAudioFrame:
    def __init__(self, samples, *, sample_rate=48_000, channels=1):
        self.data = memoryview(struct.pack(f"<{len(samples)}h", *samples)).cast("h")
        self.sample_rate = sample_rate
        self.num_channels = channels
        self.samples_per_channel = len(samples) // channels


class RecordingPublisher:
    def __init__(self):
        self.published = []

    async def publish_data(self, payload, *, reliable, topic):
        self.published.append({
            "payload": payload,
            "reliable": reliable,
            "topic": topic,
        })


class FailingRecognizer:
    def recognize(self, chunk: AudioChunk):
        raise RuntimeError("CUDA error: device-side assert triggered")


class RecordingRecognizer:
    def __init__(self):
        self.chunks = []

    def recognize(self, chunk: AudioChunk):
        self.chunks.append(chunk)
        return FakeRecognizer(["مَلِكِ"]).recognize(chunk)


class LiveKitWorkerTests(unittest.IsolatedAsyncioTestCase):
    def test_audio_frame_to_chunk_preserves_mono_pcm16(self):
        frame = FakeAudioFrame([100, -100], sample_rate=16_000)

        chunk = audio_frame_to_chunk(frame, sequence_number=7)

        self.assertEqual(chunk.sequence_number, 7)
        self.assertEqual(chunk.sample_rate_hz, 16_000)
        self.assertEqual(chunk.pcm, struct.pack("<hh", 100, -100))

    def test_audio_frame_to_chunk_downmixes_stereo_to_mono(self):
        frame = FakeAudioFrame([100, 300, -100, -300], channels=2)

        chunk = audio_frame_to_chunk(frame, sequence_number=0)

        self.assertEqual(chunk.pcm, struct.pack("<hh", 200, -200))

    def test_audio_frame_to_chunk_accepts_client_vad_metadata(self):
        voice_activity = voice_activity_from_livekit_data(json.dumps({
            "sequence_number": 7,
            "voice_activity": {
                "probability": 0.82,
                "is_speech_active": True,
                "event": "speech_start",
            },
        }).encode("utf-8"))

        chunk = audio_frame_to_chunk(
            FakeAudioFrame([1000, -1000], sample_rate=16_000),
            sequence_number=7,
            voice_activity=voice_activity,
        )

        self.assertIsNotNone(chunk.voice_activity)
        self.assertEqual(chunk.voice_activity.probability, 0.82)
        self.assertTrue(chunk.voice_activity.is_speech_active)
        self.assertEqual(chunk.voice_activity.event, "speech_start")

    def test_ignores_non_vad_livekit_data_topics(self):
        self.assertIsNone(voice_activity_from_livekit_data(
            json.dumps({"voice_activity": {"is_speech_active": True}}).encode("utf-8"),
            topic="other.topic",
        ))

    def test_decodes_livekit_vad_data_topic(self):
        voice_activity = voice_activity_from_livekit_data(
            json.dumps({
                "voice_activity": {
                    "probability": 0.34,
                    "is_speech_active": False,
                    "event": "speech_end",
                },
            }).encode("utf-8"),
            topic=VOICE_ACTIVITY_TOPIC,
        )

        self.assertIsNotNone(voice_activity)
        self.assertEqual(voice_activity.probability, 0.34)
        self.assertFalse(voice_activity.is_speech_active)
        self.assertEqual(voice_activity.event, "speech_end")

    def test_decodes_livekit_vad_data_packet_object(self):
        packet = SimpleNamespace(
            topic=VOICE_ACTIVITY_TOPIC,
            data=json.dumps({
                "voice_activity": {
                    "probability": 0.77,
                    "is_speech_active": True,
                },
            }).encode("utf-8"),
            participant=SimpleNamespace(identity="ios-reciter-123"),
        )

        voice_activity = voice_activity_from_livekit_data(packet)

        self.assertIsNotNone(voice_activity)
        self.assertEqual(voice_activity.probability, 0.77)
        self.assertTrue(voice_activity.is_speech_active)

    async def test_worker_publishes_recitation_event_for_audio_frame(self):
        publisher = RecordingPublisher()
        worker = LiveKitRecitationWorker(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer=FakeRecognizer(["مَلِكِ"]),
            publisher=publisher,
            minimum_lock_words=1,
            session_id="ios-reciter-123",
        )

        await worker.handle_audio_frame(FakeAudioFrame([1000, -1000], sample_rate=16_000))

        self.assertEqual(len(publisher.published), 1)
        published = publisher.published[0]
        self.assertEqual(published["topic"], RECITATION_EVENT_TOPIC)
        self.assertTrue(published["reliable"])
        event = json.loads(published["payload"].decode("utf-8"))
        self.assertEqual(event["type"], "locked")
        self.assertEqual(event["ayah_ref"], "114:2")
        self.assertEqual(event["chunk_sequence"], 0)
        self.assertEqual(event["session_id"], "ios-reciter-123")

    async def test_worker_attaches_latest_client_vad_to_audio_frame(self):
        publisher = RecordingPublisher()
        recognizer = RecordingRecognizer()
        voice_activity = voice_activity_from_livekit_data(json.dumps({
            "voice_activity": {
                "probability": 0.91,
                "is_speech_active": True,
                "event": "speech_start",
            },
        }).encode("utf-8"))
        worker = LiveKitRecitationWorker(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer=recognizer,
            publisher=publisher,
            minimum_lock_words=1,
            voice_activity_provider=lambda: voice_activity,
        )

        await worker.handle_audio_frame(FakeAudioFrame([1000, -1000], sample_rate=16_000))

        self.assertEqual(len(recognizer.chunks), 1)
        self.assertIsNotNone(recognizer.chunks[0].voice_activity)
        self.assertEqual(recognizer.chunks[0].voice_activity.probability, 0.91)
        self.assertTrue(recognizer.chunks[0].voice_activity.is_speech_active)

    async def test_worker_publishes_uncertain_event_when_asr_raises(self):
        publisher = RecordingPublisher()
        worker = LiveKitRecitationWorker(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer=FailingRecognizer(),
            publisher=publisher,
            minimum_lock_words=1,
        )

        await worker.handle_audio_frame(FakeAudioFrame([1000, -1000], sample_rate=16_000))

        self.assertEqual(len(publisher.published), 1)
        event = json.loads(publisher.published[0]["payload"].decode("utf-8"))
        self.assertEqual(event["type"], "uncertain")
        self.assertEqual(event["reason"], "asr_error")
        self.assertEqual(event["chunk_sequence"], 0)

    async def test_worker_factory_creates_fresh_session_for_each_audio_track(self):
        recognizer_calls = 0

        def recognizer_factory():
            nonlocal recognizer_calls
            recognizer_calls += 1
            return FakeRecognizer(["مَلِكِ"])

        publisher = RecordingPublisher()
        corpus = QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES)
        first_worker = create_livekit_recitation_worker(
            corpus=corpus,
            recognizer_factory=recognizer_factory,
            publisher=publisher,
            minimum_lock_words=1,
            session_id="first-client",
        )
        second_worker = create_livekit_recitation_worker(
            corpus=corpus,
            recognizer_factory=recognizer_factory,
            publisher=publisher,
            minimum_lock_words=1,
            session_id="second-client",
        )

        await first_worker.handle_audio_frame(FakeAudioFrame([1000], sample_rate=16_000))
        await second_worker.handle_audio_frame(FakeAudioFrame([1000], sample_rate=16_000))

        events = [
            json.loads(published["payload"].decode("utf-8"))
            for published in publisher.published
        ]
        self.assertEqual(recognizer_calls, 2)
        self.assertEqual([event["type"] for event in events], ["locked", "locked"])
        self.assertEqual([event["chunk_sequence"] for event in events], [0, 0])
        self.assertEqual([event["session_id"] for event in events], ["first-client", "second-client"])

    async def test_track_task_registry_cancels_task_when_track_unsubscribes(self):
        registry = LiveKitTrackTaskRegistry()
        started = asyncio.Event()

        async def long_running_task():
            started.set()
            await asyncio.Event().wait()

        task = asyncio.create_task(long_running_task())
        registry.add("track-1", task)
        await started.wait()

        self.assertEqual(registry.active_count, 1)
        registry.cancel("track-1")
        await asyncio.sleep(0)

        self.assertTrue(task.cancelled())
        self.assertEqual(registry.active_count, 0)

    def test_fake_transcripts_from_env_uses_pipe_delimited_script(self):
        transcripts = fake_transcripts_from_env({
            FAKE_TRANSCRIPTS_ENV: " مَلِكِ | النَّاسِ || ",
        })

        self.assertEqual(transcripts, ["مَلِكِ", "النَّاسِ"])

    def test_worker_recognizer_factory_can_use_fake_transcripts_for_smoke(self):
        recognizer = _recognizer_factory_for_livekit_worker(
            object(),
            fake_transcripts=["مَلِكِ"],
        )()

        self.assertIsInstance(recognizer, RepeatingFakeRecognizer)

    def test_repeating_fake_recognizer_reuses_last_transcript_after_script(self):
        recognizer = RepeatingFakeRecognizer(["مَلِكِ"])

        first = recognizer.recognize(audio_frame_to_chunk(
            FakeAudioFrame([1], sample_rate=16_000),
            sequence_number=0,
        ))
        second = recognizer.recognize(audio_frame_to_chunk(
            FakeAudioFrame([2], sample_rate=16_000),
            sequence_number=1,
        ))

        self.assertEqual(first.transcript, "مَلِكِ")
        self.assertEqual(second.transcript, "مَلِكِ")

    def test_smoke_sine_frame_is_pcm16_at_requested_duration(self):
        frame = sine_pcm16_frame(sample_rate=16_000, duration_ms=20)

        self.assertEqual(len(frame), 16_000 * 20 // 1_000 * 2)

    def test_smoke_ignores_unrelated_livekit_data_topics(self):
        packet = SimpleNamespace(topic="other.topic", data=b"{}")

        self.assertIsNone(recitation_payload_from_data_packet(packet))

    def test_smoke_decodes_recitation_event_data_packet(self):
        packet = SimpleNamespace(
            topic=RECITATION_EVENT_TOPIC,
            data=json.dumps({"type": "locked"}).encode("utf-8"),
        )

        self.assertEqual(
            recitation_payload_from_data_packet(packet),
            {"type": "locked"},
        )


if __name__ == "__main__":
    unittest.main()
