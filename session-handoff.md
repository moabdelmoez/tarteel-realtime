# Session Handoff

## Verified Now

- Active slice: Point 1 of the ASR latency plan, isolated in `.worktrees/asr-point-1-faster-whisper-gpu` on branch `codex/asr-point-1-faster-whisper-gpu`.
- Latest pushed implementation commit before evidence-doc updates: `dbc100b` (`Prepare faster-whisper GPU replay fixtures`).
- WebSocket `/ws/recitation` remains the only transport.
- Heavy ASR dependencies remain optional; default tests do not require Whisper, Torch, faster-whisper, GPU, R2, or network access.
- `scripts/gpu_bootstrap.sh` now supports `TARTEEL_GIT_REF` for branch/commit testing and `TARTEEL_LOCAL_AUDIO_SAMPLES` for selecting local audio artifacts.
- The default GPU bootstrap audio sample set is `004001 004002 004003 108001 108002 108003`; bootstrap downloads MP3s from R2 and converts them to mono 16 kHz WAV.
- `scripts/runpod_bootstrap.sh` remains a compatibility wrapper over `scripts/gpu_bootstrap.sh`.
- `tarteel_realtime.ws_client` supports `--disable-ping`, implemented through a small `websocket_connect_kwargs(...)` interface so long ASR inference windows do not trip Python WebSocket keepalive during real-model tests.
- RunPod pod behind SSH user `ku0qwcps749c48-64410f3e` is running the faster-whisper ASR backend from commit `dbc100b` on `0.0.0.0:8000`.
- Public manual-test URL for the iOS Custom preset: `wss://ku0qwcps749c48-8000.proxy.runpod.net/ws/recitation`.
- Public health check `https://ku0qwcps749c48-8000.proxy.runpod.net/health` returned HTTP 200 with `{"status":"ok"}`.
- RunPod backend model settings: `TARTEEL_WHISPER_BACKEND=faster-whisper`, `TARTEEL_WHISPER_MODEL_ID=OdyAsh/faster-whisper-base-ar-quran`, `TARTEEL_WHISPER_DEVICE=cuda:0`, `TARTEEL_FASTER_WHISPER_COMPUTE_TYPE=float16`.
- Pod GPU proof: NVIDIA L4, driver `570.195.03`, 23034 MiB VRAM.
- R2 hydration proof included full Tanzil checksum `054b3d9f79c0c2e44df7f9ddf42561797b3b5cb4fbdafbf2e99c805ccf1a6b49` and all six new MP3 fixtures.

## Verification

- Red TDD run before implementation failed for the missing bootstrap fixture loop, missing `TARTEEL_GIT_REF` checkout, and missing WebSocket ping-disable helper.
- Local focused tests: `uv run python -B -m unittest tests.test_runpod_bootstrap tests.test_ws_client tests.test_asr_smoke tests.test_asr_runtime tests.test_asr_app -v` passed with 29 tests.
- Script syntax: `bash -n scripts/gpu_bootstrap.sh` and `bash -n scripts/runpod_bootstrap.sh` passed.
- Full local Python suite: `uv run python -B -m unittest discover -s tests -v` passed with 166 tests.
- Compile check: `uv run python -m compileall -q tarteel_realtime tests scripts` passed.
- JSON validation: `uv run python -B -m json.tool feature_list.json` passed.
- Whitespace check: `git diff --check` passed.
- RunPod focused tests: `uv run python -B -m unittest tests.test_runpod_bootstrap tests.test_ws_client -v` passed with 14 tests.
- RunPod health: pod-local `/health` and public `/health` returned `{"status":"ok"}`.
- RunPod public WSS smoke: `uv run python -m tarteel_realtime.ws_client --url wss://ku0qwcps749c48-8000.proxy.runpod.net/ws/recitation --chunks 1 --disable-ping` returned one `locating` event with `reason=waiting_for_audio_buffer`.
- RunPod `108001.wav` replay with 1s chunks returned 9 events: 8 `locating`, 1 `lock_candidate`; first non-wait event was sequence 4 at 5.776s wall time with 5388.1ms roundtrip.
- RunPod `004001.wav` replay with 1s chunks returned 67 events: 8 `locating`, 1 `lock_candidate`, 1 `locked`, 6 `progress`, 47 `uncertain`, and 4 `wrong`; first non-wait event was sequence 4 at 0.390s with 355.0ms roundtrip, and the replay locked `4:1` at sequence 9.

## Current Risks

- Point 1 proves the faster-whisper GPU backend path and repeatable fixture replay; it does not yet solve the user wait between ayahs because the ASR buffer is still the stable `4200/4200/0` profile.
- `108001.wav` still reached only `lock_candidate`, so isolated short ayah recognition needs the next latency/segmentation points before it is user-smooth.
- `004001.wav` locked and progressed quickly after warm-up, but false `wrong` events remain from noisy ASR windows.
- The first replay includes cold model load, so judge steady-state behavior from warmed replays and manual app use.
- The RunPod backend was intentionally left running for manual testing; stop it from the pod with `pkill -f 'uvicorn tarteel_realtime.asr_app:create_app_from_env'` when done.

## Next Best Step

Manual gate before Point 2: in the iOS app, select `Custom`, use `wss://ku0qwcps749c48-8000.proxy.runpod.net/ws/recitation`, recite continuous short Surah 108 and the long Surah 4 beginning, and compare the visible app cadence against backend `recitation_chunk` logs. If accepted, create a separate worktree for the next optimization point.
