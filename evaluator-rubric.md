# Evaluator Rubric

Use this rubric to score a completed agent session or implementation slice. Record the score in the session notes when the result will guide future work.

## Session Metadata

- Date:
- Evaluator:
- Agent/model:
- Branch/commit:
- Task or slice:
- Files changed:
- Commands verified:
- External systems used: local only / RunPod / R2 / LiveKit / iOS Simulator / physical iPhone

## Score Summary

| Dimension | Weight | Score | Evidence |
| --- | ---: | ---: | --- |
| Scope control | 10 |  |  |
| Harness and context use | 10 |  |  |
| Architecture fit | 15 |  |  |
| Correctness | 20 |  |  |
| Verification quality | 20 |  |  |
| Safety and secrets | 10 |  |  |
| Communication and handoff | 10 |  |  |
| Quran-recitation product fit | 5 |  |  |
| **Total** | **100** |  |  |

Score each dimension from 0 to its weight. Award full credit only when the claim is backed by fresh evidence.

## Dimension Guidance

### Scope Control - 10

- Stays inside the requested slice.
- Avoids unrelated refactors and churn.
- Leaves unrequested product decisions documented rather than silently expanding scope.

### Harness and Context Use - 10

- Reads the root harness files before work.
- Preserves `uv` usage and the optional-heavy-dependency boundary.
- Updates `codex-progress.md`, `feature_list.json`, `session-handoff.md`, and related docs when state changes.

### Architecture Fit - 15

- Uses existing modules and contracts before adding new abstractions.
- Keeps deterministic tests independent of network, GPU, and large model downloads.
- Preserves the fake backend and WebSocket fallback while evolving LiveKit/real-ASR paths.

### Correctness - 20

- Implements the requested behavior with clear edge-case handling.
- Does not degrade current MVP flows: fake backend, real ASR WebSocket, LiveKit worker, iOS state reducer, and canonical ayah text display.
- Quran references, ayah text, and ordered progression behavior remain coherent.

### Verification Quality - 20

- Runs focused checks that prove the change.
- Runs broader checks when touching shared behavior.
- Includes exact commands and results.
- For RunPod/GPU/LiveKit claims, includes endpoint, logs, model ID, and replay evidence rather than "it worked."

### Safety and Secrets - 10

- Does not commit credentials, raw user audio, or ignored artifact payloads.
- Keeps R2 and LiveKit keys in local env files only.
- Does not mutate canonical Tanzil input.
- Does not run destructive git commands without explicit approval.

### Communication and Handoff - 10

- Explains what changed in plain language.
- Records remaining risks honestly.
- Leaves the next session able to continue without reconstructing context.

### Quran-Recitation Product Fit - 5

- Keeps the user flow centered on recitation, location, canonical ayah display, and ordered correction.
- Avoids treating noisy ASR transcript as user-facing truth when canonical Quran text is available.
- Respects that this is an MVP, not full tajweed or teacher-level assessment.

## Outcome

- **Pass**: 85-100, no blocking defects, verification evidence is fresh.
- **Pass with follow-up**: 70-84, useful slice with documented risks or missing non-critical verification.
- **Needs repair**: 50-69, behavior or verification is incomplete enough that another slice is required before relying on it.
- **Reject or revert**: below 50, unsafe, unverified, or breaks core MVP assumptions.

## Notes

- Final score:
- Outcome:
- Required follow-up:
- Evidence gaps:
- Reviewer notes:
