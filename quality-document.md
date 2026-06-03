# Quality Document

Rolling quality record for the Tarteel real-time Quran recitation MVP.

## Current Baseline

- Date: 2026-06-03
- Overall status: good enough MVP, not production-grade
- Initial quality score: 8.0 / 10
- Basis: deterministic Python suite, compile checks, Swift client tests, iOS simulator build, WebSocket simulator verification, RunPod real-ASR proof paths, and documented R2/GitHub bootstrap flow.

The MVP has strong harness discipline and a working real-ASR mobile path, but it still needs longer-session proof, physical-device validation, latency tuning, and more polished ordered-progression guidance.

## Quality Dimensions

| Dimension | Status | Notes |
| --- | --- | --- |
| Correctness and reliability | Good | Core Quran parsing, locator, session state, ASR buffering, and WebSocket transport have deterministic coverage. Real ASR remains model- and audio-quality-sensitive. |
| Test coverage | Good | Fast Python and Swift tests cover most local contracts. Real model checks are intentionally opt-in and require RunPod/GPU evidence. |
| Architecture and boundaries | Good | Fake backend, WebSocket transport, ASR adapters, and iOS state reducer are separated. Heavy dependencies remain optional. |
| Mobile UX readiness | MVP | Simulator path works and exposes ayah/ayah text status. Physical iPhone, latency, and guidance copy need more work. |
| ASR/model maturity | Experimental | `tarteel-ai/whisper-base-ar-quran` and `basharalrfooh/whisper-small-quran` have been compared on targeted cases, but neither is production-validated. |
| Ops reproducibility | Good | Public GitHub plus R2 hydration, RunPod packaging, and Modal provider-comparison scaffolding reduce manual copying. Live GPU endpoints still need explicit user coordination and measured evidence. |
| Documentation and handoff | Good | Harness files capture progress, feature state, clean-state checks, and session context. This document and rubric add quality tracking. |
| Privacy and secrets | Good | Raw audio and credentials are not committed. R2 and RunPod secrets stay local. Continue checking this during every artifact change. |

## Known Quality Debt

- Physical-device WebSocket testing is still outstanding.
- macOS native UI polish is source/build verified, but manual light/dark visual QA, keyboard focus, drag/drop, diagnostic drag-out, Settings validation layout, microphone permission, and live backend recording are still outstanding.
- Longer-surah and longer-session recitation behavior needs evaluation beyond targeted Surah 102 and Surah 114 paths.
- Latency and chunking are tuned for MVP stability, not final user experience.
- Ordered-progression guidance exists in backend behavior but still needs polished user-facing copy.
- Real ASR can hallucinate or clip phrases; canonical ayah display mitigates UI truth, but correction confidence still needs more evidence.
- Production privacy design for live microphone audio is not complete.
- Modal and RunPod serverless paths are locally contract-verified but still need live endpoint timing, cost, idle shutdown, and real-ASR replay proof.

## Quality Gates

Before treating a future slice as passing:

- Run the focused checks that prove the changed behavior.
- Run the full Python suite for shared backend/session/locator changes.
- Run Swift tests and the iOS build for client/UI changes.
- Use RunPod/GPU only when the claim depends on real ASR inference.
- Record commands, results, remaining risk, and next step in the harness docs.
- Keep `feature_list.json` with at most one `in_progress` feature.

## Quality Log


### 2026-06-03 - macOS Native UI Polish

- The macOS prototype moved closer to native utility-app behavior with a unified compact toolbar, integrated recording/search/settings controls, keyboard commands, URL/text drop-in, diagnostic drag-out, first-run onboarding, empty states, event history, adaptive colors/materials, and Settings validation feedback.
- Shared presentation state lives in `TarteelClientCore`, keeping macOS UI behavior tied to the same recording state machine instead of app-local string handling.
- Local confidence is good for contracts and builds: Swift client core passed with 42 checks, focused Apple source guardrails passed with 20 tests, the macOS and iPhone app targets built, the full deterministic Python suite passed with 223 tests, and compileall passed for `tarteel_realtime` and `tests`.
- Release posture: ready for manual macOS visual and interaction QA. It is not yet proof of microphone permission flow, live recording ergonomics, or real ASR quality.


### 2026-05-28 - Modal Serverless Provider Comparison Scaffold

