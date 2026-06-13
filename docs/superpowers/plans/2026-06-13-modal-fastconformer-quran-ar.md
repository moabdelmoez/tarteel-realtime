# Modal FastConformer Quran AR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Test `mohammed/fastconformer-quran-ar` through the existing `/ws/recitation` contract on Modal, then manually verify the macOS app and iOS Simulator can stream to that endpoint.

**Architecture:** Keep WebSocket transport and `RecitationStream` unchanged. Add a NeMo recognizer behind the existing ASR runtime seam, then configure the Modal adapter to choose that optional backend and model without adding heavy dependencies to the default project.

**Tech Stack:** Python 3.13 project tests, optional NeMo/PyTorch runtime inside Modal, FastAPI WebSocket ASR app, Modal L4 GPU worker, Swift macOS/iOS Custom backend clients.

**Status 2026-06-13:** Implemented and verified for scoped Surah 108 Modal replay plus macOS app replay. iOS Simulator app build passed, but manual Simulator install/launch control hung locally and only produced a blank screenshot, so iOS manual ASR proof remains open.

---

## File Structure

- Create `tarteel_realtime/nemo_adapter.py`: optional NeMo recognizer implementation with a small backend protocol for deterministic tests.
- Modify `tarteel_realtime/asr_runtime.py`: generalize ASR backend setting from Whisper-only to recognizer backend while preserving old `TARTEEL_WHISPER_*` env compatibility.
- Modify `tarteel_realtime/asr_app.py`: import the renamed factory while keeping compatibility exports.
- Modify `deploy/modal_asr_app.py`: configure Modal for NeMo model dependencies and `mohammed/fastconformer-quran-ar`.
- Modify `tests/test_nemo_adapter.py`: unit tests for PCM conversion, transcribe payload parsing, dependency error, and model construction.
- Modify `tests/test_asr_app.py`: runtime env/factory tests for NeMo backend selection and compatibility defaults.
- Modify `tests/test_modal_serverless.py`: Modal source guardrails for NeMo dependencies, model id, cache volume, and default-project dependency isolation.
- Modify `README.md`, `docs/modal-serverless.md`, `ios/README.md`: document the NeMo Modal comparison path and manual app verification commands.
- Modify harness docs after verification: `codex-progress.md`, `feature_list.json`, `session-handoff.md`, `clean-state-checklist.md`, and `quality-document.md` if quality posture changes.

## Task 1: Add NeMo Recognizer Adapter

**Files:**
- Create: `tarteel_realtime/nemo_adapter.py`
- Create/modify: `tests/test_nemo_adapter.py`

- [x] **Step 1: Write failing adapter tests**

Add tests that instantiate `NemoRecognizer` with an injected backend and verify:

```python
result = recognizer.recognize(AudioChunk(7, b"\x00\x40\x00\xc0", 16_000))
self.assertEqual(result.transcript, "إنا أعطيناك الكوثر")
self.assertEqual(result.chunk_sequence, 7)
self.assertTrue(result.is_final)
```

Also test `from_pretrained` dependency errors and that `model_id`, `device`, and `batch_size` are forwarded.

- [x] **Step 2: Run red test**

Run: `uv run python -B -m unittest tests.test_nemo_adapter -v`

Expected: fails because `tarteel_realtime.nemo_adapter` does not exist.

- [x] **Step 3: Implement minimal adapter**

Create `NemoConfig`, `NemoBackendMissing`, `NemoRecognizer`, and `NemoTranscribeBackend`. `NemoRecognizer.recognize(...)` decodes PCM16 to float samples, calls backend `transcribe(samples=..., sample_rate_hz=...)`, records diagnostic ASR timing when present, and returns `RecognitionResult`.

- [x] **Step 4: Run green adapter tests**

Run: `uv run python -B -m unittest tests.test_nemo_adapter -v`

Expected: all new adapter tests pass.

## Task 2: Wire Runtime Backend Selection

**Files:**
- Modify: `tarteel_realtime/asr_runtime.py`
- Modify: `tarteel_realtime/asr_app.py`
- Modify: `tests/test_asr_app.py`

- [x] **Step 1: Write failing runtime tests**

Add tests proving:

```python
settings = settings_from_env({
    "TARTEEL_ASR_BACKEND": "nemo",
    "TARTEEL_ASR_MODEL_ID": "mohammed/fastconformer-quran-ar",
    "TARTEEL_ASR_DEVICE": "cuda:0",
})
self.assertEqual(settings.asr_backend, "nemo")
self.assertEqual(settings.model_id, "mohammed/fastconformer-quran-ar")
self.assertEqual(settings.device, "cuda:0")
```

Also prove legacy `TARTEEL_WHISPER_BACKEND` still selects faster-whisper and that `create_buffered_asr_recognizer_factory(..., nemo_recognizer_builder=...)` builds one shared lazy NeMo recognizer behind per-session buffers.

- [x] **Step 2: Run red runtime tests**

Run: `uv run python -B -m unittest tests.test_asr_app -v`

Expected: fails because `asr_backend` and NeMo factory selection are missing.

- [x] **Step 3: Implement runtime selection**

Add `asr_backend` to `AsrRuntimeSettings`, parse `TARTEEL_ASR_BACKEND` with fallback to `TARTEEL_WHISPER_BACKEND`, parse `TARTEEL_ASR_MODEL_ID`/`TARTEEL_ASR_DEVICE` with legacy fallbacks, and add `create_lazy_asr_recognizer_factory` plus `create_buffered_asr_recognizer_factory`. Keep old `create_lazy_whisper_recognizer_factory` and `create_buffered_whisper_recognizer_factory` as compatibility wrappers.

