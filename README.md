# Tarteel Realtime MVP

Technical MVP for Quran recitation location and correction.

## Run The Dev API

```bash
uv run uvicorn tarteel_realtime.dev_app:app --reload
```

Health check:

```bash
curl http://127.0.0.1:8000/health
```

The dev app exposes `WS /ws/recitation` and uses a built-in fake recognizer script:

1. First chunk recognizes `مَلِكِ` and emits `locked` at `114:2:1`.
2. Second chunk recognizes `الْفَلَقِ` and emits `wrong` against expected `114:2:2`.

Each WebSocket message is JSON:

```json
{
  "sequence_number": 0,
  "pcm_base64": "AAE=",
  "sample_rate_hz": 16000
}
```

`pcm_base64` is expected to contain little-endian signed PCM16 audio. The ASR adapter decodes it to normalized float samples before model inference.

In another terminal, send two dummy chunks to the dev WebSocket:

```bash
uv run python -m tarteel_realtime.ws_client
```

The dev recognizer script should emit a `locked` event followed by a `wrong` event.

## Quran Text Data

The production path should use a pinned Tanzil UTF-8 text file, loaded with `QuranCorpus.from_tanzil_file(...)`.

Recommended local placement once downloaded:

```text
data/tanzil/quran-simple-clean.txt
```

The repo includes `fixtures/quran/sample-tanzil.txt` for deterministic smoke tests only. The full Quran file should stay local at the path above.

After placing the full file, record its source metadata and checksum:

```bash
uv run python -m tarteel_realtime.quran_data --tanzil-path data/tanzil/quran-simple-clean.txt --source-name Tanzil --source-url "record-the-source-url-you-used" --write-manifest
```

Check the pinned file before using it for real evaluation:

```bash
uv run python -m tarteel_realtime.quran_data --check-manifest
```

Do not edit the canonical Tanzil file in place. If matching needs simplified text, derive normalized data at runtime or in generated artifacts.

## Run Offline Evaluation

Run the sample fake-transcript evaluation fixture:

```bash
uv run python -m tarteel_realtime.evaluate fixtures/evaluation/juz-amma-smoke.jsonl --tanzil-path fixtures/quran/sample-tanzil.txt --minimum-lock-words 2
```

When the full Tanzil file is downloaded to `data/tanzil/quran-simple-clean.txt`, the `--tanzil-path` flag can be omitted. Add `--mvp-scope` to evaluate only Al-Fatihah and Juz Amma from a larger Tanzil file.

```bash
uv run python -m tarteel_realtime.evaluate fixtures/evaluation/juz-amma-smoke.jsonl --minimum-lock-words 2 --mvp-scope
```

## ASR Adapter

The current app uses `FakeRecognizer` for deterministic development. `WhisperRecognizer` defines the optional Quran Whisper integration boundary, but model dependencies are intentionally not part of the default install yet.

Run one local smoke transcription with the tested command wrapper. Raw `.pcm16le` input uses `--sample-rate`; `.wav` input must be mono 16-bit PCM and uses the file's embedded sample rate.

```bash
uv run python -m tarteel_realtime.asr_smoke path/to/audio.pcm16le --model-id basharalrfooh/whisper-small-quran --sample-rate 16000
uv run python -m tarteel_realtime.asr_smoke path/to/audio.wav --model-id basharalrfooh/whisper-small-quran
```

Add `--tanzil-path` when you want the smoke output to include a Quran locator decision for the transcript:

```bash
uv run python -m tarteel_realtime.asr_smoke path/to/audio.wav --model-id basharalrfooh/whisper-small-quran --tanzil-path fixtures/quran/sample-tanzil.txt --minimum-lock-words 2
```

For a real model run, keep dependencies opt-in with `uv`, for example:

```bash
uv run --with transformers --with torch python -m tarteel_realtime.asr_smoke path/to/audio.wav --model-id basharalrfooh/whisper-small-quran --tanzil-path data/tanzil/quran-simple-clean.txt --mvp-scope
```

On the RunPod L4 smoke environment verified on 2026-05-16, the reproducible GPU command used CUDA-12-compatible Torch pins and an explicit `torchvision` install so `transformers.pipeline` does not import the pod's system `torchvision`:

```bash
UV_NO_PROGRESS=1 uv run --no-project --with transformers --with 'torch==2.7.1' --with 'torchvision==0.22.1' python -m tarteel_realtime.asr_smoke path/to/mono-16k.wav --model-id basharalrfooh/whisper-small-quran --tanzil-path fixtures/quran/sample-tanzil.txt --minimum-lock-words 2 --device cuda:0
```