- Modal was added as a same-repo provider adapter around the existing ASR FastAPI app, not as a new transport or separate deployment repo.
- `TARTEEL_WS_BEARER_TOKEN` now protects `WS /ws/recitation` when configured while keeping `/health` and `/ping` public for provider probes.
- `tarteel_realtime.replay_probe` gives RunPod and Modal the same evidence surface: connect timing, first non-wait event timing, event counts, first lock/progress refs, optional raw events, scope, and bearer-token handling.
- The Apple settings gear now has a Custom provider picker for Generic, RunPod, and Modal, with memory-only bearer-token entry shared by iPhone and macOS.
- Local confidence is good for contracts and builds: focused Modal/replay/backend/Apple checks passed with 64 tests, compileall passed for `deploy`, `tarteel_realtime`, and `tests`, Swift client core passed with 39 tests, iPhone and macOS app targets built, and the full deterministic Python suite passed with 218 tests.
- Release posture: ready for Modal prewarm/deploy and provider comparison replay. It is not yet live Modal evidence and should not be treated as a RunPod replacement decision.


### 2026-05-25 - Native macOS Prototype

- Added a native macOS SwiftUI developer prototype target beside the existing iPhone target in the same Xcode project, without moving the Apple client tree out of `ios/`.
- The macOS app reuses the shared `RecitationViewModel`, shared WebSocket transport, shared preferences, and existing FluidAudio/CoreML Silero VAD path while injecting a macOS `AVAudioEngine` microphone streamer.
- The macOS target uses a separate macOS plist, macOS 14 deployment, native Settings scene, desktop status console, and no App Sandbox entitlements for this developer prototype slice.
- Local confidence is build-level: Swift client core passed with 36 tests total, focused Apple guardrails passed with 16 tests, iPhone and macOS app targets both built, JSON validation and whitespace checks passed, and the full deterministic Python suite passed with 202 tests.
- Release posture: good for a developer prototype and shared-client architecture proof. Manual macOS microphone and live RunPod ASR testing remain next-slice acceptance work.


### 2026-05-25 - Shared Recording Orchestration

- `RecitationViewModel` moved from the iPhone app target into `TarteelClientCore` so future native clients can reuse the same recording, socket, VAD, reducer, selected-scope, and preference orchestration.
- The shared view model uses protocol-injected `BackendSocketing`, `AudioStreaming`, `VoiceActivityDetecting`, and `RecitationPreferencesStoring`; the default `BackendWebSocketClient` is still created safely inside the `@MainActor` initializer body.
- A follow-up review fix guards duplicate starts while the first connect is in flight and serializes audio chunk handling so VAD processing and socket sends stay FIFO with capture-order sequence numbers.
- A second follow-up generation-gates delayed startup completions, send failures, and backend callbacks so old work cannot mutate stopped or restarted session state.
- Local confidence is good for the client contract: red Swift package tests first failed because `RecitationViewModel` was missing from core, review regression tests then failed for duplicate connect, out-of-order chunk processing, stale startup completion, stale send failures, and stale socket callbacks before the fixes; Swift client core passed with 36 tests total (12 XCTest-style tests plus 24 Swift Testing tests), focused iOS source guardrails passed with 11 tests, additional touched VAD/audio source guardrails passed with 7 tests, and the iOS app target built successfully after clearing stale derived-data caches.
- Release posture: safe as an architecture refactor for shared clients. It does not change or prove live ASR quality.


### 2026-05-25 - iOS Clean Home And Settings Sheet

- The iOS prototype home screen now uses a white, readable recitation-focused layout instead of exposing backend controls inline.
- Backend preset, custom WebSocket URL, and prototype-only RunPod API key moved behind a gear settings sheet; Auto/Surah and Surah picker remain on the home screen because they are recitation controls.
- Local confidence is good for this UI organization slice: source guardrails first failed on the old layout, then focused iOS source checks passed with 11 tests, Swift client core passed with 24 tests, the iOS app target built successfully after approved CoreSimulator/package access, and final harness checks passed with feature JSON validation, whitespace check, and 197 deterministic Python tests.
- A simulator visual sanity check installed and launched the rebuilt app in the booted iPhone 17 Pro simulator and captured `/private/tmp/tarteel-clean-home.png`.
- Release posture: ready for manual settings-sheet interaction testing. This slice does not change or prove live ASR behavior.


### 2026-05-24 - RunPod Serverless Prototype Path

