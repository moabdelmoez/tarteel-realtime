import json
from pathlib import Path
import tempfile
import unittest
import wave

from tarteel_realtime.asr_smoke import AudioInputError
from tarteel_realtime.replay_probe import (
    ReplayProbeResult,
    TimedEvent,
    format_summary,
    load_replay_audio_file,
    summarize_probe_result,
    url_with_asr_model,
    url_with_scope,
)


class ReplayProbeTests(unittest.TestCase):
    def write_wav(
        self,
        path: Path,
        *,
        channels: int,
        frames: bytes,
        sample_rate: int = 44_100,
        sample_width: int = 2,
    ) -> None:
        with wave.open(str(path), "wb") as wav_file:
            wav_file.setnchannels(channels)
            wav_file.setsampwidth(sample_width)
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(frames)

    def test_load_replay_audio_file_downmixes_stereo_pcm16_wav_to_mono(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            audio_path = Path(temp_dir) / "stereo.wav"
            self.write_wav(
                audio_path,
                channels=2,
                frames=(
                    b"\x00\x00\x00\x40"
                    b"\x00\x80\x00\x00"
                ),
            )

            audio = load_replay_audio_file(audio_path, raw_sample_rate_hz=16_000)

        self.assertEqual(audio.sample_rate_hz, 44_100)
        self.assertEqual(audio.pcm, b"\x00\x20\x00\xc0")

    def test_load_replay_audio_file_preserves_asr_smoke_strictness(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            audio_path = Path(temp_dir) / "stereo.wav"
            self.write_wav(audio_path, channels=2, frames=b"\x00\x00\x00\x00")

            from tarteel_realtime.asr_smoke import load_audio_file

            with self.assertRaises(AudioInputError):
                load_audio_file(audio_path, raw_sample_rate_hz=16_000)

    def test_url_with_scope_adds_scope_and_preserves_other_query_items(self) -> None:
        self.assertEqual(
            url_with_scope(
                "wss://example.modal.run/ws/recitation?debug=1",
                "108",
            ),
            "wss://example.modal.run/ws/recitation?debug=1&scope=108",
        )

    def test_url_with_scope_replaces_existing_scope(self) -> None:
        self.assertEqual(
            url_with_scope(
                "wss://example.modal.run/ws/recitation?scope=4&debug=1",
                "108",
            ),
            "wss://example.modal.run/ws/recitation?debug=1&scope=108",
        )

    def test_url_with_asr_model_adds_model_and_preserves_scope(self) -> None:
        self.assertEqual(
            url_with_asr_model(
                "wss://example.modal.run/ws/recitation?scope=108",
                "faster-whisper-base-ar-quran",
            ),
            "wss://example.modal.run/ws/recitation?scope=108&asr_model=faster-whisper-base-ar-quran",
        )

    def test_url_with_asr_model_replaces_existing_model(self) -> None:
        self.assertEqual(
            url_with_asr_model(
                "wss://example.modal.run/ws/recitation?asr_model=old&debug=1",
                "nemo-fastconformer-quran-ar",
            ),
            "wss://example.modal.run/ws/recitation?debug=1&asr_model=nemo-fastconformer-quran-ar",
        )

    def test_summarizes_first_non_wait_event_and_lock_ref(self) -> None:
        result = ReplayProbeResult(
            url="wss://example.modal.run/ws/recitation?scope=108",
            audio_path="fixtures/local_audio/108001.wav",
            chunk_ms=1000,
            connect_ms=1200,
            total_ms=4600,
            timed_events=(
                TimedEvent(
                    event={"type": "locating", "reason": "waiting_for_audio_buffer"},
                    elapsed_ms=1500,
                ),
                TimedEvent(
                    event={
                        "type": "locked",
                        "reason": "unique_match",
                        "ayah_ref": "108:1",
                        "start_ref": "108:1:1",
                    },
                    elapsed_ms=3200,
                ),
                TimedEvent(
                    event={"type": "progress", "next_expected_ref": "108:1:3"},
                    elapsed_ms=4300,
                ),
            ),
        )

        summary = summarize_probe_result(result)

        self.assertEqual(summary["connect_ms"], 1200)
        self.assertEqual(summary["total_ms"], 4600)
        self.assertEqual(summary["event_count"], 3)
        self.assertEqual(summary["event_type_counts"], {"locating": 1, "locked": 1, "progress": 1})
        self.assertEqual(summary["first_event_ms"], 1500)
        self.assertEqual(summary["first_non_wait_event_ms"], 3200)
        self.assertEqual(summary["first_non_wait_event_type"], "locked")
        self.assertEqual(summary["first_lock_ref"], "108:1")
        self.assertEqual(summary["first_progress_next_expected_ref"], "108:1:3")

    def test_can_include_raw_events_for_evidence_capture(self) -> None:
        result = ReplayProbeResult(
            url="wss://example.modal.run/ws/recitation",
            audio_path="fixtures/local_audio/108001.wav",
            chunk_ms=1000,
            connect_ms=1,
            total_ms=2,
            timed_events=(TimedEvent(event={"type": "uncertain"}, elapsed_ms=2),),
        )

        summary = summarize_probe_result(result, include_events=True)

        self.assertEqual(summary["events"], [{"type": "uncertain"}])
        self.assertEqual(summary["event_timings_ms"], [2])

    def test_formats_summary_as_compact_json(self) -> None:
        line = format_summary({"event_count": 1, "first_lock_ref": "108:1"})

        self.assertEqual(
            json.loads(line),
            {"event_count": 1, "first_lock_ref": "108:1"},
        )
        self.assertNotIn(" ", line)


if __name__ == "__main__":
    unittest.main()
