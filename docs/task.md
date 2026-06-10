# DSP Task — `delta` (formant-cluster wind through metal plates)

## Source
- Reference: `docs/reference_v2.md` §C.4 (`binde` — narrow-band noise / **formant
  cluster**) + §F (mapping, panorama ≤ ±0.3, loudness band).
- Harmony: `docs/decomposition.md` (3-limit lattice from 94 Hz — octaves and
  fifths only; the major third ×5 is excluded by design).
- Contract: `docs/layer_contract.md` (single `( )` block, CONFIG top, no
  Out.ar/boot/cleanup, `~spec_<class>` single source of truth, registration tail).
- Reference shell pattern: `App/synths/alpha.scd` (spec→Ndef arg parity, `\freq`
  tone group / `\tone` timbre group, registration tail).

> **§C.4 supersede flag (for the user — analyst does NOT edit reference_v2):**
> This spec **evolves** §C.4, it does not cancel it. The premise stays "noise →
> parallel formant BPFs → choir-like internal beating, no centre-pitch glide".
> What grows beyond the current §C.4 card: (a) **multi-voice** — N independent
> wind streams instead of one band; (b) each stream excites a **resonant metal
> plate** (Ringz bank, "angle to the flow" = per-voice excitation brightness /
> Q / edge-whistle); (c) a **vowel formant bank** (3-formant BPF set) over each
> stream so each reads as a distinct human-vowel voice with its own pitch from
> the 94 Hz lattice. The §C.4 forbidden moves are kept: **no centre-pitch
> glide**, **no modulation faster than 0.25 Hz on the band identity**, no
> audible bandwidth widening beyond the formant structure. If the user accepts
> this as the new `binde`/`delta` premise, mark §C.4 in `reference_v2.md` with
> `> superseded 2026-06-10` and paste the multi-voice/plate/vowel premise. Until
> then this is a flagged extension, not a silent drift.

## Architecture

**JITLib `Ndef(\delta)` driven by a `~spec_delta` config block** — the only
architecture that satisfies the layer contract: the layer must self-register
`~ungSpecs[\delta]`/`~ungVals[\delta]`, expose every audible dimension as both a
`~spec_delta.params` row and a matching `Ndef(\delta)` arg, write **stereo** to its
own Ndef output, and be live-editable by the App tuner / randomiser / preset
machinery in `0_lib.scd`. A Pbind/script cannot self-register or be slider-driven.

**One persistent `Ndef(\delta)` graph, stereo out, NO per-event Synths.** All N
voices live inside the single proxy function as a multichannel array; there is no
`{}.play`, no Routine, no transient Synth — `binde`/`delta` is a sustained register
class (§F density 0, sustained), so there is nothing to schedule. The graph runs
continuously; the mixer fades it in/out via `fadeTime` and Ndef routing.

**Voice count: 5.** Five lattice fundamentals (below) give an audible polyphonic
"choir of winds" while bounding CPU: 5 voices × (wind shaping + plate Ringz bank +
3-formant BPF bank) is well within budget. The count is FIXED in code (array of 5);
it is not a runtime control (changing N would change the spec). Each voice is a
column of a 5-channel array, summed and panned at the end.

## Voice pitch anchoring (3-limit lattice from 94 Hz)

Each voice has a fundamental that drives **both** its plate-resonance excitation
register **and** the position of its vowel formant bank (formant centres scale with
the fundamental so a high voice reads as a higher-pitched "person"). Defaults sit on
the lattice; values are exposed in **MIDI-notes** (`disp: \note`) so the tuner shows
note+cents and the `\freq` randomiser stays on musically sane pitches.

| Voice | Lattice ratio | Freq (Hz) | MIDI note (default) | Role in cluster |
|-------|---------------|-----------|---------------------|-----------------|
| f1 | ×3/2 | 141 | 48.71 | low fifth — chest voice |
| f2 | ×2   | 188 | 53.71 | octave — low register |
| f3 | ×3   | 282 | 60.72 | octave+fifth — mid |
| f4 | ×4   | 376 | 65.71 | two octaves — upper-mid |
| f5 | ×6   | 564 | 72.72 | two octaves+fifth — high voice |

