// App/synths/epsilon.scd — UNGRUND class 5/8 `epsilon` (cave bed).
// REAL LAYER, premise §C.5 `schliere` as amended 2026-07-16 (cave bed;
// supersedes the water engine's clause (c) and the comb mechanism):
// a LOW TONAL MODE FIELD excited by a diffused noise flow, with one slow
// band formant drifting through its lower octave. The modes are the
// material and the flow is their excitation — not a bed with resonances
// on top. Three strata, no events (§F density 0, no exception).
// Identity guarantee: spectral flatness 20–300 Hz ≤ 0.2.
// Reference: docs/features/epsilon/cave-reference.md. Tuning via
// 0_lib.scd; ~spec_epsilon is the single source of truth.


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
        ( key: \freqLo,   group: \freq, disp: \note,             spec: ControlSpec(30.28, 90.28, \lin, 0, 30.28) ),  // 47 Hz ÷2
        ( key: \freqHi,   group: \freq, disp: \note,             spec: ControlSpec(30.28, 90.28, \lin, 0, 49.30) ),  // 141 Hz ×3/2
        ( key: \m1,       group: \freq, disp: \note,             spec: ControlSpec(30.28, 90.28, \lin, 0, 30.28) ),  // 47 Hz ÷2
        ( key: \m2,       group: \freq, disp: \note,             spec: ControlSpec(30.28, 90.28, \lin, 0, 37.30) ),  // 70.5 Hz ×3/4
        ( key: \m3,       group: \freq, disp: \note,             spec: ControlSpec(30.28, 90.28, \lin, 0, 49.30) ),  // 141 Hz ×3/2
        ( key: \m4,       group: \freq, disp: \note,             spec: ControlSpec(30.28, 90.28, \lin, 0, 54.28) ),  // 188 Hz ×2
        ( key: \flowCeil, group: \freq, unit: " Hz", disp: \hz,  spec: ControlSpec(1200, 5000, \exp, 0, 2500)   ),  // amendment (e): 1.2–5 kHz

        // --- group \tone: mode field (the principal stratum) ---
        ( key: \mLevel,      group: \tone,              spec: ControlSpec(0.0,  0.5,  \lin, 0, 0.35) ),  // up to +6 dB over the flow (inverted)
        ( key: \mWidth,      group: \tone,              spec: ControlSpec(0.02, 0.3,  \exp, 0, 0.06) ),  // mode rq — drives the flatness metric
        ( key: \mBreath,     group: \tone, unit: " Hz", spec: ControlSpec(0.02, 0.1,  \exp, 0, 0.04) ),  // per-mode breathing base rate

        // --- group \tone: flow (excitation, subordinate) ---
        ( key: \flowLevel,   group: \tone,              spec: ControlSpec(0.0,  0.5,  \lin, 0, 0.15) ),  // the modes' medium
        ( key: \diffDepth,   group: \tone,              spec: ControlSpec(0.0,  1.0,  \lin, 0, 0.6)  ),  // AllpassC delay-mod depth

        // --- group \tone: streak (the §C.5 motion identity) ---
        ( key: \streakLevel, group: \tone,              spec: ControlSpec(0.0,  0.5,  \lin, 0, 0.20) ),  // audible, not dominant
        ( key: \streakWidth, group: \tone,              spec: ControlSpec(0.1,  1.5,  \exp, 0, 0.45) ),  // band formant rq (softness)
        ( key: \driftPeriod, group: \tone, unit: " s",  spec: ControlSpec(20,   240,  \exp, 0, 180)  ),  // §C.5 two-LFN law period T

        // --- group \tone: surface + space ---
        ( key: \surfDepth,   group: \tone, unit: " dB", spec: ControlSpec(0.0,  6.0,  \lin, 0, 3.0)  ),  // a cave's air is not still
        ( key: \surfRate,    group: \tone, unit: " Hz", spec: ControlSpec(0.05, 0.3,  \exp, 0, 0.09) ),  // aperiodic by UGen choice
        ( key: \decorrWidth, group: \tone,              spec: ControlSpec(0.0,  0.3,  \lin, 0, 0.2)  ),  // L/R decorrelation, centre fixed

        // --- group \tone: master ---
        ( key: \amp,         group: \tone,              spec: ControlSpec(0.0,  0.3,  \lin, 0, 0.14) )   // §K.4 schliere level
    ]
);


