# Quality Document

Rolling quality record for the Tarteel real-time Quran recitation MVP.

## Current Baseline

- Date: 2026-06-12
- Overall status: good enough MVP, not production-grade
- Initial quality score: 8.0 / 10
- Basis: deterministic Python suite, compile checks, Swift client tests, iOS simulator build evidence, WebSocket simulator verification, RunPod real-ASR proof paths, documented R2/GitHub bootstrap flow, and source/build/runtime-smoke/scored-fixture/app-replay/local-locator/Tanzil-loader/app-bundle/app-binary-replay plus live mic capture/replay, iOS Simulator invalid-output diagnosis, actionable failure UI, shared physical-device replay scheme/build proof, fresh-install CoreML default wiring, selected-Surah ordered CoreML locator state, selected-Surah bounded initial matching, selected-Surah current-ayah completion-gated post-lock progression, selected-Surah no-hidden-advance prefix/sequence locks, selected-Surah istiaza/basmala opening lock, selected-Surah unresolved-istiaza startup guard and sparse first-ayah recovery, selected-Surah noisy initial anchor lock, selected-Surah prefix-span first lock for cumulative basmala starts, selected-Surah sequence-anchor lock for skipped short middle ayahs, selected-Surah ordered-anchor post-lock recovery for omitted expected-ayah openings, selected-Surah short-ayah suffix recovery, bounded post-lock transcript matching without later-ayah skips, speech-boundary/post-transcript blank-streak CoreML acoustic stream reset, canonical word highlighting, local locator/audio-window/latency diagnostics, and fixed-divisor live chunk cadence for the experimental local CoreML FastConformer path.

The MVP has strong harness discipline and a working real-ASR mobile path, but it still needs longer-session proof, physical-device validation, latency tuning, and more polished ordered-progression guidance.

## Quality Dimensions

| Dimension | Status | Notes |
| --- | --- | --- |
| Correctness and reliability | Good | Core Quran parsing, locator, session state, ASR buffering, and WebSocket transport have deterministic coverage. Real ASR remains model- and audio-quality-sensitive. |
| Test coverage | Good | Fast Python and Swift tests cover most local contracts. Real model checks are intentionally opt-in through local CoreML artifacts or RunPod/GPU evidence. |
| Architecture and boundaries | Good | Fake backend, WebSocket transport, ASR adapters, local CoreML routing, and Apple state reduction are separated. Heavy dependencies and large model files remain optional/local. |
| Mobile UX readiness | MVP | Simulator path works and exposes ayah/ayah text status. The local CoreML preset is selectable and has automated fixture app-replay proof, a Tanzil-format local corpus loader, local app-bundle copy paths, and macOS app-binary replay proof, but physical iPhone, live microphone latency, and guidance copy need more work. |
| ASR/model maturity | Experimental | Whisper/faster-whisper backends have targeted GPU evidence, and the CoreML FastConformer model now loads/runs locally, but none of the ASR paths are production-validated. |
| Ops reproducibility | Good | Public GitHub plus R2 hydration, RunPod packaging, and Modal provider-comparison scaffolding reduce manual copying. Live GPU endpoints still need explicit user coordination and measured evidence. |
| Documentation and handoff | Good | Harness files capture progress, feature state, clean-state checks, and session context. This document and rubric add quality tracking. |
| Privacy and secrets | Good | Raw audio and credentials are not committed. R2 and RunPod secrets stay local. Continue checking this during every artifact change. |

## Known Quality Debt

