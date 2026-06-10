# Pipelines

> v2 (2026-06-10). v1 archived at `archives/rulus.md`. Updated for the App era:
> per-layer references, the App layer contract, acceptance metrics, and the
> lightweight layer-iteration pipeline.

Three pipelines route work through the four agents in `.claude/agents/`.

The four roles:

- `music-historian` — researches, places phenomena in historical context
- `avant-composer` — designs compositional structures, processes, forms — inside the UNGRUND system (`docs/reference_v2.md`)
- `supercollider-analyst` — DSP / SuperCollider expert; writes the implementation spec (`spec`), reviews code (`review`)
- `supercollider-dev` — implements `.scd` (App layers and standalone scripts)

---

## Project file map (current)

| Artifact | Location | Notes |
|----------|----------|-------|
| Research | `docs/research.md` | founding Tietchens study archived at `archives/research.md` — extend, don't duplicate |
| System reference | `docs/reference_v2.md` | axioms, §C sound-classes, §D processes, §E forms, §F mapping, §K effects. Amendments appended; superseded sections marked `> superseded YYYY-MM-DD` |
| Layer reference | `docs/<layer>_<topic>_reference.md` | per-layer composer/measured reference (pattern: `docs/zeta_texture_reference.md`) |
| DSP spec | `docs/task.md` | one active task; superseded specs move to `archives/` |
| Layer code | `App/synths/<class>.scd` | Greek-letter names `alpha`…`theta`; contract: `docs/layer_contract.md` |
| Infrastructure | `App/0_lib.scd` … `App/7_viz.scd` | entry point `App/1_app.scd` |
| Verification | `.claude/Tools/parse_check.scd`, `.claude/Tools/render_measure.sh` | parse without execution; render + ffmpeg measurement |
| Locked | `Tests/test_monade.scd` | finalized — NO agent may modify it |

### The two `.scd` contracts

- **App layer** (`App/synths/<class>.scd`): exactly one top-level `( )` block,
  CONFIG on top, `~spec` registration tail, NO boot / sync / cleanup, NO
  `Out.ar`/`ReplaceOut` — full contract in `docs/layer_contract.md`.
- **Standalone script**: boots the server (`s.waitForBoot`), self-frees on
  Cmd-., ends with a cleanup block clearing Pdefs/Ndefs/OSCdefs/Buffers.

---

## Pipeline 1 — Full (research → implementation)

Use when: the technique or scene is unfamiliar; a new aesthetic question; a new
sound-class premise is being established.

```
[question]
    │
    ▼
music-historian ─────────────────▶ docs/research.md
    │
    ▼
avant-composer ──────────────────▶ docs/<layer>_…_reference.md
    │                              (or a docs/reference_v2.md amendment)
    ▼
supercollider-analyst (spec) ────▶ docs/task.md  (incl. Acceptance metrics)
    │
    ▼
supercollider-dev ───────────────▶ App/synths/<layer>.scd (or named .scd)
    │                              + self-check: parse_check, render_measure
    ▼
supercollider-analyst (review) ──▶ inline findings
    │
    ▼
supercollider-dev (fix) ──── loop max 3 ──▶ updated .scd
```

| # | Agent | Reads | Writes | Exit criterion |
|---|-------|-------|--------|----------------|
| 1 | music-historian | the question | `docs/research.md` | lineage, key works, anchors present |
| 2 | avant-composer | research | layer reference / reference_v2 amendment | premise, constraint, material, process, mapping — explicit; §C card superseded-marked if premise changes |
| 3 | supercollider-analyst | reference | `docs/task.md` | spec covers architecture, signal flow, lifecycle, DSP constraints, **acceptance metrics** |
| 4 | supercollider-dev | `docs/task.md` | `.scd` | parses (`.claude/Tools/parse_check.scd`); target ↔ measured table when metrics exist; doc sync done |
| 5 | supercollider-analyst | `.scd` + spec | inline review | findings severity-ranked or PASS |
| 6 | supercollider-dev | findings | updated `.scd` | each High/Critical FIXED or DEFERRED with reason |

