# Modal Serverless Provider Comparison

This is the Modal comparison path for the real ASR WebSocket backend. It keeps
the same app contract as RunPod:

```text
wss://<modal-app>.modal.run/ws/recitation?scope=<surah>
```

V1 is evidence-only. Use it to compare Modal against RunPod for cold start,
first non-wait event latency, scoped lock/progress behavior, idle shutdown, and
cost. Do not treat Modal as a RunPod replacement until those numbers are
recorded.

## Shape

The Modal adapter lives in `deploy/modal_asr_app.py` and returns the existing
FastAPI app from `tarteel_realtime.asr_app:create_app_from_env`.

The image installs the backend runtime dependencies explicitly with
`modal.Image.uv_pip_install(...)` instead of `uv_sync()`. Keep it that way:
the project deliberately does not list `modal` or `faster-whisper` in the
default `pyproject.toml` dependency set.

The image is based on `nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04` with
Python added by Modal. This is required for the faster-whisper/CTranslate2 GPU
backend, which needs CUDA user-space libraries such as `libcublas.so.12`.
Modal provides the GPU driver on GPU workers, but not the full CUDA toolkit or
runtime libraries in `debian_slim`.

Modal defaults:

```text
Base image: nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04
GPU: L4
min_containers: 0
max_containers: 1
scaledown_window: 60
TARTEEL_WHISPER_BACKEND=faster-whisper
TARTEEL_WHISPER_MODEL_ID=OdyAsh/faster-whisper-base-ar-quran
TARTEEL_WHISPER_DEVICE=cuda:0
TARTEEL_FASTER_WHISPER_COMPUTE_TYPE=float16
TARTEEL_HF_CACHE_ROOT=/models/huggingface-cache/hub
TARTEEL_ASR_BUFFERING_PROFILE=low-latency
```

Model weights are stored in a Modal Volume named
`tarteel-asr-model-cache`. The worker image still includes the local Quran
data under `/root/data/tanzil/quran-simple-clean.txt`, so hydrate the pinned
Tanzil file locally before deployment.

## Secret

Create a Modal Secret named `tarteel-modal-asr-secrets` with:

```text
TARTEEL_WS_BEARER_TOKEN=<random prototype token>
```

`/health` and `/ping` remain public. `WS /ws/recitation` requires:

```http
Authorization: Bearer <random prototype token>
```

Do not store this token in docs or git.

## Prewarm Model Volume

From the repository root, after Modal is configured locally:

```bash
modal run deploy/modal_asr_app.py::prewarm
```

This downloads `OdyAsh/faster-whisper-base-ar-quran` into the Modal Volume.
Prewarm before timing cold starts so the measurement is not dominated by a
first-time Hugging Face download.

## Deploy

```bash
modal deploy deploy/modal_asr_app.py
```

After deploy, copy the generated Web Function URL and convert it to WebSocket
form if needed:

```text
https://<modal-app>.modal.run  ->  wss://<modal-app>.modal.run/ws/recitation
```

The Apple prototypes can use this through Settings -> Custom -> Provider:
Modal. The token field is memory-only.

## Replay Proof

Use the provider-neutral replay probe for both Modal and RunPod endpoints:

```bash
uv run --with websockets python -m tarteel_realtime.replay_probe \
  --url 'wss://<modal-app>.modal.run/ws/recitation' \
  --scope 108 \
  --audio-path fixtures/local_audio/108001.wav \
  --chunk-ms 1000 \
  --bearer-token '<token>' \
  --disable-ping \
  --include-events

uv run --with websockets python -m tarteel_realtime.replay_probe \
  --url 'wss://<modal-app>.modal.run/ws/recitation' \
  --scope '4:1-3' \
  --audio-path fixtures/local_audio/004001.wav \
  --chunk-ms 1000 \
  --bearer-token '<token>' \
  --disable-ping \
  --include-events
```

The replay probe accepts PCM16 WAV fixtures and downmixes multi-channel WAVs to
mono before sending chunks. The stricter `asr_smoke` CLI still requires mono
PCM16 input.

Record:

- Modal URL shape used, without token.
- GPU type.
- `connect_ms`, `first_non_wait_event_ms`, and `total_ms`.
- First lock/progress refs.
- Whether the app returns to zero warm containers after idle.
- Approximate cost for the test window.

Compare those values to the same replay probe against RunPod.

## Troubleshooting

If `modal run deploy/modal_asr_app.py::prewarm` fails with:

```text
Image builder version <= 2024.10 requires modal to be specified in your pyproject.toml file
```

make sure `deploy/modal_asr_app.py` is using
`.uv_pip_install(*PROJECT_RUNTIME_DEPENDENCIES, *MODAL_ASR_DEPENDENCIES)` and
not `.uv_sync()`. The old `uv_sync()` version asks Modal's legacy builder to
sync this local project, which then expects `modal` to be present in
`pyproject.toml`.

If live recitation logs repeatedly show:

```text
RuntimeError: Library libcublas.so.12 is not found or cannot be loaded
```

redeploy the version that uses the NVIDIA CUDA/cuDNN base image above. The old
`debian_slim` image can start the WebSocket app, but the GPU ASR call fails
when CTranslate2 tries to load CUDA runtime libraries.