- Physical-device WebSocket testing is still outstanding.
- macOS native UI polish is source/build verified, including drop feedback and search-driven scope selection, but manual light/dark visual QA, keyboard focus, drag/drop, diagnostic drag-out, Settings validation layout, microphone permission, and live backend recording are still outstanding.
- Longer-surah and longer-session recitation behavior needs evaluation beyond targeted Surah 102 and Surah 114 paths.
- Latency and chunking are tuned for MVP stability, not final user experience.
- Ordered-progression guidance exists in backend behavior but still needs polished user-facing copy.
- Real ASR can hallucinate or clip phrases; canonical ayah display mitigates UI truth, but correction confidence still needs more evidence.
- The local CoreML FastConformer path now has selected-Surah ordered Swift locator/session behavior, bounded selected-Surah initial matching that avoids whole-surah fuzzy startup scans while preserving clean exact late starts, current-ayah-gated post-lock progression verified against Surah 107 no-premature-107:3 regressions, no-hidden-advance prefix/sequence locks verified against a Surah 49 `49:4:1` regression, a selected-Surah opening-preface lock for istiaza plus optional basmala verified against the Surah 18 startup failure shape, an unresolved-istiaza startup guard plus sparse first-ayah recovery verified against the latest Surah 18 false later-ayah lock shape, a selected-Surah-only ordered anchor fallback for noisy initial locks verified against the latest Surah 35:1 macOS log transcript, a selected-Surah prefix-span first lock verified against the Surah 80 cumulative basmala/ayah 1/ayah 2 macOS log transcript, a selected-Surah sequence-anchor first lock verified against the latest Surah 80 ASR-skipped-80:2 macOS log transcript, selected-Surah ordered-anchor post-lock recovery verified against omitted expected-ayah openings, selected-Surah short-ayah suffix recovery verified against the Surah 18:3 missing-opening-word log shape, bounded post-lock transcript-word matching verified by a long noisy latency guard, speech-boundary/post-transcript blank-streak acoustic stream reset verified by policy tests and protected against startup blank regressions by the `108001.wav` app replay, Tanzil-format local corpus loading when `quran-simple-clean.txt` is bundled or beside local model artifacts, local iPhone/macOS app-build bundling of the ignored full Quran text and WAV replay fixtures when present, scored fixture evidence, an automated `RecitationViewModel` app replay that locks `108001.wav` to `108:1`, macOS app-binary replay logs for `108001.wav`, opt-in live mic capture to mono 16 kHz PCM16 WAV for deterministic replay, fresh-install default wiring to CoreML + selected Surah 108, canonical Tanzil word highlighting, 2,560-sample app chunk coalescing over the fixed 17,920-sample model window, local corpus/locator diagnostics, per-model-window `coreml_asr_audio_window` RMS/peak/near-silence/VAD diagnostics, `coreml_asr_stream_reset` diagnostics, local-only latency telemetry through `coreml_asr_latency_client_chunk`, `coreml_asr_latency_model_window`, `coreml_asr_latency_engine`, and `coreml_asr_latency_ui_event`, a shared `TarteelPrototypeCoreMLReplay` scheme that is Xcode-visible and buildable for generic `iphoneos`, and explicit `coreml_asr_invalid_output` diagnostics for nonfinite model tensors. The iOS Simulator replay path is diagnosed as producing nonfinite Float16 `logprobs` for this ANE-specialized model, and the app now surfaces that as an actionable "use physical Apple Neural Engine device" message instead of a silent blank-ASR state. iOS acceptance must still use physical Apple Neural Engine hardware. Fresh live microphone capture/replay confirmation of bounded locator latency, current-ayah completion-gated progression, the latency profile, stream reset recovery, Surah 18 istiaza/basmala startup lock, unresolved-istiaza sparse first-ayah recovery, Surah 35 anchor lock, Surah 80 prefix/sequence behavior under the stricter no-hidden-advance policy, Surah 59 ayah-boundary recovery, Surah 18 short-ayah suffix recovery, longer Surah 4, full-corpus performance, thermal behavior, production packaging, and Swift preprocessing correctness still need more proof.
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

### 2026-06-12 - Selected-Surah CoreML Ayah Completion Gate

- Diagnosed the latest improved manual result as a remaining locator-policy problem rather than a VAD or inference freeze: partial current-ayah evidence could still be bypassed by clearer later-ayah ASR.
- Restricted selected-Surah post-lock matching to the current expected ayah only, so later ayah evidence is rejected until the current ayah completes.
- Removed hidden multi-ayah `nextExpectedRef` advancement from prefix-span and sequence-anchor locks; those locks now display the start ayah and expect the next ayah after that display ayah.
- Bounded post-lock transcript words to avoid cumulative-ASR locator backlog while preserving short-ayah recent-suffix recovery.
- Verification passed through red/green Surah 107 completion/recovery, Surah 49 no-hidden-jump, long noisy post-lock latency guard, focused CoreML tests with 49 Swift Testing tests, full Swift client core with 34 XCTest plus 80 Swift Testing tests, Apple/CoreML Python guardrails with 26 tests, macOS and iOS app builds, full Python with 298 tests, compileall, JSON validation, diff check, and debug-grep.
- Release posture: stronger user-trust behavior because the app should now stay on the current ayah instead of looking confidently ahead when ASR skips or fuses text.

### 2026-06-11 - Selected-Surah CoreML Bounded Locator

- Diagnosed the latest CoreML selected-Surah failures as two separate locator problems: no-lock startup could spend seconds in broad fuzzy matching over the selected Surah, and post-lock noisy cumulative evidence could jump from the current ayah to later ayahs such as `107:3`.
- Bounded selected-Surah pre-lock matching to opening prefix spans, cheap exact spans, and capped fuzzy/anchor windows; clean exact late starts remain supported.
- Capped post-lock forward progression to the current and next ayah, so weak noisy suffix evidence returns locating/guidance instead of fabricated later progress.
- Verification passed through red/green Surah 107, Surah 80, and long Surah 18 startup regressions, focused CoreML tests with 45 Swift Testing tests, full Swift client core with 34 XCTest plus 76 Swift Testing tests, Apple/CoreML Python guardrails with 26 tests, macOS and iOS app builds, full Python with 298 tests, compileall, JSON validation, diff check, and debug-grep.
- Release posture: stronger locator correctness and lower locator latency risk for live selected-Surah testing; ASR transcript quality still requires manual captured-WAV proof.

