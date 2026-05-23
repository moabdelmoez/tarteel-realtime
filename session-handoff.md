# Session Handoff

## Verified Now

- Active slice: Point 4 of the ASR latency plan, isolated in `.worktrees/asr-point-4-lock-stability` on branch `codex/asr-point-4-lock-stability`.
- Base branch/commit: `origin/codex/asr-point-3-short-ayah-stability` at `b9d9a10`.
- WebSocket `/ws/recitation` remains the only transport.
- Heavy ASR dependencies remain optional; default tests do not require Whisper, Torch, faster-whisper, GPU, R2, or network access.
- The default ASR buffering profile remains `stable`; Point 4 is intended to be tested with opt-in `TARTEEL_ASR_BUFFERING_PROFILE=low-latency` on the faster-whisper GPU backend.
- Point 4 changes `tarteel_realtime/session_transitions.py` so low-evidence initial tolerant matches return `lock_candidate/needs_confirmation` instead of globally locking from two weak words.
- Exact unique initial locks still lock immediately, and stronger tolerant initial matches still lock immediately when they have at least three matched Quran words, or the configured `minimum_lock_words` if higher.
- After first lock, ayah-boundary snippets now accumulate only through the ordered progression scope so short next-ayah fragments can combine without global relock.
- The previous RunPod public manual-test URL may still be `wss://ku0qwcps749c48-8000.proxy.runpod.net/ws/recitation`, but it has not yet been updated to this Point 4 branch.

## Verification

- Red TDD checks failed first for missing initial tolerant confirmation and missing ordered ayah-boundary snippet accumulation.
- Focused local checks passed: `uv run python -B -m unittest tests.test_session_transitions tests.test_session tests.test_locator tests.test_api tests.test_recitation_stream -v` with 57 tests.
- Full local Python suite passed: `uv run python -B -m unittest discover -s tests -v` with 180 tests.
- Compile check passed: `uv run python -m compileall -q tarteel_realtime tests`.

## Current Risks

- RunPod faster-whisper replay has not yet been run for Point 4, so merge confidence is local only.
- The expected success criterion is preserving Point 3 Surah 108 gains while preventing the previous long Surah 4 false global locks from becoming `locked` events.
- `108002` was still unresolved in Point 3 and may remain unresolved unless the ASR transcript itself becomes matchable.
- Explicit selected-recitation scope is still not implemented. That should be the next slice after this lock-stability gate is accepted.

## Next Best Step

Ask for GPU approval, push/check out `codex/asr-point-4-lock-stability` on RunPod, restart the faster-whisper low-latency WebSocket backend, and replay all six local audio fixtures with disabled WebSocket pings. Do not recommend merging to `main` until that real-ASR replay is captured.
