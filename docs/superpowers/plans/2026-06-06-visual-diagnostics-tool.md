# Visual Diagnostics Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a replay-based visual diagnostics bundle generator for realtime recitation performance analysis.

**Architecture:** Keep normal `/ws/recitation` unchanged and add an opt-in `?diagnostics=1` trace envelope. Use a diagnostic collector side channel based on context variables so the existing recognizer and session return types stay stable. Generate a local ignored bundle with WAV artifacts, trace JSON, and static no-build HTML.

**Tech Stack:** Python standard library, FastAPI WebSocket query params, existing `websockets` optional CLI dependency, `uv`, `unittest`, static HTML/CSS/JS.

---

## File Structure

- Modify `.gitignore`: ignore generated `diagnostics/` bundles.
- Create `tarteel_realtime/diagnostics.py`: diagnostic collector, current-context helpers, buffering action constants, and envelope construction.
- Modify `tarteel_realtime/buffered_recognition.py`: emit keep/drop/buffer/flush actions, ASR window ids, kept segment ranges, and ASR total timing through the optional collector context.
- Modify `tarteel_realtime/asr_runtime.py`: record lazy recognizer cold-start/init timing when a diagnostic ASR context is active.
- Modify `tarteel_realtime/whisper_adapter.py`: record ASR backend inference timing when a diagnostic ASR context is active.
- Modify `tarteel_realtime/session_transitions.py`: record decision-level locator/alignment diagnostics through the optional collector context.
- Modify `tarteel_realtime/recitation_stream.py`: create a collector per chunk when diagnostics are enabled and return an optional trace envelope alongside the normal event payload.
- Modify `tarteel_realtime/api.py`: parse `diagnostics=1` and send trace envelopes only for diagnostic WebSocket connections.
- Create `tarteel_realtime/diagnostics_bundle.py`: write bundle folders, WAV files, peak arrays, `trace.json`, `index.html`, CSS, and JS.
- Create `tarteel_realtime/diagnostics_capture.py`: replay WAV/PCM16 audio in real-time sequential mode, require diagnostic envelopes, merge client timings, reconstruct audio artifacts, and print the generated HTML path.
- Modify `tests/test_api.py`: verify normal payload compatibility and diagnostic envelope shape.
- Modify `tests/test_buffered_recognition.py`: verify buffering trace actions and ASR segment metadata.
- Modify `tests/test_recitation_stream.py`: verify trace data is available without changing normal payload behavior.
- Create `tests/test_diagnostics_capture.py`: verify bundle generation and fail-fast behavior when the backend returns normal events.
- Create `tests/test_diagnostics_bundle.py`: verify WAV writing, peak generation, HTML trace inlining, and secret scrubbing.
- Modify `README.md`: add a short diagnostic replay usage section after the existing replay probe docs.
- Modify `codex-progress.md` and `session-handoff.md`: record the implementation and verification evidence at the end of the slice.

---

### Task 1: Diagnostic Collector Core

**Files:**
- Create: `tarteel_realtime/diagnostics.py`
- Create: `tests/test_diagnostics.py`

- [ ] **Step 1: Write the failing collector behavior tests**

Add `tests/test_diagnostics.py`:

```python
import unittest

from tarteel_realtime.diagnostics import (
    BUFFER_ACTION_APPEND_WAIT_MIN_AUDIO,
    BUFFER_ACTION_FLUSH_ASR,
    DiagnosticTraceCollector,
    diagnostic_asr_context,
    current_diagnostic_context,
)


class FakeClock:
    def __init__(self, values):
        self._values = iter(values)

    def __call__(self):
        return next(self._values)


class DiagnosticTraceCollectorTests(unittest.TestCase):
    def test_builds_recitation_trace_envelope_for_one_chunk(self):
        collector = DiagnosticTraceCollector(clock=FakeClock([10.000, 10.015, 10.030]))
        collector.begin_chunk(
            sequence_number=4,
            pcm_bytes=32_000,
            sample_rate_hz=16_000,
            voice_activity={"probability": 0.88, "is_speech_active": True, "event": "speech_start"},
        )
        collector.record_buffer_action(
            sequence_number=4,
            action=BUFFER_ACTION_APPEND_WAIT_MIN_AUDIO,
            incoming_rms=900,
            buffered_ms_before=0,
            buffered_ms_after=1000,
            unflushed_ms_after=1000,
            appended=True,
            appended_segments=[{"sequence_number": 4, "start_byte": 0, "end_byte": 32000}],
        )

        envelope = collector.envelope({"type": "locating", "reason": "waiting_for_audio_buffer"})

        self.assertEqual(envelope["kind"], "recitation_trace")
        self.assertEqual(envelope["event"]["type"], "locating")
        self.assertEqual(envelope["trace"]["sequence_number"], 4)
        self.assertEqual(envelope["trace"]["buffer"]["action"], "append_wait_min_audio")
        self.assertEqual(envelope["trace"]["audio"]["pcm_bytes"], 32000)
        self.assertEqual(envelope["trace"]["voice_activity"]["probability"], 0.88)

    def test_asr_context_records_window_id_for_nested_timing(self):
        collector = DiagnosticTraceCollector(clock=FakeClock([20.000, 20.025, 20.060]))
        collector.begin_chunk(sequence_number=7, pcm_bytes=64_000, sample_rate_hz=16_000, voice_activity=None)
        window_id = collector.begin_asr_window(
            triggering_sequence_number=7,
            segments=[{"sequence_number": 6, "start_byte": 0, "end_byte": 32000}],
            audio_ms=1000,
            pcm_bytes=32000,
            buffered_rms=1200,
            tail_audio_ms=0,
        )

        with diagnostic_asr_context(collector, window_id):
            context = current_diagnostic_context()
            self.assertIsNotNone(context)
            self.assertEqual(context.window_id, window_id)
            context.collector.record_asr_inference(window_id, duration_ms=35)

        collector.finish_asr_window(
            window_id,
            transcript="مَلِكِ النَّاسِ",
            confidence=0.9,
            is_final=True,
            total_duration_ms=60,
        )
        envelope = collector.envelope({"type": "locked", "reason": "unique_match"})

        self.assertEqual(envelope["trace"]["asr_window"]["id"], 0)
        self.assertEqual(envelope["trace"]["asr_window"]["asr_inference_ms"], 35)
        self.assertEqual(envelope["trace"]["asr_window"]["asr_total_ms"], 60)
        self.assertEqual(envelope["trace"]["asr_window"]["transcript"], "مَلِكِ النَّاسِ")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify the red state**

Run:

```bash
uv run python -B -m unittest tests.test_diagnostics -v
```

Expected: failure with `ModuleNotFoundError: No module named 'tarteel_realtime.diagnostics'`.

- [ ] **Step 3: Add the collector implementation**

Create `tarteel_realtime/diagnostics.py`:

```python
from __future__ import annotations

from collections.abc import Callable, Iterator
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass, field
from time import monotonic
from typing import Any


BUFFER_ACTION_DROP_VAD_OR_RMS = "drop_vad_or_rms"
BUFFER_ACTION_APPEND_WAIT_MIN_AUDIO = "append_wait_min_audio"
BUFFER_ACTION_APPEND_WAIT_FLUSH_INTERVAL = "append_wait_flush_interval"
BUFFER_ACTION_FLUSH_ASR = "flush_asr"
BUFFER_ACTION_DROP_QUIET_BUFFER = "drop_quiet_buffer"
BUFFER_ACTION_RESET_SAMPLE_RATE = "reset_sample_rate"


@dataclass(frozen=True)
class DiagnosticContext:
    collector: DiagnosticTraceCollector
    window_id: int


_CURRENT_DIAGNOSTIC_CONTEXT: ContextVar[DiagnosticContext | None] = ContextVar(
    "tarteel_current_diagnostic_context",
    default=None,
)


def current_diagnostic_context() -> DiagnosticContext | None:
    return _CURRENT_DIAGNOSTIC_CONTEXT.get()


@contextmanager
def diagnostic_asr_context(
    collector: DiagnosticTraceCollector,
    window_id: int,
) -> Iterator[None]:
    token = _CURRENT_DIAGNOSTIC_CONTEXT.set(DiagnosticContext(collector, window_id))
    try:
        yield
    finally:
        _CURRENT_DIAGNOSTIC_CONTEXT.reset(token)