### 2026-06-11 - CoreML Latency Telemetry

- Added local-only CoreML latency tracing so visible transcript delay can be separated into app queue, VAD, model-window buffering, inference, locator, and UI reducer timing.
- `AudioChunkLatencyTrace` is attached only for the `.coreML` preset and is intentionally omitted from `AudioChunkPayload` JSON encoding, preserving WebSocket transport shape.
- New logs: `coreml_asr_latency_client_chunk`, `coreml_asr_latency_model_window`, `coreml_asr_latency_engine`, and `coreml_asr_latency_ui_event`.
- Verification passed through red/green Swift latency tests, focused CoreML tests with 43 Swift Testing tests, a focused view-model trace test, full Swift client core with 34 XCTest plus 74 Swift Testing tests, Apple project Python guardrails with 16 tests, macOS xcodebuild, iOS Simulator `TarteelPrototypeCoreMLReplay` xcodebuild after sandbox/cache rerun, full Python with 298 tests, compileall, and structured harness checks.
- Release posture: observability improved, but ASR speed/quality is unchanged until a fresh manual run uses these markers to identify the dominant delay.

### 2026-06-11 - CoreML ASR Stream Reset

- Diagnosed the latest Surah 104 macOS manual run as ASR output starvation after initial success: CoreML inference kept running with normal timings, while active speech windows emitted repeated blanks.
- Added a narrow CoreML stream-reset policy for VAD speech-boundary resets and post-transcript active-speech blank streaks.
- The reset clears only acoustic cache arrays and CTC previous-token state, preserving cumulative transcript, buffered audio, chunk/window counters, and selected-Surah Quran locator/session state.
- Added `coreml_asr_stream_reset` diagnostics and red/green Swift coverage for speech-boundary reset, blank-streak reset, quiet blanks, and startup active blanks before first transcript.
- Verification passed through focused CoreML tests, full Swift client core, the real `108001.wav` app replay, focused Apple/CoreML Python guardrails, macOS xcodebuild, iOS Simulator `TarteelPrototypeCoreMLReplay` build, full Python, compileall, and structured harness checks.
- Release posture: better recovery mechanism for the observed long/repeated live starvation shape, but still needs fresh manual mic evidence to confirm it restores transcript/locator progress in the failing scenario.

### 2026-06-11 - Selected-Surah CoreML Unresolved-Istiaza Startup Guard

- Diagnosed the latest Surah 18 macOS manual run: ASR recognized istiaza, missed or blanked probable basmala, then emitted sparse noisy ayah 1 fragments. The locator could falsely sequence-anchor to a later ayah before the first real lock.
- Added a selected-Surah opening-preface guard so unresolved istiaza no longer falls through into broad startup jumps when the first Tanzil ayah begins with basmala.
- Added `coreml_local_opening_sparse_content_lock` for sparse ordered first-ayah content after the preface, restricted to the first ayah and requiring at least three strong ordered anchors.
- Red/green Swift coverage proves sparse partial evidence stays `locating/coreml_local_opening_preface_no_match`, while stronger noisy ayah 1 evidence locks to `18:1` and advances to `18:2:1`.
- Verification passed through focused istiaza regressions, full CoreML tests with 36 Swift Testing tests, full Swift client core, focused Apple/CoreML Python guardrails, macOS xcodebuild, and iOS Simulator `TarteelPrototypeCoreMLReplay` build.
- Release posture: prevents the damaging false-later-ayah jump after istiaza, but CoreML ASR still needs to emit enough first-ayah evidence for recovery.

### 2026-06-11 - Selected-Surah CoreML Istiaza/Basmala Startup Lock

- Diagnosed the latest Surah 18 macOS manual run: full Tanzil loaded and audio windows were active, but pre-lock locator events stayed `coreml_local_no_match` after istiaza-shaped startup noise and partial basmala fragments.
- Added selected-Surah opening-preface handling for Tanzil first ayahs beginning with `بسم الله الرحمن الرحيم`.
- `coreml_local_opening_basmala_lock` ignores istiaza/noisy startup and locks on a contiguous basmala suffix; `coreml_local_opening_content_lock` locks directly at post-basmala first-ayah content when basmala is skipped.
- Red/green Swift coverage proves istiaza alone remains unlocked, partial basmala reaches `18:1` with `next_expected_ref=18:1:5`, and skipped basmala locks at `18:1:5`.
- Verification passed through focused istiaza regressions, full CoreML tests with 35 Swift Testing tests, full Swift client core, macOS xcodebuild, and iOS Simulator `TarteelPrototypeCoreMLReplay` build.
- Release posture: first-lock UX is more aligned with real Quran recitation startup, but ASR quality after lock still requires manual capture/replay evidence.

