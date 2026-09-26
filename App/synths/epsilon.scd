// App/synths/epsilon.scd — machine `epsilon`: brown noise through a chain of
// moving allpasses, four narrow mode bands, a flow above them and one drifting
// band; surface AM and L/R decorrelation.


// ===== CONFIG — edit here ============================================
(
~spec_epsilon = (
    name: \epsilon,
    level: 0.462,
    fade: 6,
    params: [
        freqLo:      [18, 100, \lin, 0, 30.28],
        freqHi:      [18, 100, \lin, 0, 49.30],
        m1:          [18, 100, \lin, 0, 30.28],
        m2:          [18, 100, \lin, 0, 37.30],
        m3:          [18, 100, \lin, 0, 49.30],
        m4:          [18, 100, \lin, 0, 54.28],
        flowCeil:    [200, 14000, \exp, 0, 2500],
        mLevel:      [0.0, 1.0, \lin, 0, 0.35],
        mWidth:      [0.002, 1.0, \exp, 0, 0.06],
        mBreath:     [0.02, 40, \exp, 0, 0.04],
        flowLevel:   [0.0, 1.0, \lin, 0, 0.15],
        diffDepth:   [0.0, 1.0, \lin, 0, 0.6],
        streakLevel: [0.0, 1.0, \lin, 0, 0.20],
        streakWidth: [0.02, 2.0, \exp, 0, 0.45],
        driftPeriod: [0.02, 240, \exp, 0, 180],
        surfDepth:   [0.0, 40.0, \lin, 0, 3.0],
        surfRate:    [0.05, 120, \exp, 0, 0.09],
        decorrWidth: [0.0, 1.0, \lin, 0, 0.2]
    ],
    vars: [
        diffT:  [0.001, 0.06, \exp],
        breath: [0.0, 1.0],
        drift:  [-1.5, 1.5],
        sweep:  [20, 8000, \exp],
        surf:   [0.0, 1.0],
        apT:    [0.0005, 0.02, \exp]
    ]
);


// ===== LOGIC =========================================================
~netMachine.(~spec_epsilon, { |io|
    var nyq = io.nyq;
    var ceil = io.par(\flowCeil).clip(100, nyq);
    var mWidth = io.par(\mWidth), streakWidth = io.par(\streakWidth), driftPeriod = io.par(\driftPeriod);
    var diffCentres = #[0.011, 0.019, 0.028, 0.037, 0.046, 0.055];
    var diffRates   = #[0.15, 0.21, 0.27, 0.33, 0.39, 0.45];
    var breathMults = #[1.0, 0.83, 0.67, 0.91];
    var flowFloor = 250, modeCeilRatio = 2.2, streakCeilRatio = 2.5, modeTilt = 0.5;
    var flowTrim = 0.7, streakTrim = 0.5;
    var diff, drift, sweepHz, mFreqs, mCeil, modes, flow, streak, sum, ap;

    diff = HPF.ar(BrownNoise.ar, 40) + io.feed;
    diffCentres.do { |c, i|
        diff = AllpassC.ar(diff, 0.06,
            io.node(\diffT, c + (LFNoise2.ar(diffRates[i]) * c * 0.6 * io.par(\diffDepth))),
            1.0);
    };

    mFreqs = [\m1, \m2, \m3, \m4].collect { |k| io.par(k).midicps.clip(20, nyq) };
    modes = Mix(mFreqs.collect { |f, i|
        var breath = io.node(\breath, LFNoise2.ar(io.par(\mBreath) * breathMults[i]).range(0.45, 1.0));
        var band = BPF.ar(BPF.ar(diff, f, mWidth), f, mWidth);
        band * (150 / (f * mWidth)).sqrt.clip(0.2, 8) * (f / 47).pow(modeTilt) * breath
    }) * io.par(\mLevel);
    mCeil = (mFreqs.reduce(\max) * modeCeilRatio).clip(80, nyq);
    modes = LPF.ar(LPF.ar(modes, mCeil), mCeil);

    flow = LPF.ar(HPF.ar(diff, flowFloor), ceil) * io.par(\flowLevel) * flowTrim;

    drift = io.node(\drift, LFNoise2.ar(driftPeriod.reciprocal)
        + (LFNoise2.ar((driftPeriod * 1.37).reciprocal) * 0.5));
    sweepHz = io.node(\sweep, drift.linlin(-1.5, 1.5, io.par(\freqLo), io.par(\freqHi)).midicps);
    streak = BPF.ar(diff, sweepHz, streakWidth) * (150 / (sweepHz * streakWidth)).sqrt.clip(0.2, 5);
    streak = LPF.ar(streak, (sweepHz * streakCeilRatio).clip(80, nyq)) * io.par(\streakLevel) * streakTrim;

    sum = modes + flow + streak;
    sum = sum * io.node(\surf, LFNoise2.ar(io.par(\surfRate)).range(io.par(\surfDepth).neg.dbamp, 1));
    sum = LPF.ar(LPF.ar(sum, ceil), ceil);

    ap = AllpassC.ar(sum, 0.02, io.node(\apT, [
        LFNoise2.ar(0.19).range(0.004, 0.016),
        LFNoise2.ar(0.27).range(0.005, 0.018)
    ]), 0.8);
    XFade2.ar(sum, ap, (io.par(\decorrWidth) * 2) - 1)
});
)