@dataclass
class DiagnosticTraceCollector:
    clock: Callable[[], float] = monotonic
    _chunk: dict[str, Any] = field(default_factory=dict)
    _asr_windows: dict[int, dict[str, Any]] = field(default_factory=dict)
    _active_window_id: int | None = None
    _next_window_id: int = 0

    def begin_chunk(
        self,
        *,
        sequence_number: int,
        pcm_bytes: int,
        sample_rate_hz: int,
        voice_activity: dict[str, Any] | None,
    ) -> None:
        self._chunk = {
            "sequence_number": sequence_number,
            "backend_receive_offset_ms": self._now_ms(),
            "audio": {
                "pcm_bytes": pcm_bytes,
                "sample_rate_hz": sample_rate_hz,
            },
            "voice_activity": voice_activity,
            "buffer": None,
            "asr_window": None,
            "decision": None,
        }
        self._active_window_id = None

    def record_buffer_action(
        self,
        *,
        sequence_number: int,
        action: str,
        incoming_rms: int,
        buffered_ms_before: int,
        buffered_ms_after: int,
        unflushed_ms_after: int,
        appended: bool,
        appended_segments: list[dict[str, int]],
    ) -> None:
        self._chunk["buffer"] = {
            "sequence_number": sequence_number,
            "action": action,
            "incoming_rms": incoming_rms,
            "buffered_ms_before": buffered_ms_before,
            "buffered_ms_after": buffered_ms_after,
            "unflushed_ms_after": unflushed_ms_after,
            "appended": appended,
            "appended_segments": appended_segments,
        }

    def begin_asr_window(
        self,
        *,
        triggering_sequence_number: int,
        segments: list[dict[str, int]],
        audio_ms: int,
        pcm_bytes: int,
        buffered_rms: int,
        tail_audio_ms: int,
    ) -> int:
        window_id = self._next_window_id
        self._next_window_id += 1
        window = {
            "id": window_id,
            "triggering_sequence_number": triggering_sequence_number,
            "segments": segments,
            "audio_ms": audio_ms,
            "pcm_bytes": pcm_bytes,
            "buffered_rms": buffered_rms,
            "tail_audio_ms": tail_audio_ms,
            "cold_start": False,
            "recognizer_init_ms": None,
            "asr_inference_ms": None,
            "asr_total_ms": None,
            "transcript": "",
            "confidence": 0.0,
            "is_final": False,
        }
        self._asr_windows[window_id] = window
        self._chunk["asr_window"] = window
        self._active_window_id = window_id
        return window_id

    def record_recognizer_init(self, window_id: int, *, duration_ms: int) -> None:
        window = self._asr_windows[window_id]
        window["cold_start"] = True
        window["recognizer_init_ms"] = duration_ms

    def record_asr_inference(self, window_id: int, *, duration_ms: int) -> None:
        self._asr_windows[window_id]["asr_inference_ms"] = duration_ms

    def finish_asr_window(
        self,
        window_id: int,
        *,
        transcript: str,
        confidence: float,
        is_final: bool,
        total_duration_ms: int,
    ) -> None:
        window = self._asr_windows[window_id]
        window["transcript"] = transcript
        window["confidence"] = confidence
        window["is_final"] = is_final
        window["asr_total_ms"] = total_duration_ms

    def record_decision(self, decision: dict[str, Any]) -> None:
        self._chunk["decision"] = decision

    def envelope(self, event_payload: dict[str, Any]) -> dict[str, Any]:
        trace = dict(self._chunk)
        trace["backend_response_offset_ms"] = self._now_ms()
        return {
            "kind": "recitation_trace",
            "event": event_payload,
            "trace": trace,
        }

    def _now_ms(self) -> int:
        return int(round(self.clock() * 1_000))
```

- [ ] **Step 4: Run the collector tests to verify green**

Run:

```bash
uv run python -B -m unittest tests.test_diagnostics -v
```

Expected: `OK`.

- [ ] **Step 5: Commit**

Run:

```bash
git add tarteel_realtime/diagnostics.py tests/test_diagnostics.py
git commit -m "feat: add recitation diagnostic trace collector"
```

---

### Task 2: Opt-In Diagnostic WebSocket Envelope

**Files:**
- Modify: `tarteel_realtime/recitation_stream.py`
- Modify: `tarteel_realtime/api.py`
- Modify: `tests/test_api.py`
- Modify: `tests/test_recitation_stream.py`

- [ ] **Step 1: Add failing API tests for normal and diagnostic contracts**

Append to `tests/test_api.py`:

```python
    def test_diagnostics_query_returns_trace_envelope_without_changing_normal_socket(self):
        app = create_app(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer_factory=lambda: FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
        )
        client = TestClient(app)

        with client.websocket_connect("/ws/recitation") as websocket:
            websocket.send_json(chunk_payload(0))
            normal = websocket.receive_json()

        with client.websocket_connect("/ws/recitation?diagnostics=1") as websocket:
            websocket.send_json(chunk_payload(0))
            diagnostic = websocket.receive_json()

        self.assertEqual(normal["type"], "locked")
        self.assertNotIn("kind", normal)
        self.assertEqual(diagnostic["kind"], "recitation_trace")
        self.assertEqual(diagnostic["event"]["type"], "locked")
        self.assertEqual(diagnostic["trace"]["sequence_number"], 0)
        self.assertEqual(diagnostic["trace"]["audio"]["pcm_bytes"], 2)
```

- [ ] **Step 2: Add failing recitation stream trace test**

Append to `tests/test_recitation_stream.py`:

```python
    def test_process_chunk_can_return_diagnostic_envelope(self):
        stream = RecitationStream(
            corpus=QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES),
            recognizer=FakeRecognizer(["مَلِكِ"]),
            minimum_lock_words=1,
            diagnostics_enabled=True,
        )

        result = stream.process_chunk(chunk(0, pcm=struct.pack("<h", 1000)))

        self.assertEqual(result.payload["type"], "locked")
        self.assertIsNotNone(result.diagnostic_envelope)
        self.assertEqual(result.diagnostic_envelope["kind"], "recitation_trace")
        self.assertEqual(result.diagnostic_envelope["event"]["type"], "locked")
        self.assertEqual(result.diagnostic_envelope["trace"]["sequence_number"], 0)
```

`tests/test_recitation_stream.py` already defines `SAMPLE_TANZIL_LINES` and
`chunk`, so no additional helpers are needed for this test.

- [ ] **Step 3: Run tests to verify red**

Run:

```bash
uv run python -B -m unittest tests.test_api tests.test_recitation_stream -v
```

Expected: failures because `diagnostics_enabled` and `diagnostic_envelope` do not exist yet.

- [ ] **Step 4: Implement diagnostic envelope wiring**

Update `tarteel_realtime/recitation_stream.py`:

```python
from tarteel_realtime.diagnostics import DiagnosticTraceCollector
```

Extend `RecitationStreamResult`:

```python
@dataclass(frozen=True)
class RecitationStreamResult:
    event: SessionEvent
    payload: dict[str, Any]
    diagnostics: RecitationChunkDiagnostics
    diagnostic_envelope: dict[str, Any] | None = None
```

Extend `RecitationStream.__init__`:

```python
        diagnostics_enabled: bool = False,
    ) -> None:
        self._diagnostics_enabled = diagnostics_enabled
```

At the start of `process_chunk`, create a collector only when enabled:

```python
        diagnostic_collector = None
        if self._diagnostics_enabled:
            diagnostic_collector = DiagnosticTraceCollector()
            diagnostic_collector.begin_chunk(
                sequence_number=chunk.sequence_number,
                pcm_bytes=len(chunk.pcm),
                sample_rate_hz=chunk.sample_rate_hz,
                voice_activity=voice_activity_payload(chunk.voice_activity),
            )
```

After `payload = session_event_to_payload(...)`, build the envelope:

```python
        diagnostic_envelope = (
            None
            if diagnostic_collector is None
            else diagnostic_collector.envelope(payload)
        )
```

Return it in `RecitationStreamResult`.

Add this helper in `recitation_stream.py`:

```python
def voice_activity_payload(voice_activity) -> dict[str, Any] | None:
    if voice_activity is None:
        return None
    return {
        "probability": voice_activity.probability,
        "is_speech_active": voice_activity.is_speech_active,
        "event": voice_activity.event,
    }
```

Update `tarteel_realtime/api.py` inside `recitation_socket`:

```python
        diagnostics_enabled = websocket.query_params.get("diagnostics") == "1"
```

Pass it to `RecitationStream`:

```python
            diagnostics_enabled=diagnostics_enabled,