(MIDI = `freq.cpsmidi`; fractional = microtonal exactness of just intonation.
141→48.71, 188→53.71, 282→60.72, 376→65.71, 564→72.72.) All five lie inside the
§C.4/§F `binde` range 100 Hz – 6 kHz. The spec range per voice is wide
(MIDI 36–84 ≈ 65 Hz – 1 kHz fundamental) so the user can re-seat voices on other
lattice points (94, 376, 564…) without leaving the register; `disp: \note` keeps the
tuner honest about how far off-lattice a randomised value lands.

## Synthesis graph (single `Ndef(\delta)` function, 5 voices → stereo)

Per voice `i` (built with `Array.fill(5)` / multichannel expansion over the 5
fundamentals), then `Mix` to mono and `Splay`/`Pan2` to stereo.

### Per voice — three stages chained

**Stage A — wind stream (the air through the gap).**
- Source: `PinkNoise.ar` (or `BrownNoise` for darker voices — use `PinkNoise`,
  mid-tilted, matches "air"). One independent noise generator per voice.
- Turbulence / gust: amplitude shaped by slow smooth noise
  `LFNoise2.kr(gustRate_i).range(1 - turbulence, 1.0)` where `gustRate_i` are
  incommensurate per voice (≤ 0.25 Hz — §C.4 forbids faster than 0.25 Hz on band
  identity). `windForce` sets the overall blowing level; `turbulence` sets gust
  depth. A second, faster but shallow `LFNoise2.kr(2..6 Hz)` adds fine air
  flutter at small depth (this is air noise, not band-identity modulation, so the
  0.25 Hz rule does not bind it — keep depth ≤ ~0.15 and document it).
- Edge whistle ("angle to the flow"): a faint narrow `BPF`/`Resonz` on the wind at
  `edgeFreq_i = fund_i * edgeRatio` (high harmonic, e.g. ×6…×11) scaled by
  `edge` — the thin whistle of air over a plate corner. Per-voice `edgeRatio`
  spread gives each plate a different "angle".

**Stage B — metal plate resonance (the plate the wind hits).**
- The wind stream EXCITES a bank of inharmonic modes:
  `Mix(Ringz.ar(wind, plateFreqs_i, plateRings_i) * plateAmps_i)`.
- `plateFreqs_i` = `fund_i * [inharmonic ratio set]` — a fixed inharmonic ratio
  template (e.g. `[1, 2.76, 5.40, 8.93, 13.34]`, idiophone-like, NOT integer) so the
  plates ring metallic, not pitched-harmonic. The same template per voice scaled by
  each fundamental keeps the cluster coherent while each plate sits in its register.
- `plateQ` (global) sets ring time / sharpness = "massive plate" vs "thin sheet";
  per-voice multipliers detune ring lengths slightly for the "different angles".
- `metal` (global 0..1) = how much plate-ring vs raw-wind is in the voice
  (`XFade2`/blend). At `metal=0` it is bare wind; at `metal=1` it is a ringing
  plate. **CAUTION**: high-Q `Ringz` summed over 5 modes × 5 voices is the main
  clipping risk — see Gain staging. Clamp `plateFreqs_i` post-lag below Nyquist.

**Stage C — vowel formant bank (the "human voice" filter).**
- Over the plate+wind voice, apply a **3-formant parallel BPF bank** tuned to a
  vowel: `Mix(BPF.ar(voice, formFreqs_i, formRqs) * formAmps)`.
- Vowel set: classic formant tables for [a, e, i, o, u]. Each voice picks a vowel
  via `vowelSel_i` (default: voices spread across a, o, e, u, i so the cluster reads
  as distinct "people"). Formant centres are **offset by the voice fundamental's
  register** — i.e. `formFreq = baseVowelFreq * formScale_i` where `formScale_i`
  rises with `fund_i`, so a high voice's vowel sits higher (a child/woman vs a man).
  Use a modest scale (e.g. `fund_i / fund_mid`, clamped 0.7–1.6) so vowels stay
  recognisable.
- `vowelMix` (global 0..1) blends the formant-filtered voice against the
  un-formant-filtered plate voice — at `vowelMix=1` it is maximally "human",
  at `0` it is just ringing metal wind. This is the §C.4 "choir-like quality"
  control, now literal vowels.
