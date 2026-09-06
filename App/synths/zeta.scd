// App/synths/zeta.scd — UNGRUND class 6/8 `zeta` (vinyl/tape surface): a quiet
// "surface" — a coloured bed (hump ~1.2 kHz, wow) plus crackle (ticks, rare
// pops with a low "thock"). High crest factor, low reverb send.
// Reference: docs/features/zeta/texture-reference.md. ~spec_zeta — source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — spectral anchors (noise has no "notes"); group \tone —
// texture/density/dynamics. disp \hz shows the nearest note + cents
~spec_zeta = (
    name: \zeta,
    params: [
        // --- group \freq ---
        ( key: \bedHpf, label: "низ подложки", group: \freq, unit: " Hz", disp: \hz,
          spec: ControlSpec(80, 600, \exp, 0, 270), reread: \contBlock, arMod: \freq ),  // bed low edge
        ( key: \bedLpf, label: "потолок подложки", group: \freq, unit: " Hz", disp: \hz,
          spec: ControlSpec(3000, 12000, \exp, 0, 11000), reread: \contBlock, arMod: \freq ),  // bed ceiling (tape hiss)
        ( key: \bedHumpFreq, label: "центр горба", group: \freq, unit: " Hz", disp: \hz,
          spec: ControlSpec(600, 2500, \exp, 0, 1200), reread: \contBlock, arMod: \freq ),  // energy centroid ~1.2k
        ( key: \subFreq, label: "потолок суба", group: \freq, unit: " Hz", disp: \hz,
          spec: ControlSpec(40, 200, \exp, 0, 120), reread: \contBlock, arMod: \freq ),  // sub-rumble ceiling
        ( key: \fineHpf, label: "наклон тиков", group: \freq, unit: " Hz", disp: \hz,
          spec: ControlSpec(1500, 8000, \exp, 0, 2000), reread: \contBlock, arMod: \freq ),  // fine-crackle HF tilt
        ( key: \popHpf, label: "наклон щелчков", group: \freq, unit: " Hz", disp: \hz,
          spec: ControlSpec(500, 6000, \exp, 0, 1500), reread: \contBlock, arMod: \freq ),  // pop HF tilt
        ( key: \bodyFreq, label: "частота тела", group: \freq, unit: " Hz", disp: \hz,
          spec: ControlSpec(80, 600, \exp, 0, 180), reread: [\event, \popRate], arMod: \freq ),  // pop "thock" body freq

        // --- group \tone ---
        ( key: \amp, label: "громкость", group: \tone,
          spec: ControlSpec(0.0, 0.5, \lin, 0, 0.32), reread: \cont, arMod: \lin ),  // layer master level
        ( key: \bedAmp, label: "уровень подложки", group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.6), reread: \cont, arMod: \lin ),  // bed level
        ( key: \bedHumpRq, label: "ширина горба", group: \tone,
          spec: ControlSpec(0.2, 1.5, \lin, 0, 0.6), reread: \contBlock, arMod: \freq ),  // hump width (rq)
        ( key: \bedHumpAmt, label: "выраж. горба", group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.55), reread: \cont, arMod: \lin ),  // hump prominence
        ( key: \bedDriftRate, label: "част. wow", group: \tone, unit: " Hz",
          spec: ControlSpec(0.02, 2.0, \exp, 0, 0.1), reread: [\seg, \bedDriftRate], arMod: \rate ),  // wow drift rate
        ( key: \bedDriftDepth, label: "глуб. wow", group: \tone,
          spec: ControlSpec(0.0, 0.8, \lin, 0, 0.25), reread: \cont, arMod: \lin ),  // drift depth
        ( key: \subAmt, label: "суб-гул", group: \tone,
          spec: ControlSpec(0.0, 0.3, \lin, 0, 0.0), reread: \cont, arMod: \lin ),  // sub-rumble level
        ( key: \fineRate, label: "плотн. тиков", group: \tone, unit: " /s",
          spec: ControlSpec(5, 120, \exp, 0, 45), reread: [\event, \fineRate], arMod: \rate ),  // fine-crackle density
        ( key: \fineDecay, label: "затух. тика", group: \tone, unit: " s",
          spec: ControlSpec(0.0003, 0.005, \exp, 0, 0.0015), reread: [\event, \fineRate], arMod: \freq ),  // tick decay
        ( key: \fineAmpMin, label: "ниж. край тиков", group: \tone,
          spec: ControlSpec(0.005, 0.3, \exp, 0, 0.04), reread: [\event, \fineRate], arMod: \freq ),  // tick exp-dist low edge (TExpRand bound: scalar, A2K)
        ( key: \fineAmt, label: "уровень тиков", group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.48), reread: \cont, arMod: \lin ),  // fine-crackle level
        ( key: \popRate, label: "плотн. щелчков", group: \tone, unit: " /s",
          spec: ControlSpec(0.2, 8.0, \exp, 0, 2.4), reread: [\event, \popRate], arMod: \rate ),  // pop density
        ( key: \popDecay, label: "затух. щелчка", group: \tone, unit: " s",
          spec: ControlSpec(0.002, 0.03, \exp, 0, 0.006), reread: [\event, \popRate], arMod: \freq ),  // pop decay
        ( key: \popAmpMin, label: "ниж. край щелчков", group: \tone,
          spec: ControlSpec(0.01, 0.5, \exp, 0, 0.14), reread: [\event, \popRate], arMod: \freq ),  // pop exp-dist low edge (TExpRand bound: scalar, A2K)
        ( key: \popAmt, label: "уровень щелчков", group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.85), reread: \cont, arMod: \lin ),  // pop level
        ( key: \bodyAmt, label: "тело", group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.4), reread: \cont, arMod: \lin ),  // "thock" prominence
        ( key: \bodyRing, label: "звон тела", group: \tone, unit: " s",
          spec: ControlSpec(0.005, 0.12, \exp, 0, 0.04), reread: [\event, \popRate], arMod: \freq ),  // body ring time
        ( key: \panWidth, label: "ширина пан.", group: \tone,
          spec: ControlSpec(0.0, 0.4, \lin, 0, 0.3), reread: \cont, arMod: \lin ),  // §F: pan ≤ ±0.4
        ( key: \panRate, label: "част. пан.", group: \tone, unit: " Hz",
          spec: ControlSpec(0.02, 2.0, \exp, 0, 0.15), reread: [\seg, \panRate], arMod: \rate )  // §F: slow pan
    ]
);