This path prints one compact JSON transcription payload. It does not store raw audio.

## Real ASR WebSocket Backend

The default backend remains `tarteel_realtime.dev_app:app` with `FakeRecognizer`. The real ASR backend is a separate opt-in app that uses the same `WS /ws/recitation` contract and lazy-loads the Whisper model on the first audio chunk.

The real ASR backend buffers short mic chunks in memory before calling Whisper. Default buffering is:

```text
TARTEEL_ASR_MIN_AUDIO_MS=4200
TARTEEL_ASR_FLUSH_MS=4200
TARTEEL_ASR_TAIL_MS=0
TARTEEL_ASR_MIN_SPEECH_RMS=400
TARTEEL_ASR_MIN_FRAME_RMS=150
TARTEEL_WHISPER_BACKEND=transformers
```

Each incoming WebSocket or LiveKit audio frame is first passed through the lightweight speech-energy gate. Frames below `TARTEEL_ASR_MIN_FRAME_RMS` are not appended to the rolling ASR buffer, so low-noise transport audio does not become a Whisper request. Before each model call the backend then waits for at least `TARTEEL_ASR_MIN_AUDIO_MS` of buffered PCM16 speech audio and still requires the full buffer to meet `TARTEEL_ASR_MIN_SPEECH_RMS`. The default is the stable larger-window profile; smaller experimental windows can still be supplied through environment variables.

Local or CPU smoke command:

```bash
TARTEEL_TANZIL_PATH=data/tanzil/quran-simple-clean.txt \
TARTEEL_WHISPER_MODEL_ID=basharalrfooh/whisper-small-quran \
uv run --with transformers --with torch uvicorn tarteel_realtime.asr_app:create_app_from_env --factory --reload
```

RunPod L4 command, keeping ASR dependencies opt-in:

```bash
TARTEEL_TANZIL_PATH=data/tanzil/quran-simple-clean.txt \
TARTEEL_WHISPER_MODEL_ID=basharalrfooh/whisper-small-quran \
TARTEEL_WHISPER_DEVICE=cuda:0 \
UV_NO_PROGRESS=1 uv run --with transformers --with 'torch==2.7.1' --with 'torchvision==0.22.1' uvicorn tarteel_realtime.asr_app:create_app_from_env --factory --host 0.0.0.0 --port 8000
```

For CTranslate2/faster-whisper model IDs such as `OdyAsh/faster-whisper-base-ar-quran`, select the optional faster-whisper backend instead of the default Transformers backend:

```bash
TARTEEL_TANZIL_PATH=data/tanzil/quran-simple-clean.txt \
TARTEEL_WHISPER_BACKEND=faster-whisper \
TARTEEL_WHISPER_MODEL_ID=OdyAsh/faster-whisper-base-ar-quran \
TARTEEL_WHISPER_DEVICE=cuda:0 \
TARTEEL_FASTER_WHISPER_COMPUTE_TYPE=float16 \
UV_NO_PROGRESS=1 uv run --with faster-whisper uvicorn tarteel_realtime.asr_app:create_app_from_env --factory --host 0.0.0.0 --port 8000
```

Send one mono PCM16 WAV or raw PCM16LE file through the WebSocket:

```bash
uv run python -m tarteel_realtime.ws_client --url ws://127.0.0.1:8000/ws/recitation --audio-path path/to/mono-16k.wav
```

By default, `--audio-path` is sent as one whole-file chunk. To simulate live microphone chunks, add a chunk duration:

```bash
uv run python -m tarteel_realtime.ws_client --url ws://127.0.0.1:8000/ws/recitation --audio-path path/to/mono-16k.wav --chunk-ms 1000
```

For the first RunPod L40S chunked-WAV proof on 2026-05-17, Surah 114:2 locked reliably with a larger first buffer:

```bash
TARTEEL_TANZIL_PATH=fixtures/quran/sample-tanzil.txt \
TARTEEL_MINIMUM_LOCK_WORDS=2 \
TARTEEL_WHISPER_MODEL_ID=basharalrfooh/whisper-small-quran \
TARTEEL_WHISPER_DEVICE=cuda:0 \
TARTEEL_ASR_MIN_AUDIO_MS=4200 \
TARTEEL_ASR_FLUSH_MS=4200 \
TARTEEL_ASR_TAIL_MS=0 \
TARTEEL_ASR_MIN_SPEECH_RMS=400 \
TARTEEL_ASR_MIN_FRAME_RMS=150 \
UV_NO_PROGRESS=1 uv run --python 3.13 --with transformers --with 'torch==2.7.1' uvicorn tarteel_realtime.asr_app:create_app_from_env --factory --host 127.0.0.1 --port 8000
```

