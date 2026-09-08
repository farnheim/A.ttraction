// App/synths/alpha.scd — UNGRUND class 1/8 `alpha` (sustained sine / Grund):
// a physical model, "10 springs in oil" (ported from Tests/test_monade.scd),
// tones in MIDI notes. Walkthrough: docs/architecture/app/README.md, appendix A.
// ~spec_alpha — source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — tones; group \tone — timbre and medium
~spec_alpha = (
    name: \alpha,
    params: [
        // --- group \freq: 10 spring tones (MIDI notes, fractional = microtonal) ---
        ( key: \n1,  group: \freq, disp: \note,
          spec: ControlSpec(12, 96, \lin, 0, 29.91), reread: \contBlock, arMod: \freq ),
        ( key: \n2,  group: \freq, disp: \note,
          spec: ControlSpec(12, 96, \lin, 0, 43.87), reread: \contBlock, arMod: \freq ),
        ( key: \n3,  group: \freq, disp: \note,
          spec: ControlSpec(12, 96, \lin, 0, 54.2),  reread: \contBlock, arMod: \freq ),
        ( key: \n4,  group: \freq, disp: \note,
          spec: ControlSpec(12, 96, \lin, 0, 18.97), reread: \contBlock, arMod: \freq ),
        ( key: \n5,  group: \freq, disp: \note,
          spec: ControlSpec(12, 96, \lin, 0, 27.2),  reread: \contBlock, arMod: \freq ),
        ( key: \n6,  group: \freq, disp: \note,
          spec: ControlSpec(12, 96, \lin, 0, 26.68), reread: \contBlock, arMod: \freq ),
        ( key: \n7,  group: \freq, disp: \note,
          spec: ControlSpec(12, 96, \lin, 0, 80.12), reread: \contBlock, arMod: \freq ),
        ( key: \n8,  group: \freq, disp: \note,
          spec: ControlSpec(12, 96, \lin, 0, 87.0),  reread: \contBlock, arMod: \freq ),
        ( key: \n9,  group: \freq, disp: \note,
          spec: ControlSpec(12, 96, \lin, 0, 58.14), reread: \contBlock, arMod: \freq ),
        ( key: \n10, group: \freq, disp: \note,
          spec: ControlSpec(12, 96, \lin, 0, 16.69), reread: \contBlock, arMod: \freq ),

        // --- group \tone: timbre and medium ---
        ( key: \amp, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.30), reread: \cont, arMod: \lin ),
        ( key: \density, group: \tone, unit: " /s",
          spec: ControlSpec(0.2, 150, \exp, 0, 8.65), reread: \cont, arMod: \rate ),
        ( key: \contact, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.464), reread: \cont, arMod: \lin ),
        ( key: \decay, group: \tone, unit: " s",
          spec: ControlSpec(0.2, 8.0, \exp, 0, 3.74), reread: \cont, arMod: \freq ),
        ( key: \disperse, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.605), reread: \cont, arMod: \lin ),
        ( key: \oil, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.725), reread: \cont, arMod: \lin ),
        ( key: \muffle, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.204), reread: \cont, arMod: \lin ),
        ( key: \bright, group: \tone, unit: " Hz",
          spec: ControlSpec(1500, 6000, \exp, 0, 2800), reread: \contBlock, arMod: \freq ),  // dry-contact HPF
        ( key: \metalAmt, group: \tone,
          spec: ControlSpec(0.0, 0.8, \lin, 0, 0.22), reread: \cont, arMod: \lin ),  // contact metal-ring level
        ( key: \metalRing, group: \tone, unit: " s",
          spec: ControlSpec(0.02, 0.3, \exp, 0, 0.12), reread: \contBlock, arMod: \freq ),  // mode ring time (wood<->metal)
        ( key: \metalWeight, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.35), reread: \cont, arMod: \lin ),  // short low impact thump
        ( key: \bodyLevel, group: \tone,
          spec: ControlSpec(0.0, 0.3, \lin, 0, 0.12), reread: \cont, arMod: \lin ),  // tonal bundle body
        ( key: \drive, group: \tone,
          spec: ControlSpec(0.5, 4.0, \exp, 0, 1.2), reread: \cont, arMod: \lin ),  // tanh pre-gain
        ( key: \sprGain, group: \tone,
          spec: ControlSpec(1.0, 7.0, \lin, 0, 4.6), reread: \cont, arMod: \lin ),  // spring-sum gain
        ( key: \swayRate, group: \tone, unit: " Hz",
          spec: ControlSpec(0.02, 0.5, \exp, 0, 0.1), reread: [\seg, \swayRate], arMod: \rate ),  // breathing rate
        ( key: \cutTop, group: \tone, unit: " Hz",
          spec: ControlSpec(2000, 8000, \exp, 0, 5400), reread: \contBlock, arMod: \freq ),  // LPF top
        ( key: \cutOil, group: \tone, unit: " Hz",
          spec: ControlSpec(0, 5000, \lin, 0, 3800), reread: \contBlock, arMod: \freq )  // oil darkening depth
    ]
);


