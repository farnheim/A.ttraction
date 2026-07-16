# A.ttraction / UNGRUND

A system for absolute electronic music after Asmus Tietchens, implemented as a
live modular SuperCollider instrument. Sound is treated as substrate, not
vehicle: all material is synthesized from first principles (no samples),
composition is built from blocks rather than arcs, and the structure is
exposed to the ear as a measurement, not an expression.

Eight sound classes named `alpha`…`theta`, a seven-module JITLib app around
them (mixer, LFO, sequencer, MIDI, effects, viz), and a 94 Hz 3-limit pitch
lattice underneath everything.

## Quick start

1. Open `App/1_app.scd` in the SuperCollider IDE.
2. Select all (Cmd-A) and execute (Shift-Return) — the server boots, layers
   load with their `default` presets, and the mixer window opens.
3. Stop with **Cmd-.**; full reset: run the `// CLEANUP` paragraph or
   `~appCleanup.value(true)`.

Iterate any module by re-executing its file while the app runs — layers
crossfade in via JITLib.

## Documentation

- [`docs/architecture/app/`](docs/architecture/app/) — App architecture ([`README.md`](docs/architecture/app/README.md)) and the canonical [layer contract](docs/architecture/app/layer-contract.md)
- [`docs/architecture/system/`](docs/architecture/system/) — the UNGRUND system canon ([`README.md`](docs/architecture/system/README.md)) and [composition/harmony theory](docs/architecture/system/composition.md)
- [`docs/architecture/structure-grid/`](docs/architecture/structure-grid/) — macroform notation: canon, symbol alphabet, constructions
- [`docs/features/`](docs/features/) — per-layer references and shipped DSP specs (`zeta/`, `delta/`)
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
- `.claude/Tools/` — `parse_check.scd`, `render_layer.scd`, `render_measure.sh` (parse / headless render / measure)

## Hard rules

- `Tests/test_monade.scd` is **LOCKED** — the finalized alpha physical model.
- Exactly one top-level `( )` block per module file.
- Pitch lives on the 94 Hz lattice (octaves + fifths only; no thirds).
