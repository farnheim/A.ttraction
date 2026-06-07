# DSP Task — UNGRUND 0001 (warm/enveloping timbral revision) — v2

> Этот файл содержит обновлённую версию `task.md` с тембральной редакцией v2 (богатый эмбиент, гранулярный синтез, tape reverb/delay).
> Оригинал сохранён в `docs/task.md` без изменений.

## Source

- Reference: `docs/reference_v2.md` — Sections C (synthesis premises per class), F (mapping table), H (ungrund.0001 parameters), K (effects architecture). Section A.Amendment legitimises reverb/delay as synthesis operations.
- Research: `docs/research.md` — material discipline, ear-audited DSP, spatial dryness amended.
- Current baseline: `ungrund_0001.scd` — keep its scheduling routine, OSCdef-driven `\rissz` trigger, GUI, and lifecycle plumbing. Only the SynthDefs and the bus topology change.

## Architecture

**Script** (single `.scd`, top-to-bottom evaluable). Driven by `s.waitForBoot { SynthDef.add × N; s.sync; … }` plus a single `Routine` for the 360 s substratumwalk. Persistent effects (`\tape_reverb`, `\ping_delay`, `\ung_master`) are server-side Synths owned by `~grpFx`. This matches the existing baseline and the reference's "one process, one form" specification for ungrund.0001.

## SynthDefs

Twelve SynthDefs total: eight voice classes (`\monade`, `\rissz`, `\flockung`, `\binde`, `\schliere`, `\kratzer`, `\firnis`) — `\zäsur` is not a SynthDef, it is a clock advance — plus four infrastructure defs (`\tape_reverb`, `\ping_delay`, `\ung_master`, `\amp_watcher`).

All voice SynthDefs accept `fx_bus` as an argument and emit a reverb/delay-send copy in addition to their dry write. All sustained classes lag `amp` and `pan`. Event classes do not lag.

### `\monade` — 7-voice warm cluster (sustained, the Grund)

- **Args:** `out=0, mon_bus=16, fx_bus=18, freq=94, amp=0.25, atk=6.0, rel=12.0, gate=1, pan=0`
- **Source:** 7 `SinOsc.ar` voices summed.
- **Per-voice slow detune:**
  - Detune rates (Hz) array: `[0.011, 0.015, 0.019, 0.013, 0.022, 0.017, 0.009]`
  - Per voice `i`: `freq * (1 + LFNoise2.kr(detuneRates[i]).range(-0.005, 0.005))`
- **Per-voice slow amplitude shaping:**
  - Amp rates (Hz) array: `[0.023, 0.031, 0.041, 0.027, 0.035, 0.029, 0.019]`
  - Per voice `i`: `LFNoise2.kr(ampRates[i]).range(0.3, 1.0)`
- **Cross-AM (subtle inter-voice beating, < ±4 %, NOT FM, NOT audio-rate):**
  - Per voice `i`: multiply amp by `(1 + LFNoise2.kr(0.017 + i*0.003).range(-0.04, 0.04))`
- **Construction tip:** build with `Array.fill(7, { |i| ... })` so each voice carries its own UGen instances.
- **Sum / shape:**
  ```
  sig = Mix(voices) * (1/7);
  sig = LPF.ar(sig, 900);
  sig = sig * env * amp.lag(0.05);
  ```
- **Envelope:** `EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2)`
- **Nyquist:** `fSafe = freq.clip(20, SampleRate.ir * 0.45)` applied to the base freq before detuning.
- **Output (three writes):**
  ```
  Out.ar(mon_bus, sig);                                        // mono pre-pan for amp_watcher
  Out.ar(out,    Pan2.ar(sig, pan.lag(0.05)));                 // dry to master bus
  Out.ar(fx_bus, Pan2.ar(sig * 0.55, pan.lag(0.05)));          // reverb/delay send 0.55
  ```
- **Send notes:** Section K.1 gives `monade.tape_reverb = 0.55`. The send level is rolled into the single `fx_bus` write because both `\tape_reverb` and `\ping_delay` read from the same `~busFxSend`. K.2 allots `monade.ping_delay = 0.20`; this is satisfied by routing the same send into both fx synths.

### `\rissz` — soft granular burst

- **Args:** `out=0, fx_bus=18, amp=0.45, atk=0.01, rel=0.35, hpf=200, pan=0`
- **Note on naming:** existing baseline uses `\rissz` (no umlaut) as a JIT-safe symbol for `riß`. Keep that name; the OSCdef and Routine reference it.
- **Source:** `GrainSin.ar` (stereo channel count: 1; pan handled per-grain).
  - `density = LFNoise2.kr(4).range(60, 100)` grains/sec
  - `trigger = Impulse.ar(density)`
  - `dur = LFNoise1.kr(3).range(0.015, 0.04)`
  - `freqGrain = hpf * LFNoise0.kr(12).range(0.8, 2.5)` (scatter around the HPF cutoff to produce a near-unpitched spray)
  - `panGrain = LFNoise1.kr(5).range(-0.5, 0.5)`
  - `envBufNum = -1` (built-in Hann)
