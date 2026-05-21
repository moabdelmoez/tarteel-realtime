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

## Project Rules

- Use `uv` for Python execution and dependency management. Do not use `pip` directly.
- Keep heavyweight ASR dependencies optional. Whisper, Torch, LiveKit worker extras, and GPU-only packages must not become default test dependencies without explicit approval.
- Do not commit secrets. `.env`, RunPod env files, Cloudflare R2 credentials, LiveKit credentials, and raw user audio must remain local or ignored.
- Do not mutate canonical Quran data in place. Treat `data/tanzil/quran-simple-clean.txt` as pinned local input.
- Preserve user changes. Do not run destructive git commands or revert unrelated edits.
- Prefer small verified slices. Update harness docs after meaningful changes.
- WebSocket `/ws/recitation` remains the fallback transport. LiveKit is the preferred MVP mobile-to-RunPod path when Cloud credentials are configured.

## Repository Map

- `tarteel_realtime/`: Python backend, Quran parsing, locator, session engine, ASR adapters, LiveKit worker.
- `tests/`: deterministic Python tests; must stay fast and avoid network/GPU requirements.
- `ios/TarteelClientCore/`: Swift package for event decoding, state reduction, and transport abstractions.
- `ios/TarteelPrototype/`: SwiftUI iPhone prototype.
- `fixtures/`: small committed fixtures only.
- `data/tanzil/`: ignored full Quran text plus checked-in metadata/docs.
- `scripts/`: R2 and RunPod helper scripts.
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
  - RunPod/GPU verification only when real model behavior is part of the claim.
- LiveKit changes:
  - `uv run python -B -m unittest tests.test_livekit_tokens tests.test_livekit_worker tests.test_api`
  - Use the documented fake-transcript worker smoke before real ASR worker claims.
- iOS client changes:
  - From `ios/TarteelClientCore`: `env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test`
  - iOS app build when UI or app target changes:
    `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build`
- Docs-only changes:
  - Validate affected structured files.
  - Run the baseline Python suite if the docs change workflow, commands, or harness state.

## RunPod and R2 Rules

- Ask the user before starting or relying on a GPU pod.
- On RunPod, prefer public GitHub clone plus R2 artifact hydration over `scp`.
- The user provides `/workspace/tarteel-r2.env` manually when needed. Do not print or store credentials.
- Bind HTTP/WebSocket servers to `0.0.0.0` on exposed RunPod ports.
- Evidence for RunPod success needs command output, endpoint/log proof, and the model/backend version used.

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

## Special Local Skill

- `/graphify` triggers the graphify skill for knowledge graph generation.
