// App/synths/alpha.scd — machine `alpha`: tuned combs in oil (§C.1)

// ===== CONFIG — edit here ============================================
(
~spec_alpha = (
    name: \alpha,
    level: 0.9499,
    fade: 6,
    params: [
        n1:  [12, 96, \lin, 0, 29.91],
        n2:  [12, 96, \lin, 0, 43.87],
        n3:  [12, 96, \lin, 0, 54.2],
        n4:  [12, 96, \lin, 0, 18.97],
        n5:  [12, 96, \lin, 0, 27.2],
        n6:  [12, 96, \lin, 0, 26.68],
        n7:  [12, 96, \lin, 0, 80.12],
        n8:  [12, 96, \lin, 0, 87.0],
        n9:  [12, 96, \lin, 0, 58.14],
        n10: [12, 96, \lin, 0, 16.69],
        density:     [0.2, 2000, \exp, 0, 8.65],
        contact:     [0.0, 1.0, \lin, 0, 0.464],
        decay:       [0.05, 12.0, \exp, 0, 3.74],
        disperse:    [0.0, 1.0, \lin, 0, 0.605],
        oil:         [0.0, 1.0, \lin, 0, 0.725],
        muffle:      [0.0, 1.0, \lin, 0, 0.204],
        bright:      [200, 10000, \exp, 0, 2800],
        metalAmt:    [0.0, 1.0, \lin, 0, 0.22],
        metalRing:   [0.005, 1.0, \exp, 0, 0.12],
        metalWeight: [0.0, 1.0, \lin, 0, 0.35],
        bodyLevel:   [0.0, 0.5, \lin, 0, 0.12],
        drive:       [0.5, 12.0, \exp, 0, 1.2],
        sprGain:     [0.5, 10.0, \lin, 0, 4.6],
        swayRate:    [0.02, 200, \exp, 0, 0.1],
        cutTop:      [300, 12000, \exp, 0, 5400],
        cutOil:      [0, 8000, \lin, 0, 3800]
    ],
    vars: [
        sway:  [0.0, 1.0],
        dens:  [0.05, 4000, \exp],
        mDet:  [0.8, 1.25, \exp],
        thump: [20, 2000, \exp],
        sf:    [20, 2400, \exp],
        dt:    [0.0005, 0.03, \exp],
        cut:   [100, 12000, \exp]
    ]
);

// ===== LOGIC =========================================================
~netMachine.(~spec_alpha, { |io|
    var notes = (1..10).collect { |i| io.par(("n" ++ i).asSymbol) };
    var oil = io.par(\oil), disperse = io.par(\disperse), muffle = io.par(\muffle);
    var sway, contacts, ticks, mDet, mFreqs, mRings, mAmps, mThump, metal;
    var body, springs, bundle, cutBase, sigL;

    sway     = io.node(\sway, LFNoise2.ar(io.par(\swayRate)).range(0.3, 1.0));
    contacts = Dust2.ar(io.node(\dens, io.par(\density) * sway));

    ticks = Decay2.ar(contacts.abs, 0.0004, 0.006 + (oil * 0.02));
    ticks = ticks * ((BrownNoise.ar * 0.7) + 0.5);
    ticks = HPF.ar(ticks, io.par(\bright));

    mDet   = io.node(\mDet, LFNoise0.ar([7, 9, 11, 13, 6, 8, 10, 12, 5]).range(0.985, 1.015));
    mFreqs = (#[413, 661, 977, 1490, 2137, 3001, 4313, 5897, 7639] * mDet).clip(20, io.nyq);
    mRings = io.par(\metalRing) * #[0.8, 0.9, 1.0, 1.0, 0.95, 0.88, 0.78, 0.66, 0.55];
    mAmps  = #[0.4, 0.55, 0.7, 0.9, 1.0, 0.92, 0.78, 0.62, 0.46];
    mThump = Ringz.ar(contacts, io.node(\thump, 132 * LFNoise0.ar(4).range(0.98, 1.02)), 0.035)
        * io.par(\metalWeight) * 0.7;
    metal  = (Mix(Ringz.ar(contacts, mFreqs, mRings) * mAmps) + mThump) * 0.45 * io.par(\metalAmt);
    ticks  = ((ticks * 0.7) + metal) * io.par(\contact);

    body = BrownNoise.ar(io.par(\bodyLevel)) * LFNoise2.ar(0.35).range(0.3, 1.0);

    springs = notes.collect { |note, i|
        var sf       = io.node(\sf, note.midicps);
        var sd       = io.par(\decay) * (0.7 + (i * 0.55 / notes.size));
        var collGain = sf.linlin(110, 430, 0.08, 0.8);
        var ringGain = sf.linexp(45, 700, 1.5, 0.65);
        var voice = (body + (contacts * collGain) + io.feed)
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
    };
    bundle = (springs.mean * io.par(\sprGain)) + (ticks * 0.9);

    cutBase = io.node(\cut, io.par(\cutTop) - (oil * io.par(\cutOil)));
    bundle  = (LPF.ar(bundle, cutBase) * io.par(\drive)).tanh;

    sigL = LPF.ar(bundle, (cutBase * (1 - (muffle * 0.82))).clip(60, 12000));
    sigL = DelayC.ar(sigL, 0.05, muffle * 0.02) * (1 - (muffle * 0.4));

    [sigL, bundle] * (0.78 + (sway * 0.22))
});
)