- **Filter:** `HPF.ar(sig, hpf.clip(20, SampleRate.ir * 0.45))` on the GrainSin output.
- **Outer envelope:** `EnvGen.kr(Env.perc(atk, rel, curve: -4), doneAction: 2)`
- **Output (no lag — event-class):**
  ```
  Out.ar(out,    Pan2.ar(sig * env * amp,        pan));
  Out.ar(fx_bus, Pan2.ar(sig * env * amp * 0.30, pan));     // K.1: rissz tape_reverb 0.30
  ```
- **Fallback:** if `GrainSin` is unavailable on the target SC build, fall back to a cloud of `Array.fill(28, { ... })` overlapping short `SinOsc.ar` grains with individual `Env.perc(rrand(0.005,0.012), rrand(0.015,0.030))` envelopes scattered with `Pan2.ar(..., rrand(-0.5,0.5))`. The outer envelope and HPF are unchanged. Choose at SynthDef-add time; do not branch at run time.

### `\flockung` — granular cloud of harmonic partials

- **Args:** `out=0, fx_bus=18, fund=220, amp=0.12, atk=0.01, rel=0.6, jitter=0.03, pan=0`
- **Source:** 12 `SinOsc.ar` voices. Partials `[5, 7, 9, 11, 13]` assigned round-robin to 12 voices (so some partials are doubled with independent jitter).
- **Per-voice random onset offsets:**
  - Must be generated at SynthDef-construction time, NOT in the UGen graph. Use `var onsetOffsets = Array.fill(12, { rrand(0.0, 0.015) });` at the top of the SynthDef function. `rrand` evaluated inside the SynthDef function body fires once per `Synth(...)` call — this is the desired behaviour and is the SC idiom.
- **Per-voice freq:**
  ```
  fSafe = fund.clip(20, SampleRate.ir * 0.1);   // 1/10 SR — partial × 13 still inside Nyquist
  partial = partials[i % 5];
  voiceFreq = fSafe * partial * LFNoise2.kr(1.5 + (i*0.1)).range(1 - jitter, 1 + jitter);
  ```
- **Per-voice envelope (staggered onsets, longer grain quality):**
  ```
  Env.perc(atk + (i * 0.007) + onsetOffsets[i],
           rel * (0.7 + (i * 0.02)),
           curve: -4)
  ```
  used as `EnvGen.kr(env)` (NOT `doneAction: 2` per voice — the outer envelope owns the free).
- **Per-voice amp shaping:** `LFNoise2.kr(0.8 + (i*0.06)).range(0.3, 1.0)`
- **Sum / shape:**
  ```
  sig = Mix(voices) * (1/12);
  ```
- **Outer envelope (owns lifecycle):** `EnvGen.kr(Env.linen(0.01, rel * 1.2, 0.02), doneAction: 2)` applied as `sig = sig * outerEnv * amp`.
- **Output:**
  ```
  Out.ar(out,    Pan2.ar(sig, pan));
  Out.ar(fx_bus, Pan2.ar(sig * 0.35, pan));                  // K.1: flockung 0.35
  ```

### `\binde` — narrow-band noise / formant cluster

- **Args:** `out=0, fx_bus=18, freq=1100, rq=0.021, amp=0.18, atk=1.5, rel=4.0, gate=1, pan=0`
- **Source:** one `PinkNoise.ar` shared by all 4 BPFs.
- **Filter bank (4 parallel BPF):**
  ```
  freqs = [freq, freq*1.003, freq*0.998, freq*1.005].clip(20, SampleRate.ir * 0.45);
  rqs   = [rq, rq*1.22, rq*0.88, rq*1.07];
  mods  = LFNoise2.kr([0.13, 0.19, 0.11, 0.17]).range(0.5, 1.0);   // 4-element multichannel
  bands = (0..3).collect { |i|
      BPF.ar(noise, freqs[i], rqs[i]) * mods[i] * (rqs[i].reciprocal.sqrt * 0.35)
  };
  sig = Mix(bands);
  ```
- **Envelope:** `EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2)`
- **Shape:** `sig = sig * env * amp.lag(0.05);`
- **Output:**
  ```
  Out.ar(out,    Pan2.ar(sig, pan.lag(0.05)));
  Out.ar(fx_bus, Pan2.ar(sig * 0.45, pan.lag(0.05)));        // K.1: binde 0.45
  ```

### `\schliere` — allpass diffusion + drifting comb + chorus shimmer

