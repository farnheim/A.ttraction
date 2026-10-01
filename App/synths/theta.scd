// App/synths/theta.scd — machine `theta`: splitter fragments (§C.8); docs: docs/features/theta/dsp-spec.md

// ===== CONFIG — edit here ============================================
(
~spec_theta = (
    name: \theta,
    level: 0.0522,
    fade: 0.5,
    params: [
        fragOct:    [-2, 2, \lin, 1, 0],
        ioi0:       [0.003, 0.5, \exp, 0, 0.018],
        decel:      [1.02, 1.8, \lin, 0, 1.22],
        ioiMax:     [0.05, 4.0, \exp, 0, 0.60],
        popScale:   [0.25, 4.0, \exp, 0, 1.0],
        gapScale:   [0.05, 6.0, \exp, 0, 1.0],
        density:    [0, 1, \lin, 0, 0.5],
        edgeWidth:  [0.05, 2.0, \exp, 0, 0.7],
        edgeAmp:    [0.0, 1.0, \lin, 0, 0.45],
        decayScale: [0.05, 1.0, \exp, 0, 0.68],
        spread:     [0.0, 2.5, \lin, 0, 0.8]
    ],
    vars: [
        pulse: [0.0, 1.0],
        casc:  [-1.0, 1.0],
        ringT: [0.005, 1.0, \exp],
        envT:  [0.001, 10.0, \exp],
        rq:    [0.005, 1.0, \exp],
        level: [0.0, 1.0],
        pan:   [-1.0, 1.0]
    ]
);

// ===== LOGIC =========================================================
~netMachine.(~spec_theta, { |io|
    var feed = io.feed, feedEnv = feed.abs.lag(0.05).min(1);
    var nyq = io.nyq, fund = 94, nVoices = 14;
    var rowR0 = #[27, 16, 64, 12, 48, 24, 81, 18, 96, 36, 32, 54, 12, 72, 24,
        16, 81, 27, 54, 12, 48, 48, 64, 18, 24, 32, 36, 12, 64, 16, 72, 48, 18,
        16, 54, 32, 12, 64, 36, 18, 72];
    var rowR1 = #[27, 36, 81, 12, 54, 32, 81, 27, 96, 48, 32, 72, 16, 72, 27,
        16, 96, 32, 54, 18, 48, 81, 72, 24, 24, 96, 36, 27, 64, 24, 81, 64, 18,
        32, 96, 54, 24, 96, 54, 36, 96];
    var rowR2 = #[27, 16, 96, 12, 48, 64, 81, 18, 96, 96, 32, 54, 32, 72, 24,
        16, 81, 81, 54, 12, 48, 48, 64, 54, 24, 32, 36, 36, 64, 16, 72, 96, 18,
        48, 54, 32, 27, 64, 81, 18, 72];
    var rowN = #[1, 2, 3, 1, 2, 3, 1, 2, 1, 3, 1, 2, 3, 1, 2, 1, 2, 3, 1, 2, 1,
        2, 2, 3, 1, 2, 1, 3, 1, 2, 2, 3, 1, 3, 2, 2, 3, 2, 3, 2, 2];
    var rqTable = #[0.33, 0.90, 0.12, 0.58, 0.05, 0.71, 0.24, 0.47, 0.83, 0.16,
        0.64, 0.09, 0.40, 0.77, 0.29, 0.54, 0.20];
    var levelTable = (0..30).collect { |i| (-8 * ((i * 7) % 31) / 30).dbamp };
    var panTable = (0..28).collect { |i| (((i * 11) % 29) / 28 * 0.8) - 0.4 };
    var versatz = #[1.05, 0.60, 1.38, 0.72, 1.65, 0.55, 1.20, 0.82, 1.50, 0.68, 0.85];
    var popTable = #[18, 26, 11, 22, 8, 28, 14];
    var gapTable = #[2.6, 5.1, 1.2, 3.8, 0.8, 4.4, 2.1, 6.0, 1.5, 3.2, 0.9, 4.9,
        2.4, 1.8, 5.6, 1.1, 3.5, 2.8, 4.1, 1.4, 5.3, 2.0, 3.0];
    var cascC0 = 0.00008, cascCl = 1.9, cascLevels = #[1.0, 0.62, 0.85, 0.48, 0.71];
    var cascHP = 400, cascLP = 9024, cascGate = 0.0025;
    var t60Ref = 0.045, edgeRqExp = 0.85, edgeFExp = 0.4, edgeRef = 280;
    var fragFund, ioi0K, decelK, ioiMaxK, popScaleK, gapScaleK, densK, gapMul, kMax;
    var nEffA, nEffB, kStream, isFirst, geom, durs, tEvt;
    var wR0, wR1, wR2, wN, wRq, wLevel, wPan, cascTimes, casc, vIdx;

    fragFund = fund * (2 ** io.par(\fragOct).round(1));

    // A2K is not optional: a Demand UGen polls its inputs on its own pull and cannot read ar
    #ioi0K, decelK, ioiMaxK, popScaleK, gapScaleK, densK =
        A2K.kr([\ioi0, \decel, \ioiMax, \popScale, \gapScale, \density].collect { |k| io.par(k) });
    gapMul = 6 ** (1 - (2 * densK));
    kMax   = ((ioiMaxK / ioi0K).log / decelK.log).floor + 1;

    #nEffA, nEffB = { (Dseq(popTable, inf) * popScaleK).min(kMax).round(1).clip(2, 64) } ! 2;
    kStream = Dseq([ Dseries(0, 1, nEffB) ], inf);
    isFirst = kStream < 0.5;
    geom    = Dseq([ Dgeom(ioi0K / decelK, decelK, nEffA) ], inf);
    durs    = (geom * Dseq(versatz, inf)) + (isFirst * Dseq(gapTable, inf) * gapScaleK * gapMul);
    tEvt    = io.node(\pulse, TDuty.ar(durs) * (io.par(\density) > 0.02));

    #wR0, wR1, wR2, wN, wRq, wLevel, wPan = Demand.ar(tEvt, 0,
        [rowR0, rowR1, rowR2, rowN, rqTable, levelTable, panTable].collect { |row| Dseq(row, inf) });

    cascTimes = [0] ++ (cascC0 * (cascCl ** (0..3))).integrate;
    casc = Mix(cascTimes.collect { |t, i|
        if(t <= 0) { tEvt * cascLevels[i] } { DelayN.ar(tEvt, 0.002, t) * cascLevels[i] }
    });
    2.do { casc = HPF.ar(casc, cascHP) };
    2.do { casc = LPF.ar(casc, cascLP) };
    casc = io.node(\casc, casc);

    vIdx = Stepper.ar(tEvt, 0, 0, nVoices - 1, 1);

    Mix.fill(nVoices, { |v|
        var trig, gate, excite, nMod, freqs, ringT, target, envT;
        var modes, fTop, rqL, edgeNorm, kante, levelW, panW;

        trig   = tEvt * ((vIdx - v).abs < 0.5);
        gate   = Trig.ar(trig, cascGate);
        excite = (casc * gate) + (feed * (1 / nVoices.sqrt));

        nMod  = Latch.ar(wN, trig);
        freqs = [wR0, wR1, wR2].collect { |r| Latch.ar(r * fragFund, trig).clip(20, nyq) };

        ringT  = io.node(\ringT, (3 * (45.1 / freqs.reduce(\min)).min(0.040)).clip(0.015, 0.120));
        target = (ringT * io.par(\decayScale)).clip(0.005, 1.0);
        envT   = io.node(\envT, ringT * target / (ringT - target).max(0.0002));
        modes  = Mix(Ringz.ar(excite, freqs, ringT) * [1, nMod > 1.5, nMod > 2.5])
            / nMod.max(1).sqrt
            * Decay2.ar(trig, 0.001, envT).max(feedEnv)
            * (t60Ref / ringT).sqrt;

        fTop     = freqs.reduce(\max);
        rqL      = io.node(\rq, (Latch.ar(wRq, trig) * io.par(\edgeWidth)).clip(0.01, 1.0));
        edgeNorm = edgeRef / ((rqL ** edgeRqExp) * (fTop ** edgeFExp));
        kante    = BPF.ar(excite, fTop, rqL) * edgeNorm * Decay2.ar(trig, 0.0002, 0.0025);

        levelW = io.node(\level, Latch.ar(wLevel, trig));
        panW   = io.node(\pan, Latch.ar(wPan, trig) * Latch.ar(io.par(\spread), trig));
        Pan2.ar((modes + (kante * io.par(\edgeAmp))) * levelW, panW)
    })
});
)