```

Send the envelope when enabled:

```python
                response_payload = (
                    result.diagnostic_envelope
                    if diagnostics_enabled
                    else result.payload
                )
                await websocket.send_json(response_payload)
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
uv run python -B -m unittest tests.test_api tests.test_recitation_stream -v
```

Expected: `OK`.

- [ ] **Step 6: Commit**

Run:

```bash
git add tarteel_realtime/recitation_stream.py tarteel_realtime/api.py tests/test_api.py tests/test_recitation_stream.py
git commit -m "feat: add opt-in recitation trace envelope"
```

---

### Task 3: Buffered Recognizer Trace Actions and ASR Window Segments

**Files:**
- Modify: `tarteel_realtime/buffered_recognition.py`
- Modify: `tarteel_realtime/recitation_stream.py`
- Modify: `tests/test_buffered_recognition.py`
- Modify: `tests/test_api.py`

- [ ] **Step 1: Add failing buffering action tests**

Append to `tests/test_buffered_recognition.py`:

```python
from tarteel_realtime.diagnostics import (
    BUFFER_ACTION_APPEND_WAIT_MIN_AUDIO,
    BUFFER_ACTION_DROP_VAD_OR_RMS,
    BUFFER_ACTION_FLUSH_ASR,
    DiagnosticTraceCollector,
)
```

Add tests:

```python
    def test_records_vad_or_rms_drop_action_when_chunk_is_not_buffered(self):
        inner = RecordingRecognizer()
        recognizer = BufferedRecognizer(
            inner,
            config=BufferedRecognitionConfig(
                minimum_audio_ms=2,
                flush_interval_ms=2,
                tail_audio_ms=0,
                minimum_frame_rms=150,
            ),
        )
        collector = DiagnosticTraceCollector(clock=lambda: 1.0)
        pcm = struct.pack("<h", 100)
        audio_chunk = chunk(0, pcm)
        collector.begin_chunk(
            sequence_number=audio_chunk.sequence_number,
            pcm_bytes=len(audio_chunk.pcm),
            sample_rate_hz=audio_chunk.sample_rate_hz,
            voice_activity=None,
        )

        result = recognizer.recognize(audio_chunk, diagnostic_collector=collector)
        envelope = collector.envelope({"type": "locating", "reason": result.transcript})

        self.assertEqual(result.transcript, "")
        self.assertEqual(envelope["trace"]["buffer"]["action"], BUFFER_ACTION_DROP_VAD_OR_RMS)
        self.assertFalse(envelope["trace"]["buffer"]["appended"])
        self.assertEqual(inner.chunks, [])

    def test_records_flush_asr_window_segments_when_buffer_flushes(self):
        inner = RecordingRecognizer()
        recognizer = BufferedRecognizer(
            inner,
            config=BufferedRecognitionConfig(
                minimum_audio_ms=2,
                flush_interval_ms=2,
                tail_audio_ms=0,
                minimum_frame_rms=0,
            ),
        )
        collector = DiagnosticTraceCollector(clock=lambda: 1.0)
        first = chunk(0, struct.pack("<h", 1000))
        second = chunk(1, struct.pack("<h", -1000))

        collector.begin_chunk(sequence_number=0, pcm_bytes=len(first.pcm), sample_rate_hz=first.sample_rate_hz, voice_activity=None)
        recognizer.recognize(first, diagnostic_collector=collector)
        first_envelope = collector.envelope({"type": "locating"})

        collector.begin_chunk(sequence_number=1, pcm_bytes=len(second.pcm), sample_rate_hz=second.sample_rate_hz, voice_activity=None)
        result = recognizer.recognize(second, diagnostic_collector=collector)
        second_envelope = collector.envelope({"type": "locked"})

        self.assertEqual(first_envelope["trace"]["buffer"]["action"], BUFFER_ACTION_APPEND_WAIT_MIN_AUDIO)
        self.assertEqual(second_envelope["trace"]["buffer"]["action"], BUFFER_ACTION_FLUSH_ASR)
        self.assertEqual(result.transcript, "flush-1")
        self.assertEqual(second_envelope["trace"]["asr_window"]["segments"], [
            {"sequence_number": 0, "start_byte": 0, "end_byte": 2},
            {"sequence_number": 1, "start_byte": 0, "end_byte": 2},
        ])
```

- [ ] **Step 2: Run buffering tests to verify red**

Run:

```bash
uv run python -B -m unittest tests.test_buffered_recognition -v
```

Expected: failure because `BufferedRecognizer.recognize()` does not accept `diagnostic_collector`.

- [ ] **Step 3: Implement segment tracking and action recording**

In `tarteel_realtime/buffered_recognition.py`, add a segment dataclass:

```python
@dataclass(frozen=True)
class BufferedAudioSegment:
    sequence_number: int
    start_byte: int
    end_byte: int

    def to_payload(self) -> dict[str, int]:
        return {
            "sequence_number": self.sequence_number,
            "start_byte": self.start_byte,
            "end_byte": self.end_byte,
        }
```

Add `diagnostic_collector=None` to `recognize`:

```python
    def recognize(
        self,
        chunk: AudioChunk,
        *,
        diagnostic_collector=None,
    ) -> RecognitionResult:
```

Add `self._segments: list[BufferedAudioSegment] = []` in `__init__`.

Update `_append` to record segments:

```python
        self._buffer.extend(chunk.pcm)
        self._segments.append(
            BufferedAudioSegment(
                sequence_number=chunk.sequence_number,
                start_byte=0,
                end_byte=len(chunk.pcm),
            )
        )
        self._bytes_since_flush += len(chunk.pcm)
```

When sample rate changes in `_append`, clear segments:

```python
            self._segments.clear()
```

Record actions in `recognize` by computing `buffered_ms_before` before append, then calling:

```python
def _record_buffer_action(
    diagnostic_collector,
    *,
    chunk: AudioChunk,
    action: str,
    incoming_rms: int,
    buffered_ms_before: int,
    buffered_ms_after: int,
    unflushed_ms_after: int,
    appended: bool,
    appended_segments: list[BufferedAudioSegment],
) -> None:
    if diagnostic_collector is None:
        return
    diagnostic_collector.record_buffer_action(
        sequence_number=chunk.sequence_number,
        action=action,
        incoming_rms=incoming_rms,
        buffered_ms_before=buffered_ms_before,
        buffered_ms_after=buffered_ms_after,
        unflushed_ms_after=unflushed_ms_after,
        appended=appended,
        appended_segments=[segment.to_payload() for segment in appended_segments],
    )
```

Before calling the inner recognizer on flush, begin an ASR window:

```python
        window_id = None
        if diagnostic_collector is not None:
            window_id = diagnostic_collector.begin_asr_window(
                triggering_sequence_number=chunk.sequence_number,
                segments=[segment.to_payload() for segment in self._segments],
                audio_ms=self._buffered_ms,
                pcm_bytes=len(self._buffer),
                buffered_rms=buffered_rms,
                tail_audio_ms=self._config.tail_audio_ms,
            )
```

Wrap the recognizer call with timing:

```python
        start = monotonic()
        result = self._recognizer.recognize(AudioChunk(
            sequence_number=chunk.sequence_number,
            pcm=bytes(self._buffer),
            sample_rate_hz=self._sample_rate_hz or chunk.sample_rate_hz,
        ))
        total_ms = int(round((monotonic() - start) * 1_000))
        if diagnostic_collector is not None and window_id is not None:
            diagnostic_collector.finish_asr_window(
                window_id,
                transcript=result.transcript,
                confidence=result.confidence,
                is_final=result.is_final,
                total_duration_ms=total_ms,
            )
```

Update `_keep_tail` to trim both `_buffer` and `_segments`. Use this exact trimming helper:

```python
    def _trim_segments_to_tail(self, tail_bytes: int) -> None:
        if tail_bytes == 0:
            self._segments.clear()
            return
        remaining = tail_bytes
        kept: list[BufferedAudioSegment] = []
        for segment in reversed(self._segments):
            segment_length = segment.end_byte - segment.start_byte
            if remaining <= 0:
                break
            if segment_length <= remaining:
                kept.append(segment)
                remaining -= segment_length
                continue
            kept.append(BufferedAudioSegment(
                sequence_number=segment.sequence_number,
                start_byte=segment.end_byte - remaining,
                end_byte=segment.end_byte,
            ))
            remaining = 0
        self._segments = list(reversed(kept))
```

Call `_trim_segments_to_tail(tail_bytes)` inside `_keep_tail`.

- [ ] **Step 4: Pass the collector from `RecitationStream` to recognizer**

In `tarteel_realtime/session.py`, do not change the method signature.

In `tarteel_realtime/recitation_stream.py`, if the recognizer supports the keyword, call it through a helper instead of `self._session.handle_chunk(chunk)`. To keep `RecitationSession` stable, add a private method on `RecitationStream`:

```python
    def _handle_chunk(
        self,
        chunk: AudioChunk,
        diagnostic_collector: DiagnosticTraceCollector | None,
    ) -> SessionEvent:
        if diagnostic_collector is None:
            return self._session.handle_chunk(chunk)
        return self._session.handle_chunk_with_diagnostics(
            chunk,
            diagnostic_collector=diagnostic_collector,
        )