- **Args:** `out=0, fx_bus=18, freq_lo=200, freq_hi=1800, amp=0.14, atk=6.0, rel=6.0, gate=1, pan=0`
- **Source:** `WhiteNoise.ar * 0.5`
- **Diffusion stage** — 6 `AllpassC.ar` in series:
  ```
  diffRates = [0.17, 0.23, 0.31, 0.19, 0.27, 0.21];          // Hz, incommensurate, all ≤ 0.5
  sig = noise;
  diffRates.do { |rate|
      var dt = LFNoise2.kr(rate).range(0.008, 0.06);
      sig = AllpassC.ar(sig, 0.08, dt, 0.6);                  // maxdelay 0.08 s, decay 0.6 s
  };
  ```
- **Comb resonance** (unchanged drift logic from baseline, max delay 0.01):
  ```
  loSafe   = freq_lo.clip(20, SampleRate.ir * 0.45);
  hiSafe   = freq_hi.clip(20, SampleRate.ir * 0.45);
  drift1   = LFNoise2.kr(0.013).range(0, 1);
  drift2   = LFNoise2.kr(0.019).range(0, 1);
  combFreq = ((drift1 * 0.6) + (drift2 * 0.4)).linexp(0, 1, loSafe, hiSafe);
  delayT   = combFreq.reciprocal.clip(0.0001, 0.01);
  sig      = CombC.ar(sig, 0.01, delayT, 6.0);
  ```
- **Chorus shimmer** (added to dry pre-pan path):
  ```
  shimmer = DelayC.ar(sig, 0.005, LFNoise2.kr(0.33).range(0.001, 0.004));
  sig     = sig + (shimmer * 0.3);
  ```
- **Envelope:** `EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2)`
- **Output (low fx send — schliere is already self-diffuse):**
  ```
  Out.ar(out,    Pan2.ar(sig * env * amp,         pan));
  Out.ar(fx_bus, Pan2.ar(sig * env * amp * 0.15, pan));     // K.1: schliere 0.15
  ```

### `\kratzer` — soft high-band grain cloud

- **Args:** `out=0, fx_bus=18, amp=0.15, atk=0.015, rel=0.25, hpf=5000, pan=0`
- **Source (primary):** `GrainNoise.ar`
  - `trigger = Impulse.ar(LFNoise2.kr(1.0).range(30, 60))` — grain density modulated smoothly (no LFNoise0)
  - `dur = LFNoise1.kr(2).range(0.005, 0.020)`
  - `panGrain = LFNoise1.kr(4).range(-0.35, 0.35)`
  - `envBufNum = -1`
- **Fallback (if GrainNoise unavailable):** `WhiteNoise.ar * LFNoise2.kr(8).range(0.2, 1.0)` — smooth-noise gating, never `LFNoise0`. The reference Section C.6 explicitly forbids the mechanical-chop quality of stepped gating.
- **Filter:** `HPF.ar(sig, hpf.clip(1000, SampleRate.ir * 0.45))`
- **Outer envelope:** `EnvGen.kr(Env.perc(atk, rel, curve: -4), doneAction: 2)`
- **Output:**
  ```
  Out.ar(out,    Pan2.ar(sig * env * amp,         pan));
  Out.ar(fx_bus, Pan2.ar(sig * env * amp * 0.15, pan));     // K.1: kratzer 0.15
  ```

### `\firnis` — 9-voice ultrasonic shimmer

- **Args:** `out=0, fx_bus=18, amp=1.0, atk=8.0, rel=8.0, gate=1`
- **Frequencies (9 fixed, Hz):** `[12640, 13110, 14790, 16030, 17880, 12900, 13500, 15200, 16800]`
- **Per-voice slow AM:**
  - Rates (Hz): `[0.052, 0.073, 0.061, 0.089, 0.043, 0.067, 0.055, 0.081, 0.048]`
  - `perVoiceAM[i] = LFNoise2.kr(amRates[i]).range(0.15, 1.0)`
- **Cross-AM (subtle ±2.5 % scintillation):**
  - `crossAM[i] = (1 + LFNoise2.kr(0.021 + i*0.003).range(-0.025, 0.025))`
- **Per-voice amplitude constant:** `0.010` (rebalanced from 0.015 for the extra voices).
- **Construction:**
  ```
  voices = freqs.collect { |f, i| SinOsc.ar(f) * 0.010 * perVoiceAM[i] * crossAM[i] };
  sig    = Splay.ar(voices, 0.55);
  sig    = LPF.ar(sig, 20000);                              // aliasing guard
  ```
- **Envelope:** `EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2)`
- **Output (high reverb send — shimmer wants space):**
  ```
  Out.ar(out,    sig * env * amp.lag(0.1));
  Out.ar(fx_bus, sig * env * amp.lag(0.1) * 0.60);          // K.1: firnis 0.60
  ```
  `\firnis` writes a stereo signal (Splay output) directly — no Pan2.

### `\tape_reverb` — warm, slightly unstable diffuse reverb (persistent)