### 2026-06-11 - Selected-Surah CoreML Short-Ayah Suffix Recovery

- Diagnosed the Surah 18 macOS manual run: the locator reached `next_expected_ref=18:3:1`, but ASR missed `ماكثين` and only emitted suffix evidence shaped like `فِي أبٍ` before later blanks/noise.
- Added `coreml_local_short_ayah_suffix_progress`, scoped to selected-Surah post-lock progression and limited to current/next ordered ayahs with at most four words.
- Red/green Swift coverage proves `فِي` alone remains `coreml_local_ordered_no_match`, while `فِي أبٍ` recovers `18:3` with `start_ref=18:3:2` and `next_expected_ref=18:4:1`.
- Verification passed through the focused Surah 18 regression, focused CoreML tests with 32 Swift Testing tests, and focused Apple/CoreML Python guardrails with 26 tests.
- Release posture: better locator resilience for short ayah suffixes, but the underlying ASR still emitted blanks/noise for later Surah 18:4 attempts and needs captured-WAV replay evidence.

### 2026-06-11 - CoreML Live Mic Capture And Replay

- Added an opt-in Apple app launch argument, `--tarteel-capture-audio <wav>`, that wraps the normal iPhone/macOS microphone streamer and writes the exact mono 16 kHz PCM16 chunks forwarded into the local CoreML route.
- Captured WAVs can be replayed with the existing `--tarteel-replay-audio <wav> --tarteel-replay-surah <id>` path, so a poor manual run can be compared against deterministic replay through the same app queue, FluidAudio VAD metadata path, CoreML model, and local locator.
- Unified logs now include `coreml_asr_audio_capture_started`, `coreml_asr_audio_capture_finished`, and `coreml_asr_audio_capture_failed`.
- Verification passed through red/green Swift capture tests, Python app-project guardrails, full Swift client core, full Python, compileall, JSON/active-feature/diff checks, macOS xcodebuild, and iOS Simulator `TarteelPrototypeCoreMLReplay` build.
- Release posture: much better reproducibility for live CoreML failures, but not an ASR quality fix by itself. The next quality gate is a captured manual mic WAV plus replay comparison.

### 2026-06-10 - Selected-Surah CoreML Ayah-Boundary Recovery

- Diagnosed the latest Surah 59 macOS manual run: audio-window metrics and VAD observations were healthy, the locator locked/progressed through `59:1`, then failed at the `59:2` boundary because ASR omitted `هو الذي` and resumed at `أخرج الذين ك`.
- Added selected-Surah-only ordered-anchor post-lock recovery scoped to the current expected ayah and next ayah. It accepts ordered content-word anchors and one trailing prefix token, then emits `coreml_local_ordered_anchor_progress`.
- Red/green Swift coverage proves the exact log-shaped cumulative transcript now recovers to `59:2` with `start_ref=59:2:3`, `next_expected_ref=59:2:6`, and `consumed_words=3`.
- Verification passed through focused CoreML tests, full Swift client core, focused Apple/CoreML Python guardrails, full Python suite, compileall, macOS xcodebuild, and the shared iOS simulator scheme build.
- Release posture: better locator resilience for missing next-ayah openings, but live ASR quality is still noisy and needs fresh manual mic proof before user-facing quality claims.

### 2026-06-10 - CoreML Audio-Window Diagnostics

- Diagnosed the latest poor macOS manual-test performance as ASR-starvation after initial lock, not obvious VAD gating: VAD is metadata-only on the local CoreML route, while the logs showed steady app chunks and model windows.
- Added `coreml_asr_audio_window` logs for each fixed 17,920-sample CoreML window, reporting RMS, peak, near-silence ratio, mean VAD probability, speech-active VAD chunk count, VAD observation count, and latest VAD event.
- Red/green coverage proves the metrics math and source log marker exist; focused CoreML tests, focused Apple/CoreML Python guardrails, full Swift client core, full Python suite, compileall, macOS build, and iOS simulator build passed.
- Release posture: observability is improved, but ASR quality is not fixed yet. The next manual run should use these logs to decide between mic/preprocessing/gain work and decoder/model tuning.

### 2026-06-10 - Selected-Surah CoreML Sequence Anchor Lock

