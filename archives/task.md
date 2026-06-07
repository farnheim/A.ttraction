# DSP Task

## Source
- Reference: `docs/reference.md` (UNGRUND system; primary target `ungrund.0001`)
- Research: `docs/research.md` (Asmus Tietchens)

## Scope

Implement the **eight UNGRUND sound-classes** as reusable SynthDefs, plus the **`substratumwalk` process scheduler**, plus a complete realisation of **`ungrund.0001`** as a top-to-bottom `.scd` script with full lifecycle hygiene. The SynthDef bank must also be sufficient for `ungrund.0002` (Tafel) and `ungrund.0003` (Raster) without modification — those scripts can be added later in the same SynthDef vocabulary.

## Architecture

**Script** (single `.scd`, top-to-bottom). Reasons:
- `ungrund.0001` has a fixed 360 s duration → not a JITLib live-edit case.
- The piece is one process, no need for `Ndef` proxies that can be rerouted at runtime.
- The SynthDef bank is reusable across all UNGRUND pieces via `.add` (server-resident).
- A class-based (`.sc`) implementation is over-engineering for the current scope.

File: `ungrund_0001.scd` (preferred) or update `prototype.scd` to host the system. The orchestrator decided: **write to `ungrund_0001.scd`** and leave `prototype.scd` as the project's 94 Hz prototype.

## SynthDefs (the eight classes + scheduler helpers)

### `\monade` — sustained sine (ground class)

