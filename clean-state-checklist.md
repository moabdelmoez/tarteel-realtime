# Clean State Checklist

- [ ] The standard startup path still works: `uv run uvicorn tarteel_realtime.dev_app:app --reload`.
- [ ] The standard verification path still runs: `uv run python -B -m unittest discover`.
- [ ] ASR smoke wrapper tests still run when touched: `uv run python -B -m unittest tests.test_asr_smoke tests.test_whisper_adapter`.
- [ ] ASR backend/WebSocket client tests still run when touched: `uv run python -B -m unittest tests.test_asr_app tests.test_ws_client`.
- [ ] ASR buffering tests still run when touched: `uv run python -B -m unittest tests.test_buffered_recognition tests.test_session tests.test_asr_app`.
- [ ] Tanzil data workflow tests still run when touched: `uv run python -B -m unittest tests.test_evaluate_cli tests.test_quran_data_manifest`.
- [ ] iOS client core tests still run when touched: `cd ios/TarteelClientCore && env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test`.
- [ ] iOS app still builds when touched: `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build`.
- [ ] The compile check still runs: `uv run python -m compileall -q tarteel_realtime tests`.
- [ ] The sample evaluator still runs: `uv run python -m tarteel_realtime.evaluate fixtures/evaluation/juz-amma-smoke.jsonl --tanzil-path fixtures/quran/sample-tanzil.txt --minimum-lock-words 2 --mvp-scope`.
- [ ] The sample Tanzil manifest smoke still runs: `uv run python -m tarteel_realtime.quran_data --tanzil-path fixtures/quran/sample-tanzil.txt --source-name sample-fixture`.
- [ ] When `data/tanzil/quran-simple-clean.txt` exists, its manifest still validates: `uv run python -m tarteel_realtime.quran_data --check-manifest`.
- [ ] Current progress is recorded in `codex-progress.md`.
- [ ] Feature state in `feature_list.json` reflects what is actually passing versus unverified.
- [ ] Only one feature in `feature_list.json` has status `in_progress`.
- [ ] No half-finished step is left undocumented in `session-handoff.md`.
- [ ] All Python commands use `uv run`; dependencies are managed with `uv`, not direct `pip`.
- [ ] The next session can continue without manual repair.