// ===== LOGIC — synthesis =============================================
Ndef(\alpha, {
    // ar controls: declaration order = ~spec_alpha row order. Slew floors are
    // contract §5: levels 5 ms, frequencies/times 2 ms, LFN/Dust rates none at
    // all (they are reread, not continuous)
    var n1  = \n1.ar(29.91).lag(0.002);
    var n2  = \n2.ar(43.87).lag(0.002);
    var n3  = \n3.ar(54.2).lag(0.002);
    var n4  = \n4.ar(18.97).lag(0.002);
    var n5  = \n5.ar(27.2).lag(0.002);
    var n6  = \n6.ar(26.68).lag(0.002);
    var n7  = \n7.ar(80.12).lag(0.002);
    var n8  = \n8.ar(87.0).lag(0.002);
    var n9  = \n9.ar(58.14).lag(0.002);
    var n10 = \n10.ar(16.69).lag(0.002);
    var amp         = \amp.ar(0.30).lag(0.005);
    var density     = \density.ar(8.65);
    var contact     = \contact.ar(0.464).lag(0.005);
    var decay       = \decay.ar(3.74).lag(0.002);
    var disperse    = \disperse.ar(0.605).lag(0.005);
    var oil         = \oil.ar(0.725).lag(0.005);
    var muffle      = \muffle.ar(0.204).lag(0.005);
    var bright      = \bright.ar(2800).lag(0.002);
    var metalAmt    = \metalAmt.ar(0.22).lag(0.005);
    var metalRing   = \metalRing.ar(0.12).lag(0.002);
    var metalWeight = \metalWeight.ar(0.35).lag(0.005);
    var bodyLevel   = \bodyLevel.ar(0.12).lag(0.005);
    var drive       = \drive.ar(1.2).lag(0.005);
    var sprGain     = \sprGain.ar(4.6).lag(0.005);
    var swayRate    = \swayRate.ar(0.1);
    var cutTop      = \cutTop.ar(5400).lag(0.002);
    var cutOil      = \cutOil.ar(3800).lag(0.002);

    var decayL, oilL, dispL, muffL, swayRateK;
    var sway, dens, contacts, ticks, metal, body, notes;
    var springs, bundle, cutBase, sigL, sigR;
    var mRing, mDet, mFreqs, mRings, mAmps, mThump;
    var nSprings = 10;

    decayL = decay.clip(0.1, 10);
    oilL   = oil.clip(0, 1);
    dispL  = disperse.clip(0, 1);
    muffL  = muffle.clip(0, 1);

    // LFN rate through A2K: a kr input fed with ar is read as ZIN0, silently
    swayRateK = A2K.kr(swayRate).clip(0.005, 2);
    sway = LFNoise2.kr(swayRateK).range(0.3, 1.0);

    dens     = (A2K.kr(density) * sway).clip(0.05, 400);
    contacts = Dust2.ar(dens);

    // dry contact — bright, no low partials
    ticks = Decay2.ar(contacts.abs, 0.0004, 0.006 + (oilL * 0.02));
    ticks = ticks * ((BrownNoise.ar * 0.7) + 0.5);
    ticks = HPF.ar(ticks, bright.clip(500, 10000));
    // metal — an inharmonic bank with a HIGH centre (shimmer); the bottom is
    // only a short weight thump, no wooden note
    mRing  = metalRing.clip(0.01, 0.4);
    mDet   = LFNoise0.kr([7, 9, 11, 13, 6, 8, 10, 12, 5]).range(0.985, 1.015);
    mFreqs = [413, 661, 977, 1490, 2137, 3001, 4313, 5897, 7639] * mDet;
    mRings = mRing * [0.8, 0.9, 1.0, 1.0, 0.95, 0.88, 0.78, 0.66, 0.55];
    mAmps  = [0.4, 0.55, 0.7, 0.9, 1.0, 0.92, 0.78, 0.62, 0.46];
    mThump = Ringz.ar(contacts, 132 * LFNoise0.kr(4).range(0.98, 1.02), 0.035)
                * metalWeight * 0.7;
    metal  = (Mix(Ringz.ar(contacts, mFreqs, mRings) * mAmps) + mThump)
                * 0.45 * metalAmt;
    ticks = ((ticks * 0.7) + metal) * contact;

    // body — continuous low noise: the mass of the bundle in motion
    body = BrownNoise.ar(bodyLevel) * LFNoise2.kr(0.35).range(0.3, 1.0);

    // a bundle of 10 springs, each on its own tone (note -> Hz)
    notes = [n1, n2, n3, n4, n5, n6, n7, n8, n9, n10];
    springs = Array.fill(nSprings, { |i|
        var sf, sd, collGain, ringGain, voice;
        sf       = notes[i].midicps.clip(20, 2400);
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
    bundle = Mix(springs) * (1 / nSprings) * sprGain;
    bundle = bundle + (ticks * 0.9);

    cutBase = (cutTop - (oilL * cutOil)).clip(300, 9000);
    bundle  = LPF.ar(bundle, cutBase);
    bundle  = (bundle * drive).tanh;
    bundle  = LeakDC.ar(bundle);             // §DSP: after the nonlinearity

    sigL = LPF.ar(bundle, (cutBase * (1 - (muffL * 0.82))).clip(180, 9000));
    sigL = DelayC.ar(sigL, 0.05, muffL * 0.02);
    sigL = sigL * (1 - (muffL * 0.4));
    sigR = bundle;

    sigL = sigL * amp * (0.78 + (sway * 0.22));
    sigR = sigR * amp * (0.78 + (sway * 0.22));

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
// the Ndef.set loop above DROPS the koppelfeld node mapping (n_set > n_mapa) —
// without a rebind, reloading this file silently cuts the layer off the scheme
~kfRebind !? { |f| f.(\alpha) };

("synths/alpha — spec зарегистрирован ("
    ++ ~spec_alpha.params.size ++ " параметров); ~openTuner.(\\alpha)").postln;
)
