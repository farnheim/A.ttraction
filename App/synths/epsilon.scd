// App/synths/epsilon.scd — UNGRUND class 5/8 `epsilon`, §C.5 `schliere`
// (amended 2026-07-16, cave bed): a low tonal field of modes excited by a
// diffuse flow, plus one slow formant band. Three strata, no events;
// identity: spectral flatness 20–300 Hz ≤ 0.2.
// Reference + implementation notes: docs/features/epsilon/cave-reference.md.
// ~spec_epsilon — source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — streak drift endpoints + the four held lattice modes +
// LPF ceiling; MIDI defaults are exact cpsmidi of the Hz lattice
// (47 / 70.5 / 141 / 188 Hz = 94 ÷2, ×3/4, ×3/2, ×2).
// group \tone — mode field / flow excitation / streak / surface / space.
~spec_epsilon = (
    name: \epsilon,
    params: [
        // --- group \freq: streak endpoints + held modes (MIDI notes, 47–1504 Hz) ---
        ( key: \freqLo, group: \freq, disp: \note,
          spec: ControlSpec(30.28, 90.28, \lin, 0, 30.28), reread: \cont, arMod: \freq ),  // 47 Hz ÷2
        ( key: \freqHi, group: \freq, disp: \note,
          spec: ControlSpec(30.28, 90.28, \lin, 0, 49.30), reread: \cont, arMod: \freq ),  // 141 Hz ×3/2
        ( key: \m1, group: \freq, disp: \note,
          spec: ControlSpec(30.28, 90.28, \lin, 0, 30.28), reread: \contBlock, arMod: \freq ),  // 47 Hz ÷2
        ( key: \m2, group: \freq, disp: \note,
          spec: ControlSpec(30.28, 90.28, \lin, 0, 37.30), reread: \contBlock, arMod: \freq ),  // 70.5 Hz ×3/4
        ( key: \m3, group: \freq, disp: \note,
          spec: ControlSpec(30.28, 90.28, \lin, 0, 49.30), reread: \contBlock, arMod: \freq ),  // 141 Hz ×3/2
        ( key: \m4, group: \freq, disp: \note,
          spec: ControlSpec(30.28, 90.28, \lin, 0, 54.28), reread: \contBlock, arMod: \freq ),  // 188 Hz ×2
        ( key: \flowCeil, group: \freq, unit: " Hz", disp: \hz,
          spec: ControlSpec(1200, 5000, \exp, 0, 2500), reread: \contBlock, arMod: \freq ),  // amendment (e): 1.2–5 kHz

        // --- group \tone: mode field (the principal stratum) ---
        ( key: \mLevel, group: \tone,
          spec: ControlSpec(0.0, 0.5, \lin, 0, 0.35), reread: \cont, arMod: \lin ),  // up to +6 dB over the flow (inverted)
        ( key: \mWidth, group: \tone,
          spec: ControlSpec(0.02, 0.3, \exp, 0, 0.06), reread: \contBlock, arMod: \freq ),  // mode rq — drives the flatness metric
        ( key: \mBreath, group: \tone, unit: " Hz",
          spec: ControlSpec(0.02, 0.1, \exp, 0, 0.04), reread: [\seg, \mBreath], arMod: \rate ),  // per-mode breathing base rate

        // --- group \tone: flow (excitation, subordinate) ---
        ( key: \flowLevel, group: \tone,
          spec: ControlSpec(0.0, 0.5, \lin, 0, 0.15), reread: \cont, arMod: \lin ),  // the modes' medium
        ( key: \diffDepth, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.6), reread: \cont, arMod: \lin ),  // AllpassC delay-mod depth

        // --- group \tone: streak (the §C.5 motion identity) ---
        ( key: \streakLevel, group: \tone,
          spec: ControlSpec(0.0, 0.5, \lin, 0, 0.20), reread: \cont, arMod: \lin ),  // audible, not dominant
        ( key: \streakWidth, group: \tone,
          spec: ControlSpec(0.1, 1.5, \exp, 0, 0.45), reread: \cont, arMod: \freq ),  // band formant rq (softness)
        // reread is an LFN segment at rate 1/driftPeriod: the [\seg, \key] grammar
        // cannot express a reciprocal, so the band ceiling is 1/(2·win_hi) (§5.3)
        ( key: \driftPeriod, group: \tone, unit: " s",
          spec: ControlSpec(20, 240, \exp, 0, 180), reread: [\seg, \driftPeriod], arMod: \rate ),  // §C.5 two-LFN law period T

        // --- group \tone: surface + space ---
        ( key: \surfDepth, group: \tone, unit: " dB",
          spec: ControlSpec(0.0, 6.0, \lin, 0, 3.0), reread: \cont, arMod: \lin ),  // a cave's air is not still
        ( key: \surfRate, group: \tone, unit: " Hz",
          spec: ControlSpec(0.05, 0.3, \exp, 0, 0.09), reread: [\seg, \surfRate], arMod: \rate ),  // aperiodic by UGen choice
        ( key: \decorrWidth, group: \tone,
          spec: ControlSpec(0.0, 0.3, \lin, 0, 0.2), reread: \cont, arMod: \lin ),  // L/R decorrelation, centre fixed

        // --- group \tone: master ---
        ( key: \amp, group: \tone,
          spec: ControlSpec(0.0, 0.3, \lin, 0, 0.14), reread: \cont, arMod: \lin )  // §K.4 schliere level
    ]
);