- The backend now exposes `/ping` for RunPod load-balancer health checks while preserving `/health` and `WS /ws/recitation`.
- Serverless packaging is local-contract verified through `Dockerfile.runpod-serverless` and `scripts/runpod_serverless_start.sh`, which default to faster-whisper, `OdyAsh/faster-whisper-base-ar-quran`, CUDA `cuda:0`, `float16`, cached Hugging Face model lookup, and the low-latency ASR profile.
- The ASR runtime resolves RunPod cached Hugging Face snapshots under `/runpod-volume/huggingface-cache/hub` when present, avoiding model-ID downloads on correctly configured endpoints while preserving local fallback behavior.
- The iOS prototype can normalize bare `<endpoint-id>.api.runpod.ai` hosts, keep selected-recitation scope query handling, and send `Authorization: Bearer <token>` from a local RunPod API key field for Custom endpoints.
- Release posture: this is ready for a serverless deployment smoke, not a live-ASR quality claim. The endpoint has not yet been built, pushed, deployed, fixture-replayed, or measured for cold start, scale-to-zero, and billing behavior.


### 2026-05-24 - iOS Selected-Recitation UI

- The iOS prototype now exposes an Auto versus Surah recitation mode and a surah menu backed by local Quran surah metadata.
- Selected Surah mode appends `scope=<surah-id>` to the WebSocket URL before recording, so the already-merged backend selected-scope behavior can be used without manually editing the Custom URL. Auto mode removes the app-managed `scope` query item and preserves other query parameters.
- Local confidence is good for the client contract: Swift client core passed with 23 tests, the new iOS source guardrail passed, the full Python suite passed with 190 tests, compile and JSON checks passed, whitespace passed, and the iOS app target built successfully after rerunning with a fresh derived-data path because the old `/private/tmp/tarteel-xcode-derived` FluidAudio checkout was stale.
- Release posture: this is ready for manual Simulator/device testing against a scoped backend. It does not by itself prove real-ASR quality; scoped RunPod replay and manual recitation remain the acceptance gate for live recognition quality.


### 2026-05-24 - Point 5 Local Selected-Recitation Scope

- Point 5 adds optional selected-recitation scope on the WebSocket URL while preserving the existing audio payload contract.
- Deterministic tests cover scope parsing, scoped initial location, out-of-scope initial no-match behavior, scoped WebSocket query wiring, and stopping ordered progression after the selected range ends.
- Local confidence is good: focused selected-scope tests passed with 44 tests, full deterministic suite passed with 187 tests, compile passed, JSON parsed, and `git diff --check` passed.
- Release posture: acceptable to merge as an opt-in backend capability because default behavior is unchanged; scoped RunPod faster-whisper replay is still required before claiming low-latency/default-quality improvement.


### 2026-05-24 - Point 4 Final Lock-Stability Replay

- Point 4 now prevents unscoped global tolerant-span locks from becoming initial locks; this blocked the previous `004001 -> 39:6` false lock and let the replay reach `4:1` instead.
- Final RunPod replay from `a188fd4` preserved short gains for `108001` and `108003`, while `108002` still did not lock.
- Long Surah 4 final replay first locked `004001 -> 4:1`, `004002 -> 4:2`, and `004003 -> 4:3`, but some locks start mid-ayah and noisy wrong/progress events remain.
- Release posture: Point 4 is a valid branch/manual-test candidate, but low-latency remains opt-in. The next quality slice should use selected recitation scope to reduce full-Quran ambiguity.


### 2026-05-24 - Point 4 Lock Stability Local Gate

- Point 4 adds a candidate-stability gate for initial tolerant locks: weak global tolerant matches now produce `lock_candidate/needs_confirmation`, while exact unique locks and stronger tolerant matches remain immediate.
- Ordered ayah-boundary recovery now accumulates short snippets only through the expected ordered ayah window, preserving the no-global-relock safety posture after the first lock.
- Local proof is strong for the state-machine contract: focused session/locator/API/stream checks passed with 57 tests, full deterministic Python passed with 180 tests, and compile check passed.
- Release posture: do not merge or call this a live quality improvement until RunPod faster-whisper replay confirms Surah 108 remains improved and long Surah 4 no longer false-locks globally.

### 2026-05-24 - Point 3 Pre-Lock ASR Context