- §C.4 internal-beating: each formant band gets an independent slow AM
  `LFNoise2.kr(0.1..0.25 Hz).range(0.4, 1.0)` so the formants ebb and flow within a
  voice (the original `binde` 4-BPF beating, kept).

### Voice sum, pan, condition
- `voices` = 5-channel array of the per-voice outputs.
- Per-voice gain trim so no single voice dominates; `voiceLevel` global scales all.
- Stereo placement: `Splay.ar(voices, spread)` OR per-voice
  `Pan2.ar(voice_i, panPos_i)` where `panPos_i = LFNoise1.kr(panRate).range(panWidth.neg, panWidth)`
  with **incommensurate slow panRate per voice** so voices drift in space
  independently (§F: `panWidth ≤ 0.3` for `binde`, `panRate` slow ≤ ~0.5 Hz).
  Recommend `Splay` with `spread ≤ 0.6` for an even cluster, plus a very slow
  whole-field `LFNoise1` drift inside ±0.3. Keep total field within ±0.3.
- `sig = sig * amp.lag(0.05)` (master layer level).
- `sig = LeakDC.ar(sig)` — final, after summing + high-Q resonant content.
- **Limiter advised**: `Limiter.ar(sig, 0.95)` after LeakDC — high-Q `Ringz` banks
  can transiently spike when `plateQ`/`metal` are randomised high; a brick at 0.95
  guarantees ±1.0. Mark optional but strongly advised here.

## `~spec_delta.params` (full list)

`group: \freq` = pitch-defining controls (the 5 voice fundamentals) → driven by
`~rndFreq.(\delta)`. `group: \tone` = wind/plate/vowel/space environment → driven by
`~rndParams.(\delta)`. `disp: \note` ONLY on the 5 fundamental rows (they are in MIDI
notes); never on `\tone` rows. Every row below is consumed by the Ndef — no dead
CONFIG.

```supercollider
~spec_delta = (
    name: \delta,
    params: [
        // --- группа \freq: 5 фундаментальных тонов голосов (MIDI-ноты) ---
        // дефолты на 3-limit решётке от 94 Гц: 141/188/282/376/564 Hz
        ( key: \f1, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 48.71) ),  // 141 Hz ×3/2
        ( key: \f2, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 53.71) ),  // 188 Hz ×2
        ( key: \f3, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 60.72) ),  // 282 Hz ×3
        ( key: \f4, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 65.71) ),  // 376 Hz ×4
        ( key: \f5, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 72.72) ),  // 564 Hz ×6

        // --- группа \tone: ветер ---
        ( key: \amp,        group: \tone,             spec: ControlSpec(0.0, 0.5, \lin, 0, 0.18)  ),  // мастер-уровень слоя (§K.4: 0.18)
        ( key: \windForce,  group: \tone,             spec: ControlSpec(0.0, 1.0, \lin, 0, 0.6)   ),  // сила потока (общий уровень шума)
        ( key: \turbulence, group: \tone,             spec: ControlSpec(0.0, 0.9, \lin, 0, 0.45)  ),  // глубина медленных порывов (≤0.25 Hz)
        ( key: \gustRate,   group: \tone, unit: " Hz", spec: ControlSpec(0.02, 0.25, \exp, 0, 0.08) ),  // базовая частота порывов (§C.4 ≤0.25)
        ( key: \flutter,    group: \tone,             spec: ControlSpec(0.0, 0.3, \lin, 0, 0.12)  ),  // мелкое дрожание воздуха (быстрое, мелкое)
        ( key: \edge,       group: \tone,             spec: ControlSpec(0.0, 0.6, \lin, 0, 0.18)  ),  // свист кромки (угол к потоку)
        ( key: \edgeRatio,  group: \tone,             spec: ControlSpec(3.0, 12.0, \exp, 0, 7.0)  ),  // высота свиста = fund × edgeRatio (база)

        // --- группа \tone: металлические пластины ---
        ( key: \metal,      group: \tone,             spec: ControlSpec(0.0, 1.0, \lin, 0, 0.55)  ),  // доля резонанса пластины vs сырой ветер
        ( key: \plateQ,     group: \tone,             spec: ControlSpec(0.05, 3.0, \exp, 0, 0.9)  ),  // время звона пластины (масса/толщина)
        ( key: \plateBright,group: \tone,             spec: ControlSpec(0.3, 2.0, \lin, 0, 1.0)   ),  // яркость возбуждения (угол к потоку)
        ( key: \plateSpread,group: \tone,             spec: ControlSpec(0.0, 0.05, \lin, 0, 0.015)),  // расстройка длин звона между голосами

        // --- группа \tone: формантный «человеческий» фильтр ---
        ( key: \vowelMix,   group: \tone,             spec: ControlSpec(0.0, 1.0, \lin, 0, 0.7)   ),  // выраженность гласной (хоровое качество §C.4)
        ( key: \vowelSel,   group: \tone,             spec: ControlSpec(0.0, 1.0, \lin, 0, 0.5)   ),  // сдвиг набора гласных по голосам (a-e-i-o-u)
        ( key: \formRq,     group: \tone,             spec: ControlSpec(0.03, 0.3, \exp, 0, 0.09)  ),  // ширина формант (узко=ярче гласная)
        ( key: \formScale,  group: \tone,             spec: ControlSpec(0.6, 1.6, \lin, 0, 1.0)   ),  // привязка высоты форманты к фундаменту голоса
        ( key: \beatRate,   group: \tone, unit: " Hz", spec: ControlSpec(0.05, 0.25, \exp, 0, 0.15) ),  // §C.4 биение формант (≤0.25 Hz)

        // --- группа \tone: уровни и пространство ---
        ( key: \voiceLevel, group: \tone,             spec: ControlSpec(0.0, 1.0, \lin, 0, 0.7)   ),  // общий уровень суммы голосов (до master amp)
        ( key: \panWidth,   group: \tone,             spec: ControlSpec(0.0, 0.3, \lin, 0, 0.22)  ),  // §F: pan ≤ ±0.3 для binde
        ( key: \panRate,    group: \tone, unit: " Hz", spec: ControlSpec(0.01, 0.5, \exp, 0, 0.06) )   // §F: медленный дрейф панорамы
    ]
);
```

