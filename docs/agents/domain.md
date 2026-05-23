# Domain Docs

This is a single-context repo.

## Before exploring, read these when present

- `CONTEXT.md` at the repo root for project vocabulary and domain concepts.
- `docs/adr/` for architectural decisions relevant to the area being changed.
- Existing harness docs such as `codex-progress.md`, `feature_list.json`, `session-handoff.md`, and `quality-document.md` when they are relevant to current state.

If `CONTEXT.md` or `docs/adr/` do not exist, proceed silently. The producer skill `/grill-with-docs` can create them later when domain terms or decisions need to be recorded.

## Vocabulary

When output names a domain concept, use the term as defined in `CONTEXT.md` if it exists. If the concept is missing, note the gap rather than inventing competing terminology.

## ADR conflicts

If a proposed change contradicts an existing ADR, surface the conflict explicitly.