```

Add `handle_chunk_with_diagnostics` to `RecitationSession`:

```python
    def handle_chunk_with_diagnostics(
        self,
        chunk: AudioChunk,
        *,
        diagnostic_collector,
    ) -> SessionEvent:
        try:
            recognition = self._recognizer.recognize(
                chunk,
                diagnostic_collector=diagnostic_collector,
            )
        except TypeError:
            recognition = self._recognizer.recognize(chunk)
        return self._transitions.handle_recognition(recognition)
```

This keeps the existing `handle_chunk` public behavior unchanged.

- [ ] **Step 5: Run focused tests**

Run:

```bash
uv run python -B -m unittest tests.test_buffered_recognition tests.test_api tests.test_recitation_stream -v
```

Expected: `OK`.

- [ ] **Step 6: Commit**

Run:

```bash
git add tarteel_realtime/buffered_recognition.py tarteel_realtime/session.py tarteel_realtime/recitation_stream.py tests/test_buffered_recognition.py tests/test_api.py tests/test_recitation_stream.py
git commit -m "feat: trace ASR buffering decisions"
```

---

### Task 4: ASR Cold-Start and Inference Timing

**Files:**
- Modify: `tarteel_realtime/asr_runtime.py`
- Modify: `tarteel_realtime/whisper_adapter.py`
- Modify: `tests/test_asr_runtime.py`
- Modify: `tests/test_whisper_adapter.py`

- [ ] **Step 1: Add failing lazy recognizer timing test**

Append to `tests/test_asr_runtime.py`:

```python
from tarteel_realtime.diagnostics import DiagnosticTraceCollector, diagnostic_asr_context
```

Add:

```python
    def test_lazy_recognizer_records_cold_start_timing_in_diagnostic_context(self):
        calls = []

        class StaticRecognizer:
            def recognize(self, chunk):
                return RecognitionResult(
                    transcript="ready",
                    confidence=1.0,
                    chunk_sequence=chunk.sequence_number,
                    is_final=True,
                )

        collector = DiagnosticTraceCollector(clock=lambda: 1.0)
        collector.begin_chunk(sequence_number=0, pcm_bytes=2, sample_rate_hz=16_000, voice_activity=None)
        window_id = collector.begin_asr_window(
            triggering_sequence_number=0,
            segments=[{"sequence_number": 0, "start_byte": 0, "end_byte": 2}],
            audio_ms=1,
            pcm_bytes=2,
            buffered_rms=1000,
            tail_audio_ms=0,
        )
        recognizer = LazyRecognizer(lambda: calls.append("build") or StaticRecognizer())

        with diagnostic_asr_context(collector, window_id):
            recognizer.recognize(AudioChunk(0, b"\x00\x01", 16_000))

        envelope = collector.envelope({"type": "locked"})
        self.assertEqual(calls, ["build"])
        self.assertTrue(envelope["trace"]["asr_window"]["cold_start"])
        self.assertIsInstance(envelope["trace"]["asr_window"]["recognizer_init_ms"], int)
```

- [ ] **Step 2: Add failing Whisper inference timing test**

Append to `tests/test_whisper_adapter.py`:

```python
from tarteel_realtime.diagnostics import DiagnosticTraceCollector, diagnostic_asr_context
```

Add:

```python
    def test_whisper_recognizer_records_inference_timing_in_diagnostic_context(self):
        class StaticBackend:
            def transcribe(self, *, samples, sample_rate_hz, language):
                return {"text": "مَلِكِ", "confidence": 0.7, "is_final": True}

        collector = DiagnosticTraceCollector(clock=lambda: 1.0)
        collector.begin_chunk(sequence_number=0, pcm_bytes=2, sample_rate_hz=16_000, voice_activity=None)
        window_id = collector.begin_asr_window(
            triggering_sequence_number=0,
            segments=[{"sequence_number": 0, "start_byte": 0, "end_byte": 2}],
            audio_ms=1,
            pcm_bytes=2,
            buffered_rms=1000,
            tail_audio_ms=0,
        )
        recognizer = WhisperRecognizer(
            backend=StaticBackend(),
            config=WhisperConfig(model_id="fake"),
        )

        with diagnostic_asr_context(collector, window_id):
            recognizer.recognize(AudioChunk(0, b"\x00\x01", 16_000))

        envelope = collector.envelope({"type": "locked"})
        self.assertIsInstance(envelope["trace"]["asr_window"]["asr_inference_ms"], int)
```

- [ ] **Step 3: Run timing tests to verify red**

Run:

```bash
uv run python -B -m unittest tests.test_asr_runtime tests.test_whisper_adapter -v
```

Expected: failures because the timing calls are not implemented.

- [ ] **Step 4: Implement lazy init timing**

In `tarteel_realtime/asr_runtime.py`, import:

```python
from time import monotonic

from tarteel_realtime.diagnostics import current_diagnostic_context
```

Inside `LazyRecognizer.recognize`, wrap the first builder call:

```python
                    start = monotonic()
                    self._recognizer = self._recognizer_factory()
                    duration_ms = int(round((monotonic() - start) * 1_000))
                    context = current_diagnostic_context()
                    if context is not None:
                        context.collector.record_recognizer_init(
                            context.window_id,
                            duration_ms=duration_ms,
                        )
```

- [ ] **Step 5: Implement Whisper inference timing**

In `tarteel_realtime/whisper_adapter.py`, import:

```python
from time import monotonic

from tarteel_realtime.diagnostics import current_diagnostic_context
```

Inside `WhisperRecognizer.recognize`, wrap `_backend.transcribe(...)`:

```python
        start = monotonic()
        payload = self._backend.transcribe(
            samples=pcm16le_to_float_samples(chunk.pcm),
            sample_rate_hz=chunk.sample_rate_hz,
            language=self._config.language,
        )
        duration_ms = int(round((monotonic() - start) * 1_000))
        context = current_diagnostic_context()
        if context is not None:
            context.collector.record_asr_inference(
                context.window_id,
                duration_ms=duration_ms,
            )
```

- [ ] **Step 6: Run focused timing tests**

Run:

```bash
uv run python -B -m unittest tests.test_asr_runtime tests.test_whisper_adapter -v
```

Expected: `OK`.

- [ ] **Step 7: Commit**

Run:

```bash
git add tarteel_realtime/asr_runtime.py tarteel_realtime/whisper_adapter.py tests/test_asr_runtime.py tests/test_whisper_adapter.py
git commit -m "feat: trace ASR cold start and inference timing"
```

---

### Task 5: Decision-Level Locator and Alignment Diagnostics

**Files:**
- Modify: `tarteel_realtime/session_transitions.py`
- Modify: `tests/test_session_transitions.py`
- Modify: `tests/test_api.py`

- [ ] **Step 1: Add failing decision trace test**

Append to `tests/test_session_transitions.py`:

```python
from tarteel_realtime.diagnostics import DiagnosticTraceCollector
```

Add:

```python
    def test_records_initial_location_decision_in_diagnostic_context(self):
        corpus = QuranCorpus.from_tanzil_lines([
            "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
            "114|2|مَلِكِ النَّاسِ",
        ])
        policy = RecitationTransitionPolicy(corpus=corpus, minimum_lock_words=1)
        collector = DiagnosticTraceCollector(clock=lambda: 1.0)
        collector.begin_chunk(sequence_number=0, pcm_bytes=2, sample_rate_hz=16_000, voice_activity=None)

        event = policy.handle_recognition_with_diagnostics(
            RecognitionResult(
                transcript="مَلِكِ",
                confidence=1.0,
                chunk_sequence=0,
                is_final=True,
            ),
            diagnostic_collector=collector,
        )
        envelope = collector.envelope({"type": event.type.value})

        self.assertEqual(envelope["trace"]["decision"]["mode"], "initial_location")
        self.assertEqual(envelope["trace"]["decision"]["locator"]["status"], "locked")
        self.assertEqual(envelope["trace"]["decision"]["locator"]["reason"], "unique_match")
        self.assertEqual(envelope["trace"]["decision"]["locator"]["top_candidates"][0]["ayah_ref"], "114:2")
