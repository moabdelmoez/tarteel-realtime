# Session Handoff

## Verified Now

- Active slice: Point 2 of the ASR latency plan, isolated in `.worktrees/asr-point-2-low-latency-buffer` on branch `codex/asr-point-2-low-latency-buffer`.
- Latest pushed implementation commit before evidence-doc updates: `5ce2d36` (`Add low-latency ASR buffering profile`).
- WebSocket `/ws/recitation` remains the only transport.
- Heavy ASR dependencies remain optional; default tests do not require Whisper, Torch, faster-whisper, GPU, R2, or network access.
- `TARTEEL_ASR_BUFFERING_PROFILE=stable` remains the default `4200/4200/0` buffering behavior.
- `TARTEEL_ASR_BUFFERING_PROFILE=low-latency` is now available as an opt-in profile: `minimum_audio_ms=2000`, `flush_interval_ms=1000`, `tail_audio_ms=500`, `minimum_speech_rms=400`, and `minimum_frame_rms=150`.
- Explicit `TARTEEL_ASR_MIN_AUDIO_MS`, `TARTEEL_ASR_FLUSH_MS`, `TARTEEL_ASR_TAIL_MS`, `TARTEEL_ASR_MIN_SPEECH_RMS`, and `TARTEEL_ASR_MIN_FRAME_RMS` values override the selected profile.
- RunPod pod behind SSH user `ku0qwcps749c48-64410f3e` is running the faster-whisper ASR backend from commit `5ce2d36` on `0.0.0.0:8000`.
- Public manual-test URL for the iOS Custom preset: `wss://ku0qwcps749c48-8000.proxy.runpod.net/ws/recitation`.
- Public health check `https://ku0qwcps749c48-8000.proxy.runpod.net/health` returned `{"status":"ok"}`.
- RunPod backend model settings: `TARTEEL_WHISPER_BACKEND=faster-whisper`, `TARTEEL_WHISPER_MODEL_ID=OdyAsh/faster-whisper-base-ar-quran`, `TARTEEL_WHISPER_DEVICE=cuda:0`, `TARTEEL_FASTER_WHISPER_COMPUTE_TYPE=float16`, `TARTEEL_ASR_BUFFERING_PROFILE=low-latency`.
- RunPod fixture set present as WAV/MP3: `004001`, `004002`, `004003`, `108001`, `108002`, and `108003`.

## Verification

- Red TDD checks failed first for missing buffering profile support, then passed after implementation.
- Local focused ASR tests passed: `uv run python -B -m unittest tests.test_buffered_recognition tests.test_asr_runtime tests.test_asr_app -v` with 25 tests.
- Full local Python suite passed after evidence-doc updates: `uv run python -B -m unittest discover -s tests -v` with 172 tests.
- Compile check passed: `uv run python -m compileall -q tarteel_realtime tests scripts`.
- JSON validation passed: `uv run python -B -m json.tool feature_list.json`.
- Whitespace check passed: `git diff --check`.
- Public RunPod health passed through the proxy.
- RunPod low-latency replay with 1s chunks returned first non-wait ASR-backed events at sequence 1 for `108001`, `108002`, `108003`, `004001`, and `004002`; `004003` first returned at sequence 2.
- Backend flush logs confirmed first flushes at `buffered_ms=2000 unflushed_ms=2000 action=flush`, followed by tail-preserving flushes around `buffered_ms=2500 unflushed_ms=2000`.

## Current Risks

- Point 2 proves lower buffering latency, not end-to-end recognition quality.
- Short Surah 108 replays still failed to produce clean locks: `108001` and `108003` reached `lock_candidate`, while `108002` produced `no_match` events.
- Long Surah 4 replays produced early events but remained noisy. `004003` eventually locked once, then emitted wrong/uncertain events; this is not yet acceptable ayah-by-ayah coaching quality.
- Low-latency buffering is opt-in. Do not make it the default without a separate manual/product gate.
- The RunPod backend was intentionally left running for manual testing; stop it from the pod with `pkill -f 'uvicorn tarteel_realtime.asr_app:create_app_from_env'` when done.

## Next Best Step

Manual gate before Point 3: in the iOS app, select `Custom`, use `wss://ku0qwcps749c48-8000.proxy.runpod.net/ws/recitation`, recite continuous short Surah 108 and the long Surah 4 beginning, and compare visible cadence against backend logs. If accepted, create a separate worktree for the next optimization point.
