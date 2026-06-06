# Visual Diagnostics Tool Design

## Goal

Build a replayable visual diagnosis bundle that shows where realtime recitation
performance is being lost across microphone capture, VAD/buffering, ASR,
locator/session decisions, network latency, and client receive timing.

The tool should make it easy to answer whether the next optimization target is
audio capture, VAD thresholds, ASR buffering, ASR model quality/latency,
locator ambiguity, network/provider latency, or UI state handling.

## Scope

The first implementation slice is a replay-based developer tool. It should
replay an existing WAV fixture through the existing WebSocket backend with
diagnostics enabled, write a local bundle under `diagnostics/sessions/`, and
render an HTML timeline.

The macOS app should eventually own live-recording bundles because it can save
raw microphone audio locally and open the generated `index.html`, but the
macOS button/export flow is not part of v1.

## Core Decisions

- The diagnostic artifact is a replayable local session bundle, not only a live
  transient view.
- Generated bundles are local-only and ignored by git. They may contain raw
  voice audio and ASR transcripts.
- Normal `/ws/recitation` behavior and payloads remain unchanged.
- Diagnostic clients opt in through the query parameter
  `/ws/recitation?diagnostics=1`. V1 should not add a separate diagnostics
  header.
- Diagnostic mode returns one structured envelope per audio chunk:

```json
{
  "kind": "recitation_trace",
  "event": { "...existing RecitationEvent payload..." },
  "trace": { "...chunk-centric diagnostic data..." }
}
```

- The trace schema is chunk-centric. ASR windows, transcripts, locator
  decisions, and returned events link back to the chunk that triggered them.
- The backend sends metadata only for ASR windows. The local tool reconstructs
  audio artifacts from the PCM chunks it sent instead of receiving echoed audio
  from the backend.
- Locator diagnostics are decision-level in v1, not a full Quran-wide candidate
  scan dump.
- Transcript text is included in diagnostic envelopes because diagnosis needs
  to inspect ASR output and locator input. Normal logs remain redacted unless
  explicitly configured otherwise.
- Diagnostic mode observes the same behavior as normal recitation: same chunk
  sizing, same VAD metadata, same backend URL, same scope, same ASR buffering
  profile, and same locator thresholds.
- Diagnostic mode should return an envelope for every received audio chunk,
  including chunks whose event is only `waiting_for_audio_buffer`.

## Bundle Shape

Use this folder layout:

```text
diagnostics/sessions/20260606T143012Z-108001-scope-108/
  index.html
  trace.json
  raw-mic.wav
  asr-input.wav
  asr-windows/
    asr-window-000.wav
    asr-window-001.wav
  assets/
    diagnostics.css
    diagnostics.js
```

`diagnostics/` should be git-ignored. The bundle should not contain bearer
tokens or credential-bearing URLs.

Bundle names should use a UTC timestamp plus a safe source/scope slug, such as
`20260606T143012Z-108001-scope-108`. If the generated path already exists,
append `-2`, `-3`, and so on. Folder names must not include bearer tokens or
credential-derived text.

`trace.json` should contain normalized records for the renderer and the original
backend diagnostic envelopes for debugging instrumentation drift:

```json
{
  "metadata": {},
  "chunks": [],
  "asr_windows": [],
  "audio_artifacts": {},
  "raw_backend_envelopes": []
}
```

## Trace Model

Each chunk trace should include:

- `sequence_number`
- client capture timing, send timing, receive timing, and roundtrip latency
- raw PCM byte count, audio duration, RMS, and peak
- VAD probability, active state, and speech start/end event when present
- backend receive timing and backend response timing
- keep/drop decision, reason, and buffer duration before/after append
- whether the chunk triggered ASR
- ASR window id, kept chunk sequence numbers, tail overlap, and byte ranges
- recognizer cold-start/init duration when model loading happens
- ASR inference duration, ASR total duration, transcript, confidence, and final
  flag
- locator/session mode: initial location, ordered progression, or post-lock
  alignment
- scope, preferred ref, minimum start ref, locator status/reason, and top
  candidates
- alignment status/reason, expected word/ref, recognized word, and consumed
  words
- the existing session event payload returned for the chunk

