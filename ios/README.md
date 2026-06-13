# Apple Prototypes

This folder contains the native Apple prototypes for the realtime recitation flow.

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

For a Modal real-ASR backend, deploy `deploy/modal_asr_app.py`, then enter the
generated Web Function URL as a WebSocket URL in `Custom`:

```text
wss://<modal-app>.modal.run/ws/recitation
```

When provider `Modal` is selected, Settings also shows an `ASR model` menu. The
menu is disabled while recording and persists between app launches. The approved
choices are:

- `FastConformer Quran AR (NeMo)` -> `asr_model=nemo-fastconformer-quran-ar`
- `Faster Whisper Base AR Quran` -> `asr_model=faster-whisper-base-ar-quran`

## Backend Settings

The home screen keeps recitation controls visible and moves backend setup behind the gear button. Open settings to choose the `Simulator` or `Custom` backend preset and edit the custom WebSocket URL.

When `Custom` is selected, choose a provider:

- `Generic`: leaves custom URLs alone except for `http` to `ws` and `https` to `wss` conversion.
- `RunPod`: normalizes bare `.proxy.runpod.net` and `.api.runpod.ai` hosts to `wss://.../ws/recitation`.
- `Modal`: normalizes bare `.modal.run` hosts to `wss://.../ws/recitation`.

The bearer-token field is memory-only and is not saved. Use it only for prototype direct RunPod or Modal testing.

For Modal ASR testing, use provider `Modal`, choose the ASR model, paste the
deployed WSS URL, enter the Modal bearer token locally, select Surah 108, and
record a short recitation. The app still sends the same `AudioChunkPayload`
shape to `/ws/recitation`; the selected server-side ASR profile travels as an
app-managed `asr_model` query item.

For deterministic developer replay, the app can also be launched with local
audio and backend arguments after the token has been entered locally through
Settings or, on macOS, restored from Keychain:

```bash
open -n /path/to/TarteelPrototypeMac.app --args \
  --tarteel-replay-audio 108001.wav \
  --tarteel-replay-surah 108 \
  --tarteel-backend-url wss://<modal-app>.modal.run/ws/recitation \
  --tarteel-backend-provider modal
```

That path replays bundled/local WAV chunks through the normal app queue, VAD
metadata, WebSocket client, and backend reducer. It does not pass bearer tokens
on the command line.

## Recitation Scope

The app starts in `Auto` mode, which leaves Quran location detection global. Switch to `Surah` and choose a surah from the menu when the user already knows what they will recite. In `Surah` mode, the app appends `scope=<surah-id>` to the WebSocket URL before recording starts, for example:

```text
wss://<modal-app>.modal.run/ws/recitation?scope=108&asr_model=nemo-fastconformer-quran-ar
```

Switching back to `Auto` removes the app-managed `scope` query item while preserving other query parameters. The backend still receives the same audio chunk payload; selected-recitation scope stays in the WebSocket URL.

The app uses one microphone pipeline for every backend preset: `MicrophoneAudioStreamer` captures mono PCM16, `VoiceActivityDetector` runs the bundled Silero VAD when available, and `BackendWebSocketClient` sends audio chunks plus optional `voice_activity` metadata to the backend.

## Build The App

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeCoreMLReplay -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build
```

The 2026-06-13 Modal NeMo branch built this iOS Simulator scheme successfully,
but manual Simulator install/launch control hung locally and the captured
Simulator screen was blank. Do not treat that run as successful iOS manual ASR
evidence until Simulator control or a physical-device check is repeated.

## macOS Prototype

The same Xcode project also contains a native macOS developer prototype target:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build
```

The macOS app defaults to:

```text
ws://127.0.0.1:8000/ws/recitation
```

It uses a native Settings window for backend preset, Custom provider, custom URL, and memory-only bearer token. Non-secret settings persist between launches. The bearer token is memory-only unless a later Keychain slice adds secure storage.

The macOS recitation window uses a unified native toolbar for recording, Surah search, and Settings. Press `Space` or `Command-R` to start or stop recording, and `Command-F` to focus Surah search. Search filters and selects Surah scope, URL or text drops can populate the Custom backend URL with visible feedback, and the diagnostic summary can be dragged out as text for bug reports.

The macOS app captures microphone input, converts it to mono 16 kHz PCM16, runs the bundled FluidAudio/CoreML Silero VAD when available, and sends the same `AudioChunkPayload` shape as the iPhone app.

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

The prototype streams microphone PCM chunks to a selected backend and renders session events. Client-side Silero VAD runs on-device for transport metadata/gating, but ASR still runs only on the backend unless the experimental CoreML preset is selected. The app does not store raw audio.
