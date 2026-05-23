# Session Handoff

## Verified Now

- Active slice: Point 5 selected-recitation scope, isolated in `.worktrees/asr-point-5-selected-recitation-scope` on branch `codex/asr-point-5-selected-recitation-scope`.
- Base: Point 4 branch commit `9c774f2` (`Record Point 4 replay evidence`).
- WebSocket `/ws/recitation` remains the only transport.
- Heavy ASR dependencies remain optional; default tests do not require Whisper, Torch, faster-whisper, GPU, R2, or network access.
- Selected scope is optional and supplied on the WebSocket URL, not inside the audio payload:
  - Whole surah: `/ws/recitation?scope=108`
  - Single ayah: `/ws/recitation?scope=108:2`
  - Inclusive range: `/ws/recitation?scope=4:1-3`
- When scope is present, initial location searches only the selected ayahs.
- Ordered progression after first lock is also filtered to the selected ayahs, so the session does not continue into the next corpus ayah after the selected range ends.
- Without `scope`, the backend keeps the previous global conservative behavior from Point 4.

## Verification

- Baseline before implementation passed: `uv run python -B -m unittest discover -s tests -v` with 180 tests.
- Red TDD run failed first for missing `recitation_scope`, missing session scope wiring, and ignored WebSocket query scope.
- Focused selected-scope run passed: `uv run python -B -m unittest tests.test_recitation_scope tests.test_session_transitions tests.test_session tests.test_api -v` with 44 tests.
- Full local deterministic suite passed: `uv run python -B -m unittest discover -s tests -v` with 187 tests.
- Compile check passed: `uv run python -m compileall -q tarteel_realtime tests`.
- JSON validation passed: `uv run python -B -m json.tool feature_list.json`.
- Whitespace check passed: `git diff --check`.

## Current Risks

- RunPod faster-whisper replay has not been run for Point 5 yet.
- `108002` may still no-lock if faster-whisper output remains too distorted, but scoped search should prevent unrelated full-Quran candidates from competing.
- The iOS app can manually test scope through the Custom URL query, but it does not yet have a first-class selected-recitation UI that appends scope automatically.
- Low-latency remains opt-in. The user accepted merging selected-recitation scope to `main` as an opt-in backend capability without scoped GPU replay.

## Next Best Step

After merge, push `main`. Later, when real-ASR proof is needed, update RunPod from `main` and replay all six local audio fixtures with scoped URLs: `?scope=108` for `108001`/`108002`/`108003` and `?scope=4:1-3` for `004001`/`004002`/`004003`.