// ===== LOGIC — synthesis =============================================
// brown -> diffusion `diff` -> modes and band = BAND-PASSes off diff, flow =
// diff above the modes; sum -> AM -> 2x LPF -> decorrelation -> makeup ->
// LeakDC -> Limiter
Ndef(\epsilon, {
    // ar controls: declaration order = ~spec_epsilon row order. Slew floors are
    // contract §5: levels 5 ms, frequencies/rq 2 ms, LFN rates none at all
    var freqLo      = \freqLo.ar(30.28).lag(0.002);
    var freqHi      = \freqHi.ar(49.30).lag(0.002);
    var m1          = \m1.ar(30.28).lag(0.002);
    var m2          = \m2.ar(37.30).lag(0.002);
    var m3          = \m3.ar(49.30).lag(0.002);
    var m4          = \m4.ar(54.28).lag(0.002);
    var flowCeil    = \flowCeil.ar(2500).lag(0.002);
    var mLevel      = \mLevel.ar(0.35).lag(0.005);
    var mWidth      = \mWidth.ar(0.06).lag(0.002);
    var mBreath     = \mBreath.ar(0.04);
    var flowLevel   = \flowLevel.ar(0.15).lag(0.005);
    var diffDepth   = \diffDepth.ar(0.6).lag(0.005);
    var streakLevel = \streakLevel.ar(0.20).lag(0.005);
    var streakWidth = \streakWidth.ar(0.45).lag(0.002);
    var driftPeriod = \driftPeriod.ar(180);
    var surfDepth   = \surfDepth.ar(3.0).lag(0.005);
    var surfRate    = \surfRate.ar(0.09);
    var decorrWidth = \decorrWidth.ar(0.2).lag(0.005);
    var amp         = \amp.ar(0.14).lag(0.005);

    var nyq;
    var diffCentres = #[0.011, 0.019, 0.028, 0.037, 0.046, 0.055];
    var diffRates   = #[0.15, 0.21, 0.27, 0.33, 0.39, 0.45];
    // incommensurable and all ≤ 1.0: the amendment caps mode breathing at 0.1 Hz
    var breathMults = #[1.0, 0.83, 0.67, 0.91];
    // the flow is heard ONLY above the mode field — full brown would drown
    // 20–300 Hz and break the flatness guarantee (cave-reference, note 1)
    var flowFloor = 250;
    // a mode is a cascaded BPF pair (12 dB/oct skirts) plus a tracking ceiling
    // for both band strata: a single BPF masked 250–800 Hz (note 2)
    var modeCeilRatio   = 2.2;
    var streakCeilRatio = 2.5;
    // +3 dB/oct against the source's -6 dB/oct tilt: four modes equally loud (note 3)
    var modeTilt = 0.5;
    // trims measured per stratum in solo renders (band RMS), not analytically
    var modeTrim   = 1.0;
    var flowTrim   = 0.7;
    var streakTrim = 0.5;
    var makeup     = 3.3;
    var flowCeilL, mLevelL, mWidthL, mBreathK;
    var flowLevelL, diffDepthL, streakLevelL, streakWidthL, driftK;
    var surfDepthL, surfRateK, wL;
    var src, diff, drift, sweepHz, mFreqs, mCeil, modes, flow, streak;
    var sum, apL, apR, sig;

    nyq = SampleRate.ir * 0.45;

    flowCeilL    = flowCeil.clip(1200, nyq);
    mLevelL      = mLevel.clip(0, 0.5);
    mWidthL      = mWidth.clip(0.02, 0.3);
    flowLevelL   = flowLevel.clip(0, 0.5);
    diffDepthL   = diffDepth.clip(0, 1);
    streakLevelL = streakLevel.clip(0, 0.5);
    streakWidthL = streakWidth.clip(0.1, 1.5);
    surfDepthL   = surfDepth.clip(0, 6);
    wL           = decorrWidth.clip(0, 0.3);
    // LFN rate arguments: A2K bridge + clip, no slew — a kr input fed with ar is
    // read as ZIN0, silently (§7.2, arMod \rate)
    driftK       = A2K.kr(driftPeriod).clip(20, 240);
    surfRateK    = A2K.kr(surfRate).clip(0.05, 0.3);
    mBreathK     = A2K.kr(mBreath).clip(0.02, 0.1);

    // Stage 0: brown = white at -6 dB/oct (§C.5 (a)); HPF 40 — sub rumble below
    // the §F floor of 40 Hz must not spend filter headroom
    src = HPF.ar(BrownNoise.ar, 40);

    // Stage 1: diffusion haze; LFN rates are fixed at build time (diffDepth maps
    // only the depth of movement)
    diff = src;
    diffCentres.do { |c, i|
        diff = AllpassC.ar(diff, 0.06,
            (c + (LFNoise2.kr(diffRates[i]) * c * 0.6 * diffDepthL))
                .clip(0.008, 0.06),
            1.0);
    };

    // Stage 2: mode field — 4 static narrow noise bands of the lattice (not a
    // comb: no partials, no ring), normalized against f x rq; the breathing never
    // reaches 0 — the continuum is not gated
    mFreqs = [m1, m2, m3, m4].collect { |n|
        n.midicps.clip(47, nyq)
    };
    modes = Mix(mFreqs.collect { |f, i|
        var breath = LFNoise2.kr(mBreathK * breathMults[i]).range(0.45, 1.0);
        var band = BPF.ar(BPF.ar(diff, f, mWidthL), f, mWidthL);
        band
            * (150 / (f * mWidthL)).sqrt.clip(0.2, 8)
            * (f / 47).pow(modeTilt)
            * breath;
    }) * mLevelL * modeTrim;
    mCeil = (mFreqs.reduce(\max) * modeCeilRatio).clip(80, nyq);
    modes = LPF.ar(LPF.ar(modes, mCeil), mCeil);

    // Stage 3: flow — the medium of the modes, only above their region; the extra
    // LPF darkens toward the measured steep cave top rolloff (2500–6000 ≤ -40 rel)
    flow = HPF.ar(diff, flowFloor);
    flow = LPF.ar(flow, flowCeilL) * flowLevelL * flowTrim;

    // Stage 4: ONE drifting band — two incommensurable LFNs (not a sine), mapped
    // in MIDI space; a band-pass formant, not a comb (§C.5 (a))
    drift = LFNoise2.kr(driftK.reciprocal)
        + (LFNoise2.kr((driftK * 1.37).reciprocal) * 0.5);
    sweepHz = drift.range(freqLo, freqHi).midicps.clip(47, nyq);
    // normalization: the RMS of a BPF on noise grows as sqrt(cf x rq) — without it
    // the band would swell as it drifts upward
    streak = BPF.ar(diff, sweepHz, streakWidthL)
        * (150 / (sweepHz * streakWidthL)).sqrt.clip(0.2, 5);
    streak = LPF.ar(streak, (sweepHz * streakCeilRatio).clip(80, nyq))
        * streakLevelL * streakTrim;

    // Stage 5: surface AM over the whole field — cave air is not still
    sum = modes + flow + streak;
    sum = sum * LFNoise2.kr(surfRateK).range(surfDepthL.neg.dbamp, 1);

    // Stage 6: ceiling — 2x LPF (-24 dB/oct)
    sum = LPF.ar(LPF.ar(sum, flowCeilL), flowCeilL);

    // Stage 7: equal-power decorrelation, energy centre pinned at 0 (§F) — the
    // layer has neither Pan2 nor a pan LFO
    apL = AllpassC.ar(sum, 0.02, LFNoise2.kr(0.19).range(0.004, 0.016), 0.8);
    apR = AllpassC.ar(sum, 0.02, LFNoise2.kr(0.27).range(0.005, 0.018), 0.8);
    sig = [
        XFade2.ar(sum, apL, (wL * 2) - 1),
        XFade2.ar(sum, apR, (wL * 2) - 1)
    ];

    // Stage 8: makeup puts RMS at -24 dBFS with amp 0.14 (delta precedent: tune
    // the internals, not the spec defaults)
    sig = sig * makeup * amp;
    sig = LeakDC.ar(sig);
    sig = Limiter.ar(sig, 0.95);
    sig
});

// register spec + apply defaults (self-sufficient: 0_lib only needed for
// interactive random/presets/GUI after the full App load)
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\epsilon] = ~spec_epsilon;
~ungVals[\epsilon]  = ();
~spec_epsilon.params.do { |p|
    Ndef(\epsilon).set(p.key, p.spec.default);
    ~ungVals[\epsilon][p.key] = p.spec.default;
};
Ndef(\epsilon).fadeTime = 6;   // §C.5: onset ≥ 4 s; a schliere recedes, never cut
// the Ndef.set loop above DROPS the koppelfeld node mapping (n_set > n_mapa) —
// without a rebind, reloading this file silently cuts the layer off the scheme
~kfRebind !? { |f| f.(\epsilon) };

("synths/epsilon — spec зарегистрирован ("
    ++ ~spec_epsilon.params.size ++ " параметров); ~openTuner.(\\epsilon)").postln;
)