The top-level trace metadata should include:

- diagnostic tool version
- client/replay platform
- backend URL origin/path with secrets scrubbed
- scope
- ASR model id, backend type, device, compute type
- buffering profile and numeric thresholds
- VAD model/config if known
- sample rates and chunk duration distribution
- git commit if available
- start/end timestamps
- privacy warning

Backend diagnostic envelopes should only contain backend-relative information:
receive timing, buffering decisions, ASR timing, locator/alignment decision data,
and the emitted event. The capture client should merge local information into
`trace.json`, including capture/audio offsets, send timestamps, receive
timestamps, roundtrip duration, chunk byte ranges, and local audio reconstruction
metadata.

The backend should assign `asr_window_id` only when it flushes buffered audio
into the recognizer. The client should not infer ASR window boundaries on its
own.

Use session-relative monotonic offsets and durations for per-record timing.
Top-level metadata may include UTC start/end timestamps for human context, but
chunk records should use fields such as `capture_offset_ms`, `send_offset_ms`,
`receive_offset_ms`, `backend_receive_offset_ms`, and `asr_inference_ms` rather
than absolute wall-clock timestamps. The final merged `trace.json` should align
around client-relative offsets to avoid local/remote clock skew.

## Audio Artifacts

The visual tool should expose:

- `raw-mic.wav`: full local recording or replay input.
- `asr-input.wav`: chunks the backend kept for ASR, concatenated for quick
  inspection.
- `asr-window-*.wav`: exact buffered audio windows passed to ASR.

Python should precompute compact normalized min/max waveform peak arrays for
raw mic audio, ASR input audio, and each ASR window, then store those arrays in
`trace.json`. The HTML should render waveforms from these peak arrays and use
the WAV files only for playback.

For VAD, the HTML should show probability and active/silent overlays on the raw
waveform. It should not pretend there is a cleaned VAD audio stream. "After
VAD" means "what reached ASR."

## HTML Experience

Generate the HTML experience as plain static HTML, CSS, and JavaScript with no
frontend build step. V1 should not introduce React, Vite, npm, or any bundled
frontend toolchain. Python should write `index.html`, `assets/diagnostics.css`,
and `assets/diagnostics.js` directly into the bundle.

`index.html` must work when opened directly from `file://`. To avoid local
fetch restrictions, the renderer should inline the sanitized trace data into
`index.html` as JSON while also writing the same data to `trace.json` for
inspection. WAV playback should use relative file paths.

The HTML should prioritize one synchronized timeline with lanes:

- raw waveform
- VAD probability and active regions
- backend keep/drop and buffer duration
- ASR windows with play buttons
- ASR transcripts
- locator/session events
- latency markers

Clicking a chunk, ASR window, transcript, or event should open a detail panel
with the corresponding trace JSON.

The page should make these latency metrics visible:

- capture start to first backend event
- capture start to first non-wait event
- capture start to first lock/progress/wrong event
- per-chunk capture-to-send delay
- per-chunk send-to-response roundtrip
- backend receive-to-response duration
- backend buffering wait before each ASR call
- ASR init duration when cold start occurs
- ASR inference duration per window
- locator/session transition duration per window
- total recorded audio duration versus wall-clock session duration

Include lightweight flags such as long buffering delay, many dropped chunks,
quiet input, ASR slower than audio duration, empty/short transcript, locator
ambiguity, and network roundtrip dominating backend processing. Do not claim a
single root cause in v1.

## V1 Acceptance Fixture

Use `fixtures/local_audio/108001.wav` with `scope=108` as the first acceptance
fixture. Previous evidence showed this case can produce `lock_candidate` rather
than a clean full lock, which makes it useful for determining whether the
problem is audio/VAD/buffering, ASR transcript quality, or locator ambiguity.

V1 capture should require PCM16/WAV input and should not add MP3 decoding
dependencies. MP3 fixtures can be converted to WAV outside the diagnostic tool
using existing documented audio-prep workflows.

Example command shape:

```bash
uv run python -m tarteel_realtime.diagnostics_capture \
  --url 'wss://example/ws/recitation' \
  --scope 108 \
  --audio-path fixtures/local_audio/108001.wav \
  --chunk-ms 1000 \
  --bearer-token '<token>' \
  --disable-ping
```