## `Ndef(\delta)` arg list (defaults match the spec above)

```supercollider
Ndef(\delta, { |amp = 0.18,
    f1 = 48.71, f2 = 53.71, f3 = 60.72, f4 = 65.71, f5 = 72.72,
    windForce = 0.6, turbulence = 0.45, gustRate = 0.08, flutter = 0.12,
    edge = 0.18, edgeRatio = 7.0,
    metal = 0.55, plateQ = 0.9, plateBright = 1.0, plateSpread = 0.015,
    vowelMix = 0.7, vowelSel = 0.5, formRq = 0.09, formScale = 1.0, beatRate = 0.15,
    voiceLevel = 0.7, panWidth = 0.22, panRate = 0.06|
    ...
})
```

Defaults realise: 5 lattice-tuned wind voices (141…564 Hz), medium blow with slow
gusts, plates at moderate ring (`plateQ 0.9`) blended 55% over the wind, recognisable
vowels at 70% (`vowelMix`), slow ±0.22 pan drift, master 0.18 (§K.4 level).

## DSP constraints

- **Nyquist clamp** on EVERY user-controllable frequency that feeds a filter/Ringz,
  applied to the **post-`.lag`** value, using `SampleRate.ir * 0.45` (not a hardcoded
  20000):
  - voice fundamentals: `fN.lag(0.2).midicps.clip(40, SampleRate.ir * 0.45)`.
  - `plateFreqs_i = fund_i * ratioTemplate` → `.clip(40, SampleRate.ir * 0.45)`
    (high inharmonic ratios on a high voice can exceed Nyquist — clamp the whole
    array).
  - `edgeFreq_i = fund_i * edgeRatio` → clamp.
  - `formFreq` (vowel centres × `formScale` × register) → clamp.
- **`.lag` on all jumpy controls** (filter sweeps and amps click if stepped):
  fundamentals `.lag(0.2)`; `metal/plateQ/plateBright .lag(0.2)`;
  `vowelMix/vowelSel/formRq/formScale .lag(0.2)`; `windForce/turbulence/edge .lag(0.2)`;
  `voiceLevel .lag(0.1)`; `amp .lag(0.05)`; `panWidth .lag(0.2)`.
  `gustRate/beatRate/panRate` feed `LFNoise*.kr` rate args — clamp to their spec
  range, light lag optional.