Stages 5–6 loop up to **3 iterations**, then escalate to the user.

---

## Pipeline 2 — Short (composer + dev, analyst on call)

Use when: research and a reference already exist; a variation of an
established technique; a premise-level change to an existing layer.

```
avant-composer ─────────▶ reference updated (superseded marks!)
    │
    ▼
supercollider-dev ──────▶ .scd  (+ self-check)
    │
    ▼  (only if DSP correctness, lifecycle, or risk is unclear)
supercollider-analyst ──▶ inline findings → dev fixes
```

The analyst is **on call**: summoned when DSP risk surfaces (aliasing, leaks,
lifecycle confusion, clicks).

---

## Pipeline 3 — Layer iteration (dev-only, lightweight)

Use when: bringing a stub layer to a full panel, or tuning an existing layer,
**without changing its §C premise**. This is the project's routine work.

```
supercollider-dev:
  1. read §C premise (reference_v2) + docs/layer_contract.md
     (+ layer reference / docs/task.md if they exist)
  2. write/extend ~spec_<class> + Ndef — per the contract
  3. self-check: sclang .claude/Tools/parse_check.scd App/synths/<layer>.scd
  4. if acceptance metrics exist: .claude/Tools/render_measure.sh <layer>
     → target ↔ measured table in the report
  5. doc sync: architecture.md §9 row + appendix
analyst on call · composer only if the premise itself must change (→ Pipeline 2)
```

No per-stage user gates inside Pipeline 3 — the dev implements, self-checks and
reports once. Anything premise-level escalates to Pipeline 2.

---

## File contracts

### `docs/task.md` — analyst output

Everything from v1 (SynthDefs/args, signal flow, scheduling, lifecycle, DSP
constraints, mapping check, footguns) **plus**:

- **Acceptance metrics** — measurable targets with tolerances (octave-band RMS,
  crest factor, event densities, peak level) whenever the reference is measured;
  at minimum peak / RMS ballpark / spectral ceiling otherwise. Verified with
  `.claude/Tools/render_measure.sh`.
- **Post-tuning deviations** — section the analyst leaves empty; the developer
  appends dated entries when ear/measurement tuning overrules spec defaults
  (what changed, why). The spec must never silently disagree with the code.

### Layer reference — composer output

Per-layer file `docs/<layer>_<topic>_reference.md`: premise (§C class named),
constraint, material, mapping table with measurable ranges, stopping/lifecycle
expectations, inherited App constraints. Measured tables (like
`zeta_texture_reference.md`) are the preferred form — they become acceptance
metrics directly.

### Doc sync — developer's Definition of Done (layer work)

- `docs/architecture.md`: §9 status row + per-layer appendix updated
- `docs/task.md`: Post-tuning deviations appended when applicable
- premise changes flagged to the composer → `> superseded` mark in
  `docs/reference_v2.md` §C

---

## Gates and loop rules

- Pipelines 1–2: the user approves each stage transition; no agent
  auto-proceeds. Pipeline 3: single report at the end.
- Analyst ↔ dev review loop: max 3 iterations, then escalate.
- Dev responses to review findings carry a completion assertion: every issue
  `FIXED` (with location) or `DEFERRED` (with reason). Never silent.

---

## Agent configuration

| Agent | Model | Tools (beyond Read/Write/Edit/Glob/Grep) | Notes |
|-------|-------|------------------------------------------|-------|
| music-historian | sonnet | WebSearch, WebFetch | verifies dates/works instead of guessing |
| avant-composer | opus | — | composes inside the UNGRUND system |
| supercollider-analyst | opus | — | `review` mode writes NO files |
| supercollider-dev | opus | Bash | runs parse_check / render_measure |

Review default scope: the layer/module under iteration + its contract
touchpoints (`App/0_lib.scd`, `App/2_mixer.scd` interfaces) — pass
`target_files` explicitly to widen.

All four agents reference this file (`docs/rulus.md`) as their pipeline source
of truth.