// ===== LOGIC — synthesis =============================================
// Stage 0 brown source -> 1 diffusion haze (`diff`) -> the mode field and
// the streak are both BAND-PASSES OF `diff` (excitation), the flow is
// `diff` above the mode region; sum -> surface AM -> 2x LPF at flowCeil ->
// decorrelation pair -> makeup -> amp -> LeakDC -> Limiter.
Ndef(\epsilon, { |amp = 0.14,
    freqLo = 30.28, freqHi = 49.30,
    m1 = 30.28, m2 = 37.30, m3 = 49.30, m4 = 54.28,
    flowCeil = 2500,
    mLevel = 0.35, mWidth = 0.06, mBreath = 0.04,
    flowLevel = 0.15, diffDepth = 0.6,
    streakLevel = 0.20, streakWidth = 0.45, driftPeriod = 180,
    surfDepth = 3.0, surfRate = 0.09, decorrWidth = 0.2|

    var nyq;
    var diffCentres = #[0.011, 0.019, 0.028, 0.037, 0.046, 0.055];
    var diffRates   = #[0.15, 0.21, 0.27, 0.33, 0.39, 0.45];
    // incommensurate AND all ≤ 1.0: the amendment bounds EACH mode's
    // breathing LFN at 0.1 Hz = the mBreath slider ceiling
    var breathMults = #[1.0, 0.83, 0.67, 0.91];
    // the flow's audible stratum starts ABOVE the mode field: a full-band
    // brown flow would swamp 20–300 Hz and break the ≤ 0.2 flatness
    // guarantee that IS this class's identity (§C.5 amendment (b)). The
    // BPF excitation taps `diff` pre-HPF, so the modes still ride the flow.
    var flowFloor = 250;
    // ONE BPF's skirts fall only 6 dB/oct, so the mode field alone filled
    // 250–800 Hz to 7.6 dB under its own peak band (target: 16) — the exact
    // masking that buries gamma's drips. Each mode is therefore a CASCADED
    // pair (12 dB/oct skirts); both band strata additionally get a tracking
    // ceiling above their own highest position.
    var modeCeilRatio   = 2.2;
    var streakCeilRatio = 2.5;
    // the source's −6 dB/oct tilt would otherwise let m1/m2 dominate m3/m4;
    // +3 dB/oct holds the four modes near equal loudness, which is what the
    // reference's −0.3 / 0.0 near-tie of its two low bands reports
    var modeTilt = 0.5;
    // trims measured per-stratum in solo renders (band RMS), not derived
    // analytically
    var modeTrim   = 1.0;
    var flowTrim   = 0.7;
    var streakTrim = 0.5;
    var makeup     = 3.3;
    var freqLoL, freqHiL, flowCeilL, mLevelL, mWidthL, mBreathL;
    var flowLevelL, diffDepthL, streakLevelL, streakWidthL, driftT;
    var surfDepthL, surfRateL, wL;
    var src, diff, drift, sweepHz, mFreqs, mCeil, modes, flow, streak;
    var sum, apL, apR, sig;

    nyq = SampleRate.ir * 0.45;

    freqLoL      = freqLo.lag(0.2);
    freqHiL      = freqHi.lag(0.2);
    flowCeilL    = flowCeil.lag(0.2).clip(1200, nyq);
    mLevelL      = mLevel.lag(0.2).clip(0, 0.5);
    mWidthL      = mWidth.lag(0.2).clip(0.02, 0.3);
    flowLevelL   = flowLevel.lag(0.2).clip(0, 0.5);
    diffDepthL   = diffDepth.lag(0.2).clip(0, 1);
    streakLevelL = streakLevel.lag(0.2).clip(0, 0.5);
    streakWidthL = streakWidth.lag(0.2).clip(0.1, 1.5);
    surfDepthL   = surfDepth.lag(0.2).clip(0, 6);
    wL           = decorrWidth.lag(0.2).clip(0, 0.3);
    // LFN rate args: clip only, no lag — a lag on a rate is useless and a
    // stall at the range floor is the real risk
    driftT       = driftPeriod.clip(20, 240);
    surfRateL    = surfRate.clip(0.05, 0.3);
    mBreathL     = mBreath.clip(0.02, 0.1);

    // Stage 0: brown IS white with the -6 dB/oct tilt (darkest admitted
    // colour, §C.5 amendment (a)); HPF 40 — brown is sub-heavy and would
    // waste filter headroom on rumble under the §F 40 Hz pitch floor
    src = HPF.ar(BrownNoise.ar, 40);

    // Stage 1: diffusion haze; LFN rates fixed at build time (§C.5 card —
    // diffDepth maps motion depth only)
    diff = src;
    diffCentres.do { |c, i|
        diff = AllpassC.ar(diff, 0.06,
            (c + (LFNoise2.kr(diffRates[i]) * c * 0.6 * diffDepthL))
                .clip(0.008, 0.06),
            1.0);
    };

    // Stage 2: the mode field — 4 static NARROW NOISE BANDS on the lattice
    // (no comb: no overtone series, no ring). Level-normalised against
    // f × rq so all four positions breathe at equal loudness; the breath
    // never reaches 0 — a continuum must not gate (acceptance: no 1-s
    // window below mean − 6 dB)
    mFreqs = [m1, m2, m3, m4].collect { |n|
        n.lag(0.2).midicps.clip(47, nyq)
    };
    modes = Mix(mFreqs.collect { |f, i|
        var breath = LFNoise2.kr(mBreathL * breathMults[i]).range(0.45, 1.0);
        var band = BPF.ar(BPF.ar(diff, f, mWidthL), f, mWidthL);
        band
            * (150 / (f * mWidthL)).sqrt.clip(0.2, 8)
            * (f / 47).pow(modeTilt)
            * breath;
    }) * mLevelL * modeTrim;
    mCeil = (mFreqs.reduce(\max) * modeCeilRatio).clip(80, nyq);
    modes = LPF.ar(LPF.ar(modes, mCeil), mCeil);

    // Stage 3: the flow — the modes' medium, above the mode region only.
    // The extra LPF at flowCeil (the sum gets two more) darkens the flow to
    // the measured cave's steep upper fall: 2500–6000 must stay ≤ −40 rel
    flow = HPF.ar(diff, flowFloor);
    flow = LPF.ar(flow, flowCeilL) * flowLevelL * flowTrim;

    // Stage 4: the ONE drifting streak — two incommensurate LFNs, never a
    // sine; mapped in MIDI space for even pitch coverage. A BAND-PASS
    // formant, not a comb (amendment (a)): a comb's overtone series + ring
    // is a resonating body, a single moving noise band is a current
    drift = LFNoise2.kr(driftT.reciprocal)
        + (LFNoise2.kr((driftT * 1.37).reciprocal) * 0.5);
    sweepHz = drift.range(freqLoL, freqHiL).midicps.clip(47, nyq);
    // level-normalised: BPF-on-noise RMS grows with sqrt(cf × rq), so an
    // un-normalised streak would swell as it drifts upward
    streak = BPF.ar(diff, sweepHz, streakWidthL)
        * (150 / (sweepHz * streakWidthL)).sqrt.clip(0.2, 5);
    streak = LPF.ar(streak, (sweepHz * streakCeilRatio).clip(80, nyq))
        * streakLevelL * streakTrim;

    // Stage 5: surface AM on the whole field — a cave's air is not still
    sum = modes + flow + streak;
    sum = sum * LFNoise2.kr(surfRateL).range(surfDepthL.neg.dbamp, 1);

    // Stage 6: ceiling — 2x LPF (-24 dB/oct)
    sum = LPF.ar(LPF.ar(sum, flowCeilL), flowCeilL);

    // Stage 7: equal-power decorrelation pair, energy centre fixed at 0
    // (§F) — no Pan2, no pan LFO anywhere in the layer
    apL = AllpassC.ar(sum, 0.02, LFNoise2.kr(0.19).range(0.004, 0.016), 0.8);
    apR = AllpassC.ar(sum, 0.02, LFNoise2.kr(0.27).range(0.005, 0.018), 0.8);
    sig = [
        XFade2.ar(sum, apL, (wL * 2) - 1),
        XFade2.ar(sum, apR, (wL * 2) - 1)
    ];

    // Stage 8: internal makeup lands RMS -24 dBFS at amp 0.14 (delta
    // precedent: tune internals, never spec defaults)
    sig = sig * makeup * amp.lag(0.05);
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

("synths/epsilon — spec зарегистрирован ("
    ++ ~spec_epsilon.params.size ++ " параметров); ~openTuner.(\\epsilon)").postln;
)
