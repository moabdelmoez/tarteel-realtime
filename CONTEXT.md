# CONTEXT

This document defines shared domain language for the Tarteel realtime MVP.

## Product Scope

The MVP detects where the reciter is in Quran text and surfaces obvious text-level correction signals in realtime.
It is not tajweed scoring, phoneme scoring, or a production memorization coach.

## Core Domain Objects

- `QuranCorpus`: parsed canonical Quran text and referenceable words/ayahs.
- `QuranRef`: stable reference shape `surah:ayah[:word_index]`.
- `AudioChunk`: transport chunk with PCM16 bytes, sample rate, sequence number, optional VAD metadata.
- `RecognitionResult`: recognizer output (`transcript`, `confidence`, `chunk_sequence`, `is_final`).
- `SessionEvent`: canonical event contract emitted to clients (`locating`, `lock_candidate`, `locked`, `progress`, `wrong`, `uncertain`).

## Recitation Flow

The canonical flow is:

1. transport audio chunk (`AudioChunk`)
2. recognition output (`RecognitionResult`)
3. transition policy (`SessionEvent`)
4. wire payload + diagnostics

`RecitationStream` owns steps 1->4 behind the WebSocket transport.

## Session And Matching Seams

- `RecitationSession`: recognizer adapter (`AudioChunk` -> `RecognitionResult`) plus delegation.
- `RecitationTransitionPolicy`: stateful post-recognition decision tree.
- `QuranLocator.locate_recitation(...)`: public recitation-location seam.
- `CoreMLLocalQuranSession`: Apple local recitation-location seam that maps cumulative CoreML transcripts to SessionEvent-compatible recitation events.
- `locator_matching.py`: exact/tolerant/span matching internals, scoring, and scope constraints.
- `RecitationProgression`: ordered progression state (next expected word/ayah, ordered misses, anchor refs).
- `session_events.py`: event constructors and event type semantics.
- `event_payloads.py`: transport-neutral payload encoding with canonical ayah text enrichment.

## Runtime Wiring Seams

- `asr_runtime.py`: ASR settings parsing and recognizer factory wiring.
- `asr_app.py`: FastAPI app composition around runtime wiring.

## Transport Adapters

- WebSocket transport path: `/ws/recitation`.
- iOS `Custom` preset accepts local, LAN, tunnel, or RunPod WSS URLs for that path.

## Invariants

- Canonical displayed ayah text must come from Quran corpus data, not raw ASR transcript.
- Heavy ASR dependencies remain optional; fake recognizer path remains default for deterministic tests.
- `QuranLocator.locate_recitation(...)` remains the caller-facing location API even if internals evolve.
- Post-lock ordered progression should prefer local/ordered recovery before broad relocking.
