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

The repo does not commit Quran text or evaluator JSONL smoke fixtures. Deterministic unit tests embed the tiny smoke data they need; the full Quran file should stay local at the path above.

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

Run the deterministic evaluator tests:

```bash
uv run python -B -m unittest tests.test_evaluator tests.test_evaluate_cli
```

When the full Tanzil file is downloaded to `data/tanzil/quran-simple-clean.txt`, the `--tanzil-path` flag can be omitted. Add `--mvp-scope` to evaluate only Al-Fatihah and Juz Amma from a larger Tanzil file. Pass your own JSONL case file to the CLI:

```bash
uv run python -m tarteel_realtime.evaluate path/to/cases.jsonl --minimum-lock-words 2 --mvp-scope
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
uv run python -m tarteel_realtime.asr_smoke path/to/audio.wav --model-id basharalrfooh/whisper-small-quran --tanzil-path data/tanzil/quran-simple-clean.txt --minimum-lock-words 2
```

For a real model run, keep dependencies opt-in with `uv`, for example:

```bash
uv run --with transformers --with torch python -m tarteel_realtime.asr_smoke path/to/audio.wav --model-id basharalrfooh/whisper-small-quran --tanzil-path data/tanzil/quran-simple-clean.txt --mvp-scope
```

On the RunPod L4 smoke environment verified on 2026-05-16, the reproducible GPU command used CUDA-12-compatible Torch pins and an explicit `torchvision` install so `transformers.pipeline` does not import the pod's system `torchvision`:

```bash
UV_NO_PROGRESS=1 uv run --no-project --with transformers --with 'torch==2.7.1' --with 'torchvision==0.22.1' python -m tarteel_realtime.asr_smoke path/to/mono-16k.wav --model-id basharalrfooh/whisper-small-quran --tanzil-path data/tanzil/quran-simple-clean.txt --minimum-lock-words 2 --device cuda:0
```

This path prints one compact JSON transcription payload. It does not store raw audio.

## Real ASR WebSocket Backend

The default backend remains `tarteel_realtime.dev_app:app` with `FakeRecognizer`. The real ASR backend is a separate opt-in app that uses the same `WS /ws/recitation` contract and lazy-loads the Whisper model on the first audio chunk.

The real ASR backend buffers short mic chunks in memory before calling Whisper. Default buffering is the stable profile:

```text
TARTEEL_ASR_BUFFERING_PROFILE=stable
TARTEEL_ASR_MIN_AUDIO_MS=4200
TARTEEL_ASR_FLUSH_MS=4200
TARTEEL_ASR_TAIL_MS=0
TARTEEL_ASR_MIN_SPEECH_RMS=400
TARTEEL_ASR_MIN_FRAME_RMS=150
TARTEEL_WHISPER_BACKEND=transformers
```

For GPU replay with faster-whisper, the opt-in low-latency buffering profile is:

```text
TARTEEL_ASR_BUFFERING_PROFILE=low-latency
TARTEEL_ASR_MIN_AUDIO_MS=2000
TARTEEL_ASR_FLUSH_MS=1000
TARTEEL_ASR_TAIL_MS=500
TARTEEL_ASR_MIN_SPEECH_RMS=400
TARTEEL_ASR_MIN_FRAME_RMS=150
```

Each incoming WebSocket audio frame is first passed through the lightweight speech-energy gate. Frames below `TARTEEL_ASR_MIN_FRAME_RMS` are not appended to the rolling ASR buffer, so low-noise transport audio does not become a Whisper request. Before each model call the backend then waits for at least `TARTEEL_ASR_MIN_AUDIO_MS` of buffered PCM16 speech audio and still requires the full buffer to meet `TARTEEL_ASR_MIN_SPEECH_RMS`. `TARTEEL_ASR_BUFFERING_PROFILE=low-latency` gives the ASR backend a shorter first window and keeps 500ms of tail context between windows; explicit `TARTEEL_ASR_MIN_AUDIO_MS`, `TARTEEL_ASR_FLUSH_MS`, `TARTEEL_ASR_TAIL_MS`, `TARTEEL_ASR_MIN_SPEECH_RMS`, or `TARTEEL_ASR_MIN_FRAME_RMS` values override the selected profile.

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
TARTEEL_ASR_BUFFERING_PROFILE=low-latency \
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

For real ASR windows that may exceed WebSocket keepalive timeouts during model load or long inference, add `--disable-ping` to the replay command.

If the app knows the intended recitation range, append `scope` to the WebSocket URL so matching stays inside that range before the first lock and during ordered progression. Supported forms are a whole surah like `?scope=108`, a single ayah like `?scope=108:2`, or an inclusive range like `?scope=4:1-3`.

