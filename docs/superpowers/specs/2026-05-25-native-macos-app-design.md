# Native macOS App Design

## Goal

Add a true native macOS SwiftUI prototype alongside the existing iPhone app, sharing the realtime recitation contract and core client behavior while giving macOS a desktop-appropriate app surface.

## Scope

The first macOS slice is feature-parity with the current iPhone prototype plus a compact desktop status console. It will support:

- native macOS app target named `TarteelPrototypeMac`
- bundle identifier `dev.mostafa.TarteelPrototypeMac`
- minimum macOS version 14
- local backend default at `ws://127.0.0.1:8000/ws/recitation`
- Custom backend URL for WSS, tunnels, LAN, and RunPod
- memory-only prototype RunPod API key
- microphone capture only
- bundled CoreML Silero VAD through the existing FluidAudio path
- Auto versus Surah recitation scope
- native macOS Settings scene
- minimal keyboard/menu commands for recording and Settings

Out of scope for the first slice:

- renaming `ios/` to `apple/`
- App Sandbox and distribution entitlements
- file replay or system-audio input
- first-class ayah/range scope UI
- storing the RunPod API key
- full manual RunPod live-ASR acceptance

## Repository Layout

Keep the current `ios/` tree for this slice. The folder already contains the Apple client work, and renaming it now would mix a path migration into the macOS app proof.

The macOS app will live in the existing Xcode project:

- iPhone target: `ios/TarteelPrototype/TarteelPrototype.xcodeproj` target `TarteelPrototype`
- macOS target: same project, new native app target `TarteelPrototypeMac`
- shared Swift package/tests: `ios/TarteelClientCore`

The project should continue using the current direct shared-source-file pattern for app targets. Shared files live under `ios/TarteelClientCore/Sources/TarteelClientCore` and are included directly in each native app target. SwiftPM remains the test harness for the shared core package.

## Shared Core Architecture

Move platform-neutral recording orchestration into `TarteelClientCore` behind protocols. Shared core should own:

- recording start/stop state transitions
- backend URL construction and recitation scope application
- WebSocket connection and event receive flow
- RunPod bearer-token handoff without persistence
- VAD metadata flow
- `RecitationSessionState` event reduction
- persistence of non-secret preferences

Platform-specific app targets should inject:

- microphone audio streamer
- voice activity detector implementation
- settings persistence adapter if needed by the app shell

`BackendWebSocketClient` should move into `TarteelClientCore` behind a protocol because `URLSessionWebSocketTask` works on iOS and macOS. This enables Swift unit tests with fake socket, fake audio, and fake VAD implementations.

`FluidAudio` should stay in app targets for now. The shared core should define only the protocol boundary and continue sharing `VoiceActivityPayload`. This keeps core tests lightweight and avoids making every SwiftPM test depend on the ML package or bundled model resource.

## iPhone App Behavior

The iPhone UI should remain visually unchanged during the refactor:

- white recitation home
- gear settings sheet
- status/ayah panel
- Auto/Surah controls
- Surah picker
- voice activity indicator
- bottom mic button

Internal wiring may change to use shared orchestration and protocols, but user-facing layout should not regress.

## macOS App Behavior

The macOS app should be a desktop SwiftUI surface, not an enlarged phone layout.

Main window:

- minimum fixed-friendly desktop window size
- primary recitation area with current headline/detail and mic control
- Auto/Surah controls
- selected Surah menu when Surah mode is active
- compact event/status console showing connection, last event, ayah ref, ayah text, recent transcript/event history, and errors
- toolbar settings button that opens the native Settings scene

Settings:

- native macOS `Settings` scene
- backend preset selector
- backend URL field
- prototype-only RunPod API key secure field
- controls disabled while recording when changing them would invalidate the active connection

Commands:

- Space or Command-R toggles recording
- Command-comma opens Settings
- standard Quit remains available

## Audio And VAD

The macOS microphone path should use `AVAudioEngine` and macOS microphone permission through `AVCaptureDevice`, not iOS-only `AVAudioSession`.

The macOS streamer must convert input buffers to the same payload shape as iPhone:

- mono
- 16 kHz
- PCM16
- `AudioChunkPayload` over the existing `/ws/recitation` WebSocket contract

The macOS app should include the same bundled `Models/silero-vad-unified-256ms-v6.0.0.mlmodelc` resource used by iPhone and run the same FluidAudio/CoreML Silero VAD path where platform APIs allow it. The same model file reference should be included in both targets' resource phases to avoid duplicate artifacts.

If VAD initialization fails at runtime, recording should still stream audio and omit `voice_activity` metadata, matching the existing optional-metadata backend contract.

## Persistence

Persist only non-secret settings between launches:

- backend preset
- custom backend URL
- recitation mode
- selected Surah

Do not persist the RunPod API key in the first slice. It stays memory-only unless a later slice adds Keychain support.

## macOS App Configuration

Use a separate macOS `Info.plist`. Do not share the iPhone plist because it contains iOS-only keys such as `LSRequiresIPhoneOS`, `UIApplicationSceneManifest`, and launch-screen settings.

The macOS plist should include:

- bundle metadata through build settings
- microphone usage description
- development ATS allowance for local and prototype backend URLs

Leave App Sandbox disabled for this developer prototype slice. Sandboxing and distribution entitlements should be a later packaging task.

## Testing

Add Swift unit tests in `ios/TarteelClientCore` for the shared recording orchestration using fake socket, audio, and VAD implementations.

Keep Python source guardrails for:

- macOS target/project wiring
- macOS Info.plist expectations
- macOS source contains native Settings scene and desktop console
- iPhone source still exposes the existing clean home/settings shape
- bundled VAD model remains included in both app targets

Required verification for the first slice:

- Swift client core tests from `ios/TarteelClientCore`
- focused Python source guardrails for Apple clients
- iPhone app build still passes
- macOS app build passes
- structured docs/harness files validate where applicable

Manual mic and RunPod live-ASR testing should be documented as the next slice unless explicitly pulled into implementation acceptance.

## Success Criteria

The first slice is done when:

- `TarteelPrototypeMac` builds as a native macOS app target
- `TarteelPrototype` still builds as the iPhone target
- shared core Swift tests pass, including recording orchestration tests
- Python guardrails pass for iPhone and macOS project/source expectations
- macOS app exposes native UI, mic capture, bundled VAD, Settings, WebSocket streaming, Auto/Surah scope, event/status console, and memory-only RunPod key
- docs and harness files record the new commands, risks, and next manual verification step
