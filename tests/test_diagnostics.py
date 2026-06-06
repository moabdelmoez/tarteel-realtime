import unittest

from tarteel_realtime.diagnostics import (
    BUFFER_ACTION_APPEND_WAIT_MIN_AUDIO,
    DiagnosticTraceCollector,
    current_diagnostic_context,
    diagnostic_asr_context,
)


class FakeClock:
    def __init__(self, values):
        self._values = iter(values)

    def __call__(self):
        return next(self._values)


class DiagnosticTraceCollectorTests(unittest.TestCase):
    def test_builds_recitation_trace_envelope_for_one_chunk(self):
        collector = DiagnosticTraceCollector(clock=FakeClock([10.000, 10.030]))
        collector.begin_chunk(
            sequence_number=4,
            pcm_bytes=32_000,
            sample_rate_hz=16_000,
            voice_activity={
                "probability": 0.88,
                "is_speech_active": True,
                "event": "speech_start",
            },
        )
        collector.record_buffer_action(
            sequence_number=4,
            action=BUFFER_ACTION_APPEND_WAIT_MIN_AUDIO,
            incoming_rms=900,
            buffered_ms_before=0,
            buffered_ms_after=1000,
            unflushed_ms_after=1000,
            appended=True,
            appended_segments=[
                {"sequence_number": 4, "start_byte": 0, "end_byte": 32_000}
            ],
        )

        envelope = collector.envelope(
            {"type": "locating", "reason": "waiting_for_audio_buffer"}
        )

        self.assertEqual(envelope["kind"], "recitation_trace")
        self.assertEqual(envelope["event"]["type"], "locating")
        self.assertEqual(envelope["trace"]["sequence_number"], 4)
        self.assertEqual(envelope["trace"]["backend_receive_offset_ms"], 0)
        self.assertEqual(envelope["trace"]["backend_response_offset_ms"], 30)
        self.assertEqual(
            envelope["trace"]["buffer"]["action"],
            "append_wait_min_audio",
        )
        self.assertEqual(envelope["trace"]["audio"]["pcm_bytes"], 32_000)
        self.assertEqual(envelope["trace"]["voice_activity"]["probability"], 0.88)

    def test_asr_context_sets_current_diagnostic_context(self):
        collector = DiagnosticTraceCollector(clock=FakeClock([20.000]))

        self.assertIsNone(current_diagnostic_context())
        with diagnostic_asr_context(collector, window_id=3):
            context = current_diagnostic_context()
            self.assertIsNotNone(context)
            self.assertIs(context.collector, collector)
            self.assertEqual(context.window_id, 3)
        self.assertIsNone(current_diagnostic_context())

    def test_finish_asr_window_adds_timing_and_transcript_to_trace(self):
        collector = DiagnosticTraceCollector(
            clock=FakeClock([30.000, 30.010, 30.045])
        )
        collector.begin_chunk(
            sequence_number=7,
            pcm_bytes=64_000,
            sample_rate_hz=16_000,
            voice_activity=None,
        )
        window_id = collector.begin_asr_window(
            triggering_sequence_number=7,
            segments=[{"sequence_number": 6, "start_byte": 0, "end_byte": 32_000}],
            audio_ms=1000,
            pcm_bytes=32_000,
            buffered_rms=1200,
            tail_audio_ms=0,
        )

        with diagnostic_asr_context(collector, window_id):
            context = current_diagnostic_context()
            self.assertIsNotNone(context)
            context.collector.record_asr_inference(
                context.window_id,
                duration_ms=35,
            )
        collector.record_recognizer_init(window_id, duration_ms=12)
        collector.finish_asr_window(
            window_id,
            transcript="مَلِكِ النَّاسِ",
            confidence=0.9,
            is_final=True,
            total_duration_ms=60,
        )

        envelope = collector.envelope({"type": "locked", "reason": "unique_match"})

        self.assertEqual(envelope["trace"]["asr_window"]["id"], 0)
        self.assertEqual(envelope["trace"]["asr_window"]["start_offset_ms"], 10)
        self.assertTrue(envelope["trace"]["asr_window"]["cold_start"])
        self.assertEqual(envelope["trace"]["asr_window"]["recognizer_init_ms"], 12)
        self.assertEqual(envelope["trace"]["asr_window"]["asr_inference_ms"], 35)
        self.assertEqual(envelope["trace"]["asr_window"]["asr_total_ms"], 60)
        self.assertEqual(
            envelope["trace"]["asr_window"]["transcript"],
            "مَلِكِ النَّاسِ",
        )
        self.assertEqual(envelope["trace"]["asr_window"]["confidence"], 0.9)
        self.assertTrue(envelope["trace"]["asr_window"]["is_final"])

    def test_record_decision_adds_decision_payload_to_trace(self):
        collector = DiagnosticTraceCollector(clock=FakeClock([40.000, 40.020]))
        collector.begin_chunk(
            sequence_number=8,
            pcm_bytes=16_000,
            sample_rate_hz=16_000,
            voice_activity=None,
        )

        collector.record_decision(
            {"mode": "initial_location", "status": "ambiguous", "candidate_count": 2}
        )
        envelope = collector.envelope({"type": "lock_candidate"})

        self.assertEqual(
            envelope["trace"]["decision"],
            {
                "mode": "initial_location",
                "status": "ambiguous",
                "candidate_count": 2,
            },
        )


if __name__ == "__main__":
    unittest.main()
