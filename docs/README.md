# Documentation map

Audience: contributors.

This tree holds one topic per file, mirroring the code structure. Documents are capped at 400 lines; a
document that outgrows the cap is split rather than extended.

    architecture/   how the system is put together
    decisions/      architecture decision records, one decision per file, immutable
    guides/         how to do a thing: harness, human sessions, asset pipeline, modding
    reference/      generated material; never hand-edited

## Current contents

- `PLAN.md` (repository root of this tree) — the approved project plan, frozen as the record of what
  was agreed and why. It is exempt from the 400-line cap as a historical document, and it will be
  decomposed into `architecture/` documents and numbered ADRs under `decisions/` during M0. Once that
  decomposition exists, the architecture documents are authoritative and the plan is history.

## Rules

- Every document states its audience in the first line.
- Decisions live in `decisions/` as numbered ADRs, and are immutable. Superseding a decision means a new
  ADR that references the old one, never an edit: the reason a rejected option was rejected is the most
  valuable thing to still have in six months.
- Generated documents (`reference/config-keys.md`, `reference/gates.md`) are produced by tooling from the
  source of truth, and a gate fails if they are stale.
- Facts live in one place. Gate thresholds live in the gate files, configuration defaults in the config
  files; documents reference them and never restate them.
