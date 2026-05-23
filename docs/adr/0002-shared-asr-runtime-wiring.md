# ADR 0002: Shared ASR Runtime Wiring

- Date: 2026-05-21
- Status: Accepted

## Context

ASR runtime wiring (env parsing, recognizer factory creation, buffering settings) was centered in `asr_app.py`, while earlier transport adapters depended on that wiring indirectly.
This made ASR runtime changes riskier because app-specific composition and runtime wiring were not clearly separated.

## Decision

Introduce `asr_runtime.py` as the shared runtime wiring module.

- `asr_runtime.py` owns:
  - `AsrRuntimeSettings`
  - `settings_from_env(...)`
  - lazy recognizer factory
  - buffered recognizer factory
  - shared runtime defaults
- `asr_app.py` now focuses on FastAPI composition and re-exports runtime symbols for backward compatibility.
- Transport/runtime callers import shared factories/settings directly from `asr_runtime.py`.

## Consequences

Positive:

- ASR runtime behavior is defined once for the ASR app and WebSocket path.
- Runtime changes are easier to validate with focused tests.
- App composition is cleaner and less coupled to recognizer wiring details.

Tradeoffs:

- Additional module boundary to maintain.
- Backward compatibility exports in `asr_app.py` need to be kept until downstream imports migrate.

## Guardrails

- Keep heavy ASR dependencies optional.
- Preserve stable ASR defaults unless explicitly changed.
- Maintain compatibility exports in `asr_app.py` while tests and callers still use them.