- **Args:** `in=18, out=20, wet=0.85`
  - `in`  = `~busFxSend.index`
  - `out` = `~busFxReturn.index`
- **Body:**
  1. **Read send bus:** `var sig = In.ar(in, 2);`
  2. **Pre-delay (tape head spacing):** `sig = DelayC.ar(sig, 0.05, 0.012);` (12 ms)
  3. **8 AllpassC, 4 per channel, independent rates** to preserve stereo:
     ```
     ratesL = [0.17, 0.24, 0.19, 0.31];
     ratesR = [0.21, 0.16, 0.28, 0.23];
     var diffL = sig[0];
     var diffR = sig[1];
     ratesL.do { |r| diffL = AllpassC.ar(diffL, 0.08, LFNoise2.kr(r).range(0.010, 0.070), 1.2) };
     ratesR.do { |r| diffR = AllpassC.ar(diffR, 0.08, LFNoise2.kr(r).range(0.010, 0.070), 1.2) };
     ```
  4. **Density combs (2, one per channel):**
     ```
     var combL = CombC.ar(diffL, 0.5, 0.087 + LFNoise2.kr(0.21).range(-0.002, 0.002), 2.5);
     var combR = CombC.ar(diffR, 0.5, 0.113 + LFNoise2.kr(0.17).range(-0.002, 0.002), 2.8);
     ```
  5. **Tape HF rolloff (slow warmth modulation):**
     ```
     var rolloff = 3500 + LFNoise2.kr(0.09).range(-300, 300);
     var procL = LPF.ar(combL, rolloff);
     var procR = LPF.ar(combR, rolloff);
     ```
  6. **Output:** `Out.ar(out, [procL, procR] * wet);`
- **Lifecycle:** persistent for the whole piece. Spawned in `~ungrundSetup` before the Routine starts. Freed in `~ungrundReset`.

### `\ping_delay` — filtered ping-pong delay (persistent)

- **Args:** `in=18, out=20, wet=0.5, feedback=0.52`
  - `in`  = `~busFxSend.index` (same as tape_reverb)
  - `out` = `~busFxReturn.index` (same — both fx Synths sum on the return)
- **Body — LocalIn/LocalOut feedback** (preferred over CombC for explicit LPF-in-feedback):
  ```
  var stereoIn = In.ar(in, 2);
  var mono     = Mix(stereoIn) * 0.5;
  var delayL   = 0.37 + LFNoise2.kr(0.11).range(-0.004, 0.004);
  var delayR   = 0.53 + LFNoise2.kr(0.09).range(-0.004, 0.004);
  var fb       = LocalIn.ar(2);                              // [fbL, fbR]
  var echoL    = mono + (LPF.ar(fb[1], 2000) * feedback);    // R feeds back to L
  var echoR    = mono + (LPF.ar(fb[0], 2000) * feedback);    // L feeds back to R
  var outL     = DelayC.ar(echoL, 0.6, delayL);
  var outR     = DelayC.ar(echoR, 0.6, delayR);
  LocalOut.ar([outL, outR]);
  Out.ar(out, [outL, outR] * wet);
  ```
- **Footgun:** `LocalIn` and `LocalOut` must be in the same SynthDef. One block (≈ 64 samples) of latency on the first iteration is acceptable.
- **Lifecycle:** persistent. Spawned in `~ungrundSetup`. Freed in `~ungrundReset`.

### `\ung_master` — sums dry + fx return, LeakDC, Limiter

- **Args:** `in_dry=16, in_fx=20, out=0, master_amp=1.0`
- **Body:**
  ```
  var dry = In.ar(in_dry, 2);
  var fx  = In.ar(in_fx,  2);
  var sig = dry + fx;
  sig = LeakDC.ar(sig);
  sig = Limiter.ar(sig, 0.95, 0.01);
  sig = sig * master_amp.lag(0.05);
  Out.ar(out, sig);
  ```
- **Breaking change:** the baseline `\ung_master` accepts a single `in` arg. The Routine and `~ungrundSetup` must pass `in_dry` and `in_fx` explicitly using bus `.index` — no hardcoded indices.

### `\amp_watcher` — unchanged

Keep exactly as currently implemented in `ungrund_0001.scd:316-323`. Reads `~busMonade`, computes RMS via `Amplitude.kr`, fires `Trig1.kr` on the rising edge above `threshold`, sends `/ung/threshold` via `SendReply.kr`. No changes.

## Signal flow

