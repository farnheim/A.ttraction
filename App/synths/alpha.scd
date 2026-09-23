// App/synths/alpha.scd — machine `alpha`: ten tuned combs in oil, struck by
// contact noise and a metal bank. Everything audio rate; every parameter and
// the inner variables below are sources and destinations of the field.


// ===== CONFIG — edit here ============================================
(
~spec_alpha = (
    name: \alpha,
    params: [
        ( key: \n1,  group: \freq, spec: ControlSpec(12, 96, \lin, 0, 29.91) ),
        ( key: \n2,  group: \freq, spec: ControlSpec(12, 96, \lin, 0, 43.87) ),
        ( key: \n3,  group: \freq, spec: ControlSpec(12, 96, \lin, 0, 54.2) ),
        ( key: \n4,  group: \freq, spec: ControlSpec(12, 96, \lin, 0, 18.97) ),
        ( key: \n5,  group: \freq, spec: ControlSpec(12, 96, \lin, 0, 27.2) ),
        ( key: \n6,  group: \freq, spec: ControlSpec(12, 96, \lin, 0, 26.68) ),
        ( key: \n7,  group: \freq, spec: ControlSpec(12, 96, \lin, 0, 80.12) ),
        ( key: \n8,  group: \freq, spec: ControlSpec(12, 96, \lin, 0, 87.0) ),
        ( key: \n9,  group: \freq, spec: ControlSpec(12, 96, \lin, 0, 58.14) ),
        ( key: \n10, group: \freq, spec: ControlSpec(12, 96, \lin, 0, 16.69) ),
        ( key: \amp,         group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.30) ),
        ( key: \density,     group: \tone, spec: ControlSpec(0.2, 2000, \exp, 0, 8.65) ),
        ( key: \contact,     group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.464) ),
        ( key: \decay,       group: \tone, spec: ControlSpec(0.05, 12.0, \exp, 0, 3.74) ),
        ( key: \disperse,    group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.605) ),
        ( key: \oil,         group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.725) ),
        ( key: \muffle,      group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.204) ),
        ( key: \bright,      group: \tone, spec: ControlSpec(200, 10000, \exp, 0, 2800) ),
        ( key: \metalAmt,    group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.22) ),
        ( key: \metalRing,   group: \tone, spec: ControlSpec(0.005, 1.0, \exp, 0, 0.12) ),
        ( key: \metalWeight, group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.35) ),
        ( key: \bodyLevel,   group: \tone, spec: ControlSpec(0.0, 0.5, \lin, 0, 0.12) ),
        ( key: \drive,       group: \tone, spec: ControlSpec(0.5, 12.0, \exp, 0, 1.2) ),
        ( key: \sprGain,     group: \tone, spec: ControlSpec(0.5, 10.0, \lin, 0, 4.6) ),
        ( key: \swayRate,    group: \tone, spec: ControlSpec(0.02, 200, \exp, 0, 0.1) ),
        ( key: \cutTop,      group: \tone, spec: ControlSpec(300, 12000, \exp, 0, 5400) ),
        ( key: \cutOil,      group: \tone, spec: ControlSpec(0, 8000, \lin, 0, 3800) )
    ],
    vars: [
        ( key: \sway,  spec: ControlSpec(0.0, 1.0, \lin) ),
        ( key: \dens,  spec: ControlSpec(0.05, 4000, \exp) ),
        ( key: \mDet,  spec: ControlSpec(0.8, 1.25, \exp) ),
        ( key: \thump, spec: ControlSpec(20, 2000, \exp) ),
        ( key: \sf,    spec: ControlSpec(20, 2400, \exp) ),
        ( key: \dt,    spec: ControlSpec(0.0005, 0.03, \exp) ),
        ( key: \cut,   spec: ControlSpec(100, 12000, \exp) )
    ]
);


