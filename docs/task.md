# DSP Task — `zeta` (vinyl/tape surface noise)

## Source
- Reference: `docs/zeta_texture_reference.md` (measured analysis of `archives/Texture.wav`)
- Constraints inherited: existing `App/synths/zeta.scd` integration architecture (MUST keep)

## Architecture

**JITLib `Ndef(\zeta)` driven by a `~spec_zeta` config block — fixed, do not change.**
The reference's "Constraints inherited" section makes this a hard requirement: the
layer must register `~ungSpecs[\zeta]`/`~ungVals[\zeta]`, expose every controllable
dimension as both a `~spec_zeta.params` row and a matching `Ndef(\zeta)` arg, write
stereo to its own Ndef output, and be live-editable by the App tuner/randomiser/preset
machinery in `0_lib.scd`. A Pbind/script cannot self-register or be slider-driven, so
JITLib is the only architecture that satisfies the contract. This is a **synthesis
redesign inside an unchanged shell**.

The redesign replaces the current "HF noise-grain cloud + resonant shimmer bank"
synthesis with a **two-stratum vinyl/tape model**: a quiet mid-tilted colored-noise
**bed** plus exponentially-distributed impulsive **crackle/pops**. The `\freq` /
`\tone` grouping, stereo out, ±0.4 pan, LeakDC tail, fadeTime, Greek naming, and the
registration tail are preserved byte-for-structure with the current file.

## Synthesis graph (single `Ndef(\zeta)` function, stereo out)

Build five sub-blocks, sum to mono, pan to stereo, LeakDC, scale by master `amp`.
All sub-blocks share one server graph (no per-event Synths — JITLib proxy only).

### Block 1 — Bed (continuous mid-tilted colored noise)
- Source: `PinkNoise.ar` (pink tilt ≈ the measured −6 dB/oct skirts). Reference allows
  pink/brown; pink is the closer match to a symmetric log hump. Use `PinkNoise`.
- Band shaping to the measured hump (~800–2500 Hz peak, centroid ~1.2 kHz, hard
  ceiling ~8–12 kHz, weak sub):
  - `HPF.ar(bed, bedHpf)` — low skirt, default ~200 Hz.
  - `LPF.ar(bed, bedLpf)` — ceiling, default ~7000 Hz (NOT bright — never above ~12 kHz).
  - Plus a broad resonant hump centered at `bedHumpFreq` (~1200 Hz) to put the energy
    centroid where measured: `BPF.ar(bed, bedHumpFreq, bedHumpRq)` mixed back in, OR a
    single `Resonz.ar(bed, bedHumpFreq, bedHumpRq)` blended with the flat-banded bed via
    `bedHumpAmt`. Recommended: `bed = XFade2.ar(flatBanded, Resonz.ar(flatBanded, bedHumpFreq, bedHumpRq), bedHumpAmt*2 - 1)` so default keeps a clear but not peaky hump.
- Slow motion ("wow" / colour drift): multiply bed amplitude by
  `LFNoise2.kr(bedDriftRate).range(1 - bedDriftDepth, 1.0)` (default rate ~0.1 Hz,
  shallow depth ~0.25). No chopping — keep depth modest and use `LFNoise2` (smooth).
- Bed gain: scaled by `bedAmp` (its own control) and seated ~30 dB under the pops
  inside the graph (see Gain staging).

### Block 2 — Sub rumble (optional, very low, very quiet)
- `BrownNoise.ar` → `LPF.ar(rumble, 150)` (or `LPF` at `subFreq`, default ~120 Hz).
- Scaled by `subAmt` (default low). Must stay ≥ 15 dB under the hump — clamp the
  default so this is barely present. This is "motor/turntable floor", not a tone.

### Block 3 — Fine crackle ("frying" texture)
- Trigger: `Dust2.ar(fineRate)` (default ~40/s, range covers 20–60/s).
- Envelope: `Decay2.ar(trig, fineAtk, fineDecay)` with `fineDecay` default ~0.0015 s
  (0.5–3 ms range), very short attack (~0.0002 s).
