# Session Handoff

## Verified Now

- Latest slice: macOS native UI polish, completed locally on 2026-06-03.
- The macOS prototype now uses a unified compact toolbar for recording, Surah search, and Settings, with source/build-verified native shell behavior.
- Keyboard commands are wired for `Space`/`Command-R` recording and `Command-F` Surah search focus.
- The macOS recitation surface now includes macOS 14-compatible Surah filtering/selection, first-run onboarding, event history, empty states, URL/text drop-in for backend setup with visible feedback, diagnostic drag-out text, adaptive system colors/materials, and Settings validation feedback.
- Shared `RecitationViewModel` presentation state now exposes recent event history, backend URL validation, recording action metadata, shareable diagnostic summary text, and dropped backend feedback.
- Previous slice: Modal CUDA image fix, deployed on 2026-05-29.
- Modal logs for deployed app `ap-y0XxuwnT0t7dEPT8FaWe2W` / `tarteel-realtime-asr` showed repeated recitation failures:
  - `RuntimeError: Library libcublas.so.12 is not found or cannot be loaded`
  - The traceback originates in faster-whisper/CTranslate2 during `self.model.encode(...)`.
- `deploy/modal_asr_app.py` now uses `nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04` through `modal.Image.from_registry(..., add_python="3.13")`.
  - This replaces the old `debian_slim` base image, which did not include CUDA user-space libraries.
  - The app was redeployed and Modal reported URL `https://moabdelmoez--tarteel-realtime-asr-fastapi-app.modal.run`.
- Previous slice: Modal replay fixture fix, completed locally on 2026-05-29.
- `tarteel_realtime.replay_probe` now loads PCM16 WAV evidence fixtures through `load_replay_audio_file`.
  - Multi-channel PCM16 WAV files are downmixed to mono for WebSocket replay.
  - `asr_smoke` remains strict and still rejects stereo WAV input.
  - This fixes the documented `fixtures/local_audio/108001.wav` replay command, because that fixture is stereo 44.1 kHz PCM16.
- Previous slice: Modal prewarm failure fix, completed locally on 2026-05-29.
- `deploy/modal_asr_app.py` no longer uses `.uv_sync()`.
  - The image installs backend runtime dependencies explicitly through `.uv_pip_install(*PROJECT_RUNTIME_DEPENDENCIES, *MODAL_ASR_DEPENDENCIES)`.
  - This avoids Modal legacy image builder failures that require `modal` in `pyproject.toml`.
  - `modal` and `faster-whisper` remain out of default project dependencies.
- Previous slice: Modal GPU serverless provider comparison, completed locally on 2026-05-28.
- WebSocket `/ws/recitation` remains the only recitation transport.
- `deploy/modal_asr_app.py` is the Modal deployment adapter:
  - returns the existing `tarteel_realtime.asr_app:create_app_from_env` FastAPI app
  - uses `gpu="L4"`, `min_containers=0`, `max_containers=1`, `scaledown_window=60`
  - uses Modal Volume `tarteel-asr-model-cache` at `/models/huggingface-cache/hub`
  - exposes local entrypoint `prewarm` for model cache hydration
- `TARTEEL_WS_BEARER_TOKEN` enables provider-neutral WebSocket bearer auth.
  - `/health` and `/ping` remain public.
  - `WS /ws/recitation` rejects missing or wrong bearer tokens when configured.
- `tarteel_realtime.replay_probe` is the provider-neutral RunPod/Modal evidence tool.
  - It supports `--scope`, `--bearer-token`, `--disable-ping`, and `--include-events`.
  - It reports connect time, total time, first non-wait event timing, event counts, and first lock/progress refs.
- Apple settings now keep `Simulator` and `Custom`.
  - Under `Custom`, provider picker options are `Generic`, `RunPod`, and `Modal`.
  - RunPod normalizes bare `.proxy.runpod.net` and `.api.runpod.ai` hosts.
  - Modal normalizes bare `.modal.run` hosts.
  - Bearer token remains memory-only.

## Verification

- macOS native UI polish checks passed:
  - `cd ios/TarteelClientCore && env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test`
  - Result: 44 checks.
  - `uv run python -B -m unittest tests.test_macos_app_project tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v`
  - Result: 20 tests.
  - `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build`
  - `uv run python -B -m unittest discover -s tests -v`
  - Result: 223 tests.
  - `uv run python -m compileall -q tarteel_realtime tests`
- Focused Modal CUDA-image checks passed:
  - `uv run python -B -m unittest tests.test_modal_serverless -v`
  - Result: 5 tests.
  - `uv run python -m compileall -q deploy tests/test_modal_serverless.py`
  - `git diff --check`