The CLI should support both `--bearer-token` and `--bearer-token-env NAME`.
Bearer tokens are used only for the WebSocket `Authorization` header and must
not be written to `trace.json`, `index.html`, logs, folder names, command echo,
or error messages. Metadata may include `authorization_used: true/false` and
`authorization_source: argument|environment|none`.

The replay CLI should default to real-time pacing. When `--chunk-ms 1000` is
used, it should send chunks on the same cadence implied by the audio unless the
backend response for a chunk is already slower than the next scheduled send.
V1 replay should stay request/response sequential, matching the current Swift
WebSocket client behavior. Pipelined sending can be added later as a stress
mode if transport queueing becomes the suspected bottleneck.

After capture, the CLI should print the absolute path to `index.html` and
should not open a browser automatically by default.

The CLI should perform a best-effort `/ping` precheck derived from the WebSocket
URL and store the status/duration in metadata, unless `--disable-ping` is
passed.

If the backend does not return `recitation_trace` envelopes for
`diagnostics=1`, the CLI should fail fast with a clear error instead of falling
back to normal event-only replay.

## Implementation Slice

V1 should deliver:

- `.gitignore` entry for `diagnostics/`
- backend `?diagnostics=1` envelope while preserving normal WebSocket payloads
- optional diagnostic collector side channel rather than changing core
  `SpeechRecognizer` or `RecitationSession` return types
- buffering diagnostics for keep/drop, buffer duration, flushes, tail overlap,
  and ASR window metadata
- recognizer diagnostics for cold-start/init time, inference time, and
  transcript payload
- decision-level locator/alignment diagnostics
- `tarteel_realtime.diagnostics_capture` CLI that writes the bundle and renders
  HTML
- focused tests for normal WebSocket compatibility, diagnostic envelope shape,
  trace fields, and bundle generation

Implementation should be test-first. Start with failing tests for diagnostic
envelope shape, buffered recognizer trace actions, diagnostics bundle writing,
and normal WebSocket compatibility, then implement the smallest code needed to
pass.

Test coverage should include:

- `tests/test_api.py`: normal `/ws/recitation` still returns a plain event, and
  `/ws/recitation?diagnostics=1` returns a `recitation_trace` envelope.
- `tests/test_buffered_recognition.py`: the optional trace collector receives
  the expected buffering actions.
- `tests/test_recitation_stream.py`: diagnostic trace data can be produced
  without changing normal event payloads.
- `tests/test_diagnostics_capture.py`: the CLI writes bundle files and fails if
  the backend does not return trace envelopes.

Use this fixed buffering action vocabulary in traces:

- `drop_vad_or_rms`: chunk was not appended because VAD/RMS gate rejected it.
- `append_wait_min_audio`: chunk appended, but buffer is below minimum audio
  duration.
- `append_wait_flush_interval`: chunk appended, enough minimum audio exists, but
  flush interval or speech-end condition is not met.
- `flush_asr`: chunk appended and triggered ASR.
- `drop_quiet_buffer`: buffer reached flush conditions but total buffered RMS was
  below speech threshold and got cleared.
- `reset_sample_rate`: buffer cleared because incoming sample rate changed.

## Non-Goals

- Do not add the macOS live recording/export button in v1.
- Do not change normal `/ws/recitation` payloads.
- Do not upload bundles to R2, RunPod, Modal, or any external service.
- Do not store bearer tokens or credential-bearing URLs in bundle files.
- Do not make diagnostic mode alter chunking, buffering, ASR settings, or
  locator thresholds.
- Do not dump every locator candidate comparison in v1.
- Do not claim a root cause automatically without evidence.

## Verification

Use focused deterministic checks first:

```bash
uv run python -B -m unittest tests.test_api tests.test_buffered_recognition tests.test_recitation_stream -v
uv run python -B -m unittest tests.test_diagnostics_capture -v
uv run python -m compileall -q tarteel_realtime tests
```

Then run the capture CLI against `fixtures/local_audio/108001.wav` and open the
generated `index.html` locally to verify that the raw audio, ASR input audio,
ASR windows, trace JSON, and timeline lanes are present.