// ===== LOGIC =========================================================
~netRegister.(~spec_alpha, 6);
Ndef(\alpha, ~netMachine.(~spec_alpha, { |io|
    var notes = (1..10).collect { |i| io.par(("n" ++ i).asSymbol) };
    var amp = io.par(\amp), density = io.par(\density), contact = io.par(\contact);
    var decay = io.par(\decay), disperse = io.par(\disperse), oil = io.par(\oil);
    var muffle = io.par(\muffle), bright = io.par(\bright);
    var metalAmt = io.par(\metalAmt), metalRing = io.par(\metalRing);
    var metalWeight = io.par(\metalWeight), bodyLevel = io.par(\bodyLevel);
    var drive = io.par(\drive), sprGain = io.par(\sprGain), swayRate = io.par(\swayRate);
    var cutTop = io.par(\cutTop), cutOil = io.par(\cutOil);
    var feed = io.feed;
    var nSprings = 10;
    var sway, dens, contacts, ticks, mDet, mFreqs, mRings, mAmps, mThump, metal;
    var body, springs, bundle, cutBase, sigL, sigR;

    sway     = io.node(\sway, LFNoise2.ar(swayRate).range(0.3, 1.0));
    dens     = io.node(\dens, density * sway);
    contacts = Dust2.ar(dens);

    ticks = Decay2.ar(contacts.abs, 0.0004, 0.006 + (oil * 0.02));
    ticks = ticks * ((BrownNoise.ar * 0.7) + 0.5);
    ticks = HPF.ar(ticks, bright);

    mDet   = io.node(\mDet, LFNoise0.ar([7, 9, 11, 13, 6, 8, 10, 12, 5]).range(0.985, 1.015));
    mFreqs = ([413, 661, 977, 1490, 2137, 3001, 4313, 5897, 7639] * mDet).clip(20, 18000);
    mRings = metalRing * [0.8, 0.9, 1.0, 1.0, 0.95, 0.88, 0.78, 0.66, 0.55];
    mAmps  = [0.4, 0.55, 0.7, 0.9, 1.0, 0.92, 0.78, 0.62, 0.46];
    mThump = Ringz.ar(contacts, io.node(\thump, 132 * LFNoise0.ar(4).range(0.98, 1.02)), 0.035)
        * metalWeight * 0.7;
    metal  = (Mix(Ringz.ar(contacts, mFreqs, mRings) * mAmps) + mThump) * 0.45 * metalAmt;
    ticks  = ((ticks * 0.7) + metal) * contact;

    body = BrownNoise.ar(bodyLevel) * LFNoise2.ar(0.35).range(0.3, 1.0);

    springs = Array.fill(nSprings, { |i|
        var sf       = io.node(\sf, notes[i].midicps.clip(20, 2400));
        var sd       = decay * (0.7 + (i * 0.55 / nSprings));
        var collGain = sf.linlin(110, 430, 0.08, 0.8);
        var ringGain = sf.linexp(45, 700, 1.5, 0.65);
        var voice = (body + (contacts * collGain) + feed)
            * LFNoise2.ar(0.3 + (i * 0.05)).range(0.4, 1.0)
            * 0.05 / sd.max(0.3);
        3.do { |k|
            var dt = io.node(\dt, LFNoise2.ar(0.2 + (i * 0.04) + (k * 0.07))
                .range(0.003, 0.003 + (disperse * 0.021)));
            voice = AllpassC.ar(voice, 0.03, dt, 0.03 + (disperse * 0.07));
        };
        voice = CombC.ar(
            voice, 0.12,
            ((1 / sf) * (1 + LFNoise2.ar(0.13 + (i * 0.03)).range(oil.neg * 0.01, oil * 0.01)))
                .clip(0.0004, 0.115),
            sd * (1 - (oil * 0.55))
        );
        voice * ringGain
    });
    bundle = Mix(springs) * (1 / nSprings) * sprGain;
    bundle = bundle + (ticks * 0.9);

    cutBase = io.node(\cut, (cutTop - (oil * cutOil)).clip(100, 12000));
    bundle  = LPF.ar(bundle, cutBase);
    bundle  = LeakDC.ar((bundle * drive).tanh);

    sigL = LPF.ar(bundle, (cutBase * (1 - (muffle * 0.82))).clip(60, 12000));
    sigL = DelayC.ar(sigL, 0.05, muffle * 0.02) * (1 - (muffle * 0.4));
    sigR = bundle;

    io.emit(Limiter.ar([sigL, sigR] * amp * (0.78 + (sway * 0.22)), 0.95))
}));

~netRewire.value;
)
