# Tarteel Realtime

Technical MVP for Quran recitation location and correction, with native iPhone
and macOS prototypes. The apps can stream microphone audio to the backend over
`WS /ws/recitation`, or run the experimental local CoreML FastConformer route
inside the Apple app.

## What Is Here

- `tarteel_realtime/`: Python backend, Quran parsing, recitation session logic,
  ASR adapter seams, and WebSocket API.
- `ios/TarteelClientCore/`: shared Swift package for endpoint presets, event
  decoding, state reduction, recording orchestration, CoreML routing, and tests.
- `ios/TarteelPrototype/`: Xcode project with the iPhone app target
  `TarteelPrototype` and native macOS app target `TarteelPrototypeMac`.
- `deploy/modal_asr_app.py`: Modal deployment for the real ASR backend.

## Prerequisites

- macOS with Xcode installed.
- `uv` for Python commands.
- Modal CLI configured locally if deploying the Modal backend.
- Optional local CoreML model artifacts at:

```text
.models/fastconformer-quran-coreml-streaming/
```

Expected CoreML files:

```text
fastconformer-quran-streaming.mlpackage
pronunciation-head.mlpackage
tokenizer.model
tokens.txt
```

For full-corpus local matching, place the pinned Tanzil text locally at:

```text
data/tanzil/quran-simple-clean.txt
```

The Quran text, local audio captures, bearer tokens, and other sensitive
runtime artifacts should stay local and uncommitted.

## Run The Local Dev Backend

Use this when the Apple app is set to the `Simulator` backend preset:

```bash
uv run uvicorn tarteel_realtime.dev_app:app --reload
```

Health check:

```bash
curl http://127.0.0.1:8000/health
```

The dev backend uses a fake recognizer and emits deterministic `locked` /
`wrong` events. You can smoke it from another terminal:

```bash
uv run python -m tarteel_realtime.ws_client
```

## Run The iOS App

Open the Xcode project:

```text
ios/TarteelPrototype/TarteelPrototype.xcodeproj
```

Build the iPhone app from the command line:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeCoreMLReplay -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build
```

In Xcode, choose an iPhone simulator or physical device and run the
`TarteelPrototypeCoreMLReplay` scheme. For normal manual testing, open Settings
in the app and choose one of:

- `CoreML`: local on-device route, default for fresh installs with selected
  Surah 108.
- `Simulator`: local fake backend at `ws://127.0.0.1:8000/ws/recitation`.
- `Custom`: remote Modal WebSocket URL with the Modal ASR model picker.

Important iOS note: the CoreML FastConformer model is specialized for Apple
Neural Engine hardware. The iOS Simulator can build and render the app, but it
is not valid CoreML ASR evidence for this model. Use a physical iPhone for
local CoreML ASR proof.

## Run The macOS App

Build the macOS target:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build
```

Open the built app:

```bash
open -n /private/tmp/tarteel-xcode-derived-macos/Build/Products/Debug/TarteelPrototypeMac.app
```

The macOS app uses a native toolbar for recording, Surah search, and Settings:

- `Space` or `Command-R`: start or stop recording.
- `Command-F`: focus Surah search.
- Settings: choose `CoreML`, `Simulator`, or `Custom`.
- Custom Modal bearer tokens are stored in macOS Keychain after entry.

For deterministic local replay through the same app queue, VAD metadata path,
backend route, and reducer:

```bash
open -n /private/tmp/tarteel-xcode-derived-macos/Build/Products/Debug/TarteelPrototypeMac.app --args \
  --tarteel-replay-audio 108001.wav \
  --tarteel-replay-surah 108
```

For live-mic diagnosis, capture the exact mono 16 kHz PCM16 chunks forwarded by
the app, then replay that capture:

```bash
open -n /private/tmp/tarteel-xcode-derived-macos/Build/Products/Debug/TarteelPrototypeMac.app --args --tarteel-capture-audio /tmp/tarteel-capture.wav
open -n /private/tmp/tarteel-xcode-derived-macos/Build/Products/Debug/TarteelPrototypeMac.app --args --tarteel-replay-audio /tmp/tarteel-capture.wav --tarteel-replay-surah 108
```

## CoreML Route

`CoreML` routes `coreml://fastconformer-quran-streaming` to the in-app
`CoreMLFastConformerSocketClient`. It preserves the same app recording queue,
VAD metadata seam, reducer state, and recitation event shape used by WebSocket
backends.

CoreML currently supports selected-Surah local matching best. Fresh installs
default to selected Surah 108. If the full Tanzil file is bundled locally, the
local Quran session can use the full corpus; otherwise it falls back to the
small MVP corpus.

Important CoreML comments:

- Keep CoreML model artifacts and local recitation audio out of git.
- Use physical iPhone hardware for iOS CoreML ASR claims.
- macOS CoreML replay is useful for debugging model, locator, and UI behavior.
- The app logs CoreML audio windows, transcripts, locator events, stream resets,
  and latency markers through unified logging.

## Modal Deployment

Modal serves the real ASR backend behind the same WebSocket app contract:

```text
wss://<modal-app>.modal.run/ws/recitation
```

The Apple apps use Settings -> `Custom` for Modal. The visible Custom provider
is Modal-only, and the app appends the selected ASR model slug as `asr_model` on
the recording URL.

Approved Modal ASR model slugs:

```text
nemo-fastconformer-quran-ar
faster-whisper-base-ar-quran
```

Create a Modal Secret named `tarteel-modal-asr-secrets` containing:

```text
TARTEEL_WS_BEARER_TOKEN=<prototype token>
```

Do not store the token in docs or git.

Prewarm both model snapshots:

```bash
modal run deploy/modal_asr_app.py::prewarm
```

Deploy:

```bash
modal deploy deploy/modal_asr_app.py
```

After deployment, enter the WSS URL in the iPhone or macOS app Settings, paste
the Modal bearer token locally, choose an ASR model, select a Surah, and record.

For a command-line replay proof:

```bash
uv run --with websockets python -m tarteel_realtime.replay_probe \
  --url 'wss://<modal-app>.modal.run/ws/recitation' \
  --scope 108 \
  --asr-model nemo-fastconformer-quran-ar \
  --audio-path fixtures/local_audio/108001.wav \
  --chunk-ms 160 \
  --bearer-token-env MODAL_TOKEN \
  --disable-ping \
  --send-speech-end \
  --include-events
```

Repeat with `--asr-model faster-whisper-base-ar-quran` when comparing Modal
profiles.

## Important Comments

- WebSocket `/ws/recitation` is the only remote backend transport.
- The local CoreML route is in-app only; it is not a second backend protocol.
- The app sends PCM16 audio chunks plus optional VAD metadata.
- Canonical displayed ayah text should come from Quran data, not from noisy ASR
  transcript text.
- Heavy ASR dependencies remain opt-in and should not become default test
  dependencies.
- iPhone bearer tokens are memory-only. macOS Custom bearer tokens are stored in
  Keychain after entry.
- Raw user audio, generated diagnostics, local Quran text, and credentials must
  remain local unless intentionally shared as evidence.

## Verify

Python:

```bash
uv run python -B -m unittest discover -s tests -v
uv run python -m compileall -q tarteel_realtime tests
```

Swift client core:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test
```

Apple source/project guardrails:

```bash
uv run python -B -m unittest tests.test_macos_app_project tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v
```