- Diagnosed the latest failed Surah 80 macOS manual test from unified logs: the app had the right scope, full Tanzil, and chunk cadence, but ASR skipped the short `80:2` phrase and the local locator stayed at `coreml_local_no_match`.
- Added selected-Surah-only bounded sequence-anchor locking across multiple ayahs, plus clitic-tolerant anchor similarity for dropped leading `و` / `ف`.
- Red/green Swift coverage proves the exact 18:48 transcript now locks to displayed `80:1` with `coreml_local_sequence_anchor_lock` and advances internally to `80:4:1`.
- Verification passed through focused CoreML tests, full Swift client core, macOS xcodebuild, and the shared iOS simulator scheme build.
- Release posture: better first-lock resilience for noisy Surah 80 live runs, but manual mic proof is still needed and further quality work should bias toward ASR/preprocessing if anchors are absent.

### 2026-06-10 - Selected-Surah CoreML Forward Progression

- Fixed the next Surah 80 manual-test failure mode after the prefix lock: cumulative ASR retained stale `80:2` text and mutated word boundaries, so post-lock matching could lag on `80:2` instead of tracking the later recitation.
- Prefix locks now carry an internal next-expected override when the lock evidence spans multiple ayahs, and selected-Surah post-lock matching now has a bounded rolling-suffix forward fallback.
- Red/green Swift coverage proves the noisy Surah 80 cumulative transcript now advances from displayed `80:1` to `80:8` with `coreml_local_ordered_forward_progress`, instead of re-consuming stale `80:2`.
- Verification passed through focused CoreML tests, full Swift client core, focused Apple/CoreML Python guardrails, full Python with 297 tests, compileall, JSON/active-feature/diff/debug-grep checks, macOS xcodebuild, and the shared iOS simulator scheme build.
- Release posture: better selected-Surah live tracking for short ayah sequences, but still requires fresh microphone evidence to judge UX quality and per-ayah timing.

### 2026-06-10 - Selected-Surah CoreML Prefix Lock

- Corrected the Surah 80 diagnosis: the pinned and bundled Tanzil rows include basmala; the bad lock came from single-ayah pre-lock scoring against cumulative ASR that spanned `80:1` into short `80:2`.
- Added selected-Surah-only prefix-span first-lock matching. It can override a later short ayah when bounded ordered LCS coverage shows the cumulative transcript began earlier in the selected surah.
- Red/green Swift coverage now proves the exact Surah 80 manual transcript no longer locks at `80:2`; it locks at `80:1` with `coreml_local_prefix_lock`, and a clean later start at `80:8` remains at `80:8`.
- Release posture: fixes one concrete first-lock failure, but true multi-ayah span event modeling and noisy post-lock rolling progression remain follow-up work.

### 2026-06-10 - Selected-Surah CoreML Anchor Lock

- Added a selected-Surah-only ordered anchor fallback for initial CoreML local locks, after logs showed Surah 35:1 contained many canonical anchors but still emitted `coreml_local_no_match`.
- Red/green Swift coverage now proves noisy preface-only text stays unlocked while the full noisy Surah 35:1 transcript locks with `coreml_local_anchor_lock` and advances `nextExpectedRef` to `35:2:1`.
- Verification passed through focused CoreML tests, full Swift client core, focused Apple/CoreML Python guardrails, macOS xcodebuild, and the shared iOS simulator scheme build.
- Release posture: improves first-lock robustness for selected-Surah live testing, but still requires a fresh macOS microphone run and physical iPhone proof before calling CoreML live recitation quality acceptable.

### 2026-06-10 - Selected-Surah CoreML Locator And Chunk Cadence

- Reworked the local CoreML selected-Surah path so post-lock matching advances in order across the current and next ayah instead of broad relocking. The state now carries `nextExpectedRef`, canonical ayah words, and completed word count for highlighted Tanzil display.
- Kept the model contract fixed at 17,920 samples per inference window and coalesced app mic/replay callbacks to 2,560 samples, giving seven clean app chunks per CoreML window.
- Diagnostics now log loaded Quran corpus source/count plus local locator events with ayah refs, start/next refs, consumed words, chunk sequence, reason, and confidence.
- Verification passed red/green through focused Swift CoreML/state tests, focused Apple Python guardrails, full Swift client core, full Python with 297 tests, compileall, JSON validation, macOS xcodebuild, and the current shared iOS scheme build.
- Release posture: stronger local developer UX and auditability, but still not a product ASR-quality claim. Manual macOS microphone evidence and physical iPhone CoreML evidence remain the next gates.

### 2026-06-09 - CoreML Default App Fallback

