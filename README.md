# A.ttraction / UNGRUND

A system for absolute electronic music after Asmus Tietchens, implemented as a
live modular SuperCollider instrument. Sound is treated as substrate, not
vehicle: all material is synthesized from first principles (no samples),
composition is built from blocks rather than arcs, and the structure is
exposed to the ear as a measurement, not an expression.

Five live sound classes — `alpha`, `delta`, `epsilon`, `zeta`, `theta` (§C.2
`beta`, §C.3 `gamma` and §C.7 `eta` struck 2026-07-17) — inside a JITLib app
around them: `App/app.scd` orchestrator + `lib` (the NET modulation field) +
`ui` + `presets` + `matrix` (Matrix/Machines windows) + `mixer` (Deck window)
+ `effects` (Space Echo ×2) + `tape` (master tape stage), and a 94 Hz 3-limit
pitch lattice underneath everything.

## Quick start

1. Open `App/app.scd` in the SuperCollider IDE.
2. Select all (Cmd-A) and execute (Shift-Return) — the server boots, layers
   load, the project preset `default.scd` auto-loads (layers + mixer + fx +
   tape + wander + cells), and the **Deck**, **Matrix** and **Machines**
   windows open.
3. Stop with **Cmd-.**; full reset: run the `// CLEANUP` paragraph or
   `~appCleanup.value(true)`.

Iterate any module by re-executing its file while the app runs — layers
crossfade in via JITLib. The UI needs the **IBM Plex Mono** font installed
system-wide (`App/ui.scd`); without it Qt silently substitutes a
proportional font.

## Documentation

- [`docs/architecture/app/`](docs/architecture/app/) — App architecture ([`README.md`](docs/architecture/app/README.md)) and the canonical [layer contract](docs/architecture/app/layer-contract.md)
- [`docs/architecture/system/`](docs/architecture/system/) — the UNGRUND system canon ([`README.md`](docs/architecture/system/README.md)) and [composition/harmony theory](docs/architecture/system/composition.md)
- [`docs/architecture/structure-grid/`](docs/architecture/structure-grid/) — macroform notation: canon, symbol alphabet, constructions
- [`docs/features/`](docs/features/) — per-layer references and shipped DSP specs (`delta/`, `epsilon/`, `theta/`, `zeta/`, plus `effects/` and `master/`; `gamma/`, `grid-modulation/` and `patchbay/` are historical records of removed modules)
- [`docs/dx/`](docs/dx/) — code style, naming, testing, git conventions
- [`plans/`](plans/) — implementation plans and DSP specs (active / backlog / completed); [`plans/backlog/2026-06-10-audit.md`](plans/backlog/2026-06-10-audit.md) tracks open audit items
- `archives/` — superseded docs, old etudes, reference recordings (untracked)

## Claude Code

Development is orchestrated through Claude Code with four domain agents
(music-historian, avant-composer, supercollider-analyst, supercollider-dev).

- [`.claude/CLAUDE.md`](.claude/CLAUDE.md) — project context loaded every session
- [`.claude/rules/workflow/orchestration.md`](.claude/rules/workflow/orchestration.md) — the three pipelines, commands, gates
- [`.claude/rules/system/`](.claude/rules/system/) — ground rules (no speculation, comment policy)
- [`.claude/rules/code-style/`](.claude/rules/code-style/) — path-glob rules loading `docs/dx/code-style/` on edit
- `.claude/Tools/` — headless build/render/measurement scripts; full table in [`.claude/CLAUDE.md`](.claude/CLAUDE.md) → Tools

## Hard rules

- `Tests/test_monade.scd` is **LOCKED** — the finalized alpha physical model.
- Exactly one top-level `( )` block per module file.
- Pitch lives on the 94 Hz lattice (octaves + fifths only; no thirds).