Then, from the same pod shell:

```bash
uv run --python 3.13 --with websockets python -m tarteel_realtime.ws_client --url ws://127.0.0.1:8000/ws/recitation --audio-path fixtures/local_audio/114002.wav --chunk-ms 1000
```

Expected shape: several `waiting_for_audio_buffer` events, then a `locked` event for `114:2`. This is a capability proof, not final latency tuning.

## LiveKit Cloud + VAD Transport Spike

The WebSocket transport remains the default and fallback path. The LiveKit path is a local-dev WebRTC spike that reuses the same recitation session engine and publishes backend events over a reliable LiveKit data topic:

```text
tarteel.recitation.event
```

The iOS LiveKit preset now uses the same app-owned microphone pipeline as the WebSocket fallback: `MicrophoneAudioStreamer` captures mono PCM16, `VoiceActivityDetector` runs the bundled Silero VAD, and the LiveKit adapter feeds speech chunks into the SDK with manual rendering mode through `AudioManager.shared.mixer.capture(appAudio:)`. The client also publishes VAD metadata on:

```text
tarteel.voice_activity
```

The LiveKit worker stores the latest VAD packet by participant identity and attaches it to decoded audio frames before the rolling ASR buffer sees them. If VAD is unavailable, LiveKit audio still publishes normally; when VAD is available, inactive non-event chunks are suppressed client-side while `speech_start` and `speech_end` chunks are still sent.

For the GPU ASR smoke, prefer LiveKit Cloud instead of tunneling the media server. Copy `.env.example` to `.env` and fill the Cloud values from the LiveKit project dashboard:

```text
LIVEKIT_URL=wss://<project>.livekit.cloud
LIVEKIT_API_KEY=<livekit-api-key>
LIVEKIT_API_SECRET=<livekit-api-secret>
TARTEEL_LIVEKIT_ROOM=tarteel-recitation
```

`LIVEKIT_URL`, `LIVEKIT_API_KEY`, and `LIVEKIT_API_SECRET` must be provided together. If none are set, the code falls back to local `livekit-server --dev` defaults.

Start a local LiveKit server in dev mode:

```bash
livekit-server --dev
```

For LiveKit Cloud, do not start `livekit-server --dev`; only start the token backend locally so the iOS Simulator can fetch a Cloud join token:

```bash
uv run --env-file .env --with livekit-api \
  python -m uvicorn tarteel_realtime.dev_app:app --host 0.0.0.0 --port 8000
```

For local dev server testing, the same backend command works without `.env`:

```bash
uv run --with livekit-api \
  python -m uvicorn tarteel_realtime.dev_app:app --host 0.0.0.0 --port 8000
```

The token endpoint returns the configured LiveKit URL and grants:

```text
GET http://127.0.0.1:8000/livekit/recitation-token?identity=ios-simulator&role=client
```

Run the Python LiveKit worker on the machine that has ASR access. For RunPod, set the same LiveKit Cloud env values as RunPod secrets or source them in the pod before launching the worker. Real ASR dependencies remain opt-in just like the WebSocket ASR app:

```bash
TARTEEL_TANZIL_PATH=data/tanzil/quran-simple-clean.txt \
uv run --env-file .env --with livekit --with livekit-api --with transformers --with torch --with torchaudio \
  python -m tarteel_realtime.livekit_worker
```

LiveKit/WebRTC may deliver worker frames at a transport-selected sample rate. Include `torchaudio` for the Transformers real-ASR worker so the pipeline can resample that stream before Whisper inference. The faster-whisper backend resamples PCM to 16 kHz before calling CTranslate2, so it uses `--with faster-whisper` instead:

```bash
TARTEEL_TANZIL_PATH=data/tanzil/quran-simple-clean.txt \
TARTEEL_WHISPER_BACKEND=faster-whisper \
TARTEEL_WHISPER_MODEL_ID=OdyAsh/faster-whisper-base-ar-quran \
TARTEEL_WHISPER_DEVICE=cuda:0 \
TARTEEL_FASTER_WHISPER_COMPUTE_TYPE=float16 \
uv run --env-file .env --with livekit --with livekit-api --with faster-whisper \
  python -m tarteel_realtime.livekit_worker
```

The fixture WAV smoke path uses mono 16 kHz audio, so it can pass even when transport resampling dependencies are missing. The same speech-energy gate runs after the LiveKit/WebSocket transport frame is decoded and before the rolling ASR buffer is built.