```
Audio buses:
  ~busMaster   = Bus.audio(s, 2)   // stereo dry master
  ~busMonade   = Bus.audio(s, 1)   // mono pre-pan monade for amp_watcher
  ~busFxSend   = Bus.audio(s, 2)   // stereo reverb/delay send (accumulating)
  ~busFxReturn = Bus.audio(s, 2)   // stereo fx return (tape_reverb + ping_delay sum here)

Groups (head -> tail):
  ~grpSrc   Group.new(s, \addToHead)    // all voice synths
  ~grpAnl   Group.after(~grpSrc)        // amp_watcher
  ~grpFx    Group.after(~grpAnl)        // tape_reverb, ping_delay, ung_master

Per-class routing:
  \monade   -> ~busMaster (Pan2)       + ~busMonade (mono pre-pan) + ~busFxSend * 0.55
  \rissz    -> ~busMaster (Pan2)                                   + ~busFxSend * 0.30
  \flockung -> ~busMaster (Pan2)                                   + ~busFxSend * 0.35
  \binde    -> ~busMaster (Pan2)                                   + ~busFxSend * 0.45
  \schliere -> ~busMaster (Pan2)                                   + ~busFxSend * 0.15
  \kratzer  -> ~busMaster (Pan2)                                   + ~busFxSend * 0.15
  \firnis   -> ~busMaster (Splay stereo)                           + ~busFxSend * 0.60

Effect synths (in ~grpFx, after all source/analysis):
  \tape_reverb : In.ar(~busFxSend, 2)  -> Out.ar(~busFxReturn, 2)
  \ping_delay  : In.ar(~busFxSend, 2)  -> Out.ar(~busFxReturn, 2)   // accumulates on the same return
  \ung_master  : In.ar(~busMaster, 2) + In.ar(~busFxReturn, 2) -> Out.ar(0, 2)

Channel-count audit:
  Voice writes to ~busFxSend: stereo (Pan2 or Splay) — matches 2-ch In.ar in fx synths.
  ~busMaster: stereo from all dry writes — matches 2-ch In.ar in \ung_master.
  ~busFxReturn: stereo writes from both fx synths — matches 2-ch In.ar in \ung_master.
```

The group ordering — source → analysis → fx — guarantees that the master synth, the reverb, and the delay all read sums of *the same block's* upstream writes.

## Scheduling

**Unchanged from baseline `ungrund_0001.scd:107-182`.** The substratumwalk Routine drives the piece:

- `t = 0`: spawn `\monade` with `out=~busMaster.index, mon_bus=~busMonade.index, fx_bus=~busFxSend.index, freq=94, amp=0.25, atk=6.0, rel=12.0, pan=0`.
  Note `amp=0.25` (Section K.4 — was 0.4 in baseline).
- `t = 4`: spawn `\firnis` with `out=~busMaster.index, fx_bus=~busFxSend.index, amp=1.0, atk=8.0, rel=8.0`; spawn `\amp_watcher` in `~grpAnl` (unchanged).
- `t = 4`: set `~ungRissActive = true`.
- `t = 4 … 348`: OSCdef `\ung_threshold` spawns `\rissz` voices on rising-edge events with refractory 8 s. Update spawn args in the OSCdef body to include `fx_bus: ~busFxSend.index` and the K.4 amplitude range:
  ```
  Synth(\rissz, [
      \out,    ~busMaster.index,
      \fx_bus, ~busFxSend.index,
      \amp,    exprand(0.25, 0.55),                // K.4: was exprand(0.4, 0.85)
      \pan,    rrand(-0.6, 0.6),
      \hpf,    200,                                 // K.1 / Section C.2: 200 Hz
      \rel,    rrand(0.30, 0.40)                    // softened from 0.04..0.07
  ], ~grpSrc);
  ```
- `t = 348`: `~ungRissActive = false; ~monade.set(\gate, 0); ~firnis.set(\gate, 0);`
- `t = 360`: routine ends, `~ungrundReset.value(true)` runs.

**New requirement:** `\tape_reverb` and `\ping_delay` are spawned in `~ungrundSetup` AFTER the buses are allocated and AFTER `s.sync`, BEFORE any voice — they are persistent like `\ung_master`. Spawn order inside `~grpFx`:
  1. `\tape_reverb`  → `[\in, ~busFxSend.index, \out, ~busFxReturn.index, \wet, 0.85]`
  2. `\ping_delay`   → `[\in, ~busFxSend.index, \out, ~busFxReturn.index, \wet, 0.5, \feedback, 0.52]`
  3. `\ung_master`   → `[\in_dry, ~busMaster.index, \in_fx, ~busFxReturn.index, \out, 0, \master_amp, 1.0]`

Within `~grpFx` the order does not matter functionally (all read/write happens within one block), but the spawn sequence above is the documented contract.

## Lifecycle

- `s.waitForBoot { … }` wraps the SynthDef.add batch and the `s.sync` that follows.
- **SynthDef.add batch:** 11 defs total — `\monade, \rissz, \flockung, \binde, \schliere, \kratzer, \firnis, \tape_reverb, \ping_delay, \ung_master, \amp_watcher`. (`\zäsur` is not a SynthDef; ungrund.0001 does not use `\flockung`, `\binde`, `\schliere`, or `\kratzer` at runtime — but all 11 SynthDefs are added so the same file supports ungrund.0002/0003 later.)
- **`s.sync`** after the SynthDef batch.
- **Bus allocation (4 buses):**
  - `~busMaster = Bus.audio(s, 2)`
  - `~busMonade = Bus.audio(s, 1)`
  - `~busFxSend = Bus.audio(s, 2)`
  - `~busFxReturn = Bus.audio(s, 2)`
  All in `~ungrundSetup`, followed by a `s.sync`.
