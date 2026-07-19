// App/synths/zeta.scd — UNGRUND class 6/8 `zeta` (vinyl/tape surface): тихая
// «поверхность» — окрашенная подложка (горб ~1.2 kHz, wow) + треск (тики,
// редкие щелчки с низким «thock»). Высокий крест-фактор, ревер-посыл низкий.
// Reference: docs/features/zeta/texture-reference.md. ~spec_zeta — source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — спектральные якоря (у шума нет «нот»); group \tone —
// текстура/плотность/динамика. disp \hz кажет ближайшую ноту+центы
~spec_zeta = (
    name: \zeta,
    params: [
        // --- group \freq ---
        ( key: \bedHpf, label: "низ подложки",      group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(80,    600,   \exp, 0, 270)    ),  // bed low edge
        ( key: \bedLpf, label: "потолок подложки",      group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(3000,  12000, \exp, 0, 11000)  ),  // bed ceiling (tape hiss)
        ( key: \bedHumpFreq, label: "центр горба", group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(600,   2500,  \exp, 0, 1200)   ),  // energy centroid ~1.2k
        ( key: \subFreq, label: "потолок суба",     group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(40,    200,   \exp, 0, 120)    ),  // sub-rumble ceiling
        ( key: \fineHpf, label: "наклон тиков",     group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(1500,  8000,  \exp, 0, 2000)   ),  // fine-crackle HF tilt
        ( key: \popHpf, label: "наклон щелчков",      group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(500,   6000,  \exp, 0, 1500)   ),  // pop HF tilt
        ( key: \bodyFreq, label: "частота тела",    group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(80,    600,   \exp, 0, 180)    ),  // pop "thock" body freq

        // --- group \tone ---
        ( key: \amp, label: "громкость",          group: \tone,             spec: ControlSpec(0.0,    0.5,   \lin, 0, 0.32)   ),  // layer master level
        ( key: \bedAmp, label: "уровень подложки",       group: \tone,             spec: ControlSpec(0.0,    1.0,   \lin, 0, 0.6)    ),  // bed level
        ( key: \bedHumpRq, label: "ширина горба",    group: \tone,             spec: ControlSpec(0.2,    1.5,   \lin, 0, 0.6)    ),  // hump width (rq)
        ( key: \bedHumpAmt, label: "выраж. горба",   group: \tone,             spec: ControlSpec(0.0,    1.0,   \lin, 0, 0.55)   ),  // hump prominence
        ( key: \bedDriftRate, label: "част. wow", group: \tone, unit: " Hz", spec: ControlSpec(0.02,   2.0,   \exp, 0, 0.1)    ),  // wow drift rate
        ( key: \bedDriftDepth, label: "глуб. wow",group: \tone,             spec: ControlSpec(0.0,    0.8,   \lin, 0, 0.25)   ),  // drift depth
        ( key: \subAmt, label: "суб-гул",       group: \tone,             spec: ControlSpec(0.0,    0.3,   \lin, 0, 0.0)    ),  // sub-rumble level
        ( key: \fineRate, label: "плотн. тиков",     group: \tone, unit: " /s", spec: ControlSpec(5,      120,   \exp, 0, 45)     ),  // fine-crackle density
        ( key: \fineDecay, label: "затух. тика",    group: \tone, unit: " s",  spec: ControlSpec(0.0003, 0.005, \exp, 0, 0.0015) ),  // tick decay
        ( key: \fineAmpMin, label: "ниж. край тиков",   group: \tone,             spec: ControlSpec(0.005,  0.3,   \exp, 0, 0.04)   ),  // tick exp-dist low edge
        ( key: \fineAmt, label: "уровень тиков",      group: \tone,             spec: ControlSpec(0.0,    1.0,   \lin, 0, 0.48)   ),  // fine-crackle level
        ( key: \popRate, label: "плотн. щелчков",      group: \tone, unit: " /s", spec: ControlSpec(0.2,    8.0,   \exp, 0, 2.4)    ),  // pop density
        ( key: \popDecay, label: "затух. щелчка",     group: \tone, unit: " s",  spec: ControlSpec(0.002,  0.03,  \exp, 0, 0.006)  ),  // pop decay
        ( key: \popAmpMin, label: "ниж. край щелчков",    group: \tone,             spec: ControlSpec(0.01,   0.5,   \exp, 0, 0.14)   ),  // pop exp-dist low edge
        ( key: \popAmt, label: "уровень щелчков",       group: \tone,             spec: ControlSpec(0.0,    1.0,   \lin, 0, 0.85)   ),  // pop level
        ( key: \bodyAmt, label: "тело",      group: \tone,             spec: ControlSpec(0.0,    1.0,   \lin, 0, 0.4)    ),  // "thock" prominence
        ( key: \bodyRing, label: "звон тела",     group: \tone, unit: " s",  spec: ControlSpec(0.005,  0.12,  \exp, 0, 0.04)   ),  // body ring time
        ( key: \panWidth, label: "ширина пан.",     group: \tone,             spec: ControlSpec(0.0,    0.4,   \lin, 0, 0.3)    ),  // §F: pan ≤ ±0.4
        ( key: \panRate, label: "част. пан.",      group: \tone, unit: " Hz", spec: ControlSpec(0.02,   2.0,   \exp, 0, 0.15)   )   // §F: slow pan
    ]
);


