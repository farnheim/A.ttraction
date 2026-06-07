# Pipelines

Two pipelines route work through the four agents in `.claude/agents/`. The full one is for material that needs theoretical grounding from scratch; the short one is for iteration on established ground.

The four roles:

- `music-historian` — researches, places phenomena in historical context
- `avant-composer` — designs compositional structures, processes, forms
- `supercollider-analyst` — DSP / SuperCollider expert; writes the implementation spec in the full pipeline, reviews code in both pipelines
- `supercollider-dev` — implements the `.scd` file

---

## Pipeline 1 — Full (research → implementation)

Use when:

- the technique, idiom, or scene is unfamiliar
- the piece needs research before any sound exists
- the project is at a new junction (new instrument family, new aesthetic, new question)

### Flow

```
[question]
    │
    ▼
music-historian ─────────────────▶ docs/research.md
    │
    ▼
avant-composer ──────────────────▶ docs/reference.md
    │
    ▼
supercollider-analyst (spec) ────▶ docs/task.md
    │
    ▼
supercollider-dev ───────────────▶ prototype.scd (or named *.scd)
    │
    ▼
supercollider-analyst (review) ──▶ inline findings
    │
    ▼
supercollider-dev (fix) ──── loop max 3 ──▶ *.scd
```

### Stages

| # | Agent | Reads | Writes | Exit criterion |
|---|-------|-------|--------|----------------|
| 1 | music-historian | the question | `docs/research.md` | topic situated; lineage, key works, theoretical anchors, listening pointers present |
| 2 | avant-composer | `docs/research.md` | `docs/reference.md` | premise, constraint, material, process, form, mapping, notation choice — all explicit |
| 3 | supercollider-analyst | `docs/reference.md` | `docs/task.md` | DSP spec covers SynthDefs, signal flow, scheduling, lifecycle, DSP constraints |
| 4 | supercollider-dev | `docs/task.md` | `*.scd` | code parses, boots, plays, frees cleanly on `Cmd-.` |
| 5 | supercollider-analyst | `*.scd` + `docs/task.md` | inline review | code passes review, or returns severity-ranked findings |
| 6 | supercollider-dev | review findings | `*.scd` updated | each High/Critical finding resolved or explicitly deferred with reason |

Stages 5–6 loop up to **3 iterations**. After 3 unresolved cycles, escalate to the user.

---

## Pipeline 2 — Short (composer + dev, analyst on call)

Use when:

- `docs/research.md` and `docs/reference.md` already exist for the area
- iterating on existing `.scd` code
- minor variations of an established technique
- bug fixes or refactors

### Flow

```
avant-composer ─────────▶ docs/reference.md (updated section)
    │
    ▼
supercollider-dev ──────▶ *.scd
    │
    ▼  (only if DSP correctness, lifecycle, or risk is unclear)
supercollider-analyst ──▶ inline findings
    │
    ▼
supercollider-dev (fix) ─▶ *.scd
```

### Stages

| # | Agent | Reads | Writes | Notes |
|---|-------|-------|--------|-------|
| 1 | avant-composer | existing `docs/reference.md` | `docs/reference.md` (appended / new section) | extends; does not start from zero |
| 2 | supercollider-dev | updated reference | `*.scd` | implements directly, no separate `task.md` unless complexity warrants it |
| 3 | supercollider-analyst | `*.scd` | inline review | **optional** — invoked only when something feels off |

The analyst is **on call** in Pipeline 2: not part of every iteration, summoned when DSP risk surfaces (aliasing, leak suspicion, lifecycle confusion, clicks).

---

## File contracts

### `docs/research.md` — historian output

- Question / topic restated
- Historical position (period, geography, scene)
- Lineage: predecessors · contemporaries · descendants
- Key works table (composer · work · year · notes)
- Theory & criticism (author, title, year, publisher)
- Listening pointers — specific recordings, not generic

Full template lives in the `music-historian` agent under "Reference note".

