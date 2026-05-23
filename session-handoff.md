# Session Handoff

## Verified Now

- Active slice: Point 4 lock stability, isolated in `.worktrees/asr-point-4-lock-stability` on branch `codex/asr-point-4-lock-stability`.
- Latest pushed implementation commit: `a188fd4` (`Keep unscoped tolerant spans as candidates`).
- WebSocket `/ws/recitation` remains the only transport.
- Heavy ASR dependencies remain optional; default tests do not require Whisper, Torch, faster-whisper, GPU, R2, or network access.
- The default ASR buffering profile remains `stable`; Point 4 was verified with opt-in `TARTEEL_ASR_BUFFERING_PROFILE=low-latency`.
- Point 4 behavior:
  - Exact unique initial locks still lock immediately.
  - Initial `tolerant_match` locks require prior candidate support from earlier `lock_candidate` events.
  - Contextual tolerant locks are accepted only when the candidate was previously surfaced, not merely from re-locating merged noisy text.
  - Unscoped global `tolerant_span_match` stays a `lock_candidate/needs_confirmation` instead of becoming an initial global lock.
  - At ayah boundaries after first lock, short snippets accumulate only through ordered progression scope.
- RunPod backend is running from `/workspace/tarteel-realtime` at commit `a188fd4` with faster-whisper on CUDA and low-latency buffering.
- Public manual-test URL for the iOS Custom preset: `wss://ku0qwcps749c48-8000.proxy.runpod.net/ws/recitation`.

## Verification

- Focused local checks passed after final code change: `uv run python -B -m unittest tests.test_session_transitions tests.test_session tests.test_api -v` with 37 tests.
- Full local deterministic suite passed after final docs sanity: `uv run python -B -m unittest discover -s tests -v` with 180 tests.
- Public health check returned HTTP 200 with `{"status":"ok"}` after the corrected faster-whisper launch.
- Final RunPod replay from `a188fd4` with 1s chunks:
  - `108001`: first lock `108:1` at sequence 5.
  - `108002`: no lock; first candidate remained unrelated/multiple.
  - `108003`: first lock `108:3` at sequence 3.
  - `004001`: first lock `4:1` at sequence 19; previous false `39:6` lock is blocked.
  - `004002`: first lock `4:2` at sequence 11.
  - `004003`: first lock `4:3` at sequence 8.

## Current Risks

- Point 4 is a meaningful safety improvement, but it is not enough to make low-latency the default.
- `108002` still needs a product/model fix; the current ASR transcript is too distorted for clean matching.
- Long Surah 4 still has mid-ayah locks and noisy wrong/progress events after lock.
- Explicit selected-recitation scope should be the next slice; it is the cleanest way to avoid full-Quran ambiguity when the app already knows the user selected Surah 108 or Surah 4:1-3.

## Next Best Step

Manual-test the iOS Custom preset against `wss://ku0qwcps749c48-8000.proxy.runpod.net/ws/recitation`. If accepted, keep Point 4 as the lock-stability slice and start the next worktree for selected recitation scope.