- Amplitude distribution — **exponential, many small / few large**: scale each impulse
  by `TExpRand.ar(fineAmpMin, 1.0, trig)` (or `trig * TExpRand.kr(...)`). `TExpRand`
  gives the exponential spread the reference demands; `fineAmpMin` (e.g. 0.02) sets how
  tiny the smallest ticks are.
- Source: `WhiteNoise.ar` (broadband) → HF-lean it with `HPF.ar(fine, fineHpf)`
  (default ~3000 Hz) so it reads as ticks, not thumps.
- Overall scaled by `fineAmt` (default low — this is the quiet continuous bed of ticks).

### Block 4 — Pops (sparse, exponential up to near-peak, with low "thock")
- Trigger: `Dust2.ar(popRate)` (default ~2.5/s, range 1–4/s, irregular by nature of Dust).
- Amplitude — exponential to near peak: `popLevel = TExpRand.ar(popAmpMin, 1.0, trig)`
  (default `popAmpMin` ~0.05). This realises the crest factor: most pops small, rare
  ones near full scale.
- Click body: `Decay2.ar(trig*popLevel, popAtk, popDecay)` with `popDecay` default
  ~0.006 s (3–15 ms range), `popAtk` ~0.0003 s; source `WhiteNoise.ar`, broadband but
  slightly HF-tilted via `HPF.ar(click, popHpf)` (~1500 Hz).
- Resonant "thock" body on the loudest pops only: a damped resonator
  `Ringz.ar(Decay.ar(trig*popLevel, 0.001), bodyFreq, bodyRing)` (`bodyFreq` default
  ~180 Hz, low; `bodyRing` ~0.04 s) scaled by `bodyAmt` AND gated so only large pops get
  it — gate by reusing `popLevel` raised to a power, e.g. `bodyGain = bodyAmt * popLevel.squared`
  so small pops get negligible body, large pops get the thock. This is the
  "low-frequency thock on the largest" the reference calls for.
- Pop block = `click + body`, scaled by `popAmt`.

### Block 5 — Sum, pan, condition
- `sig = bed + sub + fine + pops` (mono).
- Pan: `pan = LFNoise1.kr(panRate).range(panWidth.neg, panWidth)` then `Pan2.ar(sig, pan)`.
  §F: `panWidth` clamped ≤ 0.4, `panRate` slow.
- `sig = sig * amp.lag(0.05)` (master).
- `sig = LeakDC.ar(sig)` — final, after summing + nonlinear-ish impulse content.
- Optional safety: `Limiter.ar(sig, 0.95)` after LeakDC — recommended because pops reach
  near full scale and `TExpRand` can occasionally stack a pop on a fine tick; a brick at
  0.95 guarantees ±1.0 without audibly squashing the quiet bed. Mark optional but advised.

## `~spec_zeta.params` (full list)

Keep the existing `disp: \hz` convention on frequency rows. `group: \freq` = the
frequency-defining controls (filter edges, hump, body/thock freqs) so `~rndFreq.(\zeta)`
randomises pitch-ish content; `group: \tone` = texture/density/amplitude/environment so
`~rndParams.(\zeta)` randomises the environment.

