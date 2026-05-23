# Session Handoff

## Verified Now

- WebSocket `/ws/recitation` is the only active transport.
- The former room transport path, token endpoint, worker modules, smoke helper, iOS SDK client, token model, preset, and SwiftPM package references have been removed in worktree `.worktrees/websocket-only`.
- iOS now has only `Simulator` and `Custom` WebSocket presets; `Custom` accepts RunPod WSS URLs and normalizes bare RunPod proxy hosts to `/ws/recitation`.
- `RecitationStream`, canonical event payloads, diagnostics, ASR buffering, Quran locator/progression, and WebSocket `voice_activity` metadata remain.
- Each WebSocket connection creates a fresh `RecitationStream`; focused regression coverage proves socket session state does not leak.
- Current ASR defaults remain the stable profile: `TARTEEL_ASR_MIN_AUDIO_MS=4200`, `TARTEEL_ASR_FLUSH_MS=4200`, `TARTEEL_ASR_TAIL_MS=0`, `TARTEEL_ASR_MIN_SPEECH_RMS=400`, `TARTEEL_ASR_MIN_FRAME_RMS=150`.
- Heavy ASR dependencies remain optional; default tests do not require Whisper, Torch, faster-whisper, GPU, R2, or network access.

## Verification

- Baseline before removal: `uv run python -B -m unittest discover -s tests -v` passed with 204 tests.
- Focused backend/iOS source run: `uv run python -B -m unittest tests.test_api tests.test_recitation_stream tests.test_event_payloads tests.test_ios_websocket_client tests.test_ios_websocket_vad tests.test_asr_runtime -v` passed with 27 tests.
- Full Python deterministic suite: `uv run python -B -m unittest discover -s tests -v` passed with 164 tests.
- Compile check: `uv run python -m compileall -q tarteel_realtime tests` passed.
- JSON validation: `uv run python -B -m json.tool feature_list.json` passed.
- Swift client core: `cd ios/TarteelClientCore && env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test` passed with 17 tests.
- iOS app target build: `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build` succeeded.
- Local WebSocket smoke: `uv run python -m tarteel_realtime.ws_client --url ws://127.0.0.1:8010/ws/recitation` returned the scripted `locked` event for `114:2` followed by the expected `wrong` event.

## Next Best Step

Run the iOS Custom preset against the RunPod WSS `/ws/recitation` endpoint on a physical device or simulator and capture the app state plus backend logs.
