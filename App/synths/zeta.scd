// App/synths/zeta.scd — machine `zeta`: a filtered noise bed with a resonant
// hump, a sub floor, dense fine ticks and rare pops with a ringing body.


// ===== CONFIG — edit here ============================================
(
~spec_zeta = (
    name: \zeta,
    level: 0.4648,
    fade: 0.5,
    params: [
        bedHpf:        [20, 2000, \exp, 0, 270],
        bedLpf:        [500, 16000, \exp, 0, 11000],
        bedHumpFreq:   [60, 8000, \exp, 0, 1200],
        subFreq:       [20, 400, \exp, 0, 120],
        fineHpf:       [200, 12000, \exp, 0, 2000],
        popHpf:        [100, 10000, \exp, 0, 1500],
        bodyFreq:      [30, 2000, \exp, 0, 180],
        bedAmp:        [0.0, 1.0, \lin, 0, 0.6],
        bedHumpRq:     [0.01, 2.0, \exp, 0, 0.6],
        bedHumpAmt:    [0.0, 1.0, \lin, 0, 0.55],
        bedDriftRate:  [0.02, 200, \exp, 0, 0.1],
        bedDriftDepth: [0.0, 1.0, \lin, 0, 0.25],
        subAmt:        [0.0, 1.0, \lin, 0, 0.0],
        fineRate:      [1, 5000, \exp, 0, 45],
        fineDecay:     [0.0002, 0.05, \exp, 0, 0.0015],
        fineAmpMin:    [0.005, 1.0, \exp, 0, 0.04],
        fineAmt:       [0.0, 1.0, \lin, 0, 0.48],
        popRate:       [0.05, 200, \exp, 0, 2.4],
        popDecay:      [0.001, 0.2, \exp, 0, 0.006],
        popAmpMin:     [0.01, 1.0, \exp, 0, 0.14],
        popAmt:        [0.0, 1.0, \lin, 0, 0.85],
        bodyAmt:       [0.0, 1.0, \lin, 0, 0.4],
        bodyRing:      [0.002, 2.0, \exp, 0, 0.04],
        panWidth:      [0.0, 1.0, \lin, 0, 0.3],
        panRate:       [0.02, 100, \exp, 0, 0.15]
    ],
    vars: [
        drift:   [0.0, 1.0],
        fineLvl: [0.005, 1.0, \exp],
        popLvl:  [0.01, 1.0, \exp],
        click:   [0.0, 1.0],
        pan:     [-1.0, 1.0]
    ]
);


// ===== LOGIC =========================================================
~netMachine.(~spec_zeta, { |io|
    var nyq = io.nyq;
    var expDraw = { |lo, trig| Latch.ar(lo * (lo.reciprocal ** WhiteNoise.ar.range(0, 1)), trig) };
    var bedFlat, bedHump, bed, drift, sub, fineTrig, fineLvl, fine, popTrig, popLvl;
    var click, body, pops, pan;

    bedFlat = PinkNoise.ar + io.feed;
    bedFlat = HPF.ar(bedFlat, io.par(\bedHpf).clip(20, nyq));
    bedFlat = LPF.ar(bedFlat, io.par(\bedLpf).clip(100, nyq));
    bedHump = Resonz.ar(bedFlat, io.par(\bedHumpFreq).clip(30, nyq), io.par(\bedHumpRq));
    bed     = XFade2.ar(bedFlat, bedHump, (io.par(\bedHumpAmt) * 2) - 1);
    drift   = io.node(\drift, LFNoise2.ar(io.par(\bedDriftRate)).range(1 - io.par(\bedDriftDepth), 1.0));
    bed     = bed * drift * io.par(\bedAmp);

    sub = LPF.ar(BrownNoise.ar, io.par(\subFreq)) * io.par(\subAmt);

    fineTrig = Dust2.ar(io.par(\fineRate));
    fineLvl  = io.node(\fineLvl, expDraw.(io.par(\fineAmpMin), fineTrig));
    fine     = Decay2.ar(fineTrig * fineLvl, 0.0002, io.par(\fineDecay)) * WhiteNoise.ar;
    fine     = HPF.ar(fine, io.par(\fineHpf).clip(20, nyq)) * io.par(\fineAmt);

    popTrig = Dust2.ar(io.par(\popRate));
    popLvl  = io.node(\popLvl, expDraw.(io.par(\popAmpMin), popTrig));
    click   = io.node(\click, Decay2.ar(popTrig * popLvl, 0.0003, io.par(\popDecay)).abs) * WhiteNoise.ar;
    click   = HPF.ar(click, io.par(\popHpf).clip(20, nyq));
    body    = Ringz.ar(Decay.ar(popTrig * popLvl, 0.001), io.par(\bodyFreq).clip(20, nyq), io.par(\bodyRing))
        * io.par(\bodyAmt) * popLvl.squared;
    pops    = (click + body) * io.par(\popAmt);

    pan = io.node(\pan, LFNoise1.ar(io.par(\panRate)) * io.par(\panWidth));
    Pan2.ar(bed + sub + fine + pops, pan)
});
)
