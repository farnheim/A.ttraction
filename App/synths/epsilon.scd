// App/synths/epsilon.scd — machine `epsilon`: brown noise through a chain of
// moving allpasses, four narrow mode bands, a flow above them and one drifting
// band; surface AM and L/R decorrelation. Everything audio rate.


// ===== CONFIG — edit here ============================================
(
~spec_epsilon = (
    name: \epsilon,
    params: [
        ( key: \freqLo,      group: \freq, spec: ControlSpec(18, 100, \lin, 0, 30.28) ),
        ( key: \freqHi,      group: \freq, spec: ControlSpec(18, 100, \lin, 0, 49.30) ),
        ( key: \m1,          group: \freq, spec: ControlSpec(18, 100, \lin, 0, 30.28) ),
        ( key: \m2,          group: \freq, spec: ControlSpec(18, 100, \lin, 0, 37.30) ),
        ( key: \m3,          group: \freq, spec: ControlSpec(18, 100, \lin, 0, 49.30) ),
        ( key: \m4,          group: \freq, spec: ControlSpec(18, 100, \lin, 0, 54.28) ),
        ( key: \flowCeil,    group: \freq, spec: ControlSpec(200, 14000, \exp, 0, 2500) ),
        ( key: \mLevel,      group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.35) ),
        ( key: \mWidth,      group: \tone, spec: ControlSpec(0.002, 1.0, \exp, 0, 0.06) ),
        ( key: \mBreath,     group: \tone, spec: ControlSpec(0.02, 40, \exp, 0, 0.04) ),
        ( key: \flowLevel,   group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.15) ),
        ( key: \diffDepth,   group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.6) ),
        ( key: \streakLevel, group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.20) ),
        ( key: \streakWidth, group: \tone, spec: ControlSpec(0.02, 2.0, \exp, 0, 0.45) ),
        ( key: \driftPeriod, group: \tone, spec: ControlSpec(0.02, 240, \exp, 0, 180) ),
        ( key: \surfDepth,   group: \tone, spec: ControlSpec(0.0, 40.0, \lin, 0, 3.0) ),
        ( key: \surfRate,    group: \tone, spec: ControlSpec(0.05, 120, \exp, 0, 0.09) ),
        ( key: \decorrWidth, group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.2) ),
        ( key: \amp,         group: \tone, spec: ControlSpec(0.0, 0.6, \lin, 0, 0.14) )
    ],
    vars: [
        ( key: \diffT,  spec: ControlSpec(0.001, 0.06, \exp) ),
        ( key: \breath, spec: ControlSpec(0.0, 1.0, \lin) ),
        ( key: \drift,  spec: ControlSpec(-1.5, 1.5, \lin) ),
        ( key: \sweep,  spec: ControlSpec(20, 8000, \exp) ),
        ( key: \surf,   spec: ControlSpec(0.0, 1.0, \lin) ),
        ( key: \apT,    spec: ControlSpec(0.0005, 0.02, \exp) )
    ]
);


// ===== LOGIC =========================================================
~netRegister.(~spec_epsilon, 6);
Ndef(\epsilon, ~netMachine.(~spec_epsilon, { |io|
    var freqLo = io.par(\freqLo), freqHi = io.par(\freqHi);
    var mNotes = [\m1, \m2, \m3, \m4].collect { |k| io.par(k) };
    var flowCeil = io.par(\flowCeil), mLevel = io.par(\mLevel), mWidth = io.par(\mWidth);
    var mBreath = io.par(\mBreath), flowLevel = io.par(\flowLevel), diffDepth = io.par(\diffDepth);
    var streakLevel = io.par(\streakLevel), streakWidth = io.par(\streakWidth);
    var driftPeriod = io.par(\driftPeriod), surfDepth = io.par(\surfDepth);
    var surfRate = io.par(\surfRate), decorrWidth = io.par(\decorrWidth), amp = io.par(\amp);
    var feed = io.feed;
    var nyq = SampleRate.ir * 0.45;
    var diffCentres = #[0.011, 0.019, 0.028, 0.037, 0.046, 0.055];
    var diffRates   = #[0.15, 0.21, 0.27, 0.33, 0.39, 0.45];
    var breathMults = #[1.0, 0.83, 0.67, 0.91];
    var flowFloor = 250, modeCeilRatio = 2.2, streakCeilRatio = 2.5, modeTilt = 0.5;
    var flowTrim = 0.7, streakTrim = 0.5, makeup = 3.3;
    var ceil, src, diff, drift, sweepHz, mFreqs, mCeil, modes, flow, streak, sum, wL, apL, apR, sig;

    ceil = flowCeil.clip(100, nyq);
    wL   = decorrWidth;

    src  = HPF.ar(BrownNoise.ar, 40) + feed;
    diff = src;
    diffCentres.do { |c, i|
        diff = AllpassC.ar(diff, 0.06,
            io.node(\diffT, c + (LFNoise2.ar(diffRates[i]) * c * 0.6 * diffDepth)),
            1.0);
    };

    mFreqs = mNotes.collect { |n| n.midicps.clip(20, nyq) };
    modes = Mix(mFreqs.collect { |f, i|
        var breath = io.node(\breath, LFNoise2.ar(mBreath * breathMults[i]).range(0.45, 1.0));
        var band = BPF.ar(BPF.ar(diff, f, mWidth), f, mWidth);
        band * (150 / (f * mWidth)).sqrt.clip(0.2, 8) * (f / 47).pow(modeTilt) * breath
    }) * mLevel;
    mCeil = (mFreqs.reduce(\max) * modeCeilRatio).clip(80, nyq);
    modes = LPF.ar(LPF.ar(modes, mCeil), mCeil);

    flow = LPF.ar(HPF.ar(diff, flowFloor), ceil) * flowLevel * flowTrim;

    drift = io.node(\drift, LFNoise2.ar(driftPeriod.reciprocal)
        + (LFNoise2.ar((driftPeriod * 1.37).reciprocal) * 0.5));
    sweepHz = io.node(\sweep, drift.linlin(-1.5, 1.5, freqLo, freqHi).midicps.clip(20, nyq));
    streak = BPF.ar(diff, sweepHz, streakWidth) * (150 / (sweepHz * streakWidth)).sqrt.clip(0.2, 5);
    streak = LPF.ar(streak, (sweepHz * streakCeilRatio).clip(80, nyq)) * streakLevel * streakTrim;

    sum = modes + flow + streak;
    sum = sum * io.node(\surf, LFNoise2.ar(surfRate).range(surfDepth.neg.dbamp, 1));
    sum = LPF.ar(LPF.ar(sum, ceil), ceil);

    apL = AllpassC.ar(sum, 0.02, io.node(\apT, LFNoise2.ar(0.19).range(0.004, 0.016)), 0.8);
    apR = AllpassC.ar(sum, 0.02, io.node(\apT, LFNoise2.ar(0.27).range(0.005, 0.018)), 0.8);
    sig = [XFade2.ar(sum, apL, (wL * 2) - 1), XFade2.ar(sum, apR, (wL * 2) - 1)];

    io.emit(Limiter.ar(LeakDC.ar(sig * makeup * amp), 0.95))
}));

~netRewire.value;
)