```

- [ ] **Step 2: Run transition tests to verify red**

Run:

```bash
uv run python -B -m unittest tests.test_session_transitions -v
```

Expected: failure because `handle_recognition_with_diagnostics` does not exist.

- [ ] **Step 3: Add diagnostic transition entry point**

In `tarteel_realtime/session_transitions.py`, add:

```python
    def handle_recognition_with_diagnostics(
        self,
        recognition: RecognitionResult,
        *,
        diagnostic_collector,
    ) -> SessionEvent:
        event = self.handle_recognition(recognition)
        diagnostic_collector.record_decision({
            "mode": self._last_decision_mode,
            "locator": self._last_locator_payload,
            "alignment": self._last_alignment_payload,
        })
        return event
```

Initialize these fields in `__init__`:

```python
        self._last_decision_mode: str | None = None
        self._last_locator_payload: dict[str, object] | None = None
        self._last_alignment_payload: dict[str, object] | None = None
```

Add helper methods:

```python
    def _remember_locator_decision(
        self,
        *,
        mode: str,
        decision: LocatorDecision,
    ) -> None:
        self._last_decision_mode = mode
        self._last_locator_payload = {
            "status": decision.status.value,
            "reason": decision.reason,
            "top_candidates": [
                {
                    "ayah_ref": str(candidate.ayah_ref),
                    "start_ref": str(candidate.start_ref),
                    "matched_words": candidate.matched_words,
                    "score": candidate.score,
                }
                for candidate in decision.candidates[:5]
            ],
        }
        self._last_alignment_payload = None

    def _remember_alignment_decision(
        self,
        *,
        mode: str,
        decision: AlignmentDecision,
    ) -> None:
        self._last_decision_mode = mode
        self._last_alignment_payload = {
            "status": decision.status.value,
            "reason": decision.reason,
            "expected_ref": None if decision.expected_ref is None else str(decision.expected_ref),
            "expected_word": decision.expected_word,
            "recognized_word": decision.recognized_word,
            "consumed_words": decision.consumed_words,
        }
        self._last_locator_payload = None
```

Call `_remember_locator_decision(mode="initial_location", decision=locator_decision)` in `_handle_initial_location` after `locator_decision` is computed.

Call `_remember_locator_decision(mode="ordered_progression", decision=ordered_decision)` in `_handle_ayah_boundary` and after `_locate_ordered_progression` in `_handle_post_lock_alignment`.

Call `_remember_alignment_decision(mode="post_lock_alignment", decision=alignment_decision)` immediately after `alignment_decision = self._aligner.evaluate_from(...)`.

- [ ] **Step 4: Wire session diagnostic entry point**

In `tarteel_realtime/session.py`, update `handle_chunk_with_diagnostics`:

```python
        return self._transitions.handle_recognition_with_diagnostics(
            recognition,
            diagnostic_collector=diagnostic_collector,
        )
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
uv run python -B -m unittest tests.test_session_transitions tests.test_api -v
```

Expected: `OK`.

- [ ] **Step 6: Commit**

Run:

```bash
git add tarteel_realtime/session.py tarteel_realtime/session_transitions.py tests/test_session_transitions.py tests/test_api.py
git commit -m "feat: trace locator and alignment decisions"
```

---

### Task 6: Diagnostic Bundle Writer and Static Renderer

**Files:**
- Create: `tarteel_realtime/diagnostics_bundle.py`
- Create: `tests/test_diagnostics_bundle.py`

- [ ] **Step 1: Write failing bundle tests**

Add `tests/test_diagnostics_bundle.py`:

```python
import json
import struct
import tempfile
from pathlib import Path
import unittest
import wave

from tarteel_realtime.diagnostics_bundle import (
    build_waveform_peaks,
    scrub_url,
    write_diagnostics_bundle,
)


class DiagnosticsBundleTests(unittest.TestCase):
    def test_scrubs_url_query_values(self):
        self.assertEqual(
            scrub_url("wss://example.test/ws/recitation?scope=108&token=secret"),
            "wss://example.test/ws/recitation?scope=108&token=<redacted>",
        )

    def test_builds_waveform_min_max_peaks(self):
        pcm = struct.pack("<hhhh", -1000, 500, -200, 1200)

        peaks = build_waveform_peaks(pcm, bucket_samples=2)

        self.assertEqual(peaks, [
            {"min": -0.0305, "max": 0.0153},
            {"min": -0.0061, "max": 0.0366},
        ])

    def test_writes_bundle_files_and_inlines_trace_json(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            output_root = Path(tmpdir)
            raw_pcm = struct.pack("<hhhh", 1000, -1000, 500, -500)
            trace = {
                "metadata": {"backend_url": "wss://example.test/ws/recitation", "authorization_used": True},
                "chunks": [],
                "asr_windows": [],
                "audio_artifacts": {},
                "raw_backend_envelopes": [],
            }

            bundle = write_diagnostics_bundle(
                output_root=output_root,
                session_slug="20260606T143012Z-108001-scope-108",
                trace=trace,
                raw_audio_pcm=raw_pcm,
                sample_rate_hz=16_000,
                asr_input_segments=[],
                asr_windows=[],
            )

            self.assertTrue((bundle.path / "index.html").is_file())
            self.assertTrue((bundle.path / "trace.json").is_file())
            self.assertTrue((bundle.path / "raw-mic.wav").is_file())
            html = (bundle.path / "index.html").read_text(encoding="utf-8")
            self.assertIn('id="trace-data"', html)
            self.assertIn("Visual Diagnostics", html)

            with wave.open(str(bundle.path / "raw-mic.wav"), "rb") as wav_file:
                self.assertEqual(wav_file.getnchannels(), 1)
                self.assertEqual(wav_file.getsampwidth(), 2)
                self.assertEqual(wav_file.getframerate(), 16_000)
```

- [ ] **Step 2: Run bundle tests to verify red**

Run:

```bash
uv run python -B -m unittest tests.test_diagnostics_bundle -v
```

Expected: failure because `tarteel_realtime.diagnostics_bundle` does not exist.

- [ ] **Step 3: Implement bundle writer**

Create `tarteel_realtime/diagnostics_bundle.py` with these public functions:

```python
from __future__ import annotations

import html
import json
import re
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
import struct


@dataclass(frozen=True)
class DiagnosticsBundle:
    path: Path
    index_html_path: Path
    trace_json_path: Path


def scrub_url(url: str) -> str:
    parts = urlsplit(url)
    safe_items = []
    for name, value in parse_qsl(parts.query, keep_blank_values=True):
        if name in {"scope", "diagnostics"}:
            safe_items.append((name, value))
        else:
            safe_items.append((name, "<redacted>"))
    return urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(safe_items), parts.fragment))


def build_waveform_peaks(pcm: bytes, *, bucket_samples: int = 320) -> list[dict[str, float]]:
    sample_count = len(pcm) // 2
    if sample_count == 0:
        return []
    samples = [
        sample
        for (sample,) in struct.iter_unpack("<h", pcm[:sample_count * 2])
    ]
    peaks: list[dict[str, float]] = []
    for offset in range(0, len(samples), bucket_samples):
        bucket = samples[offset:offset + bucket_samples]
        peaks.append({
            "min": round(min(bucket) / 32768.0, 4),
            "max": round(max(bucket) / 32768.0, 4),
        })
    return peaks


