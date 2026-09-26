// App/synths/delta.scd — machine `delta`: five pulse voices, each through a
// five-formant bank and a four-mode plate bank in parallel, `metal` crossfades
// the two.


// ===== CONFIG — edit here ============================================
(
~spec_delta = (
    name: \delta,
    level: 0.9,
    fade: 4,
    params: [
        f1: [24, 96, \lin, 0, 48.71],
        f2: [24, 96, \lin, 0, 53.71],
        f3: [24, 96, \lin, 0, 60.72],
        f4: [24, 96, \lin, 0, 65.71],
        f5: [24, 96, \lin, 0, 72.72],
        voiced:      [0.0, 1.0, \lin, 0, 0.8],
        breath:      [0.0, 1.0, \lin, 0, 0.3],
        bright:      [1.0, 40.0, \exp, 0, 9.0],
        detune:      [0.0, 100.0, \lin, 0, 6.0],
        driftRate:   [0.02, 50, \exp, 0, 0.07],
        jitter:      [0.0, 0.05, \lin, 0, 0.0015],
        shimmer:     [0.0, 1.0, \lin, 0, 0.06],
        vowelSel:    [0.0, 1.0, \lin, 0, 0.5],
        vowelDrift:  [0.0, 1.0, \lin, 0, 0.1],
        formWidth:   [0.2, 4.0, \exp, 0, 1.0],
        formTrack:   [0.0, 1.0, \lin, 0, 0.35],
        ring:        [0.0, 1.0, \lin, 0, 0.4],
        beatRate:    [0.05, 80, \exp, 0, 0.15],
        metal:       [0.0, 1.0, \lin, 0, 0.35],
        plateQ:      [0.02, 4.0, \exp, 0, 0.9],
        plateSpread: [0.0, 0.2, \lin, 0, 0.015],
        breathDepth: [0.0, 1.0, \lin, 0, 0.5],
        breathRate:  [0.02, 40, \exp, 0, 0.08],
        voiceLevel:  [0.0, 1.0, \lin, 0, 0.7],
        panWidth:    [0.0, 1.0, \lin, 0, 0.22],
        panRate:     [0.01, 40, \exp, 0, 0.06]
    ],
    vars: [
        jit:       [0.9, 1.1, \exp],
        pos:       [0.0, 1.0],
        ff:        [40, 9000, \exp],
        bw:        [10, 1200, \exp],
        beat:      [0.0, 1.0],
        plate:     [0.01, 4.0, \exp],
        breathing: [0.0, 1.0],
        pan:       [-1.0, 1.0]
    ]
);


// ===== LOGIC =========================================================
~netMachine.(~spec_delta, { |io|
    var nyq = io.nyq, breath = io.par(\breath), detune = io.par(\detune);
    var formWidth = io.par(\formWidth), plateQ = io.par(\plateQ), nForms = 5;
    var vowFreqs = #[
        [650, 1080, 2650, 2900, 3250],
        [400, 1700, 2600, 3200, 3580],
        [290, 1870, 2800, 3250, 3540],
        [400,  800, 2600, 2800, 3000],
        [350,  600, 2700, 2900, 3300]
    ];
    var vowBws = #[
        [80, 90, 120, 130, 140],
        [70, 80, 100, 120, 120],
        [40, 90, 100, 120, 120],
        [70, 80, 100, 130, 135],
        [40, 60, 100, 120, 120]
    ];
    var vowAmps = [
        [0, -6,  -7,  -8,  -22],
        [0, -14, -12, -14, -20],
        [0, -15, -18, -20, -30],
        [0, -10, -12, -12, -26],
        [0, -20, -17, -14, -26]
    ].collect { |row| row.collect(_.dbamp) };
    var baseVowel = #[0, 3, 1, 4, 2];
    var vowelDriftRates = #[0.041, 0.053, 0.067, 0.079, 0.093];
    var plateRatios = #[1.0, 2.76, 5.40, 8.93];
    var plateModeAmps = #[0.35, 0.7, 0.6, 0.45];
    var plateRingScale = #[1.0, 0.85, 0.72, 0.6];
    var formComp = #[1.0, 2.6, 2.4, 2.8, 3.2];
    var b1Trim = 360.0, b2Trim = 0.675;
    var ringGain = io.par(\ring).linlin(0, 1, 0.3, 1.6);
    var plateNorm = 0.25 / (1 + (plateQ * 0.7)) * b2Trim;
    var voices;

    voices = [\f1, \f2, \f3, \f4, \f5].collect { |key, i|
        var fund, numHarm, jit, src, breathNoise, bankIn;
        var vowelIdx, nextIdx, pos, regScale, vocal;
        var plateFreqs, plateRings, plate, voiceOut, breathing, shimGain, pan;

        fund    = io.par(key).midicps.clip(20, nyq);
        numHarm = (nyq / fund).max(1);
        jit     = io.node(\jit, 1 + (LFDNoise3.ar(7 + (i * 0.9)) * io.par(\jitter)));

        src = ([-1.0, 0.4, 1.0] * (0.82 + (i * 0.09))).collect { |offset, j|
            var cents = (offset * detune)
                + (LFNoise2.ar(io.par(\driftRate) * (0.6 + (j * 0.17) + (i * 0.023))) * (detune * 0.4));
            Blip.ar(fund * jit * (2 ** (cents / 1200)), numHarm)
        }.mean;
        src = LPF.ar(src, (fund * io.par(\bright)).clip(40, nyq));
        src = src * (numHarm * 0.016).clip(0.3, 3);
        breathNoise = HPF.ar(PinkNoise.ar, 250);
        bankIn = (src * io.par(\voiced)) + (breathNoise * breath) + io.feed;

        vowelIdx = baseVowel[i];
        nextIdx  = (vowelIdx + 1) % vowFreqs.size;
        pos      = io.node(\pos, io.par(\vowelSel)
            + (LFNoise2.ar(vowelDriftRates[i]) * io.par(\vowelDrift) * 0.5));
        regScale = (fund * (1/282)) ** io.par(\formTrack);
        vocal = Array.fill(nForms, { |k|
            var ff   = pos.linlin(0, 1, vowFreqs[vowelIdx][k], vowFreqs[nextIdx][k]) * regScale;
            var bw   = io.node(\bw, pos.linlin(0, 1, vowBws[vowelIdx][k], vowBws[nextIdx][k]));
            var ampF = pos.linlin(0, 1, vowAmps[vowelIdx][k], vowAmps[nextIdx][k]);
            var beat = io.node(\beat, LFNoise2.ar(io.par(\beatRate) * (0.6 + (k * 0.22) + (i * 0.07))).range(0.55, 1.0));
            var gainK = if(k >= 2) { ringGain } { 1.0 };
            if(k == 0) { ff = max(ff, fund * 1.05) };
            ff = io.node(\ff, ff);
            BPF.ar(bankIn, ff, (bw * formWidth / ff).clip(0.001, 2)) * ampF * formComp[k] * beat * gainK
        }).mean * formWidth.sqrt.reciprocal * b1Trim;

        plateFreqs = (fund * plateRatios).clip(20, nyq);
        plateRings = io.node(\plate, plateQ * (1 + ((i - 2) * io.par(\plateSpread))) * plateRingScale);
        plate = Mix(Ringz.ar(bankIn, plateFreqs, plateRings) * plateModeAmps) * plateNorm;

        voiceOut = XFade2.ar(vocal, plate, (io.par(\metal) * 2) - 1);
        voiceOut = voiceOut + (breathNoise * breath * 0.15);

        breathing = io.node(\breathing,
            LFNoise2.ar(io.par(\breathRate) * (0.7 + (i * 0.13))).range(1 - (io.par(\breathDepth) * 0.5), 1.0));
        shimGain  = LFNoise2.ar(4.3 + (i * 0.6)).range(1 - io.par(\shimmer), 1.0);
        voiceOut  = voiceOut * breathing * shimGain * (1 - (i * 0.07));

        pan = io.node(\pan, LFNoise1.ar(io.par(\panRate) * (0.5 + (i * 0.21))) * io.par(\panWidth));
        Pan2.ar(voiceOut, pan)
    };

    HPF.ar(Mix(voices) * (1 / voices.size.sqrt) * io.par(\voiceLevel), 40)
});
)