In **Pipeline 1**, this file is overwritten per question. If the project accumulates many topics, split into `docs/research/<slug>.md` and let the orchestrator pass a path.

### `docs/reference.md` — composer output

- One-sentence premise (premise + means)
- Constraint: what does not vary · what does
- Material: pitch / time / timbre / dynamic range
- Process: the generative principle, in implementable terms (prose or pseudocode)
- Form: sectional map or continuous-evolution description, durations, role of silence
- Mapping table: process parameter → audible dimension → range
- Notation choice and rationale
- Listening references tying back to `research.md`

In **Pipeline 2** this file is *edited*, not rewritten. The composer marks superseded sections (`> superseded YYYY-MM-DD`) rather than deleting them — the history is part of the project.

### `docs/task.md` — analyst output (Pipeline 1 only)

The DSP implementation spec. Concrete enough that the developer does not re-derive design decisions:

- **SynthDefs to write**: name · args (with defaults) · envelope shape · intended use
- **Signal flow**: groups, bus allocations, source-before-effect ordering, `In.ar` / `Out.ar` channel counts
- **Scheduling**: which mechanism (`Pbind` / `Pdef` / `Ndef` / `Routine` + `TempoClock`) and why
- **Lifecycle**: `doneAction` placement, cleanup block contents, `OSCdef` / `MIDIdef` registration pattern
- **DSP constraints**: Nyquist clamps on user-controllable freq, smoothing (`Lag` / `VarLag`) where required, gain-staging budget, `LeakDC` placement
- **Mapping check**: every row of the composer's mapping table must trace to a named code parameter
- **Footguns to avoid**: items from the analyst checklist that specifically apply to this spec

### `*.scd` — developer output

Default file: `prototype.scd`. Split into multiple `.scd` (or `.sc` for classes) only if scope warrants.

Must:

- boot the server (or be evaluable inside an existing booted session)
- contain every `SynthDef` / `Ndef` / `Pdef` / `OSCdef` / `MIDIdef` it references
- self-free on `Cmd-.`
- end with a cleanup block that clears `Pdef.all`, `Ndef.all`, frees `OSCdef` / `MIDIdef`, frees Buffers
- align with the mapping table in `docs/reference.md` — every audible parameter traces to code

---

## Pipeline selection

| Situation | Pipeline |
|-----------|----------|
| Brand-new aesthetic question | 1 |
| First piece in an unfamiliar technique | 1 |
| Project just started, `docs/` is empty | 1 |
| Variation on an existing `reference.md` | 2 |
| Bug fix or refactor of `*.scd` | 2 |
| Minor parameter tweak in a working piece | 2 (or just direct edit) |
| Unsure whether context is sufficient | 1 — the cost of writing research is lower than the cost of guessing |

---

## Gates and loop rules

- The user explicitly approves each stage transition. No agent auto-proceeds.
- After every stage the orchestrator reports what was produced and waits.
- Analyst ↔ dev review loop: **max 3 iterations** in either pipeline. After three unresolved cycles, escalate.
- The dev agent must include a completion assertion when responding to review findings: every issue is `FIXED` (with code location) or `DEFERRED` (with reason). Never silent.

---

## Agent configuration

The `supercollider-analyst` agent runs in two modes per invocation:

- **`spec` mode** — writes `docs/task.md` (Pipeline 1, stage 3). Tools: `Read, Write, Edit, Glob, Grep`. PermissionMode: `acceptEdits`.
- **`review` mode** — read-only by convention, returns findings inline (Pipeline 1 stage 5; Pipeline 2 stage 3). Same tool set, but the agent rules forbid writing files in review mode.

The orchestrator passes `mode` explicitly; if missing, the agent infers it from project state (presence of `docs/reference.md` without fresh `.scd` → `spec`; modified `.scd` → `review`).

All four agents reference this file (`docs/rulus.md`) as their pipeline source of truth.
