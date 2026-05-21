# Quality Document

Rolling quality record for the Tarteel real-time Quran recitation MVP.

## Current Baseline

- Date: 2026-05-19
- Overall status: good enough MVP, not production-grade
- Initial quality score: 8.0 / 10
- Basis: deterministic Python suite, compile checks, Swift client tests, iOS simulator build, LiveKit simulator verification, RunPod real-ASR proof paths, and documented R2/GitHub bootstrap flow.

The MVP has strong harness discipline and a working real-ASR mobile path, but it still needs longer-session proof, physical-device validation, latency tuning, and more polished ordered-progression guidance.

## Quality Dimensions

| Dimension | Status | Notes |
| --- | --- | --- |
| Correctness and reliability | Good | Core Quran parsing, locator, session state, ASR buffering, and LiveKit transport have deterministic coverage. Real ASR remains model- and audio-quality-sensitive. |
| Test coverage | Good | Fast Python and Swift tests cover most local contracts. Real model checks are intentionally opt-in and require RunPod/GPU evidence. |
| Architecture and boundaries | Good | Fake backend, WebSocket fallback, LiveKit path, ASR adapters, and iOS state reducer are separated. Heavy dependencies remain optional. |
| Mobile UX readiness | MVP | Simulator path works and exposes ayah/ayah text status. Physical iPhone, latency, and guidance copy need more work. |
| ASR/model maturity | Experimental | `tarteel-ai/whisper-base-ar-quran` and `basharalrfooh/whisper-small-quran` have been compared on targeted cases, but neither is production-validated. |
| Ops reproducibility | Good | Public GitHub plus R2 hydration and RunPod bootstrap reduce manual copying. GPU pods still need explicit user coordination. |
| Documentation and handoff | Good | Harness files capture progress, feature state, clean-state checks, and session context. This document and rubric add quality tracking. |
| Privacy and secrets | Good | Raw audio and credentials are not committed. R2/LiveKit/RunPod secrets stay local. Continue checking this during every artifact change. |

## Known Quality Debt

- Physical-device LiveKit testing is still outstanding.
- Longer-surah and longer-session recitation behavior needs evaluation beyond targeted Surah 102 and Surah 114 paths.
- Latency and chunking are tuned for MVP stability, not final user experience.
- Ordered-progression guidance exists in backend behavior but still needs polished user-facing copy.
- Real ASR can hallucinate or clip phrases; canonical ayah display mitigates UI truth, but correction confidence still needs more evidence.
- Production privacy design for live microphone audio is not complete.

## Quality Gates

Before treating a future slice as passing:

- Run the focused checks that prove the changed behavior.
- Run the full Python suite for shared backend/session/locator changes.
- Run Swift tests and the iOS build for client/UI changes.
- Use RunPod/GPU only when the claim depends on real ASR inference.
- Record commands, results, remaining risk, and next step in the harness docs.
- Keep `feature_list.json` with at most one `in_progress` feature.

## Quality Log

### 2026-05-19 - Harness Quality Baseline

- Added project-specific agent operating instructions, evaluator rubric, and quality record.
- Current MVP quality posture is good enough for continued product slices, not for production release.
- Highest leverage next quality improvements: physical-device verification, longer-surah evaluation, latency tuning, and polished ordered-progression UX.
- Verified the harness update with `uv run python -B -m json.tool feature_list.json`, `uv run python -B -m unittest discover -s tests -v` with 136 tests passing, and `uv run python -m compileall -q tarteel_realtime tests`.

### 2026-05-19 - Reduced Chunking Gate Blocked

- Local buffering/session/app tests and the full deterministic suite still pass, but the real RunPod reduced-window gate did not pass clean Surah 102.
- `tarteel-ai/whisper-base-ar-quran` can lock short Surah 114 and preserve quiet-window safety at `2500/1500/500`, but both `2500/1500/500` and `3000/2000/500` produced mostly `wrong` or `uncertain` events on clean Surah 102 instead of stable live progression.
- Release confidence for reduced-window live tracking remains blocked until the team either accepts a RapidFuzz gate override or chooses a different model/windowing strategy that passes long-audio progression first.

### 2026-05-19 - RapidFuzz Matching Implemented, Live Tracking Still Blocked

- RapidFuzz replaced the tolerant locator scoring backend and deterministic tests now cover clipped Surah 98 fragments, scoped no-jump behavior, and wrong-recitation guardrails.
- Local verification is strong: focused RapidFuzz tests, focused ASR buffering/session/app tests, the full Python suite, compile check, JSON validation, and the Surah 98 evaluator all passed.
- RunPod evidence is mixed: 114 locks with correction safety preserved, quiet audio still skips Whisper inference, and Surah 98 locks all eight ayahs with 17 progress events.
- The quality risk remains live ASR transcript stability. Clean Surah 102 under `2500/1500/500` still produced 0 progress events after the first noisy lock, so this is not ready to call usable live ayah tracking.

