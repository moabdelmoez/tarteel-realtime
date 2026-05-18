# Session Handoff

## Verified Now

- What is currently working:
  - Quran text parsing, normalization, refs, word mapping, file loading, and MVP corpus scope.
  - Locator and aligner over fake transcripts.
  - Offline evaluator and CLI over JSONL fixtures.
  - Fake recognizer, streaming session state machine, FastAPI WebSocket API, dev app, and manual WebSocket client.
  - Optional Whisper adapter boundary and PCM16 decoder.
  - Tested ASR smoke CLI wrapper for one local raw PCM16LE or mono PCM16 WAV transcription path.
  - Optional Quran locator scoring in ASR smoke JSON when `--tanzil-path` is provided.
  - Real Quran Whisper smoke on RunPod L4 for local Surah 114 samples.
  - Opt-in real ASR WebSocket backend factory with env-driven settings, lazy Whisper construction, and injected-recognizer tests.
  - WebSocket client can send a mono PCM16 WAV or raw PCM16LE file through `WS /ws/recitation`.
  - Opt-in real ASR WebSocket backend has been verified on RunPod L4 with real Surah 114 WAVs returning `locked` events.
  - Local rolling ASR buffering exists for live mic chunks: minimum audio, flush cadence, and in-memory tail overlap.
  - Rolling ASR buffering has been verified on RunPod L40S with `114002.wav` sent as 1000ms WebSocket chunks and a final real `locked` event.
  - Full Tanzil local file validation and metadata/checksum workflow for `data/tanzil/quran-simple-clean.txt`.
  - Native iOS prototype builds, launches, and has been manually verified by the user in Simulator against the fake backend.
  - iOS app now has `Simulator` and `Custom` backend presets.
  - iOS state reducer now treats `waiting_for_audio_buffer` as normal real-ASR latency before and after lock.
  - Harness state files now exist in project root.
- What verification actually ran:
  - `env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test` from `ios/TarteelClientCore` with 4 tests passing.
  - `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build` succeeded.
  - App installed and launched in iPhone 17 simulator; screenshot captured at `/private/tmp/tarteel-prototype-launch.png`.
  - `uv run python -m tarteel_realtime.ws_client --chunks 2` returned a `locked` event followed by a `wrong` event from the fake backend.
  - `uv run python -B -m unittest tests.test_asr_app tests.test_ws_client` with 10 tests passing.
  - `uv run python -B -m unittest discover` with 74 tests passing.
  - `uv run python -m compileall -q tarteel_realtime tests`.
  - `uv run python -m tarteel_realtime.quran_data --tanzil-path data/tanzil/quran-simple-clean.txt --source-name Tanzil --source-url http://tanzil.net/updates/ --write-manifest`.
  - `uv run python -m tarteel_realtime.quran_data --check-manifest`.
  - `uv run python -m tarteel_realtime.evaluate fixtures/evaluation/juz-amma-smoke.jsonl --minimum-lock-words 2 --mvp-scope` returned `locator_accuracy: 1.000`, `alignment_accuracy: 1.000`, `wrong_detection_rate: 1.000`.
  - RunPod: same focused tests with 10 tests passing.
  - RunPod GPU check: `torch 2.7.1+cu126`, CUDA runtime `12.6`, CUDA available `True`, device count `1`, NVIDIA L4 driver `570.195.03`.
  - RunPod real model smoke for `114002.wav`: transcript `مَلِكِ النَّاسِ`, locator locked to `114:2`, runtime `0m7.712s`.
  - RunPod real model smoke for `114001.wav`: transcript `قُلْ أَعُوذُ بِرَبِّ النَّاسِ`, locator locked to `114:1`, runtime `0m7.592s`.
  - RunPod real ASR WebSocket server started with `uv run --python 3.13 --with transformers --with 'torch==2.7.1' --with 'torchvision==0.22.1' uvicorn tarteel_realtime.asr_app:create_app_from_env --factory --host 127.0.0.1 --port 8000`.
  - RunPod WebSocket verification for `114002.wav` returned `type: locked`, transcript `مَلِكِ النَّاسِ`, ayah_ref `114:2`, start_ref `114:2:1`.
  - RunPod WebSocket verification for `114001.wav` returned `type: locked`, transcript `قُلْ أَعُوذُ بِرَبِّ النَّاسِ`, ayah_ref `114:1`, start_ref `114:1:1`.
  - `uv run python -B -m unittest tests.test_buffered_recognition tests.test_session tests.test_asr_app` with 16 tests passing.
  - Latest full deterministic suite: `uv run python -B -m unittest discover` with 80 tests passing.
  - RunPod L40S GPU check: NVIDIA L40S, driver `580.126.09`, memory `46068 MiB`.
  - RunPod one-shot ASR smoke for `114002.wav` returned transcript `مَلِكِ النَّاسِ`, normalized `ملك الناس`, locator locked to `114:2`.
  - RunPod buffered WebSocket command with `TARTEEL_ASR_MIN_AUDIO_MS=4200`, `TARTEEL_ASR_FLUSH_MS=4200`, and `TARTEEL_ASR_TAIL_MS=0`.
  - RunPod chunked WebSocket client for `fixtures/local_audio/114002.wav --chunk-ms 1000` returned four `waiting_for_audio_buffer` locating events followed by `type: locked`, `ayah_ref: 114:2`, `start_ref: 114:2:1`.
  - Swift client core tests now pass with 8 tests, including backend presets and buffering state.
  - iOS simulator build succeeded after adding backend presets and buffering UI behavior.