- Point 3 adds a bounded set of pre-lock transcript context alternatives so low-latency ASR snippets can combine before the first location lock.
- Local proof is strong for the state-machine contract: focused session/locator/API/stream checks passed with 55 tests, full deterministic Python passed with 178 tests, compile check passed, and whitespace check passed.
- RunPod proof is mixed but useful: `108001` improved from no lock to `108:1` at sequence 5, and `108003` improved from no clean lock to `108:3` at sequence 5.
- `108002` still no-matches, and long Surah 4 replay still false-locks under the low-latency profile, so this is not a default-quality live tracking gate.
- Release posture: keep this as a branch/manual-test candidate for short-ayah startup only; continue with false-lock mitigation before any main/default promotion.

### 2026-05-24 - Low-Latency ASR Buffering Profile

- Point 2 adds a named opt-in `low-latency` buffering profile while keeping `stable` as the default production-safe profile.
- The profile is architecture-aligned with the shared ASR runtime: env parsing selects a named profile, explicit env window variables override it, and `BufferedRecognizer` still receives a concrete config.
- Local proof is strong for the code contract: focused ASR buffering/runtime/app tests passed, the full deterministic suite passed with 172 tests, compile check passed, JSON validation passed, and whitespace check passed.
- RunPod proof confirms the latency mechanism: faster-whisper on CUDA `cuda:0` with `float16` flushed at 2 seconds on sequence 1 for most 1s-chunk replays, instead of waiting for the old 4.2 second stable window.
- Quality risk remains ASR transcript quality, not transport or buffering. Short Surah 108 samples produced early events but stayed at `lock_candidate` or `no_match`; long Surah 4 samples produced early events but still emitted noisy wrong/uncertain events.
- Release posture: keep `low-latency` opt-in until manual app testing confirms the cadence tradeoff and a later slice improves short-ayah recognition/segmentation.

### 2026-05-23 - Faster-Whisper Point 1 RunPod Replay

- Point 1 of the latency plan is verified as an infrastructure/runtime slice: faster-whisper can run behind the existing WebSocket ASR backend on RunPod using `OdyAsh/faster-whisper-base-ar-quran`, CUDA `cuda:0`, and `float16` on an NVIDIA L4.
- The GPU bootstrap path now hydrates the long Surah 4 and short Surah 108 MP3 fixtures from R2, converts them to mono 16 kHz WAV, and can check out a feature branch via `TARTEEL_GIT_REF`.
- WebSocket replay tooling now supports disabled client pings for long first model-load windows.
- RunPod replay evidence is mixed but actionable: warmed long Surah 4 first produced an ASR-backed event in 0.390s and locked `4:1`, while isolated `108001.wav` still stopped at `lock_candidate` and long replay still emitted false `wrong` events.
- Quality risk: this improves backend/runtime latency and reproducibility but does not yet reduce the stable ASR buffering window or solve short-ayah verification waits.

### 2026-05-23 - WebSocket-Only Transport

- The app and backend now use WebSocket as the only transport: `/ws/recitation` locally, by LAN, or through RunPod WSS.
- The former room transport, token endpoint, worker modules, SDK client, package references, and smoke commands were removed.
- iOS keeps `Simulator` and `Custom` presets only; `Custom` accepts RunPod WSS URLs and normalizes bare RunPod proxy hosts to `/ws/recitation`.
- VAD remains transport-neutral through `AudioChunkPayload.voice_activity` and backend `AudioChunk.voice_activity`.
- Verification passed with 27 focused Python backend/iOS-source tests, 164 full deterministic Python tests, compile check, JSON validation, 17 Swift client tests, the iOS simulator app build, and a local WebSocket smoke that returned the scripted `locked` then `wrong` events.

### 2026-05-23 - Embedded Evaluator Smoke Cases

- The committed Quran/evaluation smoke fixtures were removed; the same Juz Amma, Surah 102, and Surah 98 evaluator coverage now lives inside `tests/test_evaluate_cli.py`.
- Live workflow docs now point to embedded tests or the local full Tanzil file instead of deleted fixture paths.
- Verification passed with `uv run python -B -m unittest tests.test_evaluate_cli -v`, the full Python suite, compile check, JSON validation, and `git diff --check`.

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

### 2026-05-19 - former room transport Pre-Buffer VAD Safety

