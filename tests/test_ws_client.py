import asyncio
import base64
import json
import unittest

from tarteel_realtime.ws_client import (
    build_chunk_payload,
    collect_audio_events,
    collect_events,
    format_event,
    split_pcm_audio,
)
from tarteel_realtime.asr_smoke import SmokeAudio


class FakeWebSocket:
    def __init__(self, events):
        self.sent_payloads = []
        self._events = list(events)

    async def send(self, payload):
        self.sent_payloads.append(json.loads(payload))

    async def recv(self):
        return json.dumps(self._events.pop(0))


class WebSocketClientTests(unittest.TestCase):
    def test_builds_base64_audio_chunk_payload(self):
        payload = build_chunk_payload(
            sequence_number=7,
            pcm=b"\x00\x01",
            sample_rate_hz=16_000,
        )

        self.assertEqual(payload["sequence_number"], 7)
        self.assertEqual(payload["pcm_base64"], base64.b64encode(b"\x00\x01").decode("ascii"))
        self.assertEqual(payload["sample_rate_hz"], 16_000)

    def test_collects_events_for_scripted_dummy_chunks(self):
        websocket = FakeWebSocket([
            {"type": "locked", "start_ref": "114:2:1"},
            {"type": "wrong", "expected_ref": "114:2:2"},
        ])

        events = asyncio.run(collect_events(
            websocket,
            chunk_count=2,
            sample_rate_hz=16_000,
        ))

        self.assertEqual(
            [payload["sequence_number"] for payload in websocket.sent_payloads],
            [0, 1],
        )
        self.assertEqual([event["type"] for event in events], ["locked", "wrong"])

    def test_splits_pcm_audio_into_even_sized_duration_chunks(self):
        audio = SmokeAudio(
            pcm=b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09",
            sample_rate_hz=1_000,
        )

        chunks = split_pcm_audio(audio, chunk_duration_ms=2)

        self.assertEqual(chunks, [
            b"\x00\x01\x02\x03",
            b"\x04\x05\x06\x07",
            b"\x08\x09",
        ])

    def test_audio_chunk_split_defaults_to_one_whole_file_chunk(self):
        audio = SmokeAudio(pcm=b"\x00\x01\x02\x03", sample_rate_hz=16_000)

        self.assertEqual(split_pcm_audio(audio, chunk_duration_ms=None), [audio.pcm])

    def test_collects_events_for_real_audio_bytes(self):
        websocket = FakeWebSocket([
            {"type": "locked", "start_ref": "114:2:1"},
            {"type": "progress", "next_expected_ref": "114:2:2"},
        ])
        audio = SmokeAudio(pcm=b"\x00\x01\x02\x03", sample_rate_hz=1_000)

        events = asyncio.run(collect_audio_events(
            websocket,
            audio=audio,
            chunk_duration_ms=1,
        ))

        self.assertEqual(
            [payload["pcm_base64"] for payload in websocket.sent_payloads],
            [
                base64.b64encode(b"\x00\x01").decode("ascii"),
                base64.b64encode(b"\x02\x03").decode("ascii"),
            ],
        )
        self.assertEqual([event["type"] for event in events], ["locked", "progress"])

    def test_formats_event_as_compact_json_line(self):
        line = format_event({"type": "wrong", "expected_ref": "114:2:2"})

        self.assertEqual(line, '{"expected_ref":"114:2:2","type":"wrong"}')


if __name__ == "__main__":
    unittest.main()