## Changed This Session

- Code or behavior added:
  - Added `tarteel_realtime/buffered_recognition.py` with `BufferedRecognizer` and `BufferedRecognitionConfig`.
  - Updated `RecitationSession` to emit `waiting_for_audio_buffer` without advancing alignment when buffered ASR has no final transcript.
  - Added `TARTEEL_ASR_MIN_AUDIO_MS`, `TARTEEL_ASR_FLUSH_MS`, and `TARTEEL_ASR_TAIL_MS` settings to the opt-in ASR app.
  - Made the opt-in ASR app use buffered Whisper recognition by default.
  - Added deterministic tests for buffer cadence, tail retention, empty chunks, session waiting events, and ASR app buffered factory wiring.
  - Marked `backend-003` passing after RunPod chunked-WAV verification.
  - Added `mobile-002` as the next active slice.
  - Completed `mobile-002` phase 1 without GPU: backend presets, custom URL path, and buffer-event UX.
- Infrastructure or harness changes:
  - Updated `README.md`, `codex-progress.md`, `feature_list.json`, `clean-state-checklist.md`, and `session-handoff.md`.

## Broken Or Unverified

- Known defect:
  - None known in deterministic test path.
- Unverified path:
  - Real ASR model inference and real ASR WebSocket behavior are verified only for two short Surah 114 samples against `fixtures/quran/sample-tanzil.txt`.
  - Real Quran audio datasets and QUL Al-Husary playback are not integrated.
  - The phone has not yet been pointed at the real ASR backend; it has only been verified against the fake backend.
  - Real phone microphone audio has not yet been routed through the RunPod ASR backend.
  - Simulator/phone has not yet been manually verified against a `Custom` real-ASR URL.
- Risk for the next session:
  - Installing ASR/model dependencies may be heavy and should stay optional.
  - RunPod pods may restart with a fresh root filesystem; reinstall `uv` and keep caches on the pod root or an intentionally chosen cache path.
  - Do not weaken deterministic tests while experimenting with model inference.

## Next Best Step

- Highest-priority unfinished feature: `mobile-002` point iPhone prototype at real ASR backend.
- Why it is next: backend buffering works with chunked WAV input on GPU, and the app is ready for custom URLs; the remaining risk is the phone-to-real-backend bridge and manual mic verification.
- What counts as passing:
  - Fake backend remains the default path.
  - Heavy Whisper/Torch dependencies remain opt-in.
  - The backend URL/network bridge path for Simulator or physical iPhone is documented and reproducible.
  - Swift client core tests still pass after any event-state changes.
  - The app UI can show `waiting_for_audio_buffer` and then `locked` from the real ASR backend.
  - Manual simulator or physical iPhone verification confirms live mic chunks reach the real ASR backend.