// ===== LOGIC — synthesis =============================================
// bed + sub + fine + pops -> моно-сумма -> Pan2 -> LeakDC -> Limiter; все
// импульсы ВНУТРИ персистентного графа (Dust2/Decay2), без per-event Synth
Ndef(\zeta, { |amp = 0.32,
    bedHpf = 270, bedLpf = 11000, bedHumpFreq = 1200, bedHumpRq = 0.6, bedHumpAmt = 0.55,
    bedAmp = 0.6, bedDriftRate = 0.1, bedDriftDepth = 0.25,
    subFreq = 120, subAmt = 0.0,
    fineHpf = 2000, fineRate = 45, fineDecay = 0.0015, fineAmpMin = 0.04, fineAmt = 0.48,
    popHpf = 1500, popRate = 2.4, popDecay = 0.006, popAmpMin = 0.14, popAmt = 0.85,
    bodyFreq = 180, bodyAmt = 0.4, bodyRing = 0.04,
    panWidth = 0.3, panRate = 0.15|

    var nyq, bed, bedFlat, bedHump, drift, sub;
    var fineTrig, fineLvl, fine, fineEnv;
    var popTrig, popLvl, click, body, bodyGain, pops;
    var sig, pan;

    nyq = SampleRate.ir * 0.45;

    // bed: PinkNoise band + wide resonant hump
    bedFlat = PinkNoise.ar;
    bedFlat = HPF.ar(bedFlat, bedHpf.lag(0.2).clip(20, nyq));
    bedFlat = LPF.ar(bedFlat, bedLpf.lag(0.2).clip(1000, nyq));
    bedHump = Resonz.ar(bedFlat, bedHumpFreq.lag(0.2).clip(100, nyq), bedHumpRq.clip(0.2, 1.5));
    // XFade2: amt=0 -> plain band, amt=1 -> clear (not peaky) hump
    bed = XFade2.ar(bedFlat, bedHump, (bedHumpAmt.lag(0.1).clip(0, 1) * 2) - 1);
    // slow wow amplitude drift (smooth LFNoise2, no chopping)
    drift = LFNoise2.kr(bedDriftRate.lag(0.2).clip(0.02, 2))
                .range(1 - bedDriftDepth.clip(0, 0.8), 1.0);
    bed = bed * drift * bedAmp.lag(0.1);

    // sub rumble ("motor/tonearm" floor): keep ≥15 dB under the hump
    sub = BrownNoise.ar;
    sub = LPF.ar(sub, subFreq.lag(0.2).clip(40, nyq));
    sub = sub * subAmt.lag(0.1);

    // fine crackle: dense Dust2, EXPONENTIAL amplitude (many small / few
    // large), very short decay, HF tilt -> reads as ticks, not hits
    fineTrig = Dust2.ar(fineRate.lag(0.3).clip(0.2, 200));
    fineLvl  = TExpRand.ar(fineAmpMin.clip(0.005, 0.3), 1.0, fineTrig);
    fineEnv  = Decay2.ar(fineTrig * fineLvl, 0.0002, fineDecay.clip(0.0003, 0.005));
    fine     = fineEnv * WhiteNoise.ar;
    fine     = HPF.ar(fine, fineHpf.lag(0.2).clip(500, nyq));
    fine     = fine * fineAmt.lag(0.1);

    // pops: rare, exponential up to near-peak, with "thock"
    popTrig  = Dust2.ar(popRate.lag(0.3).clip(0.2, 8));
    popLvl   = TExpRand.ar(popAmpMin.clip(0.01, 0.5), 1.0, popTrig);
    click    = Decay2.ar(popTrig * popLvl, 0.0003, popDecay.clip(0.002, 0.03)) * WhiteNoise.ar;
    click    = HPF.ar(click, popHpf.lag(0.2).clip(200, nyq));
    // resonant "thock" body only on the loudest pops (gate popLvl^2)
    bodyGain = bodyAmt.lag(0.1).clip(0, 1) * popLvl.squared;
    body     = Ringz.ar(Decay.ar(popTrig * popLvl, 0.001),
                        bodyFreq.lag(0.2).clip(40, nyq),
                        bodyRing.clip(0.005, 0.12)) * bodyGain;
    pops     = (click + body) * popAmt.lag(0.1);

    // sum, pan, conditioning
    sig = bed + sub + fine + pops;

    pan = LFNoise1.kr(panRate.lag(0.2).clip(0.02, 2)).range(panWidth.neg, panWidth.clip(0, 0.4));
    sig = Pan2.ar(sig, pan);

    sig = sig * amp.lag(0.05);
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

("synths/zeta — spec зарегистрирован ("
    ++ ~spec_zeta.params.size ++ " параметров); ~openTuner.(\\zeta)").postln;
)