```supercollider
~spec_zeta = (
    name: \zeta,
    params: [
        // --- группа \freq: частотные составляющие текстуры ---
        ( key: \bedHpf,     group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(80,    600,   \exp, 0, 200)  ),  // низ полосы бэда
        ( key: \bedLpf,     group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(3000,  12000, \exp, 0, 7000) ),  // потолок бэда (НЕ ярко)
        ( key: \bedHumpFreq,group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(600,   2500,  \exp, 0, 1200) ),  // центроид энергии ~1.2k
        ( key: \subFreq,    group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(40,    200,   \exp, 0, 120)  ),  // потолок саб-рокота
        ( key: \fineHpf,    group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(1500,  8000,  \exp, 0, 3000) ),  // HF-наклон мелкого треска
        ( key: \popHpf,     group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(500,   6000,  \exp, 0, 1500) ),  // HF-наклон щелчков
        ( key: \bodyFreq,   group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(80,    600,   \exp, 0, 180)  ),  // частота "thock"-тела поп

        // --- группа \tone: текстура, плотность, динамика, среда ---
        ( key: \amp,        group: \tone,             spec: ControlSpec(0.0,   0.5,  \lin, 0, 0.32)   ),  // мастер-уровень слоя
        ( key: \bedAmp,     group: \tone,             spec: ControlSpec(0.0,   1.0,  \lin, 0, 0.12)   ),  // уровень бэда (тихо)
        ( key: \bedHumpRq,  group: \tone,             spec: ControlSpec(0.2,   1.5,  \lin, 0, 0.7)    ),  // ширина горба (rq)
        ( key: \bedHumpAmt, group: \tone,             spec: ControlSpec(0.0,   1.0,  \lin, 0, 0.5)    ),  // выраженность горба
        ( key: \bedDriftRate,group:\tone, unit: " Hz", spec: ControlSpec(0.02,  2.0,  \exp, 0, 0.1)    ),  // скорость "wow"-дрейфа
        ( key: \bedDriftDepth,group:\tone,            spec: ControlSpec(0.0,   0.8,  \lin, 0, 0.25)   ),  // глубина дрейфа
        ( key: \subAmt,     group: \tone,             spec: ControlSpec(0.0,   0.3,  \lin, 0, 0.04)   ),  // уровень саб-рокота (≥15 dB под горбом)
        ( key: \fineRate,   group: \tone, unit: " /s", spec: ControlSpec(5,     120,  \exp, 0, 40)     ),  // плотность мелкого треска
        ( key: \fineDecay,  group: \tone, unit: " s",  spec: ControlSpec(0.0003,0.005,\exp, 0, 0.0015) ),  // распад тика
        ( key: \fineAmpMin, group: \tone,             spec: ControlSpec(0.005, 0.3,  \exp, 0, 0.02)   ),  // нижний край эксп. распределения тиков
        ( key: \fineAmt,    group: \tone,             spec: ControlSpec(0.0,   1.0,  \lin, 0, 0.18)   ),  // уровень мелкого треска
        ( key: \popRate,    group: \tone, unit: " /s", spec: ControlSpec(0.2,   8.0,  \exp, 0, 2.5)    ),  // плотность поп
        ( key: \popDecay,   group: \tone, unit: " s",  spec: ControlSpec(0.002, 0.03, \exp, 0, 0.006)  ),  // распад щелчка
        ( key: \popAmpMin,  group: \tone,             spec: ControlSpec(0.01,  0.5,  \exp, 0, 0.05)   ),  // нижний край эксп. распределения поп
        ( key: \popAmt,     group: \tone,             spec: ControlSpec(0.0,   1.0,  \lin, 0, 0.7)    ),  // уровень поп
        ( key: \bodyAmt,    group: \tone,             spec: ControlSpec(0.0,   1.0,  \lin, 0, 0.4)    ),  // выраженность "thock"-тела
        ( key: \bodyRing,   group: \tone, unit: " s",  spec: ControlSpec(0.005, 0.12, \exp, 0, 0.04)   ),  // время звона тела
        ( key: \panWidth,   group: \tone,             spec: ControlSpec(0.0,   0.4,  \lin, 0, 0.3)    ),  // §F: pan ≤ ±0.4
        ( key: \panRate,    group: \tone, unit: " Hz", spec: ControlSpec(0.02,  2.0,  \exp, 0, 0.15)   )   // §F: медленная панорама
    ]
);
```

## `Ndef(\zeta)` arg list (defaults match the spec above — reproduce measured texture)

```supercollider
Ndef(\zeta, { |amp = 0.32,
    bedHpf = 200, bedLpf = 7000, bedHumpFreq = 1200, bedHumpRq = 0.7, bedHumpAmt = 0.5,
    bedAmp = 0.12, bedDriftRate = 0.1, bedDriftDepth = 0.25,
    subFreq = 120, subAmt = 0.04,
    fineHpf = 3000, fineRate = 40, fineDecay = 0.0015, fineAmpMin = 0.02, fineAmt = 0.18,
    popHpf = 1500, popRate = 2.5, popDecay = 0.006, popAmpMin = 0.05, popAmt = 0.7,
    bodyFreq = 180, bodyAmt = 0.4, bodyRing = 0.04,
    panWidth = 0.3, panRate = 0.15|
    ...
})
```

