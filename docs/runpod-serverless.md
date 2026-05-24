# RunPod Serverless Prototype

This is the prototype-only path for running the real ASR WebSocket backend on
RunPod Serverless Load Balancing. It preserves the existing app contract:

```text
iOS -> wss://<endpoint-id>.api.runpod.ai/ws/recitation?scope=<surah>
```

Do not use this direct iOS-to-RunPod path for public users. It requires a
RunPod API key in the prototype app so the key can be copied out of the client.
Move to a small CPU gateway before public or shared-user testing.

## Endpoint Shape

Use a RunPod Serverless endpoint with:

```text
Endpoint type: Load Balancer
GPU: L4 / A5000 / 3090
Worker type: Flex
Active workers: 0
Max workers: 1 initially
GPUs per worker: 1
FlashBoot: enabled
Idle timeout: low/default
```

With Flex and `Active workers = 0`, GPU billing starts when a worker starts and
stops when the worker shuts down after the idle timeout. Avoid network volumes
unless there is a concrete cold-start reason; a volume can add cost even when no
recitation is running.

## Build Image

Before building, make sure the pinned Quran text exists locally:

```bash
test -f data/tanzil/quran-simple-clean.txt
```

If it is missing, hydrate it from R2 locally without printing credentials:

```bash
source /path/to/local-r2.env
uv run --with boto3 python scripts/r2_artifacts.py download data/tanzil/quran-simple-clean.txt
```

Build and push the worker image from the repository root:

```bash
docker build -f Dockerfile.runpod-serverless -t <registry>/tarteel-runpod-serverless:latest .
docker push <registry>/tarteel-runpod-serverless:latest
```

The Dockerfile keeps ASR dependencies outside the default project install. It
uses `uv sync` for the base app and warms `faster-whisper` in the image layer so
the worker does not download the ASR package on each cold start.

## Worker Runtime

The container command is:

```bash
bash scripts/runpod_serverless_start.sh
```

The script supplies serverless-oriented defaults:

```text
TARTEEL_TANZIL_PATH=/app/data/tanzil/quran-simple-clean.txt
TARTEEL_WHISPER_BACKEND=faster-whisper
TARTEEL_WHISPER_MODEL_ID=OdyAsh/faster-whisper-base-ar-quran
TARTEEL_WHISPER_DEVICE=cuda:0
TARTEEL_FASTER_WHISPER_COMPUTE_TYPE=float16
TARTEEL_HF_CACHE_ROOT=/runpod-volume/huggingface-cache/hub
TARTEEL_ASR_BUFFERING_PROFILE=low-latency
```

RunPod should route to:

```text
/ping
/ws/recitation
```

`/ping` and `/health` both return `{"status": "ok"}`. The WebSocket path keeps
the existing JSON audio contract and accepts the existing `scope` query
parameter.

When the endpoint `Model` field caches
`OdyAsh/faster-whisper-base-ar-quran`, the worker resolves that cached Hugging
Face snapshot under `TARTEEL_HF_CACHE_ROOT` and passes the local path to
faster-whisper. If the cache is not present, local development falls back to the
model ID.

## Direct iOS Prototype

In the iOS prototype:

1. Select `Custom`.
2. Enter the endpoint URL:
   ```text
   wss://<endpoint-id>.api.runpod.ai/ws/recitation
   ```
3. Paste the prototype RunPod API key into the app's `RunPod API key` field.
4. Select the recitation scope, for example Surah 108.
5. Tap the mic.

The app adds:

```http
Authorization: Bearer <RUNPOD_API_KEY>
```

Do not commit this key. Prefer a restricted key for the prototype and revoke it
after the test window.

## Generate A RunPod Key

1. Open the RunPod console.
2. Go to `Settings`.
3. Open `API Keys`.
4. Click `Create API Key`.
5. Choose restricted permissions when available.
6. After the endpoint exists, scope the prototype key to that endpoint when
   RunPod offers endpoint scoping.
7. Copy it into a password manager. Treat it as unrecoverable after creation.

Use one admin/deployment key locally and a separate prototype key for direct iOS
testing.

## Acceptance Checks

Run local contract checks before deploying:

```bash
uv run python -B -m unittest tests.test_runpod_serverless tests.test_asr_app tests.test_api tests.test_ios_websocket_client -v
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test
```

After deploy, replay the known audio fixtures against the serverless endpoint:

```bash
uv run --with websockets python -m tarteel_realtime.ws_client \
  --url 'wss://<endpoint-id>.api.runpod.ai/ws/recitation?scope=108' \
  --audio-path fixtures/local_audio/108001.wav \
  --chunk-ms 1000 \
  --disable-ping

uv run --with websockets python -m tarteel_realtime.ws_client \
  --url 'wss://<endpoint-id>.api.runpod.ai/ws/recitation?scope=4:1-3' \
  --audio-path fixtures/local_audio/004001.wav \
  --chunk-ms 1000 \
  --disable-ping
```

Record cold-start time, first non-wait event latency, lock/progress behavior,
worker runtime seconds, and whether the endpoint returns to zero workers after
the idle timeout.
