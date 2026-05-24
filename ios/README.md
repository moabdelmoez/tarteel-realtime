# iOS Prototype

This folder contains the first native iPhone prototype for the realtime recitation flow.

## Run The Backend

From the repository root:

```bash
uv run python -m uvicorn tarteel_realtime.dev_app:app --reload
```

The app connects to:

```text
ws://127.0.0.1:8000/ws/recitation
```

That works for the iOS Simulator when the app is set to the `Simulator` backend preset. For a physical iPhone, run the backend on your Mac with a LAN-visible host, switch the app to `Custom`, and enter your Mac IP:

```bash
uv run uvicorn tarteel_realtime.dev_app:app --host 0.0.0.0 --reload
```

Example phone URL:

```text
ws://192.168.1.20:8000/ws/recitation
```

For a remote WebSocket GPU path, keep the app on `Custom` and enter the WebSocket URL exposed by your tunnel or network bridge. The app treats real-ASR buffering events as normal listening flow: it can show `Gathering audio` before lock, then stay in `Listening` while the backend buffers more audio.

For a RunPod real-ASR backend, enter the exposed WSS URL in `Custom`:

```text
wss://<pod-id>-8000.proxy.runpod.net/ws/recitation
```

## Recitation Scope

The app starts in `Auto` mode, which leaves Quran location detection global. Switch to `Surah` and choose a surah from the menu when the user already knows what they will recite. In `Surah` mode, the app appends `scope=<surah-id>` to the WebSocket URL before recording starts, for example:

```text
wss://<pod-id>-8000.proxy.runpod.net/ws/recitation?scope=108
```

Switching back to `Auto` removes the app-managed `scope` query item while preserving other query parameters. The backend still receives the same audio chunk payload; selected-recitation scope stays in the WebSocket URL.

The app uses one microphone pipeline for every backend preset: `MicrophoneAudioStreamer` captures mono PCM16, `VoiceActivityDetector` runs the bundled Silero VAD when available, and `BackendWebSocketClient` sends audio chunks plus optional `voice_activity` metadata to the backend.

## Build The App

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build
```

Or open:

```text
ios/TarteelPrototype/TarteelPrototype.xcodeproj
```

## Test The Shared Client Core

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test
```

The core package covers backend endpoint presets, backend event decoding, audio chunk JSON encoding, and mobile session-state reduction.

## Current Scope

The prototype streams microphone PCM chunks to a selected backend and renders session events. Client-side Silero VAD runs on-device for transport metadata/gating, but Whisper still runs only on the backend. The app does not store raw audio.
