# Documentation map

Audience: contributors.

This tree holds one topic per file, mirroring the code structure. Documents are capped at 400 lines; a
document that outgrows the cap is split rather than extended.

    architecture/   how the system is put together
    decisions/      architecture decision records, one decision per file, immutable
    guides/         how to do a thing: harness, human sessions, asset pipeline, modding
    reference/      generated material; never hand-edited

## Current contents

- `HANDOFF.md` — where the project stands and where to pick up. Read first.
- `PLAN.md` — the approved plan, authoritative for scope; exempt from the cap as a record.
- `architecture/bridge.md` — how the solver is wrapped and driven.
- `decisions/0001`–`0005` — material classification, flexbody as skinning, two deformation
  paths, measured bone counts, Godot's winding.
- `guides/harness.md` — running and writing gates; `guides/human-sessions.md` — the window.
- `guides/hard-won-facts*.md` — what cost time to learn: light, materials, mods, terrain, the rest.
- `images/` — the README's screenshot.

## Rules

- Every document states its audience in the first line.
- Decisions live in `decisions/` as numbered ADRs, and are immutable. Superseding a decision means a new
  ADR that references the old one, never an edit: the reason a rejected option was rejected is the most
  valuable thing to still have in six months.
- Generated documents (`reference/config-keys.md`, `reference/gates.md`) are produced by tooling from the
  source of truth, and a gate fails if they are stale.
- Facts live in one place. Gate thresholds live in the gate files, configuration defaults in the config
  files; documents reference them and never restate them.
