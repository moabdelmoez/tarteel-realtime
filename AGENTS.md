# AGENTS.md

Operational instructions for Codex and other AI agents working in this repository.

## Start Here

Read these files before changing code or docs:

1. `AGENTS.md`
2. `codex-progress.md`
3. `feature_list.json`
4. `session-handoff.md`
5. `clean-state-checklist.md`
6. The relevant `README.md`, `docs/`, source, and tests for the task

Use the current user request as the authority. If these docs conflict with an explicit user instruction, follow the user and record the reason in the handoff.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `moabdelmoez/tarteel-realtime`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use this repo's GitHub triage label mapping; `needs-info` maps to `question`, and `wontfix` maps to `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context repo: read root `CONTEXT.md` and `docs/adr/` when present. See `docs/agents/domain.md`.

## Project Rules

- Use `uv` for Python execution and dependency management. Do not use `pip` directly.
- Keep heavyweight ASR dependencies optional. Whisper, Torch, and GPU-only packages must not become default test dependencies without explicit approval.
- Do not commit secrets. `.env`, provider env files, deployment credentials, bearer tokens, and raw user audio must remain local or ignored.
- Do not mutate canonical Quran data in place. Treat `data/tanzil/quran-simple-clean.txt` as pinned local input.
- Preserve user changes. Do not run destructive git commands or revert unrelated edits.
- Prefer small verified slices. Update harness docs after meaningful changes.
- WebSocket `/ws/recitation` is the only backend transport. For Apple-to-GPU testing, expose the ASR backend over WSS and use the Apple app `Custom` preset. The experimental Apple `CoreML` preset is a local in-app route (`coreml://fastconformer-quran-streaming`), not a second backend transport.

## Repository Map

- `tarteel_realtime/`: Python backend, Quran parsing, locator, session engine, ASR adapters, and WebSocket transport.
- `tests/`: deterministic Python tests; must stay fast and avoid network/GPU requirements.
- `ios/TarteelClientCore/`: shared Swift package for endpoint presets, event decoding, state reduction, recording orchestration, local CoreML ASR routing, replay/capture helpers, and testable transport abstractions.
- `ios/TarteelPrototype/`: Xcode project containing the SwiftUI iPhone app (`TarteelPrototype`), native macOS app (`TarteelPrototypeMac`), shared app resources, CoreML/VAD assets, and local artifact copy scripts.
- `fixtures/`: small committed fixtures only.
- `data/tanzil/`: ignored full Quran text plus checked-in metadata/docs.
- `scripts/`: local helper scripts.
- `plans/`, `docs/`, and root harness files: project memory and operating procedure.

## Verification Expectations

Choose the smallest check that proves the change, then run broader checks when touching shared contracts.

- Python core/backend changes:
  - `uv run python -B -m unittest discover -s tests -v`
  - `uv run python -m compileall -q tarteel_realtime tests`
- Harness or JSON changes:
  - `uv run python -B -m json.tool feature_list.json`
  - `uv run python -B -m unittest discover -s tests -v` when project state or commands changed
- ASR adapter/backend changes:
  - Focused ASR tests first, then the full Python suite.
  - GPU verification only when real model behavior is part of the claim.
- WebSocket transport changes:
  - `uv run python -B -m unittest tests.test_api tests.test_recitation_stream tests.test_ws_client`
  - Use the documented WebSocket client smoke before real ASR transport claims.
- Apple client changes:
  - From `ios/TarteelClientCore`: `env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test`
  - Source/project guardrails for Apple UI, resources, settings, and Xcode project wiring: `uv run python -B -m unittest tests.test_macos_app_project tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v`
  - iPhone app build when iOS UI, resources, CoreML routing, or the app target changes:
    `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeCoreMLReplay -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build`
  - macOS app build when macOS UI, resources, settings, Keychain token storage, or the app target changes:
    `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build`
  - Local CoreML ASR changes also need focused Swift `CoreMLFastConformerTests`, app resource/bundle guardrails, iPhone and macOS builds, and manual physical-device evidence before claiming iOS ASR quality. iOS Simulator nonfinite CoreML output is expected for the ANE-specialized model and is not successful ASR evidence.
- Docs-only changes:
  - Validate affected structured files.
  - Run the baseline Python suite if the docs change workflow, commands, or harness state.

## Harness Updates

After a slice, update:

- `codex-progress.md`: what changed, exact verification, evidence, risks, next step.
- `feature_list.json`: passing/in-progress status and evidence. Keep at most one `in_progress` feature.
- `session-handoff.md`: compact restart context, changed files, unresolved risk, next best step.
- `clean-state-checklist.md`: add or revise checks when workflow changes.
- `quality-document.md`: update when quality posture, risks, or verification standards change.

## Domain Boundaries

- This MVP detects recitation location and obvious text-level mistakes. It is not yet tajweed scoring, phoneme-level correction, or production-grade Quran memorization coaching.
- Canonical displayed ayah text should come from Quran data after location, not from noisy ASR transcript.
- When confidence is low after lock, prefer ordered progression guidance before broad full-Quran relocking.