// ===== LOGIC — synthesis =============================================
// bed + sub + fine + pops -> mono sum -> Pan2 -> LeakDC -> Limiter; every
// impulse lives INSIDE the persistent graph (Dust2/Decay2), no per-event Synth
Ndef(\zeta, {
    // ar controls: declaration order = ~spec_zeta row order (parity is read by
    // eye). Slew floors are contract §5: levels 5 ms, frequencies/times/rq 2 ms,
    // Dust/LFN rates none at all
    var bedHpf        = \bedHpf.ar(270).lag(0.002);
    var bedLpf        = \bedLpf.ar(11000).lag(0.002);
    var bedHumpFreq   = \bedHumpFreq.ar(1200).lag(0.002);
    var subFreq       = \subFreq.ar(120).lag(0.002);
    var fineHpf       = \fineHpf.ar(2000).lag(0.002);
    var popHpf        = \popHpf.ar(1500).lag(0.002);
    var bodyFreq      = \bodyFreq.ar(180).lag(0.002);
    var amp           = \amp.ar(0.32).lag(0.005);
    var bedAmp        = \bedAmp.ar(0.6).lag(0.005);
    var bedHumpRq     = \bedHumpRq.ar(0.6).lag(0.002);
    var bedHumpAmt    = \bedHumpAmt.ar(0.55).lag(0.005);
    var bedDriftRate  = \bedDriftRate.ar(0.1);
    var bedDriftDepth = \bedDriftDepth.ar(0.25).lag(0.005);
    var subAmt        = \subAmt.ar(0.0).lag(0.005);
    var fineRate      = \fineRate.ar(45);
    var fineDecay     = \fineDecay.ar(0.0015).lag(0.002);
    var fineAmpMin    = \fineAmpMin.ar(0.04).lag(0.002);
    var fineAmt       = \fineAmt.ar(0.48).lag(0.005);
    var popRate       = \popRate.ar(2.4);
    var popDecay      = \popDecay.ar(0.006).lag(0.002);
    var popAmpMin     = \popAmpMin.ar(0.14).lag(0.002);
    var popAmt        = \popAmt.ar(0.85).lag(0.005);
    var bodyAmt       = \bodyAmt.ar(0.4).lag(0.005);
    var bodyRing      = \bodyRing.ar(0.04).lag(0.002);
    var panWidth      = \panWidth.ar(0.3).lag(0.005);
    var panRate       = \panRate.ar(0.15);

    var nyq, bed, bedFlat, bedHump, drift, sub;
    var fineTrig, fineLvl, fine, fineEnv;
    var popTrig, popLvl, click, body, bodyGain, pops;
    var driftRateK, panRateK, fineRateK, popRateK, fineMinK, popMinK;
    var sig, pan;

    nyq = SampleRate.ir * 0.45;

    // LFN/Dust rates through A2K: a kr UGen would silently take the first sample
    // of the block, and the declared arMod \rate demands an explicit bridge (§7.2)
    driftRateK = A2K.kr(bedDriftRate).clip(0.02, 2);
    panRateK   = A2K.kr(panRate).clip(0.02, 2);
    fineRateK  = A2K.kr(fineRate).clip(0.2, 200);
    popRateK   = A2K.kr(popRate).clip(0.2, 8);
    // TExpRand bounds are a bridge too: ar on a scalar input of the TRand family
    // raises NO error and silently yields ~0 (measured 2026-09-06), and a zero
    // level poisons the downstream Decay2 into NaN for the life of the graph
    fineMinK   = A2K.kr(fineAmpMin).clip(0.005, 0.3);
    popMinK    = A2K.kr(popAmpMin).clip(0.01, 0.5);

    // bed: PinkNoise band + wide resonant hump
    bedFlat = PinkNoise.ar;
    bedFlat = HPF.ar(bedFlat, bedHpf.clip(20, nyq));
    bedFlat = LPF.ar(bedFlat, bedLpf.clip(1000, nyq));
    bedHump = Resonz.ar(bedFlat, bedHumpFreq.clip(100, nyq), bedHumpRq.clip(0.2, 1.5));
    // XFade2: amt=0 -> plain band, amt=1 -> clear (not peaky) hump
    bed = XFade2.ar(bedFlat, bedHump, (bedHumpAmt.clip(0, 1) * 2) - 1);
    // slow wow amplitude drift (smooth LFNoise2, no chopping)
    drift = LFNoise2.kr(driftRateK).range(1 - bedDriftDepth.clip(0, 0.8), 1.0);
    bed = bed * drift * bedAmp;

    // sub rumble ("motor/tonearm" floor): keep ≥15 dB under the hump
    sub = BrownNoise.ar;
    sub = LPF.ar(sub, subFreq.clip(40, nyq));
    sub = sub * subAmt;

    // fine crackle: dense Dust2, EXPONENTIAL amplitude (many small / few
    // large), very short decay, HF tilt -> reads as ticks, not hits
    fineTrig = Dust2.ar(fineRateK);
    fineLvl  = TExpRand.ar(fineMinK, 1.0, fineTrig);
    fineEnv  = Decay2.ar(fineTrig * fineLvl, 0.0002, fineDecay.clip(0.0003, 0.005));
    fine     = fineEnv * WhiteNoise.ar;
    fine     = HPF.ar(fine, fineHpf.clip(500, nyq));
    fine     = fine * fineAmt;

    // pops: rare, exponential up to near-peak, with "thock"
    popTrig  = Dust2.ar(popRateK);
    popLvl   = TExpRand.ar(popMinK, 1.0, popTrig);
    click    = Decay2.ar(popTrig * popLvl, 0.0003, popDecay.clip(0.002, 0.03)) * WhiteNoise.ar;
    click    = HPF.ar(click, popHpf.clip(200, nyq));
    // resonant "thock" body only on the loudest pops (gate popLvl^2)
    bodyGain = bodyAmt.clip(0, 1) * popLvl.squared;
    body     = Ringz.ar(Decay.ar(popTrig * popLvl, 0.001),
                        bodyFreq.clip(40, nyq),
                        bodyRing.clip(0.005, 0.12)) * bodyGain;
    pops     = (click + body) * popAmt;

    // sum, pan, conditioning
    sig = bed + sub + fine + pops;

    pan = LFNoise1.kr(panRateK).range(panWidth.neg, panWidth.clip(0, 0.4));
    sig = Pan2.ar(sig, pan);

    sig = sig * amp;
    sig = LeakDC.ar(sig);                 // after sum + impulsive content
    sig = Limiter.ar(sig, 0.95);          // safety: rare pop+tick coincidence
    sig
});

// register spec + apply defaults (self-sufficient: 0_lib only needed for
// interactive random/presets/GUI after the full App load)
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\zeta] = ~spec_zeta;
~ungVals[\zeta]  = ();
~spec_zeta.params.do { |p|
    Ndef(\zeta).set(p.key, p.spec.default);
    ~ungVals[\zeta][p.key] = p.spec.default;
};
Ndef(\zeta).fadeTime = 0.5;   // continuous surface — soft fade
// the Ndef.set loop above DROPS the koppelfeld node mapping (n_set > n_mapa) —
// without a rebind, reloading this file silently cuts the layer off the scheme
~kfRebind !? { |f| f.(\zeta) };

("synths/zeta — spec зарегистрирован ("
    ++ ~spec_zeta.params.size ++ " параметров); ~openTuner.(\\zeta)").postln;
)
