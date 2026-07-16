// App/synths/alpha.scd — UNGRUND class 1/8 `alpha` (sustained sine / Grund).
// REAL LAYER: physical model "bundle of 10 springs in oil" (ported from
// Tests/test_monade.scd). Tones in MIDI notes (.midicps inside).
// Tuning via 0_lib.scd: ~openTuner/~rndFreq/~rndParams/~save~loadPreset.
// ~spec_alpha is the single source of truth (sliders/randomizers/presets);
// layer contract: docs/architecture/app/layer-contract.md.


// ===== CONFIG — edit here ============================================
(
// group \freq — tones; group \tone — timbre/medium. spec gives range,
// warp and DEFAULT (applied at layer load).
~spec_alpha = (
    name: \alpha,
    params: [
        // --- group \freq: 10 spring tones (MIDI notes, fractional = microtonal) ---
        ( key: \n1,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 29.91) ),
        ( key: \n2,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 43.87) ),
        ( key: \n3,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 54.2)  ),
        ( key: \n4,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 18.97) ),
        ( key: \n5,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 27.2)  ),
        ( key: \n6,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 26.68) ),
        ( key: \n7,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 80.12) ),
        ( key: \n8,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 87.0)  ),
        ( key: \n9,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 58.14) ),
        ( key: \n10, group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 16.69) ),

        // --- group \tone: timbre and medium ---
        ( key: \amp,       group: \tone,             spec: ControlSpec(0.0, 1.0,  \lin, 0, 0.30)  ),
        ( key: \density,   group: \tone, unit: " /s", spec: ControlSpec(0.2, 150,  \exp, 0, 8.65)  ),
        ( key: \contact,   group: \tone,             spec: ControlSpec(0.0, 1.0,  \lin, 0, 0.464) ),
        ( key: \decay,     group: \tone, unit: " s",  spec: ControlSpec(0.2, 8.0,  \exp, 0, 3.74)  ),
        ( key: \disperse,  group: \tone,             spec: ControlSpec(0.0, 1.0,  \lin, 0, 0.605) ),
        ( key: \oil,       group: \tone,             spec: ControlSpec(0.0, 1.0,  \lin, 0, 0.725) ),
        ( key: \muffle,    group: \tone,             spec: ControlSpec(0.0, 1.0,  \lin, 0, 0.204) ),
        ( key: \bright,    group: \tone, unit: " Hz", spec: ControlSpec(1500, 6000, \exp, 0, 2800) ),  // dry-contact HPF
        ( key: \metalAmt,  group: \tone,             spec: ControlSpec(0.0, 0.8,  \lin, 0, 0.22)  ),  // contact metal-ring level
        ( key: \metalRing, group: \tone, unit: " s",  spec: ControlSpec(0.02, 0.3, \exp, 0, 0.12)  ),  // mode ring time (wood<->metal)
        ( key: \metalWeight,group: \tone,            spec: ControlSpec(0.0, 1.0,  \lin, 0, 0.35)  ),  // short low impact thump
        ( key: \bodyLevel, group: \tone,             spec: ControlSpec(0.0, 0.3,  \lin, 0, 0.12)  ),  // tonal bundle body
        ( key: \drive,     group: \tone,             spec: ControlSpec(0.5, 4.0,  \exp, 0, 1.2)   ),  // tanh pre-gain
        ( key: \sprGain,   group: \tone,             spec: ControlSpec(1.0, 7.0,  \lin, 0, 4.6)   ),  // spring-sum gain
        ( key: \swayRate,  group: \tone, unit: " Hz", spec: ControlSpec(0.02, 0.5, \exp, 0, 0.1)   ),  // breathing rate
        ( key: \cutTop,    group: \tone, unit: " Hz", spec: ControlSpec(2000, 8000, \exp, 0, 5400) ),  // LPF top
        ( key: \cutOil,    group: \tone, unit: " Hz", spec: ControlSpec(0, 5000,   \lin, 0, 3800)  )   // oil darkening depth
    ]
);