- Fresh iPhone and macOS app installs now default to the local CoreML FastConformer route with selected Surah 108. This makes the integrated ASR path the easiest default for manual testing while preserving persisted user choices.
- Verification passed red/green through Swift preference tests and Python source guardrails; focused Apple/CoreML guardrails passed, the real `108001.wav` view-model replay still locked `108:1`, the generic `iphoneos` replay scheme build passed, and the macOS app build passed.
- Release posture: better developer ergonomics, not a production default claim. Physical iPhone and live microphone acceptance remain required.

### 2026-06-09 - CoreML Physical-Device Replay Scheme

- Added shared Xcode scheme `TarteelPrototypeCoreMLReplay` for the iPhone app target with launch arguments `--tarteel-replay-audio 108001.wav --tarteel-replay-surah 108`.
- Verification improved from "remember to add launch args manually" to a source/build-verified Xcode path: the red project guardrail failed before the shared scheme existed, Xcode listed the new scheme, and a generic `iphoneos` build of that exact scheme succeeded while copying six local replay fixtures.
- `xcrun xctrace list devices` showed no connected physical iPhone, so this is readiness proof rather than iOS ASR acceptance. The next quality gate remains running this scheme on real Apple Neural Engine hardware and checking visible app state plus `coreml_asr_transcript` / `coreml_asr_invalid_output` logs.

### 2026-06-09 - CoreML Invalid-Output UI

- Added app-facing handling for CoreML `invalidModelOutput` so iOS Simulator/nonfinite model output says to use a physical Apple Neural Engine device rather than appearing as a generic unexpected model shape.
- Updated the iPhone home screen runtime error layout so the user-visible error wraps on the small viewport; screenshot evidence shows the bottom message fully readable after `build_run_sim` replay with `108001.wav`.
- Runtime evidence remains intentionally negative for Simulator: OSLog still shows `coreml_asr_invalid_output reason=nonfinite_logprobs detail=timestep=0 nonfinite_values=1025`. The improvement is correct diagnosis and clear UX, not Simulator ASR success.
- macOS/CoreML confidence was preserved: the runner still produced `أَعْطَيْنَاكَ الْكَوْثَرَ` for `108001.wav` with normalized score `0.667`; focused Swift/Python checks, full Swift, full Python with 293 tests, compileall, and macOS app build passed.
- Release posture: safer developer testing loop. The next acceptance gate remains physical iPhone CoreML execution with transcript/progress logs, plus macOS live microphone E2E.

### 2026-06-09 - iOS Simulator CoreML Replay Diagnosis

- Launched the iOS Simulator app with `--tarteel-replay-audio 108001.wav --tarteel-replay-surah 108` through XcodeBuildMCP and confirmed the app reaches the bundled model and replay audio path, but the Simulator-compiled streaming model returns nonfinite Float16 `logprobs`.
- Temporary instrumentation showed non-silent input samples and nonzero log-mel features, while raw `logprobs` started with `FE00`; the model metadata/README identify the model as fixed-shape fp16 and ANE-specialized, so Simulator output is not valid ASR-quality evidence for this model.
- Added permanent `coreml_asr_invalid_output reason=nonfinite_logprobs` logging and `invalidModelOutput` throwing so future Simulator/nonfinite failures do not masquerade as blank speech.
- macOS confidence was preserved: the SwiftPM runner still transcribed `108001.wav` as `أَعْطَيْنَاكَ الْكَوْثَرَ`, focused Python/Swift CoreML checks passed, the iOS replay now logs the invalid-output marker, the macOS app target builds, full Swift client core passed with 31 XCTest tests plus 46 Swift Testing tests, full Python passed with 292 tests, compileall passed, and harness JSON/diff checks passed.
- Release posture: stronger diagnosis and safer failure behavior, but still not iOS success. The next acceptance gate is a physical iPhone run with Apple Neural Engine plus visible app UI progress/log evidence.

### 2026-06-09 - CoreML App-Owned Local Audio Replay

- Added a developer-only app replay path for the built iPhone and macOS apps: `--tarteel-replay-audio <wav>` plus optional `--tarteel-replay-surah <id>` injects `LocalAudioReplayStreamer`, forces CoreML selected-Surah mode through an in-memory preferences store, starts the same `RecitationViewModel` recording path, and replays fixture chunks through real VAD metadata processing and CoreML inference.
- Added conditional build-time copying for ignored local WAV fixtures via `ios/TarteelPrototype/Scripts/copy-local-audio-fixtures.sh` and `Copy Local Audio Fixtures` phases in both app targets. Local builds now bundle six WAVs under `local_audio/` when the root fixtures exist, and fresh checkouts build without them.
- Local confidence improved from SwiftPM/test-only replay to app-binary proof: focused guardrails and Swift checks passed, iOS/macOS builds copied six local WAV fixtures, bundled `108001.wav` matched root SHA-256 `86b655403b3da9e2baed9b0f2ba230b0dafe4ee7ec9c4b67cc0eee1ae36a4789`, and launching the built macOS app with replay arguments produced `coreml_asr_transcript` logs ending at cumulative `أَعْطَيْنَاكَ الْكَوْثَرَ`.
- Final verification also passed full Swift client core, full deterministic Python, compileall, and diff whitespace checks.
- Release posture: this is strong developer E2E evidence for local replay inside the app, but it is still not a live microphone or physical-device acceptance proof. iOS replay launch arguments are source/build/bundle verified but still need simulator launch proof.