- **High-Q gain staging — the main risk.** Summed high-Q `Ringz` (5 modes × 5 voices)
  and parallel formant `BPF` both add gain that depends on Q. Mandatory measures:
  1. Normalise the Ringz bank by mode count and by a `plateQ`-dependent compensation
     so raising `plateQ` does NOT raise level (e.g. divide the plate sum by a factor
     that grows with ring time, or `* (1 / nModes)` plus a `plateQ.reciprocal`-leaning
     trim — tune so `plateQ` changes timbre, not loudness).
  2. Normalise the formant bank by formant count (`* (1 / 3)`) and by `formRq`
     (narrower rq → higher peak gain → compensate).
  3. Per-voice trim `* (1 / 5)` on the voice sum before `voiceLevel`.
  4. After master `amp`, target Ndef-output peak ≤ ~0.9; the mixer adds nothing, so
     this layer must already sit within ±1.0.
- **Stability under extreme randomisation** (the `\freq`/`\tone` randomisers can
  push any control to a range edge): the graph must NOT blow up when `plateQ`→3.0,
  `metal`→1.0, `formRq`→0.03, all voice funds→84 simultaneously. Guarantee via:
  the Nyquist clamps above; the Q-compensation gain staging above; and the
  `Limiter.ar(sig, 0.95)` brick after LeakDC (advised). Verify by rendering with a
  high-Q randomised preset and checking peak ≤ 0 dBFS.
- **LeakDC**: `LeakDC.ar(sig)` as the final conditioning stage (after sum + pan),
  before the optional limiter — resonant/asymmetric content can carry DC.
- **Pan (§F)**: `binde` is `pan ≤ ±0.3`; `panWidth` spec maxes at 0.3, `panRate` slow
  (`LFNoise1.kr(panRate.clip(0.01, 0.5))`). No decay→pan or loudness→pan coupling
  (§F forbidden mappings).
- **No centre-pitch glide / no fast band modulation** (§C.4 forbidden): fundamentals
  change only via `.set` (smoothed by `.lag`, not swept by an LFO); all band-identity
  modulation (gust, formant beating) stays ≤ 0.25 Hz. `flutter` is air noise, not band
  identity — keep its depth small (≤ 0.15) so it does not read as bandwidth widening.

## Lifecycle

Registration tail per `docs/layer_contract.md` §3 (verbatim shape, `\delta`):

```supercollider
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\delta] = ~spec_delta;
~ungVals[\delta]  = ();
~spec_delta.params.do { |p|
    Ndef(\delta).set(p.key, p.spec.default);
    ~ungVals[\delta][p.key] = p.spec.default;
};
Ndef(\delta).fadeTime = 4;
```

- **`fadeTime = 4`** — `binde`/`delta` is a sustained register class (§F density 0,
  attack ≥ 0.5 s, §C.4 duration 5–60 s). A continuum/register slow fade (3–8 s band
  in the contract) fits; 4 s gives a soft, non-clicky entrance/exit with no audible
  swell rhetoric.
- **NO** `s.waitForBoot` / `s.sync` / cleanup block in this file — `1_app.scd` owns
  the server lifecycle; `2_mixer.scd` owns routing. The layer never frees its proxy.
- **NO** `Out.ar`/`ReplaceOut` — return the stereo `[L, R]` (or the `Pan2`/`Splay`
  output) from the Ndef function; the mixer routes it.
- **Stopping condition**: none intrinsic — this is a sustained register layer. It is
  started/stopped/faded by the mixer via `Ndef(\delta)` routing and `fadeTime`. Do
  NOT add a self-terminating envelope or `doneAction`; there are no transient
  per-event Synths (all motion is internal `LFNoise*`/`Ringz`, which never free).

## Acceptance metrics

Rendered with `.claude/Tools/render_measure.sh delta 30 default`. The reference is
perceptual (§C.4 card), so targets are derived from the §C.4/§F envelope (binde
loudness band −24…−9 dBFS, register 100 Hz – 6 kHz, narrow/formant spectrum) plus the
5-voice lattice (141…564 Hz fundamentals → most energy in low-mid, formants in mid).
Bands match the tool's fixed band set.

