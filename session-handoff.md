# Session Handoff

## Verified Now

- Active slice: Point 3 of the ASR latency plan, isolated in `.worktrees/asr-point-3-short-ayah-stability` on branch `codex/asr-point-3-short-ayah-stability`.
- Latest pushed implementation commit: `9ef577e` (`Track alternative pre-lock ASR contexts`).
- WebSocket `/ws/recitation` remains the only transport.
- Heavy ASR dependencies remain optional; default tests do not require Whisper, Torch, faster-whisper, GPU, R2, or network access.
- The default ASR buffering profile remains `stable`; Point 3 was verified with opt-in `TARTEEL_ASR_BUFFERING_PROFILE=low-latency`.
- Point 3 adds pre-lock ASR transcript context in `tarteel_realtime/session_transitions.py`: short ambiguous snippets are accumulated as a small set of alternatives, overlap is deduped, clean current unique locks win, and contextual locks must be supported by the current snippet candidate set.
- RunPod pod behind SSH user `ku0qwcps749c48-64410f3e` is running the faster-whisper ASR backend from commit `9ef577e` on `0.0.0.0:8000`.
- Public manual-test URL for the iOS Custom preset: `wss://ku0qwcps749c48-8000.proxy.runpod.net/ws/recitation`.
- Public health check `https://ku0qwcps749c48-8000.proxy.runpod.net/health` returned `{"status":"ok"}`.
- RunPod backend model settings: `TARTEEL_WHISPER_BACKEND=faster-whisper`, `TARTEEL_WHISPER_MODEL_ID=OdyAsh/faster-whisper-base-ar-quran`, `TARTEEL_WHISPER_DEVICE=cuda:0`, `TARTEEL_FASTER_WHISPER_COMPUTE_TYPE=float16`, `TARTEEL_ASR_BUFFERING_PROFILE=low-latency`.
- RunPod fixture set present as WAV/MP3: `004001`, `004002`, `004003`, `108001`, `108002`, and `108003`.

## Verification

- Red TDD checks failed first for missing pre-lock accumulation, stale-context poisoning, overlap duplication, incompatible context replacement, and missing multiple-context alternatives.
- Focused local checks passed: `uv run python -B -m unittest tests.test_session_transitions tests.test_session tests.test_locator tests.test_api tests.test_recitation_stream -v` with 55 tests.
- Full local Python suite passed: `uv run python -B -m unittest discover -s tests -v` with 178 tests.
- Compile check passed: `uv run python -m compileall -q tarteel_realtime tests scripts`.
- Whitespace check passed: `git diff --check`.
- RunPod short Surah 108 replay with 1s chunks: `108001` locked `108:1` at sequence 5 with `reason=tolerant_match`; `108003` locked `108:3` at sequence 5 with `reason=tolerant_match`; `108002` still produced `locating:no_match` and no lock.
- RunPod long Surah 4 replay under low-latency remains mixed: `004001` first locked `39:6` at sequence 13, `004002` first locked `4:2` at sequence 9, and `004003` first locked `36:8` at sequence 8.

## Current Risks

- Point 3 improves short-ayah startup for two Surah 108 fixtures, but it is not a complete recognition-quality fix.
- `108002` still has no clean match from faster-whisper output.
- Long Surah 4 false-lock risk remains under low-latency replay; do not push this branch to `main` as a default/product quality improvement without user acceptance or another slice to address false locks.
- The new context accumulation is pre-lock only. If the app still waits between ayahs after an initial lock, the next slice should target post-lock/ayah-boundary buffering context.
- The RunPod backend was intentionally left running for manual testing; stop it from the pod with `pkill -f 'uvicorn tarteel_realtime.asr_app:create_app_from_env'` when done.

## Next Best Step

Manual-test the iOS Custom preset with `wss://ku0qwcps749c48-8000.proxy.runpod.net/ws/recitation`, focusing first on continuous short Surah 108. Decide whether to accept Point 3 as a short-ayah improvement branch, continue into a false-lock mitigation slice, or merge only after additional manual evidence.
