// App/synths/delta.scd — UNGRUND class 4/8 `delta`, §C.4 `binde` (amended
// 2026-07-19): 5 glottal voices on the 94 Hz lattice, each IN PARALLEL into a
// 5-formant vocal BPF bank and a 4-mode Ringz plate bank; `metal` crossfades
// voice <-> plate. §C.4 bans hold: no glide, modulation ≤ 0.25 Hz.
// Spec + post-tuning deviations: docs/features/delta/dsp-spec.md.
// ~spec_delta — source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — 5 voice fundamentals (MIDI notes) on the 3-limit lattice
// from 94 Hz; group \tone — glottal source / vowel bank / plates /
// breathing / space.
~spec_delta = (
    name: \delta,
    params: [
        // --- group \freq: 5 voice fundamentals (MIDI notes) ---
        ( key: \f1, group: \freq, disp: \note,
          spec: ControlSpec(36, 84, \lin, 0, 48.71), reread: \cont, arMod: \freq ),  // 141 Hz ×3/2
        ( key: \f2, group: \freq, disp: \note,
          spec: ControlSpec(36, 84, \lin, 0, 53.71), reread: \cont, arMod: \freq ),  // 188 Hz ×2
        ( key: \f3, group: \freq, disp: \note,
          spec: ControlSpec(36, 84, \lin, 0, 60.72), reread: \cont, arMod: \freq ),  // 282 Hz ×3
        ( key: \f4, group: \freq, disp: \note,
          spec: ControlSpec(36, 84, \lin, 0, 65.71), reread: \cont, arMod: \freq ),  // 376 Hz ×4
        ( key: \f5, group: \freq, disp: \note,
          spec: ControlSpec(36, 84, \lin, 0, 72.72), reread: \cont, arMod: \freq ),  // 564 Hz ×6

        // --- group \tone: glottal source ---
        ( key: \amp, group: \tone,
          spec: ControlSpec(0.0, 0.5, \lin, 0, 0.18), reread: \cont, arMod: \lin ),  // layer level (§K.4)
        ( key: \voiced, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.8), reread: \cont, arMod: \lin ),  // phonation level
        ( key: \breath, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.3), reread: \cont, arMod: \lin ),  // aspiration level
        ( key: \bright, group: \tone,
          spec: ControlSpec(3.0, 20.0, \exp, 0, 9.0), reread: \contBlock, arMod: \freq ),  // glottal tilt (LPF = fund×bright)

        ( key: \detune, group: \tone, unit: " ct",
          spec: ControlSpec(0.0, 15.0, \lin, 0, 6.0), reread: \cont, arMod: \lin ),  // unison scatter
        ( key: \driftRate, group: \tone, unit: " Hz",
          spec: ControlSpec(0.02, 0.2, \exp, 0, 0.07), reread: [\seg, \driftRate], arMod: \rate ),  // detune wander (§C.4 ≤0.25)
        ( key: \jitter, group: \tone,
          spec: ControlSpec(0.0, 0.004, \lin, 0, 0.0015), reread: \cont, arMod: \lin ),  // aperiodic micro-jitter ≤0.4%
        ( key: \shimmer, group: \tone,
          spec: ControlSpec(0.0, 0.2, \lin, 0, 0.06), reread: \cont, arMod: \lin ),  // fast shallow amp flutter

        // --- group \tone: vowel bank ---
        ( key: \vowelSel, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.5), reread: \contBlock, arMod: \freq ),  // interpolate to next vowel
        ( key: \vowelDrift, group: \tone,
          spec: ControlSpec(0.0, 0.3, \lin, 0, 0.1), reread: \cont, arMod: \lin ),  // slow vowel wander (≤0.1 Hz)
        ( key: \formWidth, group: \tone,
          spec: ControlSpec(0.7, 2.0, \lin, 0, 1.0), reread: \cont, arMod: \freq ),  // bandwidth scale (static)
        ( key: \formTrack, group: \tone,
          spec: ControlSpec(0.0, 0.7, \lin, 0, 0.35), reread: \cont, arMod: \freq ),  // formant register tracking
        ( key: \ring, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.4), reread: \cont, arMod: \lin ),  // 2.6–3.6 kHz cluster gain
        ( key: \beatRate, group: \tone, unit: " Hz",
          spec: ControlSpec(0.05, 0.25, \exp, 0, 0.15), reread: [\seg, \beatRate], arMod: \rate ),  // §C.4 formant beating (≤0.25)

        // --- group \tone: metal plates ---
        ( key: \metal, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.35), reread: \cont, arMod: \lin ),  // bank crossfade (0 = choir)
        ( key: \plateQ, group: \tone,
          spec: ControlSpec(0.05, 3.0, \exp, 0, 0.9), reread: \contBlock, arMod: \freq ),  // plate ring time
        ( key: \plateSpread, group: \tone,
          spec: ControlSpec(0.0, 0.05, \lin, 0, 0.015), reread: \contBlock, arMod: \freq ),  // ring detune across voices

        // --- group \tone: breathing ---
        ( key: \breathDepth, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.5), reread: \cont, arMod: \lin ),  // dip ≤ −6 dB (§C.4)
        ( key: \breathRate, group: \tone, unit: " Hz",
          spec: ControlSpec(0.02, 0.25, \exp, 0, 0.08), reread: [\seg, \breathRate], arMod: \rate ),  // §C.4 period ≥ 4 s

        // --- group \tone: levels and space ---
        ( key: \voiceLevel, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.7), reread: \cont, arMod: \lin ),  // voice-sum level (pre amp)
        ( key: \panWidth, group: \tone,
          spec: ControlSpec(0.0, 0.3, \lin, 0, 0.22), reread: \cont, arMod: \lin ),  // §F: pan ≤ ±0.3
        ( key: \panRate, group: \tone, unit: " Hz",
          spec: ControlSpec(0.01, 0.5, \exp, 0, 0.06), reread: [\seg, \panRate], arMod: \rate )  // §F: slow pan drift
    ]
);