- **Persistent synths in `~grpFx`:** `\tape_reverb`, `\ping_delay`, `\ung_master` — held in `~rev`, `~dly`, `~mst`.
- **Cleanup block (`~ungrundReset`):** extend the existing block to free the new buses and synths.
  ```
  if(~ungR.notNil)     { ~ungR.stop; ~ungR = nil };
  OSCdef(\ung_threshold).notNil.if({ OSCdef(\ung_threshold).free });
  if(~watcher.notNil)  { ~watcher.free;  ~watcher = nil };
  if(~mst.notNil)      { ~mst.free;      ~mst = nil };
  if(~rev.notNil)      { ~rev.free;      ~rev = nil };
  if(~dly.notNil)      { ~dly.free;      ~dly = nil };
  if(~monade.notNil)   { ~monade.free;   ~monade = nil };
  if(~firnis.notNil)   { ~firnis.free;   ~firnis = nil };
  if(~grpSrc.notNil)   { ~grpSrc.freeAll; ~grpSrc.free; ~grpSrc = nil };
  if(~grpAnl.notNil)   { ~grpAnl.freeAll; ~grpAnl.free; ~grpAnl = nil };
  if(~grpFx.notNil)    { ~grpFx.freeAll;  ~grpFx.free;  ~grpFx  = nil };
  if(~busMaster.notNil)   { ~busMaster.free;   ~busMaster   = nil };
  if(~busMonade.notNil)   { ~busMonade.free;   ~busMonade   = nil };
  if(~busFxSend.notNil)   { ~busFxSend.free;   ~busFxSend   = nil };
  if(~busFxReturn.notNil) { ~busFxReturn.free; ~busFxReturn = nil };
  Pdef.all.do(_.clear);
  Ndef.all.do(_.clear);
  ```
- **Stopping condition (from reference §H):** at t = 360 s the monade envelope has reached zero; the routine calls `~ungrundReset.value(true)`. Any rissz still in its release tail completes naturally because it owns `doneAction:2`. Reverb tails may continue ringing inside `\tape_reverb` for ~3–5 s after the last source write — this is expected. The test plan accepts up to t ≈ 375 s for true silence. The reset happens at t = 360 regardless; the reverb tail is audible as the bus drains before the fx synths are freed.

## DSP constraints

1. **Nyquist clamp** on every controllable frequency: `freq.clip(20, SampleRate.ir * 0.45)` is mandatory. For `\flockung`, use `fund.clip(20, SampleRate.ir * 0.1)` because the highest partial is `× 13`.
2. **`Lag.kr` smoothing** on `amp` and `pan` for sustained classes (`\monade`, `\binde`, `\schliere`, `\firnis`). Lag time: 0.05 s for `amp` and `pan`, 0.1 s for `\firnis.amp`. **No lag** on event-class amps (`\rissz`, `\flockung`, `\kratzer`) — the arg is set at spawn and never changed.
3. **AllpassC delay-time modulation:** rates strictly ≤ 0.5 Hz. Use `LFNoise2` (smooth quadratic). Never `LFNoise0` for delay-line modulation — stepped delay changes produce zipper artefacts.
4. **CombC max delay:** `\tape_reverb` combs use max 0.5 s with a tiny modulation (±0.002 s) around 0.087 / 0.113 s — well inside the bound.
5. **LocalIn/LocalOut** in `\ping_delay`: must appear in the same SynthDef. One-block latency on first iteration accepted.
6. **`~busFxSend` accumulation:** SC's `Out.ar` adds to bus contents. The reference send levels (0.15–0.60 per class) have been budgeted with this in mind. Worst-case simultaneous send energy (monade 0.55 + firnis 0.60 + rissz transient 0.30) sums to roughly the equivalent of an unattenuated signal; with the source amp reductions (Section K.4) the post-reverb peak target is ≤ −4 dBFS, and the `Limiter.ar(0.95, 0.01)` in `\ung_master` is the safety net.
7. **DC blocking:** `LeakDC.ar` only at the master after the dry+fx sum. The Limiter follows.
8. **Aliasing guard on `\firnis`:** keep the explicit `LPF.ar(sig, 20000)` after Splay even though the SinOsc voices are all below 18 kHz — the Splay arithmetic and the cross-AM sidebands can place energy near Nyquist on 44.1 kHz systems.
9. **Per-event SynthDef construction is forbidden.** Use `Synth(\name, args, group)` against the pre-added defs — never `{ … }.play` in the OSCdef callback (it would re-compile a SynthDef on every rissz event).
10. **Gain ceiling:** master peak ≤ −4 dBFS expected, Limiter set to 0.95. Headroom: ≥ 6 dB nominal, < 1 dB after limiter engagement.

