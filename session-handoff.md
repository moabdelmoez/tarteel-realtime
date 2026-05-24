# Session Handoff

## Verified Now

- Active slice: RunPod Serverless prototype path, isolated in `.worktrees/runpod-serverless-prototype` on branch `codex/runpod-serverless-prototype`.
- Base: `main` commit `5d0edd9` (`Add iOS selected-recitation UI`).
- WebSocket `/ws/recitation` remains the only recitation transport.
- Backend now exposes both `/health` and `/ping`; `/ping` is for RunPod Load Balancer health checks.
- Serverless packaging files:
  - `Dockerfile.runpod-serverless`
  - `.dockerignore`
  - `scripts/runpod_serverless_start.sh`
  - `docs/runpod-serverless.md`
- The serverless start script defaults to:
  - `TARTEEL_WHISPER_BACKEND=faster-whisper`
  - `TARTEEL_WHISPER_MODEL_ID=OdyAsh/faster-whisper-base-ar-quran`
  - `TARTEEL_WHISPER_DEVICE=cuda:0`
  - `TARTEEL_FASTER_WHISPER_COMPUTE_TYPE=float16`
  - `TARTEEL_HF_CACHE_ROOT=/runpod-volume/huggingface-cache/hub`
  - `TARTEEL_ASR_BUFFERING_PROFILE=low-latency`
- `settings_from_env(...)` resolves cached RunPod Hugging Face snapshots under `TARTEEL_HF_CACHE_ROOT` when present, and falls back to the model ID locally.
- iOS Custom endpoint handling now accepts bare serverless hosts like `<endpoint-id>.api.runpod.ai`, normalizes them to `wss://.../ws/recitation`, and keeps selected-recitation `scope` query behavior.
- iOS direct RunPod access is prototype-only: a local `RunPod API key` field sends `Authorization: Bearer <token>` on Custom WebSocket connections. Do not commit or document real keys.

## Verification

- Red tests failed first for missing `/ping`, missing serverless Docker/start files, missing `.api.runpod.ai` normalization, missing iOS bearer-token support, and missing cached Hugging Face snapshot resolution.
- Focused serverless/backend/iOS checks passed:
  - `uv run python -B -m unittest tests.test_runpod_serverless tests.test_asr_app tests.test_api tests.test_ios_websocket_client -v` with 28 tests.
  - `uv run python -B -m unittest tests.test_asr_runtime tests.test_asr_app -v` with 14 tests.
  - `bash -n scripts/runpod_serverless_start.sh`.
  - `uv run python -m compileall -q tarteel_realtime tests`.
  - Swift client core: `env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test` from `ios/TarteelClientCore` with 24 tests.
- Full deterministic Python suite passed after final harness updates with 197 tests.
- `uv run python -B -m json.tool feature_list.json` passed.
- `git diff --check` passed.
- iOS app build:
  - First attempt using `/private/tmp/tarteel-xcode-derived` failed due stale `FluidAudio` package checkout/CoreSimulator access.
  - Rerun with escalated permissions and fresh derived data `/private/tmp/tarteel-xcode-derived-serverless` succeeded.

## Current Risks

- No RunPod Serverless endpoint has been deployed yet.
- Docker image build/push has not been run.
- No real endpoint cold-start, worker runtime, scale-to-zero, billing, or scoped fixture replay evidence exists yet.
- Direct iOS-to-RunPod is not production-safe because the RunPod API key lives in the client during prototype testing.
- The Docker build expects `data/tanzil/quran-simple-clean.txt` to be hydrated locally before build. Keep R2 keys local and out of iOS/runtime docs.

## Next Best Step

Build and push the serverless image, create a RunPod Load Balancer endpoint with `Active workers = 0`, `Max workers = 1`, GPU `L4/A5000/3090`, and cached model `OdyAsh/faster-whisper-base-ar-quran`, then replay:

- `108001`, `108002`, `108003` with `?scope=108`
- `004001`, `004002`, `004003` with `?scope=4:1-3`