| Metric | Target | Tolerance | Rationale |
|--------|--------|-----------|-----------|
| Peak level | ≤ −1.0 dBFS | hard ceiling 0.0 | never clip even at randomised high-Q; limiter guarantees |
| RMS level (overall) | −20 dBFS | ±4 dB | §F binde loudness band −24…−9; sustained, mid-level |
| Crest (Peak − RMS) | ~14 dB | ±5 dB | textured but sustained — not impulsive (cf. zeta ~30); gust/beat give moderate crest |
| DC offset | ~0.0 | < 0.003 | LeakDC must hold it near zero |
| Band 20–80 Hz | ≤ −42 dB | — | below the lowest fundamental (141 Hz); only faint plate sub — must stay weak |
| Band 80–250 Hz | −24 dB | ±5 dB | f1/f2 fundamentals (141, 188 Hz) live here — present |
| Band 250–800 Hz | −20 dB | ±5 dB | f3/f4/f5 funds (282/376/564) + low formants — the body of the cluster |
| Band 800–2500 Hz | −22 dB | ±5 dB | vowel formants (F1/F2 of a/e/o) — the "human" zone, clearly present |
| Band 2500–6000 Hz | −30 dB | ±6 dB | high formants + edge whistle + plate brightness — audible but secondary |
| Band 6000–12000 Hz | ≤ −40 dB | — | only edge whistle / plate shimmer tops out here; must not become hiss |
| Band 12000–20000 Hz | ≤ −50 dB | — | essentially silent — this is `binde`, not `firnis`; no HF energy |

Spectral shape acceptance: energy concentrated 80 Hz – 6 kHz (matches §C.4 register
100 Hz – 6 kHz), a clear low-mid body (fundamentals) plus a mid formant presence
(vowels), and a hard roll-off above ~6 kHz. If 6–20 kHz bands exceed targets, `edge`
/ `plateBright` are too hot — back them off (they must not turn `delta` into a bright
texture; that would collide with `kratzer`/`firnis`).

## Mapping check (reference / user goal ↔ code param)

| Reference / user dimension | Code parameter(s) | Notes |
|----------------------------|-------------------|-------|
| §C.4 noise source → parallel formant BPFs | `PinkNoise.ar` per voice → Stage C 3-formant `BPF` bank | evolved from 4-BPF to per-voice 3-formant vowel bank |
| §C.4 internal beating / choir quality (slow indep. AM 0.1–0.25 Hz) | per-formant `LFNoise2.kr(beatRate~0.15)` range 0.4–1.0 | preserved; `beatRate` capped 0.25 Hz |
| §C.4 no centre-pitch glide / mod ≤ 0.25 Hz | funds via `.set`+`.lag` only; `gustRate`/`beatRate` clamped ≤ 0.25 | forbidden-move guard |
| §F binde pan ≤ ±0.3, slow | `panWidth` (max 0.3), `panRate` (≤0.5) via `LFNoise1` | §F compliant |
| §F binde loudness −24…−9 dBFS | `amp` 0.18, `voiceLevel`, gain staging | acceptance RMS −20 ±4 |
| User: multi-voice wind stream | 5 voices, `windForce`, `turbulence`, `gustRate`, `flutter` | Stage A per voice |
| User: each voice = wind + massive metal plate at an angle | Stage B `Ringz` bank `metal`/`plateQ`/`plateBright`/`plateSpread`; `edge`/`edgeRatio` = "angle"/edge whistle | inharmonic ratio template = "metal" |
| User: formant filter → human voice, own tone & pitch per voice | Stage C vowel `BPF` bank `vowelMix`/`vowelSel`/`formRq`/`formScale` + per-voice fundamental | each voice a distinct vowel/register |
| User: pitches on 94 Hz lattice (octaves & fifths) | `f1..f5` defaults 141/188/282/376/564 Hz on the 3-limit lattice | `disp: \note`, exact JI fractions |

Every audible dimension of the user goal and every §C.4/§F constraint appears above.

## Known footguns

- **Single `( )` block, CONFIG top / LOGIC below** — `.load` runs only the first
  block; a stray second block silently dies or breaks compilation (`docs/layer_contract.md` §1).
- **`disp: \note` only on `\freq` rows** (the 5 funds); never on `\tone` rows — the
  tuner uses it to show note+cents (App convention from `0_lib.scd`).