## Mapping check (reference ↔ code)

Every audible parameter declared in `docs/reference_v2.md` Section H is realised in code:

| Reference parameter | Code parameter | Notes |
|---------------------|----------------|-------|
| `monade.freq` (94 Hz, fixed) | `\monade` arg `freq=94` passed at spawn | base of the 7-voice detune cluster |
| `monade.amp` (loudness) | `\monade` arg `amp=0.25` (K.4 revision) | with `.lag(0.05)` |
| `monade.atk`, `monade.rel` | `\monade` args `atk=6.0, rel=12.0` | `Env.asr(atk, 1, rel, curve:-4)` |
| `monade` warmth / "breathing" | per-voice `LFNoise2` detune + amp shaping + cross-AM, `LPF.ar(900)` | Section C.1 synthesis premise |
| `riß.threshold` (RMS trigger) | `\amp_watcher` arg `threshold=0.30` | rising edge → OSC `/ung/threshold` |
| `riß.refractory` | `~ungMinInterval = 8.0` in OSCdef gate | 8 s minimum between events |
| `riß.amp_min/max` (K.4 revision) | `exprand(0.25, 0.55)` in OSCdef body | was 0.40–0.85 |
| `riß` soft-grain identity | `\rissz` `GrainSin.ar` with density 60–100/s, scattered freq, Hann grains | Section C.2 |
| `firnis.freqs` (now 9 voices) | `\firnis` frequency array `[12640, 13110, 14790, 16030, 17880, 12900, 13500, 15200, 16800]` | extended from 5 → 9 per Section C.8 |
| `firnis.amp_each` (K.4 revision) | per-voice constant `0.010` | was 0.015 |
| `firnis.lfn_rate` (per-voice AM rates) | array `[0.052, 0.073, 0.061, 0.089, 0.043, 0.067, 0.055, 0.081, 0.048]` Hz | slower / deeper than baseline |
| `firnis` scintillation | per-voice cross-AM `(1 + LFNoise2(...).range(-0.025, 0.025))` | Section C.8 |
| `firnis` width | `Splay.ar(voices, 0.55)` | Section C.8: 0.55 was 0.5 |
| `tape_reverb` send per class | per-class fx-send multiplier in each SynthDef's `Out.ar(fx_bus, ...)` | Section K.1: monade 0.55, rissz 0.30, firnis 0.60, etc. |
| `tape_reverb` architecture | `DelayC` pre-delay + 8 `AllpassC` (4 L / 4 R) + 2 `CombC` + `LPF` rolloff | Section K.1 |
| `ping_delay` architecture | `LocalIn`/`LocalOut` ping-pong, L 0.37 s / R 0.53 s, LPF 2 kHz in feedback | Section K.2 |
| `ping_delay` send per class | rolled into the same `fx_bus` write (Section K.2: monade 0.20 / rissz 0.25 — currently merged into the unified send) | see Known footguns #11 below |
| Stopping condition | Routine `~ungR` ends at t = 360, calls `~ungrundReset` | reference §H "monade fades, voices freed" |
| Master peak ≤ −4 dBFS | `\ung_master` Limiter at 0.95, K.4-revised source amps | Section K.4 |

Section F mapping rows for ungrund.0001's three active classes (`monade`, `riß`, `firnis`):

| Dimension | Class | Code parameter |
|-----------|-------|----------------|
| Pitch / centroid | monade.freq, firnis.freqs | `\monade` `freq` arg; `\firnis` SinOsc freq array |
| Bandwidth | monade ≈ 0 (sine); firnis sine-cluster | LPF 900 in monade; LPF 20000 in firnis |
| Event density | rissz threshold + refractory | `\amp_watcher` + OSCdef gate |
| Attack-sharpness | monade.atk; rissz.atk | `Env.asr` atk arg; `Env.perc` atk arg |
| Decay law | exponential per class | curve −4 on all Env shapes |
| Spatial position | monade pan; rissz pan; firnis Splay | `\monade` Pan2; `\rissz` Pan2; `\firnis` Splay 0.55 |
| Loudness register | monade.amp; rissz exprand range; firnis amp_each | K.4 revised values |

The reference's other five classes (`\flockung`, `\binde`, `\schliere`, `\kratzer`, `\zäsur`) are not used by ungrund.0001 but are added to the server so the same file supports ungrund.0002 (`tafel`) and ungrund.0003 (`raster`) later without re-engineering the bus topology.

## Known footguns

