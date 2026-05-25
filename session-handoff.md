# Session Handoff

## Verified Now

- Latest slice: Task 4, shared recording orchestration, completed on 2026-05-25.
- WebSocket `/ws/recitation` remains the only recitation transport.
- `RecitationViewModel` now lives in shared core at `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift`.
- The app-local `ios/TarteelPrototype/TarteelPrototype/App/RecitationViewModel.swift` was deleted.
- `RecitationViewModel` is a public `@MainActor ObservableObject` with injected:
  - `BackendSocketing`
  - `AudioStreaming`
  - `VoiceActivityDetecting`
  - `RecitationPreferencesStoring`
- `BackendWebSocketClient` remains the default socket, but it is created inside the initializer body to avoid `@MainActor` default-argument isolation problems.
- Duplicate start attempts while the first connection is still in flight are ignored through an `isStartingRecording` guard.
- Audio chunks are queued through a chained `audioSendTask`; sequence numbers are assigned synchronously in capture order before VAD, and queued sends are canceled/invalidated on stop.
- Delayed audio send failures and stale socket events are generation-gated so old work cannot mutate stopped or restarted session UI.
- The iPhone app injects `MicrophoneAudioStreamer()` and `VoiceActivityDetector()` from `TarteelPrototypeApp.swift`.
- The iPhone target compiles shared `RecitationViewModel.swift`, `RecitationMode.swift`, and `RecitationPreferencesStore.swift` through project file references.
- The iOS clean home/settings UI remains unchanged from the user-facing perspective.

## Verification

- Red TDD run failed first as expected:
  - `env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test`
  - Failure: `cannot find 'RecitationViewModel' in scope`.
- Swift client core passed after implementation with 33 tests total: 9 XCTest-style tests plus 24 Swift Testing tests.
- Review regression tests first failed before the fix:
  - duplicate `toggleRecording()` while connect was suspended called `socket.connect` twice
  - the second audio chunk reached VAD/send before the first suspended VAD call completed
- Stale-generation regressions first failed before the fix:
  - delayed old audio send failure stopped the restarted session and set a stale error
  - old socket callback after stop moved the UI out of stopped state
- Focused iOS source guardrails passed:
  - `uv run python -B -m unittest tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v` with 11 tests.
- Additional touched iOS source guardrails passed:
  - `uv run python -B -m unittest tests.test_ios_websocket_vad tests.test_ios_audio_streamer -v` with 7 tests.
- iOS app build passed with the requested derived-data path after clearing stale derived-data caches:
  - `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build`

## Current Risks

- This was an orchestration move, not a live backend or microphone quality proof.
- The app target still compiles shared core source files directly; a future cleanup could make the app depend on the Swift package product instead.
- RunPod Serverless endpoint deployment is still outstanding:
  - no Docker image build/push
  - no endpoint creation
  - no cold-start, worker runtime, scale-to-zero, billing, or scoped fixture replay evidence

## Next Best Step

Continue the native macOS app task by reusing shared `RecitationViewModel` and providing macOS-specific audio/VAD adapters. The RunPod Serverless proof remains a separate outstanding path:

- build and push the serverless image
- create a RunPod Load Balancer endpoint with `Active workers = 0`, `Max workers = 1`
- replay `108001`, `108002`, `108003` with `?scope=108`
- replay `004001`, `004002`, `004003` with `?scope=4:1-3`