Defaults reproduce: mid hump ~1.2 kHz, ceiling 7 kHz (hard roll-off, not bright),
fine crackle 40/s, pops 2.5/s, very high crest (bed at 0.12 under pops at 0.7),
quiet bed, slow ±0.3 pan.

## DSP constraints

- **Nyquist clamps** on every user-controllable frequency that feeds a filter/oscillator.
  Clamp the *post-`.lag`* value below Nyquist, e.g. `bedLpf.lag(0.2).clip(1000, SampleRate.ir * 0.45)`,
  `bedHpf.lag(0.2).clip(20, SampleRate.ir * 0.45)`, and likewise `bedHumpFreq`, `fineHpf`,
  `popHpf`, `bodyFreq`, `subFreq`. Use `SampleRate.ir * 0.45`, not a hard-coded 20000.
- **`.lag` smoothing** on jumpy controls (filter sweeps and amplitudes click if stepped):
  `bedHpf .lag(0.2)`, `bedLpf .lag(0.2)`, `bedHumpFreq .lag(0.2)`, `fineHpf .lag(0.2)`,
  `popHpf .lag(0.2)`, `bodyFreq .lag(0.2)`, `subFreq .lag(0.2)`, `amp .lag(0.05)`,
  `bedAmp .lag(0.1)`, `fineAmt .lag(0.1)`, `popAmt .lag(0.1)`, `subAmt .lag(0.1)`,
  `bodyAmt .lag(0.1)`. Density/rate controls (`fineRate`, `popRate`) feed `Dust2` —
  lag lightly (`.lag(0.3)`) so density changes glide rather than jump.
  Do NOT lag `fineDecay`/`popDecay` per-sample inside `Decay2` time args (they're set
  at trigger time; lagging is harmless but unnecessary) — light lag is fine if convenient.
- **Gain staging**: seat the bed ~30 dB under the pops *inside the graph*, before master.
  Concretely: bed default `bedAmp = 0.12`, pops default `popAmt = 0.7` → ~15 dB on the
  amplitude controls, and the bed is further filtered/diffuse while pops are impulsive,
  so peak-to-bed-RMS lands near the measured ~30 dB crest. Fine crackle `fineAmt = 0.18`
  sits between. Sub `subAmt = 0.04` keeps it ≥ 15 dB under the hump. After summing,
  master `amp.lag(0.05)` default 0.32 keeps headroom; expected peak at the Ndef output
  ≤ ~0.9. The mixer adds nothing — this layer must already be within ±1.0.
- **Limiter**: recommended `Limiter.ar(sig, 0.95)` after LeakDC (advised, not mandatory) —
  guards against rare pop-on-tick coincidence pushing past 1.0 given `TExpRand` reaching 1.0.
- **LeakDC**: `LeakDC.ar(sig)` as the final stage, after `Pan2` and master gain, before
  the optional limiter. Impulsive `Decay2`/`Ringz` content can carry slight DC.
- **Pan (§F)**: `panWidth` clamped ≤ 0.4 in the spec; `panRate` slow (≤ ~2 Hz, default 0.15).
  `LFNoise1.kr(panRate.clip(0.02, 2))`.

## Lifecycle

The shell is unchanged from the current file. Keep exactly:

```supercollider
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\zeta] = ~spec_zeta;
~ungVals[\zeta]  = ();
~spec_zeta.params.do { |p|
    Ndef(\zeta).set(p.key, p.spec.default);
    ~ungVals[\zeta][p.key] = p.spec.default;
};
Ndef(\zeta).fadeTime = 0.5;
```

- No `s.waitForBoot` / `s.sync` in this file — JITLib `Ndef` defers graph build to the
  server itself; the App boot sequence (0_lib.scd / mixer) owns server lifecycle.
- No explicit cleanup in this file — `Ndef.all.do(_.clear)` is the App's responsibility
  on session reset; this layer must not free its own proxy.