- [x] **Step 4: Run green runtime tests**

Run: `uv run python -B -m unittest tests.test_asr_app tests.test_whisper_adapter tests.test_nemo_adapter -v`

Expected: all focused runtime and adapter tests pass.

## Task 3: Update Modal Adapter For NeMo

**Files:**
- Modify: `deploy/modal_asr_app.py`
- Modify: `tests/test_modal_serverless.py`

- [x] **Step 1: Write failing Modal guardrail tests**

Update guardrails to expect:

```python
self.assertIn('DEFAULT_MODEL_ID = "mohammed/fastconformer-quran-ar"', source)
self.assertIn('"nemo_toolkit[asr]"', source)
self.assertIn('"TARTEEL_ASR_BACKEND": "nemo"', source)
self.assertIn('"TARTEEL_ASR_MODEL_ID": DEFAULT_MODEL_ID', source)
self.assertNotIn("nemo_toolkit", pyproject)
```

- [x] **Step 2: Run red Modal tests**

Run: `uv run python -B -m unittest tests.test_modal_serverless -v`

Expected: fails because Modal still defaults to faster-whisper.

- [x] **Step 3: Implement Modal source changes**

Set `DEFAULT_MODEL_ID` to `mohammed/fastconformer-quran-ar`, install NeMo ASR dependencies only in `MODAL_ASR_DEPENDENCIES`, set `TARTEEL_ASR_BACKEND=nemo`, `TARTEEL_ASR_MODEL_ID`, `TARTEEL_ASR_DEVICE=cuda:0`, and keep model cache volume/prewarm with Hugging Face `snapshot_download`.

- [x] **Step 4: Run green Modal tests**

Run: `uv run python -B -m unittest tests.test_modal_serverless tests.test_asr_app tests.test_nemo_adapter -v`

Expected: Modal and focused ASR tests pass.

## Task 4: Document Modal And App Manual Test Flow

**Files:**
- Modify: `README.md`
- Modify: `docs/modal-serverless.md`
- Modify: `ios/README.md`

- [x] **Step 1: Update docs**

Document that the Modal branch uses NeMo FastConformer, requires optional Modal GPU dependencies, keeps `/ws/recitation`, and should be verified with:

```bash
modal run deploy/modal_asr_app.py::prewarm
modal deploy deploy/modal_asr_app.py
uv run --with websockets python -m tarteel_realtime.replay_probe \
  --url 'wss://<modal-app>.modal.run/ws/recitation' \
  --scope 108 \
  --audio-path fixtures/local_audio/108001.wav \
  --chunk-ms 1600 \
  --bearer-token '<token>' \
  --disable-ping \
  --include-events
```

Also document macOS/iOS Simulator manual steps: Custom provider `Modal`, paste WSS URL, provide bearer token, select Surah 108, record/replay, and inspect first lock/progress refs.

- [x] **Step 2: Validate docs/source checks**

Run: `uv run python -B -m unittest tests.test_modal_serverless tests.test_ios_websocket_client tests.test_macos_app_project -v`

Expected: source guardrails pass.

## Task 5: Verify Locally And Prepare Modal/App Run

**Files:**
- No production source edits unless verification exposes an issue.
- Modify harness docs with final evidence after local checks and any Modal/app run.

- [x] **Step 1: Run focused Python tests**

Run: `uv run python -B -m unittest tests.test_nemo_adapter tests.test_asr_app tests.test_modal_serverless tests.test_replay_probe tests.test_ws_client tests.test_api -v`

Expected: all focused backend/WebSocket tests pass.

- [x] **Step 2: Run compile check**

Run: `uv run python -m compileall -q deploy tarteel_realtime tests`

Expected: exit 0.

- [x] **Step 3: Build Apple apps**

Run macOS build:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos-modal-nemo CODE_SIGNING_ALLOWED=NO build
```

Run iOS Simulator build:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeCoreMLReplay -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived-ios-modal-nemo CODE_SIGNING_ALLOWED=NO build
```

Expected: both builds succeed because Custom WebSocket app behavior is unchanged.

- [x] **Step 4: Hydrate local ignored artifacts in worktree if needed**

Ensure `data/tanzil/quran-simple-clean.txt` and `fixtures/local_audio/*.wav` are present in the worktree before Modal deploy/replay evidence, using symlinks or local copies that remain ignored.

- [x] **Step 5: Modal prewarm/deploy and replay proof**

With user-approved GPU spend and a Modal secret configured:

```bash
modal run deploy/modal_asr_app.py::prewarm
modal deploy deploy/modal_asr_app.py
MODAL_TOKEN='<token>' uv run --with websockets python -m tarteel_realtime.replay_probe \
  --url 'wss://<modal-app>.modal.run/ws/recitation' \
  --scope 108 \
  --audio-path fixtures/local_audio/108001.wav \
  --chunk-ms 1600 \
  --bearer-token "$MODAL_TOKEN" \
  --disable-ping \
  --include-events
```

Expected: report `connect_ms`, `first_non_wait_event_ms`, first lock/progress refs, and raw events without printing the token.

- [x] **Step 6: Manual macOS and iOS Simulator app checks**

Open macOS app, set Custom provider Modal with the deployed WSS URL and bearer token, select Surah 108, record a short recitation, and record visible state plus logs. Run iOS Simulator app with the same Custom settings and confirm it connects to Modal, streams mic/replay audio if available, and displays backend events.
