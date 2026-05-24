# Session Handoff

## Verified Now

- Active slice: iOS selected-recitation UI, isolated in `.worktrees/ios-selected-recitation-ui` on branch `codex/ios-selected-recitation-ui`.
- Base: `main` commit `4fab816` (`Record Point 5 merge posture`).
- WebSocket `/ws/recitation` remains the only transport. The app still sends the same audio chunk payload; selected-recitation scope is expressed only as a WebSocket URL query item.
- The iOS app now has two recitation modes:
  - `Auto`: global backend detection; app-managed `scope` is removed from the recording URL.
  - `Surah`: user selects one surah from the local catalog; the recording URL gets `scope=<surah-id>`, for example `?scope=108`.
- The Surah picker is populated from `SurahCatalog`, generated from `data/quran-metadata-surah-name.json` with all 114 surahs, Arabic names, English simple names, and verse counts.
- `BackendEndpointPreset.recordingURLText(..., recitationScope:)` normalizes Simulator/Custom/RunPod URLs, replaces stale `scope`, and preserves unrelated query parameters. The old `recordingURLText(currentURLText:)` behavior remains for existing callers.

## Verification

- Baseline before implementation passed: Swift client core had 17 tests passing; focused iOS source guardrails had 11 tests passing.
- Red TDD run failed first for missing `SurahCatalog`, missing `RecitationScopeSelection`, missing scoped URL overload, and missing SwiftUI/ViewModel controls.
- Green focused checks passed:
  - `env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test` from `ios/TarteelClientCore` with 23 tests.
  - `uv run python -B -m unittest tests.test_ios_recitation_scope_ui -v` with 3 tests.
- iOS app build passed with fresh derived data: `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived-ios-scope CODE_SIGNING_ALLOWED=NO build`.
- Full deterministic Python suite passed: `uv run python -B -m unittest discover -s tests -v` with 190 tests.
- Compile check passed: `uv run python -m compileall -q tarteel_realtime tests`.
- JSON validation passed for `feature_list.json` and `data/quran-metadata-surah-name.json`.
- Whitespace check passed: `git diff --check`.
- The first app build attempt using `/private/tmp/tarteel-xcode-derived` failed because the cached `FluidAudio` checkout was stale and missing `Package.swift`; rerunning with fresh derived data and network access resolved package dependencies and built successfully.

## Current Risks

- No manual Simulator or physical-device test has been run yet for the new controls.
- No scoped RunPod faster-whisper replay has been run from this UI slice. The UI only makes selected scope easier to exercise; it does not prove real-ASR quality.
- The selected Surah UI currently scopes whole surahs only. Ayah-range UI remains backend-capable but not surfaced in the iOS app.

## Next Best Step

Manually test the iOS app against a backend using Auto and Surah 108/4 selection before merging to `main`.
