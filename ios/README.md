# iOS Prototype

This folder contains the first native iPhone prototype for the realtime recitation flow.

## Run The Backend

From the repository root:

```bash
uv run --with livekit-api python -m uvicorn tarteel_realtime.dev_app:app --reload
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

For the older WebSocket RunPod path, keep the app on `Custom` and enter the WebSocket URL exposed by your tunnel or network bridge. The app treats real-ASR buffering events as normal listening flow: it can show `Gathering audio` before lock, then stay in `Listening` while the backend buffers more audio.

For the LiveKit Cloud + RunPod path, keep the app on the `LiveKit` preset. Start the token backend with the Cloud values loaded from `.env`:

```bash
uv run --env-file .env --with livekit-api \
  python -m uvicorn tarteel_realtime.dev_app:app --host 127.0.0.1 --port 8000
```

The Simulator reaches that token backend at `http://127.0.0.1:8000/livekit/recitation-token`, then connects directly to the `LIVEKIT_URL` returned by the backend. The RunPod worker must use the same `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, and `TARTEEL_LIVEKIT_ROOM` values.

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

The prototype streams microphone PCM chunks to a selected backend and renders session events. It does not run Whisper on-device and does not store raw audio.
