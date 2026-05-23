# Session Handoff

## Verified Now

- WebSocket `/ws/recitation` is the only active transport.
- The former room transport path, token endpoint, worker modules, smoke helper, iOS SDK client, token model, preset, and SwiftPM package references have been removed in worktree `.worktrees/websocket-only`.
- iOS now has only `Simulator` and `Custom` WebSocket presets; `Custom` accepts RunPod WSS URLs and normalizes bare RunPod proxy hosts to `/ws/recitation`.
- Fresh RunPod pod `tlk814bso1lnjs` is running the real ASR WebSocket backend from commit `5e8b4b5` on `0.0.0.0:8000`.
- Public Custom URL for simulator/manual testing: `wss://tlk814bso1lnjs-8000.proxy.runpod.net/ws/recitation`.
- `RecitationStream`, canonical event payloads, diagnostics, ASR buffering, Quran locator/progression, and WebSocket `voice_activity` metadata remain.
- Each WebSocket connection creates a fresh `RecitationStream`; focused regression coverage proves socket session state does not leak.
- Current ASR defaults remain the stable profile: `TARTEEL_ASR_MIN_AUDIO_MS=4200`, `TARTEEL_ASR_FLUSH_MS=4200`, `TARTEEL_ASR_TAIL_MS=0`, `TARTEEL_ASR_MIN_SPEECH_RMS=400`, `TARTEEL_ASR_MIN_FRAME_RMS=150`.
- Heavy ASR dependencies remain optional; default tests do not require Whisper, Torch, faster-whisper, GPU, R2, or network access.
- The iPhone 17 Pro simulator has the rebuilt app installed and launched as process `4167`; microphone permission is granted and the RunPod WSS URL is on the simulator pasteboard.
- Committed Quran/evaluation smoke fixtures were removed from the worktree; the same Juz Amma, Surah 102, and Surah 98 smoke coverage now lives in `tests/test_evaluate_cli.py`.

## Verification

- Baseline before removal: `uv run python -B -m unittest discover -s tests -v` passed with 204 tests.
- Focused backend/iOS source run: `uv run python -B -m unittest tests.test_api tests.test_recitation_stream tests.test_event_payloads tests.test_ios_websocket_client tests.test_ios_websocket_vad tests.test_asr_runtime -v` passed with 27 tests.
- Full Python deterministic suite: `uv run python -B -m unittest discover -s tests -v` passed with 164 tests.
- Compile check: `uv run python -m compileall -q tarteel_realtime tests` passed.
- JSON validation: `uv run python -B -m json.tool feature_list.json` passed.
- Swift client core: `cd ios/TarteelClientCore && env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test` passed with 17 tests.
- iOS app target build: `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build` succeeded.
- Local WebSocket smoke: `uv run python -m tarteel_realtime.ws_client --url ws://127.0.0.1:8010/ws/recitation` returned the scripted `locked` event for `114:2` followed by the expected `wrong` event.
- RunPod full Tanzil manifest validated: 6236 ayahs, checksum `054b3d9f79c0c2e44df7f9ddf42561797b3b5cb4fbdafbf2e99c805ccf1a6b49`.
- RunPod public health: `https://tlk814bso1lnjs-8000.proxy.runpod.net/health` returned HTTP 200 with `{"status":"ok"}`.
- Public WSS replay for concatenated Surah 108 returned 23 events: 18 `locating`, 2 `lock_candidate`, 1 `locked`, 2 `uncertain`; locked `108:3`.
- Pod-local replay for `004001.wav` returned 67 events: 1 `locked` at `4:1`, 6 `progress`, 47 `uncertain`, 4 `wrong`, 1 `lock_candidate`, 8 `locating`.
- Latest local Swift client core test passed with 17 tests.
- Latest iOS simulator app target build succeeded and copied `silero-vad-unified-256ms-v6.0.0.mlmodelc` into the app.
- Simulator screenshot captured at `/private/tmp/tarteel-websocket-only-sim.png`.
- Commit-prep evaluator regression: `uv run python -B -m unittest tests.test_evaluate_cli -v` passed with 7 tests.
- Commit-prep full Python suite: `uv run python -B -m unittest discover -s tests -v` passed with 164 tests.
- Commit-prep compile check: `uv run python -m compileall -q tarteel_realtime tests` passed.
- Commit-prep JSON validation: `uv run python -B -m json.tool feature_list.json` passed.

## Current Risks

- First cold model load can exceed default Python WebSocket keepalive timeout; warm the model before interpreting app connection failures.
- Current 4200ms buffering plus minimum lock words of 3 underperform on isolated short ayah audio. Continuous Surah 108 locked `108:3`, while `108:1` and `108:2` stayed at `lock_candidate`.
- Long Surah 4 audio proves lock/progression through WebSocket, but noisy ASR windows still trigger false `wrong` events.

## Next Best Step

In the Simulator, select `Custom`, paste `wss://tlk814bso1lnjs-8000.proxy.runpod.net/ws/recitation`, tap the mic, and recite continuous short and long samples while watching `/tmp/tarteel-ws-asr.log` on the pod for `recitation_chunk` events.