### 2026-06-09 - CoreML App-Build Tanzil Resource Bundling

- Added conditional app-build bundling for the ignored local `data/tanzil/quran-simple-clean.txt` via `ios/TarteelPrototype/Scripts/copy-local-tanzil-resource.sh` and `Copy Local Tanzil Quran` phases in both Apple app targets.
- Local confidence improved from "loader exists but bundle is missing" to actual app-bundle proof: iOS simulator and macOS builds both copied the root workspace's local Tanzil file, and bundle inspection found matching 794,313-byte files with SHA-256 `054b3d9f79c0c2e44df7f9ddf42561797b3b5cb4fbdafbf2e99c805ccf1a6b49`.
- Proof passed through the project guardrail, focused Apple/CoreML Python suite, iOS simulator build through XcodeBuildMCP, macOS xcodebuild, bundle SHA inspection, focused Swift CoreML/view-model tests including the real `108001.wav` app replay, full Swift client core, full Python suite, compileall, JSON/active-feature sanity, diff check, and local Tanzil manifest validation.
- Release posture: the local developer app builds can now exercise the full pinned Quran text without committing it. Production distribution of that resource, real microphone/VAD runtime behavior, physical-device behavior, and full-corpus matcher performance remain open.

### 2026-06-09 - CoreML Tanzil-Format Corpus Loading

- Added a Tanzil `surah|ayah|text` parser for the Swift CoreML local Quran path, with explicit malformed-row and empty-corpus failures.
- `CoreMLFastConformerEngine` now loads `quran-simple-clean.txt` from the app bundle or local model directory when available, preserving the MVP Surah 108/local Surah 4 fallback when it is absent.
- Local confidence improved from hard-coded corpus only to a data-backed seam: red Swift checks failed before `CoreMLLocalQuranCorpus` existed, then focused CoreML tests passed with a Surah 114:2 Tanzil-backed lock and an opt-in parse of the local pinned 6,236-ayah file. App-level replay, focused CoreML/view-model tests, full Swift client core, focused Apple/CoreML guardrails, macOS xcodebuild, and iOS simulator xcodebuild passed.
- Release posture: this reduces an architectural limitation, but it is not yet a full shipped Quran engine. The app bundles still need an approved/generated Quran resource, and the local matcher needs full-corpus performance and behavior tuning before broad auto-detect use.

### 2026-06-09 - CoreML App-Level Fixture Replay

- Added an opt-in app-level replay proof around the real CoreML socket: when local gated artifacts exist, `RecitationViewModelTests.testCoreMLFixtureReplayThroughViewModelLocksSelectedSurah` loads `108001.wav`, emits live-sized 16 kHz chunks through a fixture `AudioStreaming` implementation, processes queued chunks through the VAD metadata seam, runs real CoreML inference, and verifies the shared app state locks on `108:1` with canonical ayah text.
- Added `CoreMLFastConformerSocketClient(modelDirectoryURL:)` so local tests/tools can load `.models/fastconformer-quran-coreml-streaming` without changing the iOS/macOS app bundle path.
- Local confidence improved from model-runner proof to app-orchestration proof: the new replay failed red before the directory-backed socket and test-visible resampled fixture PCM existed, then focused replay, focused CoreML/view-model tests, full Swift client core, focused Apple/CoreML guardrails, macOS xcodebuild, and iOS simulator xcodebuild all passed.
- Release posture: better evidence for the CoreML path inside shared app architecture, but still not final E2E acceptance. Manual microphone/VAD runtime, visible UI behavior, physical-device behavior, and full-Quran local locator/session remain open.

### 2026-06-08 - CoreML App-Side Locator MVP