def write_diagnostics_bundle(
    *,
    output_root: Path,
    session_slug: str,
    trace: dict[str, Any],
    raw_audio_pcm: bytes,
    sample_rate_hz: int,
    asr_input_segments: list[dict[str, Any]],
    asr_windows: list[dict[str, Any]],
) -> DiagnosticsBundle:
    bundle_path = unique_bundle_path(output_root / session_slug)
    assets_path = bundle_path / "assets"
    windows_path = bundle_path / "asr-windows"
    assets_path.mkdir(parents=True, exist_ok=True)
    windows_path.mkdir(parents=True, exist_ok=True)

    raw_wav_path = bundle_path / "raw-mic.wav"
    write_pcm16_wav(raw_wav_path, raw_audio_pcm, sample_rate_hz=sample_rate_hz)

    asr_input_pcm = b"".join(segment["pcm"] for segment in asr_input_segments)
    write_pcm16_wav(bundle_path / "asr-input.wav", asr_input_pcm, sample_rate_hz=sample_rate_hz)

    normalized_windows = []
    for window in asr_windows:
        filename = f"asr-window-{int(window['id']):03d}.wav"
        write_pcm16_wav(windows_path / filename, window["pcm"], sample_rate_hz=sample_rate_hz)
        normalized = {key: value for key, value in window.items() if key != "pcm"}
        normalized["filename"] = f"asr-windows/{filename}"
        normalized["waveform_peaks"] = build_waveform_peaks(window["pcm"])
        normalized_windows.append(normalized)

    trace = dict(trace)
    trace["asr_windows"] = normalized_windows
    trace["audio_artifacts"] = {
        "raw_mic": {
            "filename": "raw-mic.wav",
            "waveform_peaks": build_waveform_peaks(raw_audio_pcm),
        },
        "asr_input": {
            "filename": "asr-input.wav",
            "waveform_peaks": build_waveform_peaks(asr_input_pcm),
        },
    }

    trace_json_path = bundle_path / "trace.json"
    trace_json_path.write_text(
        json.dumps(trace, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    (assets_path / "diagnostics.css").write_text(DIAGNOSTICS_CSS, encoding="utf-8")
    (assets_path / "diagnostics.js").write_text(DIAGNOSTICS_JS, encoding="utf-8")
    index_html_path = bundle_path / "index.html"
    index_html_path.write_text(render_index_html(trace), encoding="utf-8")
    return DiagnosticsBundle(
        path=bundle_path,
        index_html_path=index_html_path,
        trace_json_path=trace_json_path,
    )


def unique_bundle_path(path: Path) -> Path:
    if not path.exists():
        return path
    index = 2
    while True:
        candidate = path.with_name(f"{path.name}-{index}")
        if not candidate.exists():
            return candidate
        index += 1


def write_pcm16_wav(path: Path, pcm: bytes, *, sample_rate_hz: int) -> None:
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate_hz)
        wav_file.writeframes(pcm)


def render_index_html(trace: dict[str, Any]) -> str:
    encoded_trace = html.escape(json.dumps(trace, ensure_ascii=False), quote=False)
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Visual Diagnostics</title>
  <link rel="stylesheet" href="assets/diagnostics.css">
</head>
<body>
  <main>
    <header>
      <h1>Visual Diagnostics</h1>
      <p>This local bundle contains voice audio and ASR transcripts.</p>
    </header>
    <section id="summary"></section>
    <section id="timeline"></section>
    <section>
      <h2>Playback</h2>
      <audio controls src="raw-mic.wav"></audio>
      <audio controls src="asr-input.wav"></audio>
    </section>
    <pre id="detail"></pre>
  </main>
  <script type="application/json" id="trace-data">{encoded_trace}</script>
  <script src="assets/diagnostics.js"></script>
</body>
</html>
"""


DIAGNOSTICS_CSS = """body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;margin:0;background:#f6f7f9;color:#17202a}main{max-width:1180px;margin:0 auto;padding:24px}header{border-bottom:1px solid #d7dde5;margin-bottom:16px}.lane{display:grid;grid-template-columns:160px 1fr;gap:12px;align-items:center;border-bottom:1px solid #e1e6ee;padding:8px 0}.bar{height:20px;background:#2f8f83}.chunk{display:inline-block;margin:2px;padding:4px 6px;border:1px solid #bec8d4;background:white;border-radius:4px;cursor:pointer}pre{white-space:pre-wrap;background:#17202a;color:white;padding:12px;border-radius:6px;overflow:auto}audio{display:block;width:100%;margin:8px 0}"""


DIAGNOSTICS_JS = """const trace = JSON.parse(document.getElementById('trace-data').textContent);
const summary = document.getElementById('summary');
const timeline = document.getElementById('timeline');
const detail = document.getElementById('detail');
summary.innerHTML = `<h2>Summary</h2><p>Chunks: ${(trace.chunks || []).length}</p>`;
function show(value){ detail.textContent = JSON.stringify(value, null, 2); }
function lane(title, content){ const row = document.createElement('div'); row.className='lane'; row.innerHTML = `<strong>${title}</strong><div>${content}</div>`; return row; }
timeline.appendChild(lane('Raw waveform', '<div class="bar"></div>'));
timeline.appendChild(lane('Chunks', (trace.chunks || []).map((chunk, index) => `<button class="chunk" data-index="${index}">${chunk.sequence_number}</button>`).join('')));
timeline.addEventListener('click', event => { const button = event.target.closest('button[data-index]'); if (button) show(trace.chunks[Number(button.dataset.index)]); });
show(trace.metadata || {});
"""
```

- [ ] **Step 4: Run bundle tests**

Run:

```bash
uv run python -B -m unittest tests.test_diagnostics_bundle -v
```

Expected: `OK`.

- [ ] **Step 5: Commit**

Run:

```bash
git add tarteel_realtime/diagnostics_bundle.py tests/test_diagnostics_bundle.py
git commit -m "feat: render local diagnostics bundles"
```

---

### Task 7: Diagnostics Capture CLI

**Files:**
- Create: `tarteel_realtime/diagnostics_capture.py`
- Create: `tests/test_diagnostics_capture.py`
- Modify: `.gitignore`

- [ ] **Step 1: Add `.gitignore` entry**

Modify `.gitignore`:

```gitignore
diagnostics/
```

- [ ] **Step 2: Write failing CLI/bundle tests**

Add `tests/test_diagnostics_capture.py`:

```python
import json
import struct
import tempfile
from pathlib import Path
import unittest

from tarteel_realtime.asr_smoke import SmokeAudio
from tarteel_realtime.diagnostics_capture import (
    DiagnosticCaptureError,
    merge_trace_records,
    reconstruct_asr_windows,
    session_slug,
    validate_trace_envelope,
)


class DiagnosticsCaptureTests(unittest.TestCase):
    def test_session_slug_uses_timestamp_audio_name_and_scope(self):
        self.assertEqual(
            session_slug(
                timestamp_utc="20260606T143012Z",
                audio_path=Path("fixtures/local_audio/108001.wav"),
                scope="108",
            ),
            "20260606T143012Z-108001-scope-108",
        )

    def test_validate_trace_envelope_rejects_plain_event_payload(self):
        with self.assertRaises(DiagnosticCaptureError) as context:
            validate_trace_envelope({"type": "locked"})

        self.assertIn("diagnostics-enabled backend", str(context.exception))

    def test_reconstructs_asr_window_audio_from_backend_segments(self):
        chunks = {
            0: b"aaaa",
            1: b"bbbb",
        }
        envelopes = [{
            "kind": "recitation_trace",
            "event": {"type": "locked"},
            "trace": {
                "sequence_number": 1,
                "asr_window": {
                    "id": 0,
                    "segments": [
                        {"sequence_number": 0, "start_byte": 1, "end_byte": 4},
                        {"sequence_number": 1, "start_byte": 0, "end_byte": 2},
                    ],
                },
            },
        }]

        windows = reconstruct_asr_windows(envelopes, chunks)

        self.assertEqual(windows, [{"id": 0, "pcm": b"aaabb"}])

    def test_merges_client_timing_with_backend_trace(self):
        envelopes = [{
            "kind": "recitation_trace",
            "event": {"type": "locating", "reason": "waiting_for_audio_buffer"},
            "trace": {"sequence_number": 0, "buffer": {"action": "append_wait_min_audio"}},
        }]
        client_chunks = [{
            "sequence_number": 0,
            "capture_offset_ms": 0,
            "send_offset_ms": 2,
            "receive_offset_ms": 20,
            "roundtrip_ms": 18,
            "pcm_bytes": 32000,
            "sample_rate_hz": 16000,
        }]

        trace = merge_trace_records(
            metadata={"scope": "108"},
            envelopes=envelopes,
            client_chunks=client_chunks,
        )

        self.assertEqual(trace["metadata"]["scope"], "108")
        self.assertEqual(trace["chunks"][0]["sequence_number"], 0)
        self.assertEqual(trace["chunks"][0]["roundtrip_ms"], 18)
        self.assertEqual(trace["raw_backend_envelopes"], envelopes)
```

- [ ] **Step 3: Run capture tests to verify red**

Run:

```bash
uv run python -B -m unittest tests.test_diagnostics_capture -v
```

Expected: failure because `tarteel_realtime.diagnostics_capture` does not exist.

- [ ] **Step 4: Implement CLI helpers**

Create `tarteel_realtime/diagnostics_capture.py` with:

```python
from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, datetime
import json
import os
from pathlib import Path
import re
from time import monotonic
from typing import Any

from tarteel_realtime.diagnostics_bundle import scrub_url, write_diagnostics_bundle
from tarteel_realtime.replay_probe import load_replay_audio_file, url_with_scope
from tarteel_realtime.ws_client import build_chunk_payload, split_pcm_audio, websocket_connect_kwargs


class DiagnosticCaptureError(RuntimeError):
    pass


def session_slug(*, timestamp_utc: str, audio_path: Path, scope: str | None) -> str:
    audio_slug = re.sub(r"[^A-Za-z0-9]+", "-", audio_path.stem).strip("-") or "audio"
    scope_slug = "auto" if not scope else re.sub(r"[^A-Za-z0-9]+", "-", scope).strip("-")
    return f"{timestamp_utc}-{audio_slug}-scope-{scope_slug}"


def validate_trace_envelope(payload: dict[str, Any]) -> dict[str, Any]:
    if payload.get("kind") != "recitation_trace":
        raise DiagnosticCaptureError(
            "Backend did not return recitation_trace envelopes. Deploy diagnostics-enabled backend code and use diagnostics=1."
        )
    if not isinstance(payload.get("trace"), dict) or not isinstance(payload.get("event"), dict):
        raise DiagnosticCaptureError("Invalid recitation_trace envelope shape.")
    return payload


def reconstruct_asr_windows(
    envelopes: list[dict[str, Any]],
    chunks: dict[int, bytes],
) -> list[dict[str, Any]]:
    windows: dict[int, bytes] = {}
    for envelope in envelopes:
        window = envelope.get("trace", {}).get("asr_window")
        if not isinstance(window, dict):
            continue
        window_id = int(window["id"])
        if window_id in windows:
            continue
        pieces = []
        for segment in window.get("segments", []):
            sequence_number = int(segment["sequence_number"])
            start_byte = int(segment["start_byte"])
            end_byte = int(segment["end_byte"])
            pieces.append(chunks[sequence_number][start_byte:end_byte])
        windows[window_id] = b"".join(pieces)
    return [
        {"id": window_id, "pcm": pcm}
        for window_id, pcm in sorted(windows.items())
    ]


def merge_trace_records(
    *,
    metadata: dict[str, Any],
    envelopes: list[dict[str, Any]],
    client_chunks: list[dict[str, Any]],
) -> dict[str, Any]:
    client_by_sequence = {
        chunk["sequence_number"]: chunk
        for chunk in client_chunks
    }
    chunks = []
    for envelope in envelopes:
        trace = dict(envelope["trace"])
        sequence_number = int(trace["sequence_number"])
        trace.update(client_by_sequence.get(sequence_number, {}))
        trace["event"] = envelope["event"]
        chunks.append(trace)
    return {
        "metadata": metadata,
        "chunks": chunks,
        "asr_windows": [],
        "audio_artifacts": {},
        "raw_backend_envelopes": envelopes,
    }
```

- [ ] **Step 5: Implement replay run and command parser**

Continue in `diagnostics_capture.py`:

```python
async def run_capture(
    *,
    url: str,
    audio_path: Path,
    chunk_ms: int,
    scope: str | None,
    output_root: Path,
    raw_sample_rate_hz: int,
    disable_ping: bool,
    bearer_token: str | None,
    authorization_source: str,
) -> Path:
    import websockets

    audio = load_replay_audio_file(audio_path, raw_sample_rate_hz=raw_sample_rate_hz)
    diagnostic_url = url_with_scope(url, scope)
    separator = "&" if "?" in diagnostic_url else "?"
    diagnostic_url = f"{diagnostic_url}{separator}diagnostics=1"
    chunks = split_pcm_audio(audio, chunk_duration_ms=chunk_ms)
    chunk_bytes_by_sequence = {
        sequence_number: pcm
        for sequence_number, pcm in enumerate(chunks)
    }
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    start = monotonic()
    envelopes: list[dict[str, Any]] = []
    client_chunks: list[dict[str, Any]] = []

    async with websockets.connect(
        diagnostic_url,
        **websocket_connect_kwargs(
            disable_ping=disable_ping,
            authorization_token=bearer_token,
        ),
    ) as websocket:
        for sequence_number, pcm in enumerate(chunks):
            scheduled_offset_ms = sequence_number * chunk_ms
            elapsed_ms = int(round((monotonic() - start) * 1_000))
            sleep_ms = scheduled_offset_ms - elapsed_ms
            if sleep_ms > 0:
                await asyncio.sleep(sleep_ms / 1_000)
            send_offset_ms = int(round((monotonic() - start) * 1_000))
            await websocket.send(json.dumps(build_chunk_payload(
                sequence_number=sequence_number,
                pcm=pcm,
                sample_rate_hz=audio.sample_rate_hz,
            )))
            response = json.loads(await websocket.recv())
            receive_offset_ms = int(round((monotonic() - start) * 1_000))
            envelope = validate_trace_envelope(response)
            envelopes.append(envelope)
            client_chunks.append({
                "sequence_number": sequence_number,
                "capture_offset_ms": scheduled_offset_ms,
                "send_offset_ms": send_offset_ms,
                "receive_offset_ms": receive_offset_ms,
                "roundtrip_ms": receive_offset_ms - send_offset_ms,
                "pcm_bytes": len(pcm),
                "sample_rate_hz": audio.sample_rate_hz,
            })

    metadata = {
        "diagnostic_tool_version": 1,
        "privacy_warning": "This local bundle contains voice audio and ASR transcripts.",
        "backend_url": scrub_url(diagnostic_url),
        "scope": scope,
        "audio_path": str(audio_path),
        "sample_rate_hz": audio.sample_rate_hz,
        "chunk_ms": chunk_ms,
        "authorization_used": bool(bearer_token),
        "authorization_source": authorization_source,
        "started_at_utc": timestamp,
        "ended_at_utc": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    trace = merge_trace_records(
        metadata=metadata,
        envelopes=envelopes,
        client_chunks=client_chunks,
    )
    asr_windows = reconstruct_asr_windows(envelopes, chunk_bytes_by_sequence)
    asr_input_segments = [
        {"pcm": chunk_bytes_by_sequence[chunk["sequence_number"]]}
        for chunk in trace["chunks"]
        if chunk.get("buffer", {}).get("appended") is True
    ]
    bundle = write_diagnostics_bundle(
        output_root=output_root,
        session_slug=session_slug(timestamp_utc=timestamp, audio_path=audio_path, scope=scope),
        trace=trace,
        raw_audio_pcm=audio.pcm,
        sample_rate_hz=audio.sample_rate_hz,
        asr_input_segments=asr_input_segments,
        asr_windows=asr_windows,
    )
    return bundle.index_html_path


def bearer_token_from_args(args) -> tuple[str | None, str]:
    if args.bearer_token_env:
        token = os.environ.get(args.bearer_token_env, "")
        return (token or None), "environment"
    if args.bearer_token:
        return args.bearer_token, "argument"
    return None, "none"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Capture a replayed recitation diagnostics bundle.")
    parser.add_argument("--url", required=True)
    parser.add_argument("--scope", default=None)
    parser.add_argument("--audio-path", type=Path, required=True)
    parser.add_argument("--chunk-ms", type=int, default=1000)
    parser.add_argument("--sample-rate", type=int, default=16_000)
    parser.add_argument("--output-root", type=Path, default=Path("diagnostics/sessions"))
    parser.add_argument("--bearer-token", default=None)
    parser.add_argument("--bearer-token-env", default=None)
    parser.add_argument("--disable-ping", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    bearer_token, authorization_source = bearer_token_from_args(args)
    try:
        index_html_path = asyncio.run(run_capture(
            url=args.url,
            audio_path=args.audio_path,
            chunk_ms=args.chunk_ms,
            scope=args.scope,
            output_root=args.output_root,
            raw_sample_rate_hz=args.sample_rate,
            disable_ping=args.disable_ping,
            bearer_token=bearer_token,
            authorization_source=authorization_source,
        ))
    except DiagnosticCaptureError as exc:
        print(str(exc))
        return 2
    print(index_html_path.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 6: Run capture helper tests**

Run:

```bash
uv run python -B -m unittest tests.test_diagnostics_capture -v
```

Expected: `OK`.

- [ ] **Step 7: Commit**

Run:

```bash
git add .gitignore tarteel_realtime/diagnostics_capture.py tests/test_diagnostics_capture.py
git commit -m "feat: capture replay diagnostics bundles"
```

---

### Task 8: Ping Precheck and CLI Integration Test

**Files:**
- Modify: `tarteel_realtime/diagnostics_capture.py`
- Modify: `tests/test_diagnostics_capture.py`

- [ ] **Step 1: Add failing ping metadata test**

Append to `tests/test_diagnostics_capture.py`:

```python
from tarteel_realtime.diagnostics_capture import ping_url_from_websocket_url
```

Add:

```python
    def test_derives_ping_url_from_websocket_url(self):
        self.assertEqual(
            ping_url_from_websocket_url("wss://example.test/ws/recitation?scope=108"),
            "https://example.test/ping",
        )
        self.assertEqual(
            ping_url_from_websocket_url("ws://127.0.0.1:8000/ws/recitation"),
            "http://127.0.0.1:8000/ping",
        )
```

- [ ] **Step 2: Run test to verify red**

Run:

```bash
uv run python -B -m unittest tests.test_diagnostics_capture -v
```

Expected: failure because `ping_url_from_websocket_url` does not exist.

- [ ] **Step 3: Implement ping URL and precheck**

In `diagnostics_capture.py`, add:

```python
from urllib.parse import urlsplit, urlunsplit
from urllib.request import urlopen
```

Add:

```python
def ping_url_from_websocket_url(url: str) -> str:
    parts = urlsplit(url)
    scheme = "https" if parts.scheme == "wss" else "http"
    return urlunsplit((scheme, parts.netloc, "/ping", "", ""))


def run_ping_precheck(url: str, *, disabled: bool) -> dict[str, Any]:
    if disabled:
        return {"enabled": False}
    ping_url = ping_url_from_websocket_url(url)
    start = monotonic()
    try:
        with urlopen(ping_url, timeout=5) as response:
            body = response.read(1024).decode("utf-8", errors="replace")
            status_code = response.status
    except Exception as exc:
        return {
            "enabled": True,
            "url": scrub_url(ping_url),
            "ok": False,
            "error": str(exc),
            "duration_ms": int(round((monotonic() - start) * 1_000)),
        }
    return {
        "enabled": True,
        "url": scrub_url(ping_url),
        "ok": 200 <= status_code < 300,
        "status_code": status_code,
        "body": body,
        "duration_ms": int(round((monotonic() - start) * 1_000)),
    }
```

Inside `run_capture`, add to `metadata`:

```python
        "ping": run_ping_precheck(url, disabled=disable_ping),
```

- [ ] **Step 4: Run capture tests**

Run:

```bash
uv run python -B -m unittest tests.test_diagnostics_capture -v
```

Expected: `OK`.

- [ ] **Step 5: Commit**

Run:

```bash
git add tarteel_realtime/diagnostics_capture.py tests/test_diagnostics_capture.py
git commit -m "feat: add diagnostics ping metadata"
```

---

### Task 9: Documentation and Harness Notes

**Files:**
- Modify: `README.md`
- Modify: `codex-progress.md`
- Modify: `session-handoff.md`

- [ ] **Step 1: Add README usage section**

In `README.md`, after the existing replay probe section, add:

```markdown
### Visual diagnostics bundle

Use the diagnostics capture CLI when you need a local HTML bundle that aligns
raw audio, VAD metadata, backend buffering, ASR windows, transcripts, locator
decisions, and latency.

```bash
uv run --with websockets python -m tarteel_realtime.diagnostics_capture \
  --url 'ws://127.0.0.1:8000/ws/recitation' \
  --scope 108 \
  --audio-path fixtures/local_audio/108001.wav \
  --chunk-ms 1000 \
  --disable-ping
```

For protected remote backends, prefer an environment variable so the bearer
token does not appear in shell history:

```bash
MODAL_TOKEN='<token>' uv run --with websockets python -m tarteel_realtime.diagnostics_capture \
  --url 'wss://example.modal.run/ws/recitation' \
  --scope 108 \
  --audio-path fixtures/local_audio/108001.wav \
  --chunk-ms 1000 \
  --bearer-token-env MODAL_TOKEN \
  --disable-ping
```

The command prints the generated `index.html` path. Generated bundles live under
ignored `diagnostics/sessions/` and contain raw voice audio plus ASR transcripts.
Do not commit or upload them unless intentionally sharing diagnostic evidence.
```
```

- [ ] **Step 2: Add progress log entry**

Add a new top session entry to `codex-progress.md`:

```markdown
### Session 084

- Date: 2026-06-06
- Goal: Add replay-based visual diagnostics bundle generation for realtime recitation performance analysis.
- Completed:
  - Added opt-in `/ws/recitation?diagnostics=1` trace envelopes while preserving normal WebSocket payloads.
  - Added chunk-centric diagnostic collection for buffering actions, ASR windows, recognizer timing, transcripts, and locator/alignment decisions.
  - Added `tarteel_realtime.diagnostics_capture` to replay WAV audio and write ignored local HTML bundles.
  - Added static no-build bundle rendering with trace JSON, raw mic WAV, ASR input WAV, and ASR window WAVs.
- Verification run:
  - `uv run python -B -m unittest tests.test_diagnostics tests.test_api tests.test_buffered_recognition tests.test_recitation_stream tests.test_diagnostics_bundle tests.test_diagnostics_capture -v`
  - `uv run python -m compileall -q tarteel_realtime tests`
  - `git diff --check`
- Known risk or unresolved issue:
  - V1 is replay-based. The macOS live recording/export button is a follow-up.
  - Remote Modal/RunPod diagnostics require deploying this backend code before the CLI can receive envelopes.
- Next best step: run the CLI against `fixtures/local_audio/108001.wav` and inspect the generated HTML timeline before adding macOS live capture.
```

- [ ] **Step 3: Update session handoff**

In `session-handoff.md`, add this at the top of `Verified Now`:

```markdown
- Latest planned/implemented slice: replay-based visual diagnostics bundle generation for realtime recitation performance analysis.
- Design spec: `docs/superpowers/specs/2026-06-06-visual-diagnostics-tool.md`.
- Implementation plan: `docs/superpowers/plans/2026-06-06-visual-diagnostics-tool.md`.
- V1 scope: backend `?diagnostics=1` trace envelopes plus `tarteel_realtime.diagnostics_capture`; macOS live recording/export remains a follow-up.
```

- [ ] **Step 4: Run docs-adjacent checks**

Run:

```bash
uv run python -B -m json.tool feature_list.json
git diff --check
```

Expected: JSON validates and whitespace check passes.

- [ ] **Step 5: Commit**

Run:

```bash
git add README.md codex-progress.md session-handoff.md
git commit -m "docs: document visual diagnostics workflow"
```

---

### Task 10: Final Verification

**Files:**
- No new files.

- [ ] **Step 1: Run focused diagnostics suite**

Run:

```bash
uv run python -B -m unittest tests.test_diagnostics tests.test_api tests.test_buffered_recognition tests.test_recitation_stream tests.test_session_transitions tests.test_diagnostics_bundle tests.test_diagnostics_capture -v
```

Expected: all tests pass.

- [ ] **Step 2: Run full deterministic Python suite**

Run:

```bash
uv run python -B -m unittest discover -s tests -v
```

Expected: all deterministic tests pass.

- [ ] **Step 3: Run compile and whitespace checks**

Run:

```bash
uv run python -m compileall -q tarteel_realtime tests
git diff --check
```

Expected: compile succeeds and whitespace check reports no output.

- [ ] **Step 4: Run local fixture capture against dev backend**

Start the local backend in one terminal:

```bash
uv run uvicorn tarteel_realtime.dev_app:app --reload
```

Run the diagnostic capture in another terminal:

```bash
uv run --with websockets python -m tarteel_realtime.diagnostics_capture \
  --url 'ws://127.0.0.1:8000/ws/recitation' \
  --scope 108 \
  --audio-path fixtures/local_audio/108001.wav \
  --chunk-ms 1000 \
  --disable-ping
```

Expected: command prints an absolute `diagnostics/sessions/.../index.html` path, and the bundle contains `trace.json`, `raw-mic.wav`, `asr-input.wav`, `assets/diagnostics.css`, and `assets/diagnostics.js`.

- [ ] **Step 5: Inspect generated bundle structure**

Run:

```bash
find diagnostics/sessions -maxdepth 3 -type f | sort | tail -40
```

Expected: latest bundle contains:

```text
index.html
trace.json
raw-mic.wav
asr-input.wav
assets/diagnostics.css
assets/diagnostics.js
```

- [ ] **Step 6: Final commit**

Run:

```bash
git status --short
git add .
git commit -m "feat: add visual diagnostics bundle generator"
```

Expected: commit succeeds only after verifying no generated `diagnostics/` files are staged.

---

## Self-Review

- Spec coverage: The plan covers local ignored bundles, `?diagnostics=1`, normal WebSocket compatibility, chunk-centric traces, buffering actions, ASR windows, cold-start timing, decision-level locator diagnostics, static no-build HTML, WAV-only v1 input, real-time sequential replay, bearer token scrubbing, ping metadata, and tests.
- Placeholder scan: No step depends on a named undefined future task. Each code-changing step includes concrete code or exact command text.
- Type consistency: Diagnostic collector methods used by buffering, ASR runtime, Whisper adapter, session transitions, API, and capture tests use the same names: `DiagnosticTraceCollector`, `diagnostic_asr_context`, `record_buffer_action`, `begin_asr_window`, `record_recognizer_init`, `record_asr_inference`, `finish_asr_window`, and `envelope`.