For a transport-only smoke without pulling Whisper/Torch, pass a deterministic transcript script:

```bash
TARTEEL_TANZIL_PATH=fixtures/quran/sample-tanzil.txt \
uv run --env-file .env --with livekit --with livekit-api \
  python -m tarteel_realtime.livekit_worker --fake-transcript "مَلِكِ"
```

With the worker running, publish synthetic audio and wait for a recitation event:

```bash
uv run --env-file .env --with livekit --with livekit-api \
  python -m tarteel_realtime.livekit_smoke
```

The iOS prototype includes a `LiveKit` preset that fetches the token endpoint above. In the Simulator, `http://127.0.0.1:8000/livekit/recitation-token` reaches the Mac token backend; the returned `wss://...livekit.cloud` URL is what both iOS and the RunPod worker join. LiveKit and FluidAudio are compile-guarded: the app still builds without those SDKs linked, and selecting the LiveKit preset reports that the SDK is unavailable until the app target is linked with LiveKit. FluidAudio/Silero VAD is also guarded; when linked, local microphone chunks carry `voice_activity` metadata through the WebSocket fallback path and the LiveKit `tarteel.voice_activity` topic. Backend buffering can trust `speech_start` as speech and flush early on `speech_end` after minimum audio is present.

The app bundles the FluidInference Silero VAD Core ML asset at `ios/TarteelPrototype/TarteelPrototype/Models/silero-vad-unified-256ms-v6.0.0.mlmodelc`. `VoiceActivityDetector` prefers that local compiled model through `VadManager(config: .default, vadModel:)` and falls back to `VadManager()` only if the bundle is absent. Streaming VAD state is reset whenever recording starts or stops.

## GitHub And R2 Artifact Workflow

Use GitHub for source code and Cloudflare R2 for ignored local artifacts such as the full Tanzil text and recitation WAVs. The R2 helper expects S3-compatible R2 credentials in environment variables, not a general Cloudflare API token.

```bash
export R2_ENDPOINT_URL="https://bb8b1b9ffb067e41f5657c9f1400c42b.r2.cloudflarestorage.com"
export R2_BUCKET="tarteel-realtime"
export R2_ACCESS_KEY_ID="replace-with-r2-access-key-id"
export R2_SECRET_ACCESS_KEY="replace-with-r2-secret-access-key"
```

Upload local artifacts:

```bash
uv run --with boto3 python scripts/r2_artifacts.py upload data/tanzil/quran-simple-clean.txt
uv run --with boto3 python scripts/r2_artifacts.py upload fixtures/local_audio
```

If upload fails with `AccessDenied` during `PutObject`, the credentials are authenticating but do not have write access to the bucket. Use an R2 S3 token with Object Read & Write scope for `tarteel-realtime`.

Download on RunPod:

```bash
source /workspace/tarteel-r2.env
uv run --with boto3 python scripts/r2_artifacts.py download data/tanzil/quran-simple-clean.txt
uv run --with boto3 python scripts/r2_artifacts.py download fixtures/local_audio/114001.mp3
uv run --with boto3 python scripts/r2_artifacts.py download fixtures/local_audio/114002.mp3
ffmpeg -y -i fixtures/local_audio/114001.mp3 -ac 1 -ar 16000 -sample_fmt s16 fixtures/local_audio/114001.wav
ffmpeg -y -i fixtures/local_audio/114002.mp3 -ac 1 -ar 16000 -sample_fmt s16 fixtures/local_audio/114002.wav
```

The full RunPod/R2 workflow is documented in `docs/runpod-r2.md`.

The current GitHub repo is public, so a fresh RunPod pod can clone it over HTTPS. If the repo becomes private again, configure a read-only deploy key or another GitHub auth method before running the bootstrap. Do not use `scp` for pod setup; add R2 credentials manually to `/workspace/tarteel-r2.env` or through RunPod secrets.

## iOS Prototype

The first native SwiftUI prototype lives under `ios/`.

Run the deterministic backend first:

```bash
uv run uvicorn tarteel_realtime.dev_app:app --reload
```

Then open:

```text
ios/TarteelPrototype/TarteelPrototype.xcodeproj
```

The app defaults to the `Simulator` backend preset:

```text
ws://127.0.0.1:8000/ws/recitation
```

Switch to `Custom` for a LAN, tunnel, or later RunPod real-ASR WebSocket URL. For a physical iPhone, run the backend with `--host 0.0.0.0` and enter your Mac LAN IP in the app. More details are in `ios/README.md`.

## Verify

```bash
uv run python -B -m unittest discover
uv run python -m compileall -q tarteel_realtime tests
```