- CoreML transcripts now feed a tiny scoped Swift Quran session before reaching the shared Apple reducer. Selected Surah mode is preserved in `coreml://fastconformer-quran-streaming?scope=...`, and matched local transcripts emit canonical `locked` / `progress` events with ayah refs/text.
- The MVP corpus is intentionally limited to Surah 108 plus the local Surah 4 fixture ayahs. It supports the immediate app E2E loop for Al-Kawthar and fixture-driven tests, but it is not a full Quran locator/session port.
- Local confidence is good for the app contract: red Swift tracer failed before `CoreMLLocalQuranSession` existed; focused CoreML/preset/state/view-model checks passed; full Swift client core passed with 29 XCTest tests plus 41 Swift Testing tests; focused Apple/CoreML guardrails passed with 15 tests; both macOS and iOS app targets built; and `108001.wav` still replayed through CoreML with final transcript `أَعْطَيْنَاكَ الْكَوْثَرَ`.
- Release posture: ready for manual macOS/iOS CoreML microphone E2E testing on selected Surah 108. Still experimental until manual latency/accuracy evidence exists and the local Quran data/session path becomes full-corpus.

### 2026-06-08 - CoreML Fixture Scoring Gate

- Added a committed `fixtures/local_audio_manifest.json` mapping the six ignored local WAV fixture names to expected ayah body text and Quran refs.
- `coreml-fixture-runner` now accepts `--manifest` and emits scored reports with normalized expected/actual text, normalized word score, word error rate, character error rate, missing words, extra words, substitutions, and average inference latency.
- Scored baseline: `108001=0.667`, `108002=0.333`, `108003=1.000`, `004001=0.517`, `004002=0.312`, and `004003=0.214` normalized word score.
- The scoring gate confirms the architecture is useful for repeatable model evaluation, but quality remains uneven. The next CoreML quality work should tune decoding/preprocessing against this scorecard, starting with the `108002` word-boundary/fusion failure and preserving the clean `108003` result.
- Release posture: still experimental. The CoreML path is now measurable, not product-ready.


### 2026-06-07 - Local CoreML FastConformer Spike

- The Apple prototypes now have an experimental `CoreML` preset for `Muno459/fastconformer-quran-coreml-streaming`, routed through `RoutingBackendSocketClient` so WebSocket backends and local model inference share the existing `BackendSocketing` boundary.
- The iPhone and macOS targets bundle the FastConformer model package, pronunciation head, tokenizer, and token list; Xcode compiles the model packages into `.mlmodelc` resources.
- The local engine buffers PCM, resamples to 16 kHz, computes 80x112 log-mel windows, carries model caches, decodes CTC output, and emits compatible transcript-only `locating` events.
- A follow-up diagnostic pass added unified-log markers for model load, buffering, blank inference windows, transcript windows, confidence, emitted token count, and inference timing so manual recitation can distinguish "model ran but blank" from "model emitted usable text".
- The first manual recitation showed useful Al-Ikhlas-like transcript fragments; follow-up stitching work preserved SentencePiece word-boundary spaces across streaming windows and added `cumulative_transcript` logs while keeping the model-card fixed non-overlapping chunk/cache contract intact.
- A repeatable SwiftPM fixture harness now replays ignored local WAV files through the same CoreML transcriber. It downmixes stereo PCM16, resamples to 16 kHz once, feeds live-sized chunks, and reports per-window/cumulative transcripts.
- Fixture quality is mixed: short Surah 108 WAVs are promising enough to justify more investigation, while longer Surah 4 WAVs expose noisy greedy streaming output that should not be routed directly into correction UX without stabilization.
- Local confidence is good for architecture and runtime loading: CoreML compiler check passed, Swift CoreML tests passed, full Swift client core passed with 28 XCTest tests plus 31 Swift Testing tests, focused Apple guardrails passed, iOS build/run and macOS build passed, both bundles contained the model resources, and a macOS CoreML prediction smoke returned the expected output shapes.
- Release posture: useful for manual model evaluation now, but not yet a local Quran-correction product path. The Python locator/session engine is not ported to Swift, transcript quality/latency need real recitation evidence before deeper investment, and public transcript logging must stay a local developer diagnostic rather than a production privacy default.


### 2026-06-03 - macOS Native UI Polish

- The macOS prototype moved closer to native utility-app behavior with a unified compact toolbar, integrated recording/search/settings controls, keyboard commands, URL/text drop-in with visible feedback, diagnostic drag-out, first-run onboarding, empty states, event history, adaptive colors/materials, and Settings validation feedback.
- Shared presentation state lives in `TarteelClientCore`, keeping macOS UI behavior tied to the same recording state machine instead of app-local string handling.
- Search-driven Surah selection and visible drop feedback were added after final code review, with shared tests covering Surah matching/selection and backend drop feedback state.
- Local confidence is good for contracts and builds: Swift client core passed with 44 checks, focused Apple source guardrails passed with 20 tests, the macOS and iPhone app targets built, the full deterministic Python suite passed with 223 tests, and compileall passed for `tarteel_realtime` and `tests`.
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