```bash
uv run python -m tarteel_realtime.ws_client --url 'ws://127.0.0.1:8000/ws/recitation?scope=108' --audio-path path/to/mono-16k.wav --chunk-ms 1000
uv run python -m tarteel_realtime.ws_client --url 'ws://127.0.0.1:8000/ws/recitation?scope=4:1-3' --audio-path path/to/mono-16k.wav --chunk-ms 1000
```

Without `scope`, the backend keeps the current conservative global behavior.

For the first RunPod L40S chunked-WAV proof on 2026-05-17, Surah 114:2 locked reliably with a larger first buffer:

```bash
TARTEEL_TANZIL_PATH=data/tanzil/quran-simple-clean.txt \
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
uv run --python 3.13 --with websockets python -m tarteel_realtime.ws_client --url ws://127.0.0.1:8000/ws/recitation --audio-path fixtures/local_audio/108001.wav --chunk-ms 1000 --disable-ping
uv run --python 3.13 --with websockets python -m tarteel_realtime.ws_client --url ws://127.0.0.1:8000/ws/recitation --audio-path fixtures/local_audio/004001.wav --chunk-ms 1000 --disable-ping
```

Expected shape: several `waiting_for_audio_buffer` events, then a meaningful `locked`, `progress`, `lock_candidate`, or `uncertain` event stream. This is a capability proof, not final latency tuning.

## WebSocket + VAD Transport

WebSocket is the only transport for app audio. The iOS prototype uses one app-owned microphone pipeline: `MicrophoneAudioStreamer` captures mono PCM16, `VoiceActivityDetector` runs the bundled Silero VAD when available, and `BackendWebSocketClient` sends `AudioChunkPayload` messages to `WS /ws/recitation`.

When VAD metadata is available, each WebSocket chunk may include:

```json
{
  "voice_activity": {
    "probability": 0.82,
    "is_speech_active": true,
    "event": "speech_start"
  }
}
```

The backend treats that metadata as transport-neutral input to the rolling ASR buffer. It can trust `speech_start` as speech and flush early on `speech_end` after minimum audio is present. If VAD is unavailable, the WebSocket path still works with PCM16 audio and backend RMS gating.

For RunPod or another GPU host, expose the real ASR backend directly over WSS and enter that URL in the iOS `Custom` preset:

```text
wss://<pod-id>-8000.proxy.runpod.net/ws/recitation
```

The `Custom` preset accepts full WebSocket URLs. For RunPod proxy hosts pasted without a scheme or path, the app normalizes to `wss://.../ws/recitation`.

For the prototype RunPod Serverless path, use a Load Balancer endpoint and paste the full endpoint URL or bare host into the iOS `Custom` preset:

```text
wss://<endpoint-id>.api.runpod.ai/ws/recitation
```

Direct iOS-to-RunPod serverless testing is prototype-only because the app sends `Authorization: Bearer <RUNPOD_API_KEY>` on the WebSocket request. Enter that key in the local iOS `RunPod API key` field; do not commit it or put it in docs. The serverless worker keeps the same `/ws/recitation` contract and also exposes `/ping` for RunPod health checks. See `docs/runpod-serverless.md` for the Dockerfile, endpoint settings, key workflow, and replay checks.

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

Download on a GPU host (RunPod example):

```bash
source /workspace/tarteel-r2.env
uv run --with boto3 python scripts/r2_artifacts.py download data/tanzil/quran-simple-clean.txt
for sample in 004001 004002 004003 108001 108002 108003; do
  uv run --with boto3 python scripts/r2_artifacts.py download "fixtures/local_audio/${sample}.mp3"
  ffmpeg -y -i "fixtures/local_audio/${sample}.mp3" -ac 1 -ar 16000 -sample_fmt s16 "fixtures/local_audio/${sample}.wav"
done
```

For full host bootstrap steps, see `docs/runpod-r2.md`. The preferred bootstrap entrypoint is `scripts/gpu_bootstrap.sh` (with `scripts/runpod_bootstrap.sh` kept as a compatibility wrapper).

The current GitHub repo is public, so a fresh GPU host can clone it over HTTPS. If the repo becomes private again, configure a read-only deploy key or another GitHub auth method before running the bootstrap. Do not use `scp` for host setup; add R2 credentials manually to your host env file (for RunPod, `/workspace/tarteel-r2.env`) or through provider secrets.

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

Switch to `Custom` for a LAN, tunnel, or any remote real-ASR WebSocket URL. For a physical iPhone, run the backend with `--host 0.0.0.0` and enter your Mac LAN IP in the app. More details are in `ios/README.md`.

## Verify

```bash
uv run python -B -m unittest discover
uv run python -m compileall -q tarteel_realtime tests
```