- What must not change during that step:
  - Do not remove fake recognizer tests.
  - Do not make heavyweight ASR dependencies required for the default test suite unless explicitly approved.
  - Do not mutate canonical Tanzil text in place.
  - Do not store raw user audio.

## Commands

- Startup: `uv run uvicorn tarteel_realtime.dev_app:app --reload`
- Verification:
  - `uv run python -B -m unittest discover`
  - `uv run python -m compileall -q tarteel_realtime tests`
  - `uv run python -B -m json.tool feature_list.json`
  - `uv run python -B -c "import json; data=json.load(open('feature_list.json', encoding='utf-8')); active=[f['id'] for f in data['features'] if f['status']=='in_progress']; print(active); assert active == ['mobile-002']"`
- Focused debug command:
  - `cd ios/TarteelClientCore && env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test`
  - `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build`
  - `uv run uvicorn tarteel_realtime.dev_app:app --reload`
  - `uv run python -B -m unittest tests.test_evaluate_cli tests.test_quran_data_manifest`
  - `uv run python -m tarteel_realtime.quran_data --tanzil-path fixtures/quran/sample-tanzil.txt --source-name sample-fixture`
  - `uv run python -m tarteel_realtime.quran_data --tanzil-path data/tanzil/quran-simple-clean.txt --source-name Tanzil --source-url <source-url> --write-manifest`
  - `uv run python -m tarteel_realtime.quran_data --check-manifest`
  - `uv run python -B -m unittest tests.test_asr_smoke tests.test_whisper_adapter`
  - `uv run python -m tarteel_realtime.asr_smoke path/to/audio.wav --model-id basharalrfooh/whisper-small-quran --tanzil-path fixtures/quran/sample-tanzil.txt --minimum-lock-words 2`
  - `UV_NO_PROGRESS=1 uv run --no-project --with transformers --with 'torch==2.7.1' --with 'torchvision==0.22.1' python -m tarteel_realtime.asr_smoke path/to/mono-16k.wav --model-id basharalrfooh/whisper-small-quran --tanzil-path fixtures/quran/sample-tanzil.txt --minimum-lock-words 2 --device cuda:0`
  - `uv run python -m tarteel_realtime.asr_smoke path/to/audio.pcm16le --model-id basharalrfooh/whisper-small-quran --sample-rate 16000`
  - `uv run python -B -m unittest tests.test_audio tests.test_whisper_adapter`
  - `uv run python -m tarteel_realtime.evaluate fixtures/evaluation/juz-amma-smoke.jsonl --tanzil-path fixtures/quran/sample-tanzil.txt --minimum-lock-words 2 --mvp-scope`
  - `TARTEEL_TANZIL_PATH=data/tanzil/quran-simple-clean.txt TARTEEL_WHISPER_MODEL_ID=basharalrfooh/whisper-small-quran TARTEEL_WHISPER_DEVICE=cuda:0 UV_NO_PROGRESS=1 uv run --with transformers --with 'torch==2.7.1' --with 'torchvision==0.22.1' uvicorn tarteel_realtime.asr_app:create_app_from_env --factory --host 0.0.0.0 --port 8000`
  - `TARTEEL_TANZIL_PATH=fixtures/quran/sample-tanzil.txt TARTEEL_MINIMUM_LOCK_WORDS=2 TARTEEL_WHISPER_MODEL_ID=basharalrfooh/whisper-small-quran TARTEEL_WHISPER_DEVICE=cuda:0 TARTEEL_ASR_MIN_AUDIO_MS=4200 TARTEEL_ASR_FLUSH_MS=4200 TARTEEL_ASR_TAIL_MS=0 UV_NO_PROGRESS=1 uv run --python 3.13 --with transformers --with 'torch==2.7.1' uvicorn tarteel_realtime.asr_app:create_app_from_env --factory --host 127.0.0.1 --port 8000`
  - `uv run python -m tarteel_realtime.ws_client --url ws://127.0.0.1:8000/ws/recitation --audio-path path/to/mono-16k.wav`
  - `uv run python -m tarteel_realtime.ws_client --url ws://127.0.0.1:8000/ws/recitation --audio-path path/to/mono-16k.wav --chunk-ms 1000`
