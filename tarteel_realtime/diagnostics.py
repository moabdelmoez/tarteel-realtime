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
    collector: "DiagnosticTraceCollector"
    window_id: int


_CURRENT_DIAGNOSTIC_CONTEXT: ContextVar[DiagnosticContext | None] = ContextVar(
    "tarteel_current_diagnostic_context",
    default=None,
)


def current_diagnostic_context() -> DiagnosticContext | None:
    return _CURRENT_DIAGNOSTIC_CONTEXT.get()


@contextmanager
def diagnostic_asr_context(
    collector: "DiagnosticTraceCollector",
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
    _trace: dict[str, Any] = field(default_factory=dict)
    _asr_windows: dict[int, dict[str, Any]] = field(default_factory=dict)
    _next_window_id: int = 0
    _base_time: float | None = None

    def begin_chunk(
        self,
        sequence_number: int,
        pcm_bytes: int,
        sample_rate_hz: int,
        voice_activity: dict[str, Any] | None,
    ) -> None:
        self._trace = {
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

    def record_buffer_action(
        self,
        sequence_number: int,
        action: str,
        incoming_rms: int,
        buffered_ms_before: int,
        buffered_ms_after: int,
        unflushed_ms_after: int,
        appended: bool,
        appended_segments: list[dict[str, int]],
    ) -> None:
        self._trace["buffer"] = {
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
            "start_offset_ms": self._now_ms(),
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
            "confidence": None,
            "is_final": False,
        }
        self._asr_windows[window_id] = window
        self._trace["asr_window"] = window
        return window_id

    def record_recognizer_init(self, window_id: int, duration_ms: int) -> None:
        window = self._asr_windows[window_id]
        window["cold_start"] = True
        window["recognizer_init_ms"] = duration_ms

    def record_asr_inference(self, window_id: int, duration_ms: int) -> None:
        self._asr_windows[window_id]["asr_inference_ms"] = duration_ms

    def finish_asr_window(
        self,
        window_id: int,
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
        self._trace["decision"] = decision

    def envelope(self, event_payload: dict[str, Any]) -> dict[str, Any]:
        trace = dict(self._trace)
        trace["backend_response_offset_ms"] = self._now_ms()
        return {
            "kind": "recitation_trace",
            "event": event_payload,
            "trace": trace,
        }

    def _now_ms(self) -> int:
        now = self.clock()
        if self._base_time is None:
            self._base_time = now
        return int(round((now - self._base_time) * 1_000))