- The former room transport `Last event: none` symptom was traced to an ASR crash after audio transport succeeded, not to Surah 98 matching: RunPod received iOS audio, flushed a low-energy window around `buffered_rms=124`, then Whisper/Torch raised a CUDA device-side assert before the worker could publish an event.
- The backend now gates speech energy after WebSocket/former room transport frame decode and before rolling ASR buffering. Low-RMS startup frames produce `waiting_for_audio_buffer` with `action=wait_vad` instead of entering Whisper.
- `TARTEEL_ASR_MIN_SPEECH_RMS=400` is documented as the default, and existing `wait_quiet` safety still protects accumulated quiet windows.
- former room transport ASR/session exceptions now surface as `uncertain` events with `reason=asr_error`, improving failure visibility in the app.
- Verification passed locally with 25 focused tests, 146 full deterministic tests, compile check, a RunPod compile/smoke check, and a connected RunPod former room transport worker ready for manual Surah 98 retest.

### 2026-05-19 - former room transport Soft-Speech Gate Split

- A follow-up manual former room transport test reached ayah text but stalled at ayah 1. RunPod logs showed the worker kept receiving frames, but after the last flush the buffer stalled at about `3110ms` because the 400 RMS per-frame gate dropped too much soft recitation.
- The gate now uses `TARTEEL_ASR_MIN_FRAME_RMS=150` for individual decoded frames and keeps `TARTEEL_ASR_MIN_SPEECH_RMS=400` for complete buffers before Whisper. This keeps low-noise startup safety while allowing softer speech to accumulate enough audio.
- Evidence from the failed run supported the threshold split: post-flush frames above 400 RMS totaled about `3110ms`, while frames above 150 RMS totaled about `4430ms`, enough for the 4200ms ASR window.
- Verification passed with 16 focused buffer/app tests, 26 focused buffer/app/former room transport worker tests, 147 full deterministic tests, compile check, RunPod compile/smoke, and a restarted RunPod former room transport worker with a fresh log.

### 2026-05-19 - former room transport Session Isolation And Visible State

- Filtered RunPod former room transport replay proved the worker was receiving audio and could advance Surah 98 from `98:1` to `98:2`; the remaining failure mode is noisy ASR output, not a frozen transport.
- The former room transport runner no longer shares one `RecitationSession` and one rolling ASR buffer across every subscribed audio track. Each track now receives a fresh worker/session/buffer while the heavy Whisper model remains lazily shared.
- The iOS reducer now preserves the last meaningful post-lock event when `waiting_for_audio_buffer` arrives, so the UI should not look stuck simply because buffer-wait packets are frequent.
- Verification passed with red/green backend and Swift regressions, 27 focused backend tests, 16 Swift client core tests, 148 full deterministic Python tests, compile check, iOS app build, RunPod worker compile check, and a warm two-pass former room transport replay that locked `114:2` twice in one worker process.
- Quality risk remains ASR/progression accuracy: clean Surah 102 still skipped early short ayahs in the fixture and then produced mostly `wrong` events after `102:4`.

### 2026-05-19 - Simulator WebSocket Handshake Fix

- The `Simulator` preset `Socket is not connected` symptom was traced to an iOS client race: microphone streaming could begin immediately after `task.resume()` before the WebSocket open handshake had completed.
- `BackendWebSocketClient` now waits for a successful WebSocket ping before streaming mic chunks, and Simulator connection failures now tell the user to start the local backend on `127.0.0.1:8000`.
- Verification passed with the new red/green WebSocket source regressions, 11 focused iOS source tests, 150 full deterministic Python tests, compile/JSON/whitespace checks, a successful iOS app target build, local backend health returning HTTP 200, and the rebuilt app launched in the iPhone 17 Pro simulator.
- Quality risk remains separate from this fix: local WebSocket connection stability is improved, but former room transport ASR progression and model transcript quality still need their own evidence.

### 2026-05-19 - former room transport Session Isolation

- The latest manual Surah 98 symptom was not caused primarily by RapidFuzz. RunPod logs showed six subscribed former room transport tracks in the shared room, including stale diagnostic/warm tracks and multiple `ios-reciter` tracks, while the iOS app accepted every reliable recitation packet on the topic.
- The former room transport contract now carries `session_id`: token responses generate unique client identities by default, worker events include the publishing participant identity, and iOS filters incoming events to the current token session.
- Worker track consumers are now cancellable on `track_unsubscribed`, reducing stale background event producers in the shared room.
- Local verification passed with red/green Python and Swift regressions, 37 focused former room transport/API/iOS tests, 17 Swift client tests, 154 full deterministic Python tests, compile check, and iOS app build.
- RunPod code patch, inline smoke, worker restart, and former room transport smoke passed. The active worker is connected with a clean log, and a smoke event returned a matching `session_id`, so manual Surah 98/102 retesting can now focus on ASR/progression quality instead of shared-room event contamination.

