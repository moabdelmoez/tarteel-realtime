# Modal Serverless Provider Comparison

This is the Modal comparison path for the real ASR WebSocket backend. It keeps
the same app contract as RunPod:

```text
wss://<modal-app>.modal.run/ws/recitation?scope=<surah>&asr_model=<slug>
```

The app and replay tooling keep one Modal WSS endpoint. The selected model is
sent per WebSocket recording session as `asr_model`. Missing `asr_model`
defaults to `nemo-fastconformer-quran-ar`; unknown values are rejected with
WebSocket close code `1008`.

V1 is evidence-only. Use it to compare Modal against RunPod for cold start,
first non-wait event latency, scoped lock/progress behavior, idle shutdown, and
cost. Do not treat Modal as a RunPod replacement until those numbers are
recorded.

## Shape

The Modal adapter lives in `deploy/modal_asr_app.py` and returns the existing
FastAPI WebSocket app from `tarteel_realtime.asr_app:create_model_selecting_asr_app`.

The image installs the backend runtime dependencies explicitly with
`modal.Image.uv_pip_install(...)` instead of `uv_sync()`. Keep it that way:
the project deliberately does not list `modal`, `faster-whisper`, or
`nemo_toolkit` in the default `pyproject.toml` dependency set.

The image is based on `nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04` with
Python added by Modal. This keeps CUDA user-space libraries available for GPU
ASR runtimes. Modal provides the GPU driver on GPU workers, but not the full
CUDA toolkit or runtime libraries in `debian_slim`.

Modal service defaults:

```text
Base image: nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04
GPU: L4
min_containers: 0
max_containers: 1
scaledown_window: 60
TARTEEL_HF_CACHE_ROOT=/models/huggingface-cache/hub
TARTEEL_ASR_BUFFERING_PROFILE=low-latency
TARTEEL_ASR_MIN_AUDIO_MS=3000
TARTEEL_ASR_FLUSH_MS=3000
TARTEEL_ASR_TAIL_MS=2500
TARTEEL_ASR_SPEECH_END_MIN_AUDIO_MS=1500
TARTEEL_ASR_FLUSH_ON_SPEECH_END=1
```

Approved Modal ASR profiles:

```text
asr_model=nemo-fastconformer-quran-ar
  backend: nemo
  model: mohammed/fastconformer-quran-ar
  checkpoint: phase3_full/phase3_full_wer0.0014.nemo

asr_model=faster-whisper-base-ar-quran
  backend: faster-whisper
  model: OdyAsh/faster-whisper-base-ar-quran
  compute_type: float16
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

This downloads both approved Hugging Face snapshots and verifies the nested
NeMo `phase3_full/phase3_full_wer0.0014.nemo` checkpoint exists in the Modal
Volume. Prewarm before timing cold starts so the measurement is not dominated
by first-time Hugging Face downloads.

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
Modal. The Modal-only `ASR model` picker sends the selected slug on the next
recording URL and is disabled while recording. The iPhone prototype keeps
bearer tokens memory-only. The macOS prototype uses Modal as the first-launch
Custom default and stores selected Custom provider bearer tokens in macOS
Keychain after the user enters them once.

## Replay Proof

Use the provider-neutral replay probe for both Modal and RunPod endpoints.
Export `MODAL_TOKEN` locally first so the token does not appear in the command
line.

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

uv run --with websockets python -m tarteel_realtime.replay_probe \
  --url 'wss://<modal-app>.modal.run/ws/recitation' \
  --scope '4:1-3' \
  --asr-model faster-whisper-base-ar-quran \
  --audio-path fixtures/local_audio/004001.wav \
  --chunk-ms 160 \
  --bearer-token-env MODAL_TOKEN \
  --disable-ping \
  --send-speech-end \
  --include-events
```

`--chunk-ms 160` approximates the app's live PCM cadence. `--send-speech-end`
sends one final empty VAD marker so the backend can flush the last ready buffer
after a short fixture or replay stops. The replay probe accepts PCM16 WAV
fixtures and downmixes multi-channel WAVs to mono before sending chunks. The
stricter `asr_smoke` CLI still requires mono PCM16 input.
Repeat each scoped replay for both `--asr-model` values before comparing model
quality; the Faster Whisper proof only needs to show that the selected Modal
profile runs and returns ASR-backed events.

Record:

- Modal URL shape used, without token.
- `asr_model` slug.
- GPU type.
- `connect_ms`, `first_non_wait_event_ms`, and `total_ms`.
- First lock/progress refs.
- Whether the app returns to zero warm containers after idle.
- Approximate cost for the test window.

Compare those values to the same replay probe against RunPod.

## Current Modal Evidence

2026-06-13 NeMo FastConformer checkpoint:

```text
Modal HTTPS: https://moabdelmoez--tarteel-realtime-asr-fastapi-app.modal.run
Modal WSS: wss://moabdelmoez--tarteel-realtime-asr-fastapi-app.modal.run/ws/recitation
GPU: L4
Model: mohammed/fastconformer-quran-ar
Checkpoint: phase3_full/phase3_full_wer0.0014.nemo
```

Modal `/ping` returned `{"status":"ok"}` after deploy, and worker logs showed
`EncDecHybridRNNTCTCBPEModel` restored from the nested checkpoint above.

Scoped Surah 108 app-cadence replay with `--chunk-ms 160 --send-speech-end`
returned:

| Fixture | Result |
| --- | --- |
| `108001.wav` | `locked` `108:1`, final transcript `إِنَّهَا أعطَيْنَاكَ الْكَوْثَرَ`, 57 events, 54 locating, 2 lock candidates, 1 lock, total about 45.9s including cold/warm worker delay |
| `108002.wav` | `locked` `108:2`, 38 events, 36 locating, 1 lock candidate, 1 lock, total about 9.3s |
| `108003.wav` | `locked` `108:3`, 50 events, 48 locating, 1 lock candidate, 1 lock, total about 11.7s |

Manual macOS app replay through the same Modal WSS URL succeeded with
`108001.wav`: Modal logs showed a final empty `speech_end` chunk flushed the
buffer and emitted `event_type=locked reason=unique_match ayah_ref=108:1`.

iOS Simulator build succeeded for `TarteelPrototypeCoreMLReplay`, but manual
Simulator install/launch control hung locally and the captured Simulator screen
was blank. Treat that as an unresolved local Simulator-control issue, not a
successful iOS manual ASR result.

## Manual Apple App Check

Use the deployed Modal WSS URL through the existing Custom backend path:

1. Open the macOS app or iOS Simulator app.
2. Open Settings, set backend to `Custom`, and set provider to `Modal`.
3. Pick the ASR model: `FastConformer Quran AR (NeMo)` or
   `Faster Whisper Base AR Quran`.
4. Paste `wss://<modal-app>.modal.run/ws/recitation`.
5. Enter the Modal bearer token locally.
6. Select Surah 108, start recording, and recite or replay `108001.wav`.
7. Record the visible first lock/progress refs and compare them with the
   `replay_probe` event stream.

Do not print, commit, or paste the bearer token into docs.

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