1. **`rrand` inside SynthDef body** (used in `\flockung` for onset offsets) evaluates *once per `Synth(\name, …)` call*, not at `SynthDef.add` time and not on every UGen sample. This is correct SC behaviour and produces per-instance randomisation. Do not try to "fix" it with `Rand.kr` unless you specifically want server-side random — the design here wants language-side per-instance constants so every flockung event has its own fixed micro-staggering.
2. **`GrainSin.ar` / `GrainNoise.ar` availability** — both ship with stock SC since 3.9. If the target SC is older, fall back to the documented multi-`SinOsc` cloud (`\rissz`) and smooth `WhiteNoise * LFNoise2` (`\kratzer`). Decide at SynthDef-add time, never at run time.
3. **Do not use `LFSaw.ar` or `LFPulse.ar` as audio sources.** They are LFO-only — non-bandlimited. None of the SynthDefs above need them.
4. **`Out.ar` is summing, not assigning.** Multiple voices writing to `~busFxSend` accumulate. The send-level coefficients (0.15–0.60) account for this; do not "normalise" away because the bus seems hot.
5. **`\ung_master` reads two buses now.** Always pass `\in_dry, ~busMaster.index, \in_fx, ~busFxReturn.index`. Never hardcode `16` or `20`.
6. **OSCdef survives re-evaluation.** Use the `OSCdef(\ung_threshold, …)` keyed-by-symbol form (already idiomatic in baseline). On re-evaluation it overwrites the function and does not stack callbacks. `~ungrundReset` calls `.free` defensively.
7. **GUI mutations from server data** (the elapsed-time tick) must go through `.defer` — baseline already does this in `~ungrundUpdateTime` and `~ungrundSetStatus`; preserve that.
8. **`s.sync` is needed twice**: once after `SynthDef.add` batch (so the server has the defs before any Synth is asked for), once after `Bus.audio` allocations in `~ungrundSetup` (so bus indices are valid by the time we spawn the persistent fx + master synths).
9. **`AllpassC` decay parameter is *not* a Q.** It is the −60 dB ring time of the allpass; 0.6 in diffusion is fine, 1.2 in `\tape_reverb` makes the bath denser. Values above ~5 s start to ring as comb resonances rather than diffuse — do not increase.
10. **Reverb tail past t = 360.** The Routine frees `\tape_reverb` and `\ping_delay` at t = 360 (via `~ungrundReset`). This cuts the tail mid-decay. If a smooth fade is desired, add a separate `\fade_out` step that ramps `\tape_reverb.set(\wet, 0)` and `\ping_delay.set(\wet, 0)` over ~5 s before the free. The reference does not require this; the baseline behaviour is acceptable.
11. **Merged ping-pong send vs reference K.2 send-per-class.** The reference §K.2 lists distinct ping_delay sends (monade 0.20, rissz 0.25, flockung 0.20, others 0.0). The implementation routes every voice's fx send through a single bus that both `\tape_reverb` and `\ping_delay` read — so a voice that should send to reverb but NOT to delay still excites the delay. For ungrund.0001 the only active voices are monade (intended to feed both) and rissz (intended to feed both) and firnis (intended to feed only reverb). To honour the K.2 firnis = 0.0 ping_delay constraint cleanly, either:
    - (a) accept the small ping_delay contribution from firnis as part of the warm bath (recommended for ungrund.0001 — the high-frequency content sits at the edge of audibility and the delay LPF at 2 kHz attenuates it heavily); or
    - (b) split into two send buses (`~busRevSend`, `~busDlySend`) and double every voice's `Out.ar(fx_bus, …)` write. This is the strict reading of K.1/K.2.
    Implement (a) for now. Note it; revisit if firnis-through-delay reads as unwanted glassy ping-pong tail.

## Test plan

1. File evaluates without compile errors. All 11 SynthDefs print "ungrund.0001 — synthdefs ready."
2. At t ≈ 6 s: `\monade` cluster is audible, warm, multi-layered. No single-voice tone is identifiable.
3. At t ≈ 6 s: reverb tail audible — the monade has spatial depth, not the dry sine of the baseline.
4. At t ≈ 12 s: `\firnis` shimmer present. On headphones, the 9-voice spread is wider than the baseline 5-voice version.
5. By t ≈ 60 s: first `\rissz` event has fired as a soft granular burst. No hard click; no sharp transient.
6. `\rissz` events are at least 8 s apart for the full 4–348 s window.
7. At t = 360 s: routine ends, reset runs. Audible silence by t ≈ 363–365 s (reverb tail completes via bus drain before the fx synths are freed).
8. `Cmd-.` at any point leaves a clean server (no orphan Synths, no leaked buses). Verify with `s.queryAllNodes` after `Cmd-.`.
9. Re-evaluating the file does not stack OSCdef callbacks (single `/ung/threshold` listener).
10. Peak meter at master never exceeds −0.5 dBFS (Limiter at 0.95 protects, but should not be hit hard).
