import json
import struct
import unittest
from types import SimpleNamespace

from tarteel_realtime.livekit_smoke import (
    recitation_payload_from_data_packet,
    sine_pcm16_frame,
)
from tarteel_realtime.livekit_worker import (
    FAKE_TRANSCRIPTS_ENV,
    RECITATION_EVENT_TOPIC,
    LiveKitRecitationWorker,
    RepeatingFakeRecognizer,
    audio_frame_to_chunk,
    fake_transcripts_from_env,
    _recognizer_factory_for_livekit_worker,
)
from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recognition import FakeRecognizer


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

    async def test_worker_publishes_recitation_event_for_audio_frame(self):
        publisher = RecordingPublisher()
        worker = LiveKitRecitationWorker(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer=FakeRecognizer(["مَلِكِ"]),
            publisher=publisher,
            minimum_lock_words=1,
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
