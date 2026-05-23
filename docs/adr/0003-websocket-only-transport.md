# ADR 0003: WebSocket-Only Transport

- Date: 2026-05-23
- Status: Accepted

## Context

The WebSocket transport now provides better app behavior than the former room transport path.
Maintaining two transport adapters made the interface wider across backend, iOS, tests, docs, and harness state without enough leverage.

## Decision

Use `WS /ws/recitation` as the only transport.

- `RecitationStream` remains the deep processing module behind the transport:
  - `AudioChunk` -> `SessionEvent` -> wire payload -> diagnostics.
- The iOS app keeps `Simulator` and `Custom` WebSocket presets only.
- RunPod and other GPU hosts expose the ASR backend directly over WSS.
- VAD metadata remains transport-neutral `AudioChunk.voice_activity` input sent in WebSocket payloads.

## Consequences

Positive:

- One transport interface to test, document, and operate.
- WebSocket connection lifetime becomes the session seam.
- Former room-transport credentials, token generation, worker code, SDK dependencies, and smoke commands disappear.

Tradeoffs:

- Remote mobile testing depends on direct WSS reachability to the backend.
- Room-based fanout and participant identity are no longer available.

## Guardrails

- Keep one fresh `RecitationStream` per WebSocket connection.
- Keep canonical ayah text coming from Quran corpus data, not ASR transcript text.
- Keep ASR dependencies optional and outside default tests.
- Keep WebSocket fixture smokes as the transport proof before real-ASR claims.
