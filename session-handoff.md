# Session Handoff

## Verified Now

- Latest slice: native macOS SwiftUI prototype, completed on 2026-05-25.
- WebSocket `/ws/recitation` remains the only recitation transport.
- The existing iPhone target remains `TarteelPrototype`.
- The new native macOS target is `TarteelPrototypeMac` in `ios/TarteelPrototype/TarteelPrototype.xcodeproj`.
- The macOS bundle id is `dev.mostafa.TarteelPrototypeMac`.
- The macOS deployment target is 14.0.
- App Sandbox remains disabled for this developer prototype slice.
- `RecitationViewModel` lives in shared core at `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift`.
- The shared view model is a public `@MainActor ObservableObject` with injected:
  - `BackendSocketing`
  - `AudioStreaming`
  - `VoiceActivityDetecting`
  - `RecitationPreferencesStoring`
- The iPhone app injects `MicrophoneAudioStreamer()` and `VoiceActivityDetector()`.
- The macOS app injects `MacMicrophoneAudioStreamer()` and `VoiceActivityDetector()`.
- `BackendWebSocketClient` is shared by both app targets.
- The macOS app includes a separate macOS `Info.plist`, native Settings scene, desktop recitation surface, status console, Auto/Surah controls, Command-R recording command, and Settings toolbar entry.
- The macOS microphone path uses `AVAudioEngine` plus `AVCaptureDevice.requestAccess(for: .audio)`, converts to mono 16 kHz PCM16, and avoids `AVAudioSession`.
- The bundled `silero-vad-unified-256ms-v6.0.0.mlmodelc` resource is included in both app targets.
- The iOS clean home/settings UI remains unchanged from the user-facing perspective.

## Verification

- Swift client core passed:
  - `env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test`
  - Result: 36 tests total, 12 XCTest-style plus 24 Swift Testing.
- Focused Apple source/project guardrails passed:
  - `uv run python -B -m unittest tests.test_macos_app_project tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v`
  - Result: 16 tests.
- iPhone target build passed:
  - `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build`
- macOS target build passed after escalated rerun because sandboxed Xcode package/cache access was blocked:
  - `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build`
- Full deterministic Python suite passed:
  - `uv run python -B -m unittest discover -s tests -v`
  - Result: 202 tests.
- JSON validation and whitespace checks passed:
  - `uv run python -B -m json.tool feature_list.json`
  - `git diff --check`

## Current Risks

- This was an automated build and source-guardrail slice, not manual macOS microphone proof.
- RunPod Serverless endpoint deployment is still outstanding:
  - no Docker image build/push
  - no endpoint creation
  - no cold-start, worker runtime, scale-to-zero, billing, or scoped fixture replay evidence
- RunPod live-ASR quality remains separate from the Apple client build proof.

## Next Best Step

Manually launch the macOS app, grant microphone permission, and test local backend recording against `/ws/recitation`. The RunPod Serverless proof remains a separate outstanding path:

- build and push the serverless image
- create a RunPod Load Balancer endpoint with `Active workers = 0`, `Max workers = 1`
- replay `108001`, `108002`, `108003` with `?scope=108`
- replay `004001`, `004002`, `004003` with `?scope=4:1-3`