- Post-deploy remote checks passed:
  - `curl -sS https://moabdelmoez--tarteel-realtime-asr-fastapi-app.modal.run/ping` returned `{"status":"ok"}`.
  - Modal logs since `2026-05-29T16:00:38` show `GET /ping -> 200 OK`.
  - Searching post-deploy logs for `libcublas` returned no results.
- Focused replay fixture checks passed:
  - `uv run python -B -m unittest tests.test_replay_probe tests.test_ws_client tests.test_asr_smoke -v`
  - Result: 22 tests.
- Local fixture load proof passed:
  - `load_replay_audio_file(Path("fixtures/local_audio/108001.wav"), raw_sample_rate_hz=16000)` returned 44.1 kHz mono PCM, 787,968 bytes, about 8.934 seconds.
- Original command shape now passes audio loading:
  - A dummy `ws://127.0.0.1:9/ws/recitation` URL reaches connection setup and fails with connection refused instead of `AudioInputError`.
- Focused Modal prewarm-fix checks passed:
  - `uv run python -B -m unittest tests.test_modal_serverless -v`
  - Result: 5 tests.
- Syntax and whitespace checks passed:
  - `uv run python -m compileall -q deploy tests/test_modal_serverless.py`
  - `git diff --check`
- Focused Modal/replay/backend/Apple source checks passed:
  - `uv run python -B -m unittest tests.test_modal_serverless tests.test_replay_probe tests.test_ws_client tests.test_api tests.test_asr_runtime tests.test_asr_app tests.test_ios_websocket_client tests.test_ios_recitation_scope_ui tests.test_ios_status_panel tests.test_macos_app_project -v`
  - Result: 64 tests.
- Compile check passed:
  - `uv run python -m compileall -q deploy tarteel_realtime tests`
- Swift client core passed:
  - `env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test`
  - Result: 39 tests total.
- iPhone target build passed:
  - `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build`
- macOS target build passed after escalated rerun because sandboxed Xcode/SwiftPM cache access was blocked:
  - `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build`
- Full deterministic Python suite passed:
  - `uv run python -B -m unittest discover -s tests -v`
  - Result: 218 tests.
- JSON/active-feature/whitespace checks passed:
  - `uv run python -B -m json.tool feature_list.json` after escalated rerun for uv cache access
  - `uv run python -B -c "import json; data=json.load(open('feature_list.json', encoding='utf-8')); active=[f['id'] for f in data['features'] if f['status']=='in_progress']; print(active); assert len(active) <= 1"` returned `[]`
  - `git diff --check`

## Current Risks

- The macOS UI polish is source/build verified, but manual visual QA and interaction testing are still outstanding for light/dark mode, drag/drop, diagnostic drag-out, keyboard focus, Settings validation layout, microphone permission, and live backend recording.
- Modal is deployed, but no fresh post-deploy ASR replay/recitation proof has been captured after the CUDA image fix.
- Modal still needs scoped replay proof, idle shutdown evidence, and cost evidence.
- `prewarm` may need rerun after the CUDA image deployment if the model cache Volume is not already hydrated.
- RunPod Serverless remains locally packaged but not live endpoint verified.
- The Apple provider picker was source/build verified, not manually exercised on iPhone or macOS.
- Real ASR quality remains model/audio dependent; this slice only adds provider comparison infrastructure.

## Next Best Step

For the current UI branch, manually launch the macOS app and exercise light/dark mode, `Space`/`Command-R`, `Command-F`, Surah filtering, URL/text drop-in, diagnostic drag-out, Settings validation feedback, microphone permission, and a local `/ws/recitation` recording.

Run a fresh post-deploy Modal replay or recitation, then check logs after the
test window. Replay command:

```bash
uv run --with websockets python -m tarteel_realtime.replay_probe \
  --url 'wss://moabdelmoez--tarteel-realtime-asr-fastapi-app.modal.run/ws/recitation' \
  --scope 108 \
  --audio-path fixtures/local_audio/108001.wav \
  --chunk-ms 1000 \
  --bearer-token '<token>' \
  --disable-ping \
  --include-events

uv run --with websockets python -m tarteel_realtime.replay_probe \
  --url 'wss://moabdelmoez--tarteel-realtime-asr-fastapi-app.modal.run/ws/recitation' \
  --scope '4:1-3' \
  --audio-path fixtures/local_audio/004001.wav \
  --chunk-ms 1000 \
  --bearer-token '<token>' \
  --disable-ping \
  --include-events
```

If the first post-deploy request has to hydrate model cache again, rerun:

```bash
uvx modal run deploy/modal_asr_app.py::prewarm
```

Repeat the same replay probe against RunPod once Modal is clean so the provider
comparison uses the same evidence shape.