### 2026-05-19 - Stable ASR Defaults Restored

- Reduced-window chunking was accepted as a failed live-ASR default and rolled back from active settings.
- The backend now defaults again to `4200/4200/0`, while smaller windows remain possible only through explicit environment overrides.
- RapidFuzz matching was kept because deterministic tests and Surah 98 evidence show it helps matching quality, even though it cannot repair very poor short-window ASR transcripts by itself.
- Rollback verification passed with the focused ASR buffering/session/app suite at 28 tests, the full deterministic Python suite at 143 tests, and compile check.
- The next quality gate is a RunPod replay using restored stable defaults plus RapidFuzz, especially Surah 102 and quiet audio.

### 2026-05-19 - LiveKit Pre-Buffer VAD Safety

- The LiveKit `Last event: none` symptom was traced to an ASR crash after audio transport succeeded, not to Surah 98 matching: RunPod received iOS audio, flushed a low-energy window around `buffered_rms=124`, then Whisper/Torch raised a CUDA device-side assert before the worker could publish an event.
- The backend now gates speech energy after WebSocket/LiveKit frame decode and before rolling ASR buffering. Low-RMS startup frames produce `waiting_for_audio_buffer` with `action=wait_vad` instead of entering Whisper.
- `TARTEEL_ASR_MIN_SPEECH_RMS=400` is documented as the default, and existing `wait_quiet` safety still protects accumulated quiet windows.
- LiveKit ASR/session exceptions now surface as `uncertain` events with `reason=asr_error`, improving failure visibility in the app.
- Verification passed locally with 25 focused tests, 146 full deterministic tests, compile check, a RunPod compile/smoke check, and a connected RunPod LiveKit worker ready for manual Surah 98 retest.

### 2026-05-19 - LiveKit Soft-Speech Gate Split

- A follow-up manual LiveKit test reached ayah text but stalled at ayah 1. RunPod logs showed the worker kept receiving frames, but after the last flush the buffer stalled at about `3110ms` because the 400 RMS per-frame gate dropped too much soft recitation.
- The gate now uses `TARTEEL_ASR_MIN_FRAME_RMS=150` for individual decoded frames and keeps `TARTEEL_ASR_MIN_SPEECH_RMS=400` for complete buffers before Whisper. This keeps low-noise startup safety while allowing softer speech to accumulate enough audio.
- Evidence from the failed run supported the threshold split: post-flush frames above 400 RMS totaled about `3110ms`, while frames above 150 RMS totaled about `4430ms`, enough for the 4200ms ASR window.
- Verification passed with 16 focused buffer/app tests, 26 focused buffer/app/LiveKit worker tests, 147 full deterministic tests, compile check, RunPod compile/smoke, and a restarted RunPod LiveKit worker with a fresh log.

### 2026-05-19 - LiveKit Session Isolation And Visible State

- Filtered RunPod LiveKit replay proved the worker was receiving audio and could advance Surah 98 from `98:1` to `98:2`; the remaining failure mode is noisy ASR output, not a frozen transport.
- The LiveKit runner no longer shares one `RecitationSession` and one rolling ASR buffer across every subscribed audio track. Each track now receives a fresh worker/session/buffer while the heavy Whisper model remains lazily shared.
- The iOS reducer now preserves the last meaningful post-lock event when `waiting_for_audio_buffer` arrives, so the UI should not look stuck simply because buffer-wait packets are frequent.
- Verification passed with red/green backend and Swift regressions, 27 focused backend tests, 16 Swift client core tests, 148 full deterministic Python tests, compile check, iOS app build, RunPod worker compile check, and a warm two-pass LiveKit replay that locked `114:2` twice in one worker process.
- Quality risk remains ASR/progression accuracy: clean Surah 102 still skipped early short ayahs in the fixture and then produced mostly `wrong` events after `102:4`.

### 2026-05-19 - Simulator WebSocket Handshake Fix

- The `Simulator` preset `Socket is not connected` symptom was traced to an iOS client race: microphone streaming could begin immediately after `task.resume()` before the WebSocket open handshake had completed.
- `BackendWebSocketClient` now waits for a successful WebSocket ping before streaming mic chunks, and Simulator connection failures now tell the user to start the local backend on `127.0.0.1:8000`.
- Verification passed with the new red/green WebSocket source regressions, 11 focused iOS source tests, 150 full deterministic Python tests, compile/JSON/whitespace checks, a successful iOS app target build, local backend health returning HTTP 200, and the rebuilt app launched in the iPhone 17 Pro simulator.
- Quality risk remains separate from this fix: local WebSocket connection stability is improved, but LiveKit ASR progression and model transcript quality still need their own evidence.

### 2026-05-19 - LiveKit Session Isolation