- **Spec↔arg parity**: every `~spec_delta.params` row must have an `Ndef(\delta)` arg
  with the SAME default, and vice-versa — no dead CONFIG, no hardcoded literal where a
  CONFIG value should reach the graph.
- **`Ringz`/`BPF` gain depends on Q** — do the Q-compensated gain staging; a naive
  `Mix(Ringz...) * const` will clip the moment `plateQ`/`formRq` are randomised.
- **Nyquist on the WHOLE plate ratio array**, not just the fundamental — a ×13 mode on
  voice f5 (564 Hz) is already 7.3 kHz; randomised funds push modes past Nyquist
  without an array clamp.
- **Clamp `LFNoise*.kr` rate args** (`gustRate`, `beatRate`, `panRate`) to their spec
  range so a slider at the floor does not stall motion or (at the ceiling) break the
  §C.4 ≤0.25 Hz band-identity rule.
- **Sum to the right channel shape before `Pan2`** — if using `Pan2` per voice you get
  5 stereo pairs to `Mix`; if using `Splay`, feed the 5-channel array directly. Do not
  feed a 5-channel array into a single `Pan2` (would mis-expand). `LeakDC` after the
  stereo stage is 2-channel — fine.
- **No `LFSaw`/`LFPulse` as audio sources** — none needed; sources are
  `PinkNoise`/`BrownNoise` (broadband, no aliasing). `LFNoise2`/`LFNoise1` are control
  rate only.
- **Keep all motion inside the persistent `Ndef` graph** — no `{}.play` / Routine /
  per-event Synth; `binde` is sustained, there is nothing to schedule.

## Post-tuning deviations

(left empty by the analyst — the developer appends dated entries here when
ear/measurement tuning overrules spec defaults, with what changed and why.)

### 2026-06-10 — gain staging / band balance (developer)

Все 24 `~spec_delta` дефолта оставлены БЕЗ ИЗМЕНЕНИЙ (включая `amp 0.18`,
`metal 0.55`, `vowelMix 0.7` и т.д.). Подстройка велась ВНУТРЕННИМИ
константами графа (не CONFIG), чтобы попасть в Acceptance metrics при штатных
дефолтах. Конкретно:

- **Внутренний makeup-гейн `* 3.3`** перед master `amp` — компенсирует каскад
  нормировок (`plateNorm`, `1/3` формант, `1/√N` голосов). Без него весь слой
  выходил на RMS ≈ −47 dBFS (на ~27 dB ниже цели). `amp` остаётся уровнем слоя
  §K.4 = 0.18.
- **Питание формантного банка широкополосным ветром** (`voiceSig + wind*1.1`):
  форманты, возбуждаемые только подрезанным плато-голосом, не давали энергии в
  зоне гласной (800–6000 Hz). Зона «человеческого голоса» — целевая, поэтому
  BPF возбуждаются полноспектральным PinkNoise.
- **`formGains [1.0, 0.95, 0.75]`** (вместо более крутого спада) — F2/F3
  присутствуют, иначе полосы 800–2500 / 2500–6000 проваливались ниже допуска.
- **`plateModAmps [0.55, 0.7, 0.6, 0.45, 0.3]`** — приглушён нижний (×1)
  мод пластины, чтобы низ-середина (фундаменты) не маскировала формантную зону;
  спектр стал ровнее и ближе к §C.4 «narrow/formant».
- **Тройной HPF 125 Hz (~36 dB/oct)** на финальной шине — держит полосу
  20–80 Hz на −42 dB (§C.4 регистр 100 Hz – 6 kHz; ниже нижнего фундамента
  141 Hz). Незначительно подрезает f1/f2 на 80 Hz — компенсировано makeup.
- **`Limiter.ar(sig, 0.95)`** включён (рекомендован спекой как «strongly
  advised»). Стресс-тест (все funds=84, plateQ=3.0, metal=1.0, formRq=0.03,
  amp=0.5, voiceLevel=1.0) даёт peak −3.0 dBFS — ±1.0 гарантирован.

Измеренный результат (`render_measure.sh delta 30 default`): peak −6.1,
RMS −20.2, crest 14.1, DC ≈ 0; все полосные RMS в допуске. Floor-тест (все
уровни 0) — чистая цифровая тишина, без NaN.
