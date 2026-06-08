# Reference — `archives/Texture.wav` → `zeta` (vinyl/tape surface noise)

Measured spectral/temporal analysis of `archives/Texture.wav`, to be realised as the
`Ndef(\zeta)` sound layer. This is the **composer reference** for this layer: every
audible dimension below must trace into the implementation.

## Source file

| Property | Value |
|----------|-------|
| Path | `archives/Texture.wav` |
| Format | WAV PCM s16le, mono, 44100 Hz, 16-bit |
| Duration | 30.72 s |

## What it is

Low-level **continuous colored-noise bed** (the "surface" / medium hiss-rumble of
worn vinyl or aged tape) with **sparse-to-moderate broadband impulsive clicks/pops
(crackle)** riding on top. It is NOT bright hiss and NOT a mains-hum recording —
the energy is band-limited and mid-weighted, and there is no discrete 50/60 Hz tone.

Two layers to synthesize:
1. **Bed** — steady, quiet, mid-tilted filtered noise.
2. **Crackle** — impulsive transients, wide dynamic spread (mostly tiny ticks, the
   occasional loud pop), broadband but HF-rich enough to read as "clicks".

## Measured level / dynamics (ffmpeg astats + volumedetect)

| Metric | Value | Reading |
|--------|-------|---------|
| Peak level | −2.5 dB | a few near-full-scale pops |
| RMS (mean) | −37.0 dB | the bed is quiet |
| RMS peak | −23.7 dB | loudest 1-s windows (cluster of pops) |
| **Crest factor** | **53.2** | very spiky → impulsive clicks over a quiet bed |
| Peak count | 2 | isolated maxima (rare big pops) |
| Noise floor | −29.9 dB | |
| Dynamic range | 93.8 dB | |
| DC offset | −0.00002 | negligible |
| Zero-crossing rate | 0.168 | moderately HF content |

**Implication:** the loud transients are ~14 dB above the bed's mean RMS, and the
absolute peaks ~34 dB above it. Crackle amplitude must be *exponentially* distributed
(many small, few large), not uniform.

## Measured spectral tilt — octave-band RMS (bandpass + volumedetect)

| Band (Hz) | mean dB | shape |
|-----------|---------|-------|
| 20 – 80 | −54.2 | rolled off (sub rumble weak) |
| 80 – 250 | −48.5 | rising |
| 250 – 800 | −44.0 | rising |
| **800 – 2500** | **−40.5** | **peak — energy centroid here** |
| 2500 – 6000 | −42.8 | gentle fall |
| 6000 – 12000 | −48.4 | falling |
| 12000 – 20000 | −58.5 | rolled off hard (no bright air) |

**Bed profile:** band-pass shaped noise, broad hump centered ~1–1.5 kHz, roughly
symmetric on a log axis. ~ −6 dB/oct skirts each side. Pink/brown-tilted noise
sent through a wide band-pass (≈ HPF 150–250 Hz + LPF 6–8 kHz, soft slopes) is the
simplest match. There is NO content worth speaking of above 12 kHz — do not make it
hiss-bright.

## Tonal check (narrow bandpass, w=8 Hz)

50 Hz −63 · 60 Hz −64 · 100 Hz −62 · 120 Hz −61 · 150 Hz −58 dB — **flat, no hum
peak**. Do not add a discrete mains tone. (A very low, very quiet broadband
rumble < 150 Hz is acceptable as "motor/turntable" floor but must stay ≥ 15 dB under
the mid hump.)

## Click / crackle density (HPF 2 kHz, gate at −32 dB, min 20 ms)

~96 above-threshold transient bursts over 30.7 s → **≈ 3 audible pops/s average**,
irregular (clustered, not metronomic). Under those audible pops sits a **denser,
finer crackle bed** of tiny ticks (much lower in level, continuous). So model crackle
as (at least) two strata:
- **fine crackle**: dense (~20–60/s), tiny amplitude, short — the "frying" texture;
- **pops**: sparse (~1–4/s), exponential amplitude up to near-peak, slightly longer
  decay, broadband with a low-frequency "thock" component on the largest ones.

Clicks are short impulses (sub-millisecond to a few ms), broadband; the largest read
as a vinyl "pop" with a tiny resonant body, not pure white spikes.

## Visual confirmation

- **Waveform** (`/tmp/tex_wave.png` at analysis time): near-flat quiet line with
  sparse vertical spikes across the whole 30 s — quiet bed + discrete clicks.
- **Spectrogram** (`/tmp/tex_spectrum.png`): continuous low-mid-weighted noise band
  with thin full-height vertical streaks = broadband clicks; no horizontal tonal
  lines (confirms: no hum, no pitched content).

## Synthesis target (summary for implementation)

| Dimension | Target |
|-----------|--------|
| Bed source | colored noise (pink/brown tilt), band-passed ≈ 150 Hz – 7 kHz, hump ~1.2 kHz |
| Bed level | quiet, steady; ≈ −37 dB RMS relative to the loud pops |
| Bed motion | very slow amplitude/colour drift (medium "wow"), subtle, no chopping |
| Fine crackle | dense Dust (~20–60/s), tiny exponential amplitude, ~0.5–3 ms decay, HF-leaning |
| Pops | sparse Dust (~1–4/s), exponential amplitude → near peak, ~3–15 ms decay, broadband + low "thock" body on the loudest |
| Spectral ceiling | hard roll-off above ~8–12 kHz (NOT bright) |
| Sub | optional very low quiet rumble < 150 Hz, ≥ 15 dB below hump |
| Crest | overall very high — preserve the quiet-bed / loud-pop contrast |

## Constraints inherited from the existing `App/synths/zeta.scd` (MUST keep)

The implementation **redesigns the synthesis** of the existing `zeta` layer toward
this vinyl/tape texture, but must preserve the App-integration architecture already
in `App/synths/zeta.scd`:

- `~spec_zeta = ( name: \zeta, params: [ ... ] )` config block — driven slider/
  randomiser/preset machinery (0_lib.scd). Each controllable dimension above becomes
  a `~spec_zeta.params` row **and** a matching `Ndef(\zeta)` arg.
- Param grouping: `group: \freq` for the frequency-defining controls (bed band-pass
  edges, any resonant "body" freqs of pops) so `~rndFreq.(\zeta)` randomises pitch-ish
  content; `group: \tone` for texture/density/amplitude controls so `~rndParams`
  randomises the environment.
- `Ndef(\zeta, { ... })` writes **stereo** to its own output (mixer reads it via
  Ndef routing; effect sends are done by the mixer, not the layer).
- §F panorama discipline: pan within ±0.4, slow.
- The self-registration tail: register `~ungSpecs[\zeta]`/`~ungVals[\zeta]`, apply
  `p.spec.default` to the Ndef, set `Ndef(\zeta).fadeTime`.
- Greek-letter naming throughout (`zeta` / `Ndef(\zeta)` / `~spec_zeta`).
- Premise hygiene: `LeakDC.ar` at the end; keep reverb-send expectation low (handled
  by mixer). Smoothing (`.lag`) on jumpy user controls. Clamp any user freq below
  Nyquist.