- **Args:** `out = 0, freq = 94, amp = 0.4, atk = 6.0, rel = 12.0, gate = 1, pan = 0, mon_bus = ?`
- **Envelope:** `Env.asr(atk, 1, rel, curve: -4)` with `doneAction: 2` on gate release.
- **Body:** `SinOsc.ar(freq.clip(20, SampleRate.ir * 0.45)) * env * amp`
- **Output:**
  - `Pan2.ar(sig, pan)` → `Out.ar(out, ...)` (master)
  - **Also** `Out.ar(mon_bus, sig)` (mono pre-pan signal to the monitor bus for `substratumwalk`'s amplitude watcher)
- **Purpose:** the *Grund* of `ungrund.0001`.

### `\rissz` — broadband impulse (event class)
*Note: SynthDef name `\rissz` (no ß) for ASCII safety; symbol is fine in SC but file safety preferred.*

- **Args:** `out = 0, amp = 0.6, atk = 0.001, rel = 0.05, hpf = 100, pan = 0`
- **Envelope:** `Env.perc(atk, rel, curve: -4)` with `doneAction: 2`.
- **Body:** `WhiteNoise.ar` → `HPF.ar(noise, hpf)` × `env` × `amp`
- **Output:** `Pan2.ar(sig, pan)` → `Out.ar(out, ...)`
- **Purpose:** punctuation events in `ungrund.0001`.

### `\flockung` — granular cluster of sines (event class)

- **Args:** `out = 0, fund = 220, amp = 0.15, atk = 0.01, rel = 0.4, jitter = 0.02, pan = 0`
- **Body:** five sines at partials 5, 7, 9, 11, 13 of `fund`, each multiplied by an independent `LFNoise2.kr(2)`-modulated jitter for ±`jitter` × freq deviation; each via a per-grain `EnvGen.kr(Env.perc(atk, rel, ...))` with `Done.none` on the per-grain envelopes; the **outer** envelope uses `Env.linen(0, rel * 1.2, 0)` with `doneAction: 2`.
- **Output:** `Pan2.ar(Mix(grains), pan)`.
- **Purpose:** scattered foreground events.

### `\binde` — narrow-band noise (register class)

- **Args:** `out = 0, freq = 1100, rq = 0.02, amp = 0.25, atk = 1.5, rel = 4.0, gate = 1, pan = 0`
- **Envelope:** `Env.asr(atk, 1, rel, curve: -4)` with `doneAction: 2` on gate release.
- **Body:** `PinkNoise.ar` → `BPF.ar(noise, freq.clip(20, SampleRate.ir * 0.45), rq)` × `env` × `amp` × **post-filter compensating gain** (`rq.reciprocal.sqrt * 0.3` or similar empirical factor — must be tuned).
- **Output:** `Pan2.ar(sig, pan)`.
- **Purpose:** held frequency zones.

### `\schliere` — drifting comb-filtered noise (continuum class)

- **Args:** `out = 0, freq_lo = 200, freq_hi = 1800, sweep_t = 90, amp = 0.18, atk = 6.0, rel = 6.0, gate = 1, pan = 0`
- **Envelope:** `Env.asr(atk, 1, rel, curve: -4)` with `doneAction: 2`.
- **Body:**
  - Drift signal: sum of two `LFNoise2.kr` at incommensurate rates (0.013, 0.019 Hz) mapped via `linexp` to range `freq_lo..freq_hi`.
  - Apply to comb delay time: `delayTime = drift.reciprocal`.
  - `CombC.ar(WhiteNoise.ar * 0.5, 0.05, delayTime.clip(0.0001, 0.05), 6.0)` — decay 6 s, max delay 50 ms.
  - Multiply by amp and env.
- **Output:** `Pan2.ar(sig, pan)`.
- **Purpose:** slow spectral motion.

### `\kratzer` — dry granulated noise burst (event class)

- **Args:** `out = 0, amp = 0.2, atk = 0.01, rel = 0.3, hpf = 5000, gate_rate = 40, pan = 0`
- **Envelope:** `Env.perc(atk, rel, curve: -4)` with `doneAction: 2`.
- **Body:** `WhiteNoise.ar` → `HPF.ar(noise, hpf.clip(1000, SampleRate.ir * 0.45))` × `LFNoise0.kr(gate_rate).range(0.2, 1.0)` × `env` × `amp`.
- **Output:** `Pan2.ar(sig, pan)`.
- **Purpose:** high-band texture events.

### `\firnis` — ultrasonic shimmer (ceiling class)

- **Args:** `out = 0, amp = 0.05, atk = 8.0, rel = 8.0, gate = 1`
- **NOTE:** This SynthDef does **not** take `freq` as an arg — it takes an array of fixed frequencies (5 voices). Implement as a fixed multi-voice SynthDef per the score's 5 frequencies, or accept a `freqs` Array via `\freqs.kr([12640, 13110, 14790, 16030, 17880], 0)`.
- **Envelope:** `Env.asr(atk, 1, rel, curve: -4)` with `doneAction: 2`.
- **Body:** for each of 5 fixed frequencies, an independent `LFNoise2.kr(0.12)`-modulated amplitude (range 0.2…1.0), summed via `Mix`. Pan voices statically across stereo via `Splay.ar` (slight spread, width 0.5). Apply piece envelope and master amp.
- **Output:** `Out.ar(out, sig)` — already stereo from `Splay.ar`.
- **Purpose:** the upper glaze across the piece.

### `\zäsur` — no SynthDef
Silence is a scheduler concept. The master `Routine` simply advances its clock by the *zäsur* duration without spawning anything.

### `\ung_master` — master bus envelope + limiter

- **Args:** `in = ?, out = 0, master_amp = 1.0`
- **Body:** read piece bus, sum, `LeakDC.ar`, `Limiter.ar(sig, 0.95, 0.01)`, `master_amp` scale, `Out.ar(0, sig)`.
- **Purpose:** sit at the tail of `fxGroup`; protects hardware from any unexpected peak.
- **Lifecycle:** lives for the whole piece; freed at cleanup.

### `\amp_watcher` — `substratumwalk` amplitude monitor

- **Args:** `mon_bus = ?, threshold = 0.30, lag = 1.5, id = 100`
- **Body:**
  ```
  sig = In.ar(mon_bus, 1);
  rms = Amplitude.kr(sig, attackTime: lag, releaseTime: lag);
  trig = (rms > threshold) * Changed.kr(rms > threshold);   // upward crossing
  SendReply.kr(trig, '/ung/threshold', [rms], id);
  ```
- **Output:** none (control-side OSC).
- **Lifecycle:** lives for the whole piece; freed at cleanup.
- **Purpose:** emits `/ung/threshold` whenever the monade's RMS crosses upward. Language-side `OSCdef` then enforces the refractory period and spawns `\rissz`.

## Signal flow

```
groups:
  ~grpSrc   = Group.new(s, \addToHead)      // sources: monade, rissz, flockung, binde, schliere, kratzer, firnis
  ~grpAnl   = Group.new(~grpSrc, \addAfter) // amp_watcher (control-side only; no audio out)
  ~grpFx    = Group.new(~grpAnl, \addAfter) // master limiter
```

```
buses:
  ~busMaster   = audio, 2 channels (the piece bus before the limiter)
  ~busMonade   = audio, 1 channel (the monade's pre-pan signal, for amp_watcher)
```

```
routing:
  monade  ──→  ~busMonade  ──→  amp_watcher (control-rate analysis)
  monade  ──→  ~busMaster  ─┐
  rissz   ──→  ~busMaster  ─┤
  flockung──→  ~busMaster  ─┤
  binde   ──→  ~busMaster  ─┤
  schliere──→  ~busMaster  ─┼──→  ung_master (limiter)  ──→  Out.ar(0, ...) (hardware 0,1)
  kratzer ──→  ~busMaster  ─┤
  firnis  ──→  ~busMaster  ─┘
```

**Channel counts**: every voice SynthDef writes stereo (Pan2.ar or Splay.ar) to `~busMaster`. `\ung_master` reads stereo, writes stereo. `\amp_watcher` is control-rate-only; reads mono from `~busMonade`.

## Scheduling

The piece is **`ungrund.0001`** in form `schicht` with process `substratumwalk`. The orchestration:

| Time (s) | Event |
|----------|-------|
| 0        | boot complete; SynthDefs added; groups + buses allocated; `\ung_master` started in `~grpFx` |
| 0        | spawn `\monade` (gate = 1) in `~grpSrc` with 6 s attack — written to `~busMaster` AND `~busMonade` |
| 4        | spawn `\firnis` (gate = 1) in `~grpSrc` with 8 s attack — written to `~busMaster` |
| 4        | spawn `\amp_watcher` in `~grpAnl` reading `~busMonade` |
| 4 → 348  | `OSCdef(\ung_threshold)` listens; on each `/ung/threshold` it checks language-side refractory (8 s) and, if cleared, spawns a `\rissz` in `~grpSrc` with `amp = rrand(0.4, 0.85)`, `pan = rrand(-0.6, 0.6)` |
| 348      | `\monade.set(\gate, 0)` and `\firnis.set(\gate, 0)` — both fade out (12 s and 8 s respectively) |
| 360      | piece end; cleanup block runs |

Mechanism choice: a single **`Routine`** on `TempoClock.default` schedules the macro events (monade start, firnis start, watcher start, gates off, cleanup). The `substratumwalk` triggers are handled by `\amp_watcher` + `OSCdef` — server-side analysis, language-side debouncing.

Why not `Pbind` for the `\rissz` events? Because the trigger is *content-conditional* (RMS-driven), not time-conditional. `Pbind` is wrong shape. A `\rissz`-only Pbind would lose the `substratumwalk` semantic.

## Lifecycle

- Wrap everything in `s.waitForBoot({ ... });`.
- After `SynthDef(...).add` × 9, call `s.sync` before allocating buses or starting synths.
- Bus allocation via `Bus.audio(s, 2)` / `Bus.audio(s, 1)`, never magic indices. Hardware out remains channel 0..1.
- `OSCdef(\ung_threshold)` is registered fresh each run; `OSCdef.newMatching` semantics ensure re-evaluation replaces rather than stacks.
- **Cleanup block** at file bottom, evaluatable independently:
  ```
  (
      Routine.run({ s.bind {
          ~ungR.stop;
          OSCdef(\ung_threshold).free;
          ~grpSrc.freeAll; ~grpAnl.freeAll; ~grpFx.freeAll;
          ~grpSrc.free; ~grpAnl.free; ~grpFx.free;
          ~busMaster.free; ~busMonade.free;
          Pdef.all.do(_.clear);
          Ndef.all.do(_.clear);
      } });
  )
  ```
- `Cmd-.` (`s.freeAll`) must leave a clean server — covered by `doneAction: 2` on every transient SynthDef plus the cleanup block for the persistent ones.

**Stopping condition** (from reference §H ungrund.0001): at t = 360 s the master Routine sets `monade.gate = 0`. The `monade`'s 12 s release means it audibly tails to silence by t ≈ 360 s exactly (release started at t = 348 s). The cleanup block then runs at t = 361 s to guarantee no leak even if any voice missed its `doneAction`.

## DSP constraints

- **Nyquist clamp** on every user-controllable frequency: `freq.clip(20, SampleRate.ir * 0.45)` — required in `\monade`, `\binde`, `\schliere` (drift), `\kratzer` (hpf), and the per-voice partials in `\flockung`.
- **Smoothing**: `\amp`, `\freq`, `\pan` on every sustained class wrapped in `\name.kr(default).lag(0.05)` (or `Lag.kr(\name.kr(default), 0.05)`).
- **Gain staging budget**:
  - `\monade` at amp 0.4 → ≈ −8 dBFS peak (sine, pre-master).
  - `\rissz` at amp 0.85 peak transient → ≈ −1.4 dBFS peak (filtered noise, brief).
  - `\firnis` total ≈ −24 dBFS (5 voices × 0.015 ≈ 0.075).
  - Sum at master expected peak: ≤ −2 dBFS.
  - `Limiter.ar(.., 0.95, 0.01)` in `\ung_master` is the safety net.
- **LeakDC** in `\ung_master` to clear any accumulated DC.
- **Filter compensating gain** in `\binde` and `\kratzer`: narrow filters attenuate; their post-filter signal must be boosted to reach the declared amp. The exact compensation is empirical; bake into the SynthDef body, not into the user-facing `amp` arg.
- **`\firnis` HF safety**: must include a fixed `LPF.ar(sig, 20000)` after the sine cluster to prevent any aliasing artefacts that could fold downward. (Sine partials at 17.88 kHz are below Nyquist at 44.1 kHz but the post-modulation envelope can introduce sidebands.)

## Mapping check (`docs/reference.md` ↔ code parameters)

The mapping table from `ungrund.0001`:

| Reference parameter | Code parameter | Carrier |
|---------------------|----------------|---------|
| `monade.freq` | `Synth(\monade).set(\freq, ...)` or instantiation arg | `\monade` `freq` |
| `monade.amp` | instantiation arg + envelope shape | `\monade` `amp`, `Env.asr` |
| `monade.atk`, `monade.rel` | instantiation args | `\monade` `atk`, `rel` |
| `riß.threshold` | `\amp_watcher` `threshold` | server-side; comparison in `\amp_watcher` body |
| `riß.refractory` | language-side `OSCdef` debounce | `~lastRissTime` + 8 s |
| `riß.amp_min/max` | language-side `rrand(0.4, 0.85)` | per-event arg to `Synth(\rissz)` |
| `firnis.freqs` | array baked into `\firnis` SynthDef | `\firnis` body |
| `firnis.amp_each` | per-voice constant inside SynthDef | `\firnis` body |
| `firnis.lfn_rate` | `LFNoise2.kr(rate)` rate | `\firnis` body |

Every row traces to a code location.

## Known footguns

- **`\firnis` aliasing**: with the LFN AM and the cluster of high sines, sidebands can fold. Mitigation: `LPF.ar(sig, 20000)` after the cluster.
- **Refractory in `\amp_watcher` server-side**: the simplest implementation (`> threshold`) fires every block while the signal is above threshold. **Use `Changed.kr` or an edge-trigger**: trigger only on the *rising* edge, then `SendReply.kr` will fire once per crossing. Language-side refractory is the second line.
- **`Limiter.ar` look-ahead**: 10 ms look-ahead is enough for `\rissz` transients; longer values smear the impulse character.
- **`monade.gate = 0` and `monade`'s `\mon_bus` write**: when the monade fades out, the amp_watcher will still see signal until release ends. That is correct; we want the late-piece *riß* triggers to come from the actual ground RMS, not a logical "is it gated" flag.
- **`OSCdef.newMatching` vs `OSCdef`**: use plain `OSCdef(\ung_threshold, ..., '/ung/threshold')` — the symbolic key automatically replaces an existing handler on re-evaluation.
- **`SendReply.kr(trig, '/path', [val], id)`**: the `id` arg lets multiple SendReplies be distinguished by a single OSCdef. Use a constant id (e.g. 100) so the watcher's pattern matches.
- **Boot-time async**: `SynthDef.add` is asynchronous on the server; `s.sync` after the batch before any `Synth(...)` call. Wrap the whole start sequence in a single `Routine` to make the `s.sync` calls work.
- **`Splay.ar` width**: keep narrow (≤ 0.5). UNGRUND axiom V allows stereo only as a dimension, not as immersion.
- **Don't use `LFSaw.ar` / `LFPulse.ar` as audio sources** — they alias above ~5 kHz. Stick to `SinOsc.ar`, `WhiteNoise.ar`, `PinkNoise.ar`, `Saw.ar` (bandlimited) for audio.
- **`Pan2.ar` doubles signal energy** at centre — already accounted for in the gain staging budget above; keep amps moderate.

## Test plan (for the developer)

After `s.boot;` + evaluating the file, verify:
1. The file evaluates with no compile errors and no missing-symbol errors.
2. At t ≈ 6 s the *monade* is audible (94 Hz, ~ −12 dBFS).
3. At t ≈ 12 s the *firnis* is audible on a sufficient playback system (very quiet shimmer near 13–18 kHz).
4. By t ≈ 30 – 60 s the first *rissz* fires (broadband click, ~ −5 dBFS peak).
5. *Rissz* events are at least 8 s apart.
6. At t = 360 s the piece is silent.
7. `Cmd-.` followed by re-evaluation leaves a clean server — no leaked Synths (`s.queryAllNodes` shows root group only after cleanup).

## Future extensions (not in this task)

- `ungrund.0002` (Tafel) — separate `.scd` reusing the SynthDef bank; replaces the `substratumwalk` scheduler with a sequential per-class scheduler.
- `ungrund.0003` (Raster) — separate `.scd` reusing the SynthDef bank; uses a fixed 32-cell schedule.
- An `.ungrund` parser (optional): a small sclang parser that reads `.ungrund` scores and instantiates the right pieces. Defer until after the three etudes are running.

