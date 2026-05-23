# ADR 0001: Recitation Stream And Transition Seams

- Date: 2026-05-21
- Status: Superseded by ADR 0003 for transport strategy

## Context

WebSocket and the former room transport were both active transport adapters in this repository.
Without a shared processing seam, event behavior and diagnostics could diverge between adapters.
Also, recitation-state transitions were previously embedded directly inside `RecitationSession`, making policy changes harder to isolate.

## Decision

Adopt shared recitation seams:

- `RecitationStream` is the adapter-neutral processing path for:
  - `AudioChunk` -> `SessionEvent` -> wire payload -> diagnostics.
- `RecitationTransitionPolicy` owns the stateful post-recognition decision tree.
- `RecitationSession` is narrowed to recognizer adaptation:
  - `AudioChunk` -> `RecognitionResult` -> transition policy.
- `session_events.py` and `event_payloads.py` remain the canonical event/payload contract modules.

## Consequences

Positive:

- The transport adapters shared one event/payload/diagnostics path while both existed.
- Transition-policy logic can evolve without transport coupling.
- Session behavior is easier to test directly from `RecognitionResult` inputs.

Tradeoffs:

- More modules and seams to understand.
- Runtime deployments must include all seam modules together to avoid mixed behavior across environments.

## Guardrails

- Keep payload shape stable for existing clients.
- Keep `QuranLocator.locate_recitation(...)` as the caller-facing location seam.
- Preserve deterministic fake-recognizer coverage for session transitions.