// ===== LOGIC — synthesis =============================================
// 5 voices: A (Blip ensemble + breath) -> B1 || B2 -> XFade2 on `metal` ->
// C (breath/shimmer/pan); sum -> LeakDC -> Limiter
Ndef(\delta, {
    // ar controls: declaration order = ~spec_delta row order. Slew floors are
    // contract §5: levels 5 ms, frequencies/rq/times 2 ms, LFN rates none at all
    var f1 = \f1.ar(48.71).lag(0.002);
    var f2 = \f2.ar(53.71).lag(0.002);
    var f3 = \f3.ar(60.72).lag(0.002);
    var f4 = \f4.ar(65.71).lag(0.002);
    var f5 = \f5.ar(72.72).lag(0.002);
    var amp         = \amp.ar(0.18).lag(0.005);
    var voiced      = \voiced.ar(0.8).lag(0.005);
    var breath      = \breath.ar(0.3).lag(0.005);
    var bright      = \bright.ar(9.0).lag(0.002);
    var detune      = \detune.ar(6.0).lag(0.005);
    var driftRate   = \driftRate.ar(0.07);
    var jitter      = \jitter.ar(0.0015).lag(0.005);
    var shimmer     = \shimmer.ar(0.06).lag(0.005);
    var vowelSel    = \vowelSel.ar(0.5).lag(0.002);
    var vowelDrift  = \vowelDrift.ar(0.1).lag(0.005);
    var formWidth   = \formWidth.ar(1.0).lag(0.002);
    var formTrack   = \formTrack.ar(0.35).lag(0.002);
    var ring        = \ring.ar(0.4).lag(0.005);
    var beatRate    = \beatRate.ar(0.15);
    var metal       = \metal.ar(0.35).lag(0.005);
    var plateQ      = \plateQ.ar(0.9).lag(0.002);
    var plateSpread = \plateSpread.ar(0.015).lag(0.002);
    var breathDepth = \breathDepth.ar(0.5).lag(0.005);
    var breathRate  = \breathRate.ar(0.08);
    var voiceLevel  = \voiceLevel.ar(0.7).lag(0.005);
    var panWidth    = \panWidth.ar(0.22).lag(0.005);
    var panRate     = \panRate.ar(0.06);

    var nyq, funds, nVoices = 5, nSubs = 3, nForms = 5;
    var voicedL, breathL, brightL, detuneL, driftRateK, jitterL, shimmerL;
    var vowelSelL, vowelDriftL, formWidthL, formTrackL, ringL, beatRateK;
    var metalL, plateQL, plateSpreadL, breathDepthL, breathRateK;
    var voiceLevelL, panWidthL, panRateK;
    // tenor formant tables (5 vowels a-e-i-o-u x 5 formants)
    var vowFreqs = #[
        [650, 1080, 2650, 2900, 3250],
        [400, 1700, 2600, 3200, 3580],
        [290, 1870, 2800, 3250, 3540],
        [400,  800, 2600, 2800, 3000],
        [350,  600, 2700, 2900, 3300]
    ];
    var vowBws = #[
        [80, 90, 120, 130, 140],
        [70, 80, 100, 120, 120],
        [40, 90, 100, 120, 120],
        [70, 80, 100, 130, 135],
        [40, 60, 100, 120, 120]
    ];
    var vowAmps = [
        [0, -6,  -7,  -8,  -22],
        [0, -14, -12, -14, -20],
        [0, -15, -18, -20, -30],
        [0, -10, -12, -12, -26],
        [0, -20, -17, -14, -26]
    ].collect { |row| row.collect(_.dbamp) };
    // the base vowel per voice is chosen at BUILD time (a UGen cannot index an
    // array); vowelSel interpolates toward the next one
    var baseVowel = #[0, 3, 1, 4, 2];
    var vowelDriftRates = #[0.041, 0.053, 0.067, 0.079, 0.093];  // ≤ 0.1 Hz (§C.4)
    var subOffsets = Array.fill(5, { |i| [-1.0, 0.4, 1.0] * (0.82 + (i * 0.09)) });
    var subDriftIncom = Array.fill(5, { |i|
        Array.fill(3, { |j| 0.6 + (j * 0.17) + (i * 0.023) })
    });
    // invariant inharmonic plate template (idiophone, NOT integers)
    var plateRatios = #[1.0, 2.76, 5.40, 8.93];
    var plateModeAmps = #[0.35, 0.7, 0.6, 0.45];
    // the x1 mode of the two lowest voices is cut: leakage into 20–80 Hz (deviation)
    var plateMode1Trim = #[0.4, 0.55, 1.0, 1.0, 1.0];
    var plateRingScale = #[1.0, 0.85, 0.72, 0.6];
    // measured trims: `metal` changes timbre, not level (post-tuning deviations)
    var b1Trim = 360.0, b2Trim = 0.675, makeup = 5.0;
    // compensates the glottal LPF tilt on the upper formants (deviation)
    var formComp = #[1.0, 2.6, 2.4, 2.8, 3.2];
    var voices, sig, fieldDrift;

    nyq = SampleRate.ir * 0.45;

    // §C.4 rate guards (slew lives on the control declarations above)
    voicedL      = voiced.clip(0, 1);
    breathL      = breath.clip(0, 1);
    brightL      = bright.clip(3, 20);
    detuneL      = detune.clip(0, 15);
    jitterL      = jitter.clip(0, 0.004);
    shimmerL     = shimmer.clip(0, 0.2);
    vowelSelL    = vowelSel.clip(0, 1);
    vowelDriftL  = vowelDrift.clip(0, 0.3);
    formWidthL   = formWidth.clip(0.7, 2.0);
    formTrackL   = formTrack.clip(0, 0.7);
    ringL        = ring.clip(0, 1);
    metalL       = metal.clip(0, 1);
    plateQL      = plateQ.clip(0.05, 3.0);
    plateSpreadL = plateSpread.clip(0, 0.05);
    breathDepthL = breathDepth.clip(0, 1);
    voiceLevelL  = voiceLevel.clip(0, 1);
    panWidthL    = panWidth.clip(0, 0.3);
    // LFN rates: A2K bridge + §C.4 clip — a kr input fed with ar is read as ZIN0,
    // silently (§7.2, arMod \rate)
    driftRateK   = A2K.kr(driftRate).clip(0.02, 0.2);
    beatRateK    = A2K.kr(beatRate).clip(0.05, 0.25);
    breathRateK  = A2K.kr(breathRate).clip(0.02, 0.25);
    panRateK     = A2K.kr(panRate).clip(0.01, 0.5);

    // static fundamentals: .set + .lag only, never a sweep (§C.4)
    funds = [f1, f2, f3, f4, f5].collect { |n| n.midicps.clip(60, nyq) };

    voices = Array.fill(nVoices, { |i|
        var fund, numHarm, jit, ensemble, src, breathNoise, bankIn;
        var vowelIdx, nextIdx, pos, regScale, ringGain, vocal;
        var plateFreqs, plateRings, plateNorm, plate;
        var voiceOut, breathing, shimGain, pan;

        fund = funds[i];
        // numHarm off the CLAMPED fund: no aliasing, never 0
        numHarm = (nyq / fund).max(1);
        jit = 1 + (LFDNoise3.kr(7 + (i * 0.9)) * jitterL);

        // Stage A: glottal unison ensemble (fixed scatter + slow drift)
        ensemble = Mix(Array.fill(nSubs, { |j|
            var cents = (subOffsets[i][j] * detuneL)
                + (LFNoise2.kr((driftRateK * subDriftIncom[i][j]).clip(0.01, 0.2))
                    * (detuneL * 0.4));
            Blip.ar(fund * jit * (2 ** (cents / 1200)), numHarm);
        })) * (1 / nSubs);
        src = LPF.ar(ensemble, (fund * brightL).clip(300, nyq));
        // undoes Blip's 1/numHarm normalization: constant partial level across
        // registers — the soprano neither vanishes nor screams
        src = src * (numHarm * 0.016).clip(0.3, 3);
        breathNoise = HPF.ar(PinkNoise.ar, 250);
        bankIn = (src * voicedL) + (breathNoise * breathL);

        // Stage B1: vocal bank (freq, bw AND amp interpolate together — morphing
        // frequencies alone yields wrong vowels)
        vowelIdx = baseVowel[i];
        nextIdx  = (vowelIdx + 1) % 5;
        pos      = (vowelSelL + (LFNoise2.kr(vowelDriftRates[i]) * vowelDriftL * 0.5))
                       .clip(0, 1);
        regScale = (fund * (1/282)) ** formTrackL;
        ringGain = ringL.linlin(0, 1, 0.3, 1.6);
        vocal = Mix(Array.fill(nForms, { |k|
            var ff   = pos.linlin(0, 1, vowFreqs[vowelIdx][k], vowFreqs[nextIdx][k]);
            var bw   = pos.linlin(0, 1, vowBws[vowelIdx][k], vowBws[nextIdx][k]);
            var ampF = pos.linlin(0, 1, vowAmps[vowelIdx][k], vowAmps[nextIdx][k]);
            var beat = LFNoise2.kr((beatRateK * (0.6 + (k * 0.22) + (i * 0.07)))
                           .clip(0.02, 0.25)).range(0.55, 1.0);
            var gainK = if(k >= 2) { ringGain } { 1.0 };
            ff = ff * regScale;
            // soprano F1 rule: F1 is pulled toward the fundamental on high voices
            if(k == 0) { ff = max(ff, fund * 1.05) };
            ff = ff.clip(60, nyq);
            BPF.ar(bankIn, ff, (bw * formWidthL / ff)) * ampF * formComp[k] * beat * gainK;
        })) * (1 / nForms) * formWidthL.sqrt.reciprocal * b1Trim;

        // Stage B2: plate bank in parallel with B1; mode frequencies are pure
        // functions of the static fund (the WHOLE array is clamped)
        plateFreqs = (fund * plateRatios).clip(60, nyq);
        plateRings = (plateQL * (1 + ((i - 2) * plateSpreadL)) * plateRingScale)
                         .clip(0.02, 4.0);
        // Q compensation: plateQ changes TIMBRE, not level
        plateNorm = 0.25 / (1 + (plateQL * 0.7));
        plate = Mix(Ringz.ar(bankIn, plateFreqs, plateRings)
                    * (plateModeAmps * [plateMode1Trim[i], 1, 1, 1]))
                    * plateNorm * b2Trim;

        voiceOut = XFade2.ar(vocal, plate, (metalL * 2) - 1);
        voiceOut = voiceOut + (breathNoise * breathL * 0.15);

        // Stage C: incoherent per-voice breath (dip ≤ -6 dB) + shimmer
        breathing = LFNoise2.kr((breathRateK * (0.7 + (i * 0.13))).clip(0.02, 0.25))
                        .range(1 - (breathDepthL * 0.5), 1.0);
        shimGain  = LFNoise2.kr(4.3 + (i * 0.6)).range(1 - shimmerL, 1.0);
        voiceOut  = voiceOut * breathing * shimGain * (1 - (i * 0.07));

        pan = LFNoise1.kr((panRateK * (0.5 + (i * 0.21))).clip(0.01, 0.67))
                  .range(panWidthL.neg, panWidthL);
        Pan2.ar(voiceOut, pan);
    });

    // voices are partly decorrelated (the sum grows ~sqrt(N)) — sqrt(N) normalization
    sig = Mix(voices) * (1 / nVoices.sqrt) * voiceLevelL;

    // very slow drift of the whole field within ±0.3 (§F)
    fieldDrift = LFNoise1.kr(0.03).range(-0.12, 0.12);
    sig = Balance2.ar(sig[0], sig[1], fieldDrift);

    // makeup BEFORE the master amp: amp stays the layer's §K.4 level (0.18)
    sig = sig * makeup;

    // §C.4 register 100 Hz – 6 kHz: triple HPF (~36 dB/oct) below f1 = 141 Hz
    sig = HPF.ar(HPF.ar(HPF.ar(sig, 120), 120), 120);

    sig = sig * amp;
    sig = LeakDC.ar(sig);                 // impulse trains and high-Q banks carry DC
    sig = Limiter.ar(sig, 0.95);          // §DSP: guarantees ±1.0 at randomizer extremes
    sig
});

// register spec + apply defaults (self-sufficient: 0_lib only needed for
// interactive random/presets/GUI after the full App load)
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\delta] = ~spec_delta;
~ungVals[\delta]  = ();
~spec_delta.params.do { |p|
    Ndef(\delta).set(p.key, p.spec.default);
    ~ungVals[\delta][p.key] = p.spec.default;
};
Ndef(\delta).fadeTime = 4;   // §F sustained register: soft in/out 4 s
// the Ndef.set loop above DROPS the koppelfeld node mapping (n_set > n_mapa) —
// without a rebind, reloading this file silently cuts the layer off the scheme
~kfRebind !? { |f| f.(\delta) };

("synths/delta — spec зарегистрирован ("
    ++ ~spec_delta.params.size ++ " параметров); ~openTuner.(\\delta)").postln;
)