### 2026-05-19 - Faster-Whisper Quran Model Spike

- `OdyAsh/faster-whisper-base-ar-quran` runs successfully with the `faster-whisper` package on the active RunPod NVIDIA L4 using `compute_type=float16`.
- Short Surah 114 evidence is good: the model transcribed and located `114001.wav` to `114:1` and `114002.wav` to `114:2`.
- Ordered Surah 102 evidence is promising when using per-ayah transcripts through the existing session engine: all eight ayahs locked in order.
- Surah 98 evidence remains mixed: per-ayah transcripts lock ayahs 1-4, then ASR hallucinated extra trailing words in 98:5 and the session correctly treated later ayahs as out-of-order.
- The current Transformers adapter cannot load this model ID because it is a CTranslate2/faster-whisper conversion, so app integration requires an optional faster-whisper backend rather than an environment-only model swap.
- A separate quality bug was exposed: standalone Tanzil pause marks such as `ۚ` are parsed as empty Quran words, which can cause false `no_match` results even for an otherwise correct ASR transcript.

### 2026-05-19 - Optional Faster-Whisper Backend For former room transport

- Added a selectable ASR backend while keeping Transformers as the default. `TARTEEL_WHISPER_BACKEND=faster-whisper` now routes through a CTranslate2/faster-whisper recognizer.
- The backend parses `cuda:0`, accepts `TARTEEL_FASTER_WHISPER_COMPUTE_TYPE=float16`, and resamples PCM to 16 kHz before inference so former room transport 48 kHz audio can reach faster-whisper safely.
- Local verification passed with red/green tests, 14 focused adapter/app tests, 26 focused adapter/app/former room transport tests, 157 full deterministic Python tests, and compile check.
- RunPod verification passed for model construction and a short `114002.wav` recognizer smoke: transcript `مَلِكِ النَّاسِ`, normalized `ملك الناس`.
- The active RunPod former room transport worker is connected using the OdyAsh faster-whisper model and returned a matching-session smoke event, so manual iOS Simulator testing can proceed.
- Operational risk: the pod workspace mount hit a write quota during patching, so the active worker is running from `/tmp/tarteel-realtime-live`; future pod edits should repair or freshly bootstrap `/workspace/tarteel-realtime`.

### 2026-05-19 - Explicit iOS Silero VAD Bundle

- The iOS client now bundles `silero-vad-unified-256ms-v6.0.0.mlmodelc` from `FluidInference/silero-vad-coreml`, so WebSocket fallback VAD no longer depends on FluidAudio reaching Hugging Face at runtime.
- `VoiceActivityDetector` now prefers the bundled Core ML model through `VadManager(config: .default, vadModel:)`, falls back to `VadManager()` only when the bundle is absent, and uses FluidAudio's streaming `processStreamingChunk(...)` state machine.
- VAD stream state resets on recording start/stop, preventing stale speech state from leaking between sessions.
- Verification passed with red/green iOS VAD source tests, 10 focused iOS VAD tests, 17 Swift client core tests, a successful iOS app target build, and a built-app resource check confirming the `.mlmodelc` is packaged.
- Quality risk: this currently improves the WebSocket fallback metadata path. The former room transport preset still publishes microphone audio through former room transport directly, so using iOS VAD to affect former room transport transport needs a separate data-topic or custom-capture design.

### 2026-05-20 - former room transport Client-Side VAD Capture Path

- The former room transport iOS preset now uses the same app-owned microphone stream as WebSocket: PCM16 capture, bundled Silero VAD, then a transport adapter.
- former room transport uses SDK manual rendering mode and `AudioManager.shared.mixer.capture(appAudio:)`, with VAD metadata published on `former.transport.voice_activity`.
- The worker decodes former room transport Python `DataPacket` objects and attaches latest VAD metadata by participant identity before rolling ASR buffering.
- Local verification passed for the new red/green iOS source and worker tests, 47 focused former room transport/token/API/iOS contract tests, 167 full Python tests, compile check, 17 Swift client core tests, JSON validation, `git diff --check`, and an iOS app target build.
- Quality risk: manual former room transport mic verification is still required, especially to check whether client-side suppression clips initial speech before VAD triggers.