- The latest manual Surah 98 symptom was not caused primarily by RapidFuzz. RunPod logs showed six subscribed LiveKit tracks in the shared room, including stale diagnostic/warm tracks and multiple `ios-reciter` tracks, while the iOS app accepted every reliable recitation packet on the topic.
- The LiveKit contract now carries `session_id`: token responses generate unique client identities by default, worker events include the publishing participant identity, and iOS filters incoming events to the current token session.
- Worker track consumers are now cancellable on `track_unsubscribed`, reducing stale background event producers in the shared room.
- Local verification passed with red/green Python and Swift regressions, 37 focused LiveKit/API/iOS tests, 17 Swift client tests, 154 full deterministic Python tests, compile check, and iOS app build.
- RunPod code patch, inline smoke, worker restart, and LiveKit smoke passed. The active worker is connected with a clean log, and a smoke event returned a matching `session_id`, so manual Surah 98/102 retesting can now focus on ASR/progression quality instead of shared-room event contamination.

### 2026-05-19 - Faster-Whisper Quran Model Spike

- `OdyAsh/faster-whisper-base-ar-quran` runs successfully with the `faster-whisper` package on the active RunPod NVIDIA L4 using `compute_type=float16`.
- Short Surah 114 evidence is good: the model transcribed and located `114001.wav` to `114:1` and `114002.wav` to `114:2`.
- Ordered Surah 102 evidence is promising when using per-ayah transcripts through the existing session engine: all eight ayahs locked in order.
- Surah 98 evidence remains mixed: per-ayah transcripts lock ayahs 1-4, then ASR hallucinated extra trailing words in 98:5 and the session correctly treated later ayahs as out-of-order.
- The current Transformers adapter cannot load this model ID because it is a CTranslate2/faster-whisper conversion, so app integration requires an optional faster-whisper backend rather than an environment-only model swap.
- A separate quality bug was exposed: standalone Tanzil pause marks such as `ۚ` are parsed as empty Quran words, which can cause false `no_match` results even for an otherwise correct ASR transcript.

### 2026-05-19 - Optional Faster-Whisper Backend For LiveKit

- Added a selectable ASR backend while keeping Transformers as the default. `TARTEEL_WHISPER_BACKEND=faster-whisper` now routes through a CTranslate2/faster-whisper recognizer.
- The backend parses `cuda:0`, accepts `TARTEEL_FASTER_WHISPER_COMPUTE_TYPE=float16`, and resamples PCM to 16 kHz before inference so LiveKit 48 kHz audio can reach faster-whisper safely.
- Local verification passed with red/green tests, 14 focused adapter/app tests, 26 focused adapter/app/LiveKit tests, 157 full deterministic Python tests, and compile check.
- RunPod verification passed for model construction and a short `114002.wav` recognizer smoke: transcript `مَلِكِ النَّاسِ`, normalized `ملك الناس`.
- The active RunPod LiveKit worker is connected using the OdyAsh faster-whisper model and returned a matching-session smoke event, so manual iOS Simulator testing can proceed.
- Operational risk: the pod workspace mount hit a write quota during patching, so the active worker is running from `/tmp/tarteel-realtime-live`; future pod edits should repair or freshly bootstrap `/workspace/tarteel-realtime`.

### 2026-05-19 - Explicit iOS Silero VAD Bundle

- The iOS client now bundles `silero-vad-unified-256ms-v6.0.0.mlmodelc` from `FluidInference/silero-vad-coreml`, so WebSocket fallback VAD no longer depends on FluidAudio reaching Hugging Face at runtime.
- `VoiceActivityDetector` now prefers the bundled Core ML model through `VadManager(config: .default, vadModel:)`, falls back to `VadManager()` only when the bundle is absent, and uses FluidAudio's streaming `processStreamingChunk(...)` state machine.
- VAD stream state resets on recording start/stop, preventing stale speech state from leaking between sessions.
- Verification passed with red/green iOS VAD source tests, 10 focused iOS VAD tests, 17 Swift client core tests, a successful iOS app target build, and a built-app resource check confirming the `.mlmodelc` is packaged.
- Quality risk: this currently improves the WebSocket fallback metadata path. The LiveKit preset still publishes microphone audio through LiveKit directly, so using iOS VAD to affect LiveKit transport needs a separate data-topic or custom-capture design.

### 2026-05-20 - LiveKit Client-Side VAD Capture Path

- The LiveKit iOS preset now uses the same app-owned microphone stream as WebSocket: PCM16 capture, bundled Silero VAD, then a transport adapter.
- LiveKit uses SDK manual rendering mode and `AudioManager.shared.mixer.capture(appAudio:)`, with VAD metadata published on `tarteel.voice_activity`.
- The worker decodes LiveKit Python `DataPacket` objects and attaches latest VAD metadata by participant identity before rolling ASR buffering.
- Local verification passed for the new red/green iOS source and worker tests, 47 focused LiveKit/token/API/iOS contract tests, 167 full Python tests, compile check, 17 Swift client core tests, JSON validation, `git diff --check`, and an iOS app target build.
- Quality risk: manual LiveKit mic verification is still required, especially to check whether client-side suppression clips initial speech before VAD triggers.
