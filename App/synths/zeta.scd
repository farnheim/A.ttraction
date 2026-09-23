// App/synths/zeta.scd — machine `zeta`: a filtered noise bed with a resonant
// hump, a sub floor, dense fine ticks and rare pops with a ringing body.
// Everything audio rate; the ticks are Dust inside the graph.


// ===== CONFIG — edit here ============================================
(
~spec_zeta = (
    name: \zeta,
    params: [
        ( key: \bedHpf,        group: \freq, spec: ControlSpec(20, 2000, \exp, 0, 270) ),
        ( key: \bedLpf,        group: \freq, spec: ControlSpec(500, 16000, \exp, 0, 11000) ),
        ( key: \bedHumpFreq,   group: \freq, spec: ControlSpec(60, 8000, \exp, 0, 1200) ),
        ( key: \subFreq,       group: \freq, spec: ControlSpec(20, 400, \exp, 0, 120) ),
        ( key: \fineHpf,       group: \freq, spec: ControlSpec(200, 12000, \exp, 0, 2000) ),
        ( key: \popHpf,        group: \freq, spec: ControlSpec(100, 10000, \exp, 0, 1500) ),
        ( key: \bodyFreq,      group: \freq, spec: ControlSpec(30, 2000, \exp, 0, 180) ),
        ( key: \amp,           group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.32) ),
        ( key: \bedAmp,        group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.6) ),
        ( key: \bedHumpRq,     group: \tone, spec: ControlSpec(0.01, 2.0, \exp, 0, 0.6) ),
        ( key: \bedHumpAmt,    group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.55) ),
        ( key: \bedDriftRate,  group: \tone, spec: ControlSpec(0.02, 200, \exp, 0, 0.1) ),
        ( key: \bedDriftDepth, group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.25) ),
        ( key: \subAmt,        group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.0) ),
        ( key: \fineRate,      group: \tone, spec: ControlSpec(1, 5000, \exp, 0, 45) ),
        ( key: \fineDecay,     group: \tone, spec: ControlSpec(0.0002, 0.05, \exp, 0, 0.0015) ),
        ( key: \fineAmpMin,    group: \tone, spec: ControlSpec(0.005, 1.0, \exp, 0, 0.04) ),
        ( key: \fineAmt,       group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.48) ),
        ( key: \popRate,       group: \tone, spec: ControlSpec(0.05, 200, \exp, 0, 2.4) ),
        ( key: \popDecay,      group: \tone, spec: ControlSpec(0.001, 0.2, \exp, 0, 0.006) ),
        ( key: \popAmpMin,     group: \tone, spec: ControlSpec(0.01, 1.0, \exp, 0, 0.14) ),
        ( key: \popAmt,        group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.85) ),
        ( key: \bodyAmt,       group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.4) ),
        ( key: \bodyRing,      group: \tone, spec: ControlSpec(0.002, 2.0, \exp, 0, 0.04) ),
        ( key: \panWidth,      group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.3) ),
        ( key: \panRate,       group: \tone, spec: ControlSpec(0.02, 100, \exp, 0, 0.15) )
    ],
    vars: [
        ( key: \drift,   spec: ControlSpec(0.0, 1.0, \lin) ),
        ( key: \fineLvl, spec: ControlSpec(0.005, 1.0, \exp) ),
        ( key: \popLvl,  spec: ControlSpec(0.01, 1.0, \exp) ),
        ( key: \click,   spec: ControlSpec(0.0, 1.0, \lin) ),
        ( key: \pan,     spec: ControlSpec(-1.0, 1.0, \lin) )
    ]
);


// ===== LOGIC =========================================================
~netRegister.(~spec_zeta, 0.5);
Ndef(\zeta, ~netMachine.(~spec_zeta, { |io|
    var bedHpf = io.par(\bedHpf), bedLpf = io.par(\bedLpf), bedHumpFreq = io.par(\bedHumpFreq);
    var subFreq = io.par(\subFreq), fineHpf = io.par(\fineHpf), popHpf = io.par(\popHpf);
    var bodyFreq = io.par(\bodyFreq), amp = io.par(\amp), bedAmp = io.par(\bedAmp);
    var bedHumpRq = io.par(\bedHumpRq), bedHumpAmt = io.par(\bedHumpAmt);
    var bedDriftRate = io.par(\bedDriftRate), bedDriftDepth = io.par(\bedDriftDepth);
    var subAmt = io.par(\subAmt), fineRate = io.par(\fineRate), fineDecay = io.par(\fineDecay);
    var fineAmpMin = io.par(\fineAmpMin), fineAmt = io.par(\fineAmt), popRate = io.par(\popRate);
    var popDecay = io.par(\popDecay), popAmpMin = io.par(\popAmpMin), popAmt = io.par(\popAmt);
    var bodyAmt = io.par(\bodyAmt), bodyRing = io.par(\bodyRing);
    var panWidth = io.par(\panWidth), panRate = io.par(\panRate);
    var feed = io.feed;
    var nyq = SampleRate.ir * 0.45;
    var expDraw = { |lo, trig| Latch.ar(lo * (lo.reciprocal ** WhiteNoise.ar.range(0, 1)), trig) };
    var bedFlat, bedHump, bed, drift, sub, fineTrig, fineLvl, fine, popTrig, popLvl;
    var click, bodyGain, body, pops, sig, pan;

    bedFlat = PinkNoise.ar + feed;
    bedFlat = HPF.ar(bedFlat, bedHpf.clip(20, nyq));
    bedFlat = LPF.ar(bedFlat, bedLpf.clip(100, nyq));
    bedHump = Resonz.ar(bedFlat, bedHumpFreq.clip(30, nyq), bedHumpRq);
    bed     = XFade2.ar(bedFlat, bedHump, (bedHumpAmt * 2) - 1);
    drift   = io.node(\drift, LFNoise2.ar(bedDriftRate).range(1 - bedDriftDepth, 1.0));
    bed     = bed * drift * bedAmp;

    sub = LPF.ar(BrownNoise.ar, subFreq) * subAmt;

    fineTrig = Dust2.ar(fineRate);
    fineLvl  = io.node(\fineLvl, expDraw.(fineAmpMin, fineTrig));
    fine     = Decay2.ar(fineTrig * fineLvl, 0.0002, fineDecay) * WhiteNoise.ar;
    fine     = HPF.ar(fine, fineHpf.clip(20, nyq)) * fineAmt;

    popTrig  = Dust2.ar(popRate);
    popLvl   = io.node(\popLvl, expDraw.(popAmpMin, popTrig));
    click    = io.node(\click, Decay2.ar(popTrig * popLvl, 0.0003, popDecay).abs.clip(0, 1))
        * WhiteNoise.ar;
    click    = HPF.ar(click, popHpf.clip(20, nyq));
    bodyGain = bodyAmt * popLvl.squared;
    body     = Ringz.ar(Decay.ar(popTrig * popLvl, 0.001), bodyFreq.clip(20, nyq), bodyRing) * bodyGain;
    pops     = (click + body) * popAmt;

    sig = bed + sub + fine + pops;
    pan = io.node(\pan, LFNoise1.ar(panRate) * panWidth);
    sig = Pan2.ar(sig, pan) * amp;

    io.emit(Limiter.ar(LeakDC.ar(sig), 0.95))
}));

~netRewire.value;
)