### 2026-05-21 - Quran Tokenization And Locator Interface Cleanup

- `QuranCorpus` now skips standalone Tanzil tokens whose normalized text is empty, so pause marks such as `ۚ` preserve canonical ayah text without creating empty `QuranWord` entries or shifting following word refs.
- `QuranLocator.locate_recitation(...)` centralizes exact-first, tolerant-fallback matching, and `RecitationSession` now uses it for both initial lock and ordered-progression recovery.
- Verification passed with red/green parser and locator regressions, 50 focused Quran/locator/session/evaluator tests, 172 full deterministic tests, compile check, JSON validation, active-feature sanity `[]`, `git diff --check`, and a final 43-test touched-area rerun after harness updates.
- Quality risk: this is local deterministic evidence. The active RunPod worker still needs redeployment or fresh bootstrap before Surah 98/102 live behavior can be judged against the parser cleanup.

### 2026-05-21 - Event Payload Contract Module Cleanup

- `SessionEvent` wire payload encoding now lives in `tarteel_realtime/event_payloads.py`, so the FastAPI WebSocket path and former room transport worker share the same payload module without coupling former room transport to the FastAPI transport module.
- Canonical ayah text enrichment remains part of the shared payload encoder, preserving the visible `Ayah text` contract for both transports.
- Verification passed with red/green `tests.test_event_payloads`, 31 focused event/API/former room transport/app tests, 173 full deterministic tests, compile check, JSON validation, active-feature sanity `[]`, and `git diff --check`.
- Quality risk: this is local source cleanup only. The active RunPod worker still needs redeployment or fresh bootstrap before live diagnostics reflect this module layout.

### 2026-05-21 - Recitation Progression Module Cleanup

- `RecitationProgression` now owns next expected refs, progression anchors, ordered ayah scope, and ordered miss counts.
- `RecitationSession` remains the orchestrator for recognizer/location/alignment/event flow, but no longer owns the progression state implementation directly.
- Verification passed with red/green `tests.test_progression`, 50 focused progression/session/locator/API/payload tests, 177 full deterministic tests, compile check, JSON validation, active-feature sanity `[]`, and `git diff --check`.
- Quality risk: this is local source cleanup only. The active RunPod worker still needs redeployment or fresh bootstrap before live diagnostics reflect this module layout.

### 2026-05-21 - Session Event Module Cleanup

- `SessionEvent`, `SessionEventType`, and named session-event constructors now live in `tarteel_realtime/session_events.py`.
- `RecitationSession` remains responsible for recognition/location/alignment orchestration, but delegates event construction to the new module.
- Verification passed with red/green `tests.test_session_events`, 70 focused session/progression/locator/API/payload/former room transport tests, 180 full deterministic tests, compile check, JSON validation, active-feature sanity `[]`, and `git diff --check`.
- Quality risk: this is local source cleanup only. The active RunPod worker still needs redeployment or fresh bootstrap before live diagnostics reflect this module layout.

### 2026-05-21 - Shared Recitation Stream Module

- `RecitationStream` now owns the shared `AudioChunk -> SessionEvent -> payload -> diagnostics` flow behind both WebSocket and former room transport.
- WebSocket recognizer failures now return visible `uncertain/asr_error` events instead of closing the socket, matching the former room transport safety behavior.
- Verification passed with red/green `tests.test_recitation_stream`, adapter red tests for WebSocket ASR errors and former room transport diagnostics, 32 focused transport tests, 185 full deterministic tests, and compile check.
- Quality risk: this is local source cleanup only. The active RunPod worker still needs redeployment or fresh bootstrap before live diagnostics reflect this module layout.

### 2026-05-21 - former room transport Worker Split

- former room transport frame decoding, VAD metadata decoding/tracking, room handler registration, and recitation publishing now live in separate modules.
- `former-room-transport_worker.py` is reduced to the former room transport room runner/CLI surface while preserving compatibility imports for existing tests and smoke helpers.
- Verification passed with red/green `tests.test_former-room-transport_room`, `tests.test_former-room-transport_audio`, and `tests.test_former-room-transport_recitation`; 43 focused former room transport/API tests; 190 full deterministic tests; and compile check.
- Quality risk: this is local source cleanup only. The active RunPod worker still needs redeployment or fresh bootstrap before live diagnostics reflect this module layout.

### 2026-05-21 - Locator Internals Cleanup

