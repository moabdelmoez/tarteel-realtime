# Session Handoff

## Verified Now

- Latest slice: iOS clean home/settings UI, completed on 2026-05-25.
- WebSocket `/ws/recitation` remains the only recitation transport.
- The iOS home screen is now a light recitation surface:
  - top-right gear button
  - status and ayah panel
  - Ready/listening state text
  - Auto/Surah segmented control
  - Surah picker when Surah mode is active
  - voice activity indicator
  - mic button
- Backend technical controls now live in the gear settings sheet:
  - backend preset
  - custom WebSocket URL
  - prototype-only RunPod API key
- The app still sends selected-recitation `scope` through `BackendEndpointPreset.recordingURLText(currentURLText:recitationScope:)`.
- Direct RunPod access remains prototype-only because the RunPod API key is entered into the app and sent from the client.

## Verification

- Red source tests failed first for the old layout:
  - missing `Image(systemName: "gearshape.fill")`
  - missing `private struct SettingsSheet`
- Focused iOS source checks passed:
  - `uv run python -B -m unittest tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v` with 11 tests.
- Swift client core passed:
  - `env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test` from `ios/TarteelClientCore` with 24 tests.
- iOS app build:
  - First sandboxed attempt failed because CoreSimulator access and the FluidAudio GitHub fetch were blocked.
  - Approved rerun passed:
    `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived-ios-clean-home CODE_SIGNING_ALLOWED=NO build`
- Simulator visual sanity check passed:
  - Installed and launched `dev.mostafa.TarteelPrototype` in the booted iPhone 17 Pro simulator.
  - Screenshot captured at `/private/tmp/tarteel-clean-home.png`.
- Final harness checks passed:
  - `uv run python -B -m json.tool feature_list.json`
  - `git diff --check`
  - `uv run python -B -m unittest discover -s tests -v` with 197 tests.

## Current Risks

- Settings sheet interaction was compile/source verified but not manually tapped through in the simulator during this slice.
- No live backend or microphone behavior changed; this does not prove live ASR quality.
- RunPod Serverless endpoint deployment is still outstanding:
  - no Docker image build/push
  - no endpoint creation
  - no cold-start, worker runtime, scale-to-zero, billing, or scoped fixture replay evidence

## Next Best Step

Manually open the iOS gear settings sheet in Simulator and verify backend fields are editable while idle and disabled while recording, then resume the RunPod Serverless proof:

- build and push the serverless image
- create a RunPod Load Balancer endpoint with `Active workers = 0`, `Max workers = 1`
- replay `108001`, `108002`, `108003` with `?scope=108`
- replay `004001`, `004002`, `004003` with `?scope=4:1-3`