// ===== LOGIC — synthesis =============================================
Ndef(\alpha, { |amp = 0.30, density = 8.65, contact = 0.464,
                 decay = 3.74, disperse = 0.605, oil = 0.725, muffle = 0.204,
                 bright = 2800, metalAmt = 0.22, bodyLevel = 0.12, drive = 1.2,
                 sprGain = 4.6, swayRate = 0.1, cutTop = 5400, cutOil = 3800,
                 metalRing = 0.12, metalWeight = 0.35,
                 n1 = 29.91, n2 = 43.87, n3 = 54.2, n4 = 18.97, n5 = 27.2,
                 n6 = 26.68, n7 = 80.12, n8 = 87.0, n9 = 58.14, n10 = 16.69|
    var decayL, oilL, dispL, muffL,
        sway, dens, contacts, ticks, metal, body, notes,
        springs, bundle, cutBase, sigL, sigR,
        mRing, mDet, mFreqs, mRings, mAmps, mThump;
    var nSprings = 10;

    decayL = decay.lag(0.3).clip(0.1, 10);
    oilL   = oil.lag(0.3).clip(0, 1);
    dispL  = disperse.lag(0.3).clip(0, 1);
    muffL  = muffle.lag(0.3).clip(0, 1);

    sway = LFNoise2.kr(swayRate.clip(0.005, 2)).range(0.3, 1.0);

    dens     = (density.lag(0.2) * sway).clip(0.05, 400);
    contacts = Dust2.ar(dens);

    // dry contact — bright, no low overtone content
    ticks = Decay2.ar(contacts.abs, 0.0004, 0.006 + (oilL * 0.02));
    ticks = ticks * ((BrownNoise.ar * 0.7) + 0.5);
    ticks = HPF.ar(ticks, bright.lag(0.2).clip(500, 10000));
    // metal — spring-contact ring: inharmonic modal bank with a HIGH spectral
    // centre; high modes louder and longer (shimmer), lows only a short
    // weight thump (metalWeight), no ringing wooden note
    mRing  = metalRing.lag(0.2).clip(0.01, 0.4);
    mDet   = LFNoise0.kr([7, 9, 11, 13, 6, 8, 10, 12, 5]).range(0.985, 1.015);
    mFreqs = [413, 661, 977, 1490, 2137, 3001, 4313, 5897, 7639] * mDet;
    mRings = mRing * [0.8, 0.9, 1.0, 1.0, 0.95, 0.88, 0.78, 0.66, 0.55];
    mAmps  = [0.4, 0.55, 0.7, 0.9, 1.0, 0.92, 0.78, 0.62, 0.46];
    mThump = Ringz.ar(contacts, 132 * LFNoise0.kr(4).range(0.98, 1.02), 0.035)
                * metalWeight.lag(0.2) * 0.7;
    metal  = (Mix(Ringz.ar(contacts, mFreqs, mRings) * mAmps) + mThump)
                * 0.45 * metalAmt.lag(0.2);
    ticks = ((ticks * 0.7) + metal) * contact.lag(0.2);

    // body — continuous low noise: the bundle's mass in motion
    body = BrownNoise.ar(bodyLevel.lag(0.2)) * LFNoise2.kr(0.35).range(0.3, 1.0);

    // bundle of 10 springs, each on its own tone (note -> Hz)
    notes = [n1, n2, n3, n4, n5, n6, n7, n8, n9, n10];
    springs = Array.fill(nSprings, { |i|
        var sf, sd, collGain, ringGain, voice;
        sf       = notes[i].lag(0.2).midicps.clip(20, 2400);
        sd       = decayL * (0.7 + (i * 0.55 / nSprings));
        collGain = sf.linlin(110, 430, 0.08, 0.8);
        ringGain = sf.linexp(45, 700, 1.5, 0.65);
        voice = ((body) + (contacts * collGain))
                    * LFNoise2.kr(0.3 + (i * 0.05)).range(0.4, 1.0)
                    * 0.05 / sd.max(0.3);
        3.do { |k|
            var dt = LFNoise2.kr(0.2 + (i * 0.04) + (k * 0.07))
                .range(0.003, 0.003 + (dispL * 0.021));
            voice = AllpassC.ar(voice, 0.03, dt, 0.03 + (dispL * 0.07));
        };
        voice = CombC.ar(
            voice, 0.12,
            ((1 / sf) * (1 + LFNoise2.kr(0.13 + (i * 0.03))
                .range(oilL.neg * 0.01, oilL * 0.01))).clip(0.0004, 0.115),
            sd * (1 - (oilL * 0.55))
        );
        voice * ringGain
    });
    bundle = Mix(springs) * (1 / nSprings) * sprGain.lag(0.2);
    bundle = bundle + (ticks * 0.9);

    cutBase = (cutTop.lag(0.3) - (oilL * cutOil.lag(0.3))).clip(300, 9000);
    bundle  = LPF.ar(bundle, cutBase);
    bundle  = (bundle * drive.lag(0.2)).tanh;
    bundle  = LeakDC.ar(bundle);             // §DSP: after the nonlinearity

    sigL = LPF.ar(bundle, (cutBase * (1 - (muffL * 0.82))).clip(180, 9000));
    sigL = DelayC.ar(sigL, 0.05, muffL * 0.02);
    sigL = sigL * (1 - (muffL * 0.4));
    sigR = bundle;

    sigL = sigL * amp.lag(0.05) * (0.78 + (sway * 0.22));
    sigR = sigR * amp.lag(0.05) * (0.78 + (sway * 0.22));

    [sigL, sigR]
});

// register spec + apply defaults (self-sufficient: 0_lib only needed for
// interactive random/presets/GUI after the full App load)
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\alpha] = ~spec_alpha;
~ungVals[\alpha]  = ();
~spec_alpha.params.do { |p|
    Ndef(\alpha).set(p.key, p.spec.default);
    ~ungVals[\alpha][p.key] = p.spec.default;
};
Ndef(\alpha).fadeTime = 6;   // §0001: atk/rel framing ~6 s

("synths/alpha — spec зарегистрирован ("
    ++ ~spec_alpha.params.size ++ " параметров); ~openTuner.(\\alpha)").postln;
)