- Exact matching, tolerant matching, tolerant span matching, scope constraints, candidate sorting, and RapidFuzz word similarity now live in `locator_matching.py`.
- Locator decision types now live in `locator_types.py`, while `QuranLocator.locate_recitation(...)` remains the public seam used by session callers.
- Verification passed with red/green `tests.test_locator_matching`, 75 focused locator/session/API/stream/former room transport tests, 193 full deterministic tests, and compile check.
- Quality risk: this is local source cleanup only. The active RunPod worker still needs redeployment or fresh bootstrap before live diagnostics reflect this module layout.

### 2026-05-21 - Session Transition Policy Extraction

- `RecitationTransitionPolicy` now owns the post-recognition decision tree for initial lock, ordered guidance, alignment progress, tolerant ordered recovery, and wrong events.
- `RecitationSession` is narrowed to the recognizer adapter: it recognizes an `AudioChunk`, then delegates the `RecognitionResult` to the transition policy.
- Verification passed with red/green `tests.test_session_transitions`, 78 focused session/API/stream/former room transport tests, 196 full deterministic tests, and compile check.
- Quality risk: this is local source cleanup only. The active RunPod worker still needs redeployment or fresh bootstrap before live diagnostics reflect this module layout.

### 2026-05-21 - Shared ASR Runtime Wiring

- `asr_runtime.py` now owns ASR runtime settings, env parsing, lazy recognizer factory wiring, buffered recognizer factory wiring, and runtime defaults shared by ASR app and former room transport worker paths.
- `asr_app.py` is narrowed to FastAPI composition and compatibility re-exports, while former room transport imports runtime wiring directly from `asr_runtime.py`.
- Verification passed with red/green `tests.test_asr_runtime`, 29 focused runtime/asr_app/former room transport tests, 200 full deterministic tests, and compile check.
- Quality risk: this is local source cleanup only. The active RunPod worker still needs redeployment or fresh bootstrap before live diagnostics reflect this module layout.

### 2026-05-21 - Domain Docs And ADR Slice

- Added root `CONTEXT.md` for shared domain language and seam definitions.
- Added ADRs for recitation stream/transition seams and shared ASR runtime wiring under `docs/adr/`.
- Structured checks passed (`feature_list.json` parse, active-feature sanity, whitespace check), with the full deterministic suite and compile check already green in the preceding slice.
- Quality risk: documentation is now aligned with code seams locally, but deployed runtime behavior still depends on updating the active GPU worker with these local slices.

### 2026-05-21 - Provider-Neutral GPU Bootstrap Entry

- Added `scripts/gpu_bootstrap.sh` as the preferred bootstrap entrypoint and kept `scripts/runpod_bootstrap.sh` as a compatibility wrapper.
- Bootstrap defaults are now host-portable: `/workspace` paths are used when present, with `$HOME` fallbacks on non-RunPod hosts.
- Artifact-download intent now accepts `TARTEEL_DOWNLOAD_ARTIFACTS=1` while preserving `TARTEEL_DOWNLOAD_R2_ARTIFACTS=1` compatibility.
- Verification passed with `tests.test_runpod_bootstrap` (6 tests) and `bash -n` syntax checks for both bootstrap scripts.
- Quality risk: this improves portability at the scripting seam, but runtime behavior still depends on bootstrapping and validating the active GPU worker with the latest local architecture slices.

### 2026-05-23 - WebSocket-Only RunPod And Simulator Verification

- Fresh RunPod pod `tlk814bso1lnjs` was bootstrapped from commit `5e8b4b5` with no file copy path, using `/workspace/tarteel-r2.env` for R2 artifact hydration.
- The real ASR WebSocket backend ran on NVIDIA L4 with `basharalrfooh/whisper-small-quran`, `torch==2.7.1`, `torchvision==0.22.1`, CUDA `cuda:0`, full Tanzil data, and stable 4200/4200/0 buffering defaults.
- Public `/health` and public WSS `/ws/recitation` were verified through `tlk814bso1lnjs-8000.proxy.runpod.net`.
- The iOS Simulator app built, installed, launched, and has microphone permission granted. The RunPod WSS URL is on the simulator pasteboard for the Custom preset.
- Quality risk: transport health is now proven, but model quality remains uneven. Continuous Surah 108 locked only `108:3`; the first two short ayahs remained `lock_candidate`. Long Surah 4 locked `4:1` and progressed but still emitted false `wrong` events from noisy ASR windows.