- **Stopping condition**: this is a continuous environmental layer with no intrinsic end
  (matches the reference's 30 s loopable surface). It is started/stopped/faded by the
  mixer via `Ndef(\zeta)` routing and `fadeTime`. Do not add a self-terminating envelope.
- `doneAction` is N/A: there are no transient per-event Synths — all impulses live inside
  the persistent proxy graph via `Dust2`/`Decay2`, which never free.

## Mapping check (reference Synthesis-target row ↔ code param)

| Reference dimension | Code parameter(s) | Notes |
|---------------------|-------------------|-------|
| Bed source — colored noise, band-passed ≈150–7000 Hz, hump ~1.2 kHz | `PinkNoise.ar` → `bedHpf` (200) / `bedLpf` (7000) / `bedHumpFreq` (1200), `bedHumpRq`, `bedHumpAmt` | hump via `Resonz`/`BPF` blend |
| Bed level — quiet, ~−37 dB RMS rel. pops | `bedAmp` (0.12) vs `popAmt` (0.7) | ~30 dB crest by construction |
| Bed motion — very slow amp/colour drift ("wow"), no chopping | `bedDriftRate` (0.1 Hz), `bedDriftDepth` (0.25) via `LFNoise2.kr` | smooth, shallow |
| Fine crackle — dense Dust ~20–60/s, tiny exp amp, 0.5–3 ms decay, HF-leaning | `Dust2.ar(fineRate=40)`, `TExpRand(fineAmpMin=0.02,1)`, `Decay2(_, _, fineDecay=0.0015)`, `HPF(_, fineHpf=3000)`, `fineAmt` | exponential dist. via TExpRand |
| Pops — sparse Dust ~1–4/s, exp amp → near peak, 3–15 ms decay, broadband + low "thock" | `Dust2.ar(popRate=2.5)`, `TExpRand(popAmpMin=0.05,1)`, `Decay2(_, _, popDecay=0.006)`, `HPF(_, popHpf=1500)`, `popAmt`; body: `Ringz(_, bodyFreq=180, bodyRing=0.04)` gated by `bodyAmt*popLevel.squared` | thock only on loudest |
| Spectral ceiling — hard roll-off above ~8–12 kHz | `bedLpf` (7000, max 12000) | never bright; not above 12 kHz |
| Sub — optional very low quiet rumble <150 Hz, ≥15 dB below hump | `BrownNoise.ar` → `LPF(_, subFreq=120)`, `subAmt=0.04` | barely present by default |
| Crest — overall very high, preserve quiet-bed / loud-pop contrast | structural: bed/fine/pop amp ratios + `TExpRand` distributions + optional `Limiter(0.95)` | the defining quality of the texture |

Every row of the reference's Synthesis-target table is covered above.

## Known footguns

- Do NOT use `LFSaw`/`LFPulse`/non-bandlimited oscillators as audio sources — none are
  needed here; sources are `PinkNoise`/`BrownNoise`/`WhiteNoise` (broadband, no aliasing risk).
- Do NOT let `bedLpf` default drift toward bright hiss; the reference is explicit that
  there is nothing worth speaking of above 12 kHz. Keep default 7 kHz.
- `TExpRand` must be re-triggered by the same `trig` used for the envelope, or the
  amplitude won't track each impulse — feed the `Dust2` trig to both `TExpRand` and
  `Decay2`.
- `Dust2.ar` density is events/sec; clamp to ≥ ~0.2 to avoid a stalled trigger and a
  silent layer if a user drags the slider to the floor.
- Keep all impulse generation INSIDE the persistent `Ndef` graph — do not spawn
  per-event Synths (`{...}.play` in a Routine), which would leak and break the
  slider-driven contract.
- Preserve the `disp: \hz` rows on every `\freq` param so the tuner shows nearest
  note+cents (App convention from `0_lib.scd`); do not add `disp` to `\tone` rows.
- Match `Pan2.ar` mono-in / 2-out: sum to a single mono channel BEFORE `Pan2`; do not
  feed an array into `Pan2` (would N-way duplicate). LeakDC after Pan2 is 2-channel — fine.
```
