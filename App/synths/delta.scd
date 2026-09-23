// App/synths/delta.scd — machine `delta`: five pulse voices, each through a
// five-formant bank and a four-mode plate bank in parallel, `metal` crossfades
// the two. Everything audio rate; parameters and inner variables are ports.


// ===== CONFIG — edit here ============================================
(
~spec_delta = (
    name: \delta,
    params: [
        ( key: \f1, group: \freq, spec: ControlSpec(24, 96, \lin, 0, 48.71) ),
        ( key: \f2, group: \freq, spec: ControlSpec(24, 96, \lin, 0, 53.71) ),
        ( key: \f3, group: \freq, spec: ControlSpec(24, 96, \lin, 0, 60.72) ),
        ( key: \f4, group: \freq, spec: ControlSpec(24, 96, \lin, 0, 65.71) ),
        ( key: \f5, group: \freq, spec: ControlSpec(24, 96, \lin, 0, 72.72) ),
        ( key: \amp,         group: \tone, spec: ControlSpec(0.0, 0.5, \lin, 0, 0.18) ),
        ( key: \voiced,      group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.8) ),
        ( key: \breath,      group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.3) ),
        ( key: \bright,      group: \tone, spec: ControlSpec(1.0, 40.0, \exp, 0, 9.0) ),
        ( key: \detune,      group: \tone, spec: ControlSpec(0.0, 100.0, \lin, 0, 6.0) ),
        ( key: \driftRate,   group: \tone, spec: ControlSpec(0.02, 50, \exp, 0, 0.07) ),
        ( key: \jitter,      group: \tone, spec: ControlSpec(0.0, 0.05, \lin, 0, 0.0015) ),
        ( key: \shimmer,     group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.06) ),
        ( key: \vowelSel,    group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.5) ),
        ( key: \vowelDrift,  group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.1) ),
        ( key: \formWidth,   group: \tone, spec: ControlSpec(0.2, 4.0, \exp, 0, 1.0) ),
        ( key: \formTrack,   group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.35) ),
        ( key: \ring,        group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.4) ),
        ( key: \beatRate,    group: \tone, spec: ControlSpec(0.05, 80, \exp, 0, 0.15) ),
        ( key: \metal,       group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.35) ),
        ( key: \plateQ,      group: \tone, spec: ControlSpec(0.02, 4.0, \exp, 0, 0.9) ),
        ( key: \plateSpread, group: \tone, spec: ControlSpec(0.0, 0.2, \lin, 0, 0.015) ),
        ( key: \breathDepth, group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.5) ),
        ( key: \breathRate,  group: \tone, spec: ControlSpec(0.02, 40, \exp, 0, 0.08) ),
        ( key: \voiceLevel,  group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.7) ),
        ( key: \panWidth,    group: \tone, spec: ControlSpec(0.0, 1.0, \lin, 0, 0.22) ),
        ( key: \panRate,     group: \tone, spec: ControlSpec(0.01, 40, \exp, 0, 0.06) )
    ],
    vars: [
        ( key: \jit,       spec: ControlSpec(0.9, 1.1, \exp) ),
        ( key: \pos,       spec: ControlSpec(0.0, 1.0, \lin) ),
        ( key: \ff,        spec: ControlSpec(40, 9000, \exp) ),
        ( key: \bw,        spec: ControlSpec(10, 1200, \exp) ),
        ( key: \beat,      spec: ControlSpec(0.0, 1.0, \lin) ),
        ( key: \plate,     spec: ControlSpec(0.01, 4.0, \exp) ),
        ( key: \breathing, spec: ControlSpec(0.0, 1.0, \lin) ),
        ( key: \pan,       spec: ControlSpec(-1.0, 1.0, \lin) )
    ]
);


// ===== LOGIC =========================================================
~netRegister.(~spec_delta, 4);
Ndef(\delta, ~netMachine.(~spec_delta, { |io|
    var funds = [\f1, \f2, \f3, \f4, \f5].collect { |k| io.par(k).midicps };
    var amp = io.par(\amp), voiced = io.par(\voiced), breath = io.par(\breath);
    var bright = io.par(\bright), detune = io.par(\detune), driftRate = io.par(\driftRate);
    var jitter = io.par(\jitter), shimmer = io.par(\shimmer), vowelSel = io.par(\vowelSel);
    var vowelDrift = io.par(\vowelDrift), formWidth = io.par(\formWidth);
    var formTrack = io.par(\formTrack), ring = io.par(\ring), beatRate = io.par(\beatRate);
    var metal = io.par(\metal), plateQ = io.par(\plateQ), plateSpread = io.par(\plateSpread);
    var breathDepth = io.par(\breathDepth), breathRate = io.par(\breathRate);
    var voiceLevel = io.par(\voiceLevel), panWidth = io.par(\panWidth), panRate = io.par(\panRate);
    var feed = io.feed;
    var nyq = SampleRate.ir * 0.45, nVoices = 5, nSubs = 3, nForms = 5;
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
    var subOffsets = Array.fill(5, { |i| [-1.0, 0.4, 1.0] * (0.82 + (i * 0.09)) });
    var plateRatios = #[1.0, 2.76, 5.40, 8.93];
    var plateModeAmps = #[0.35, 0.7, 0.6, 0.45];
    var plateRingScale = #[1.0, 0.85, 0.72, 0.6];
    var b1Trim = 360.0, b2Trim = 0.675, makeup = 5.0;
    var formComp = #[1.0, 2.6, 2.4, 2.8, 3.2];
    var voices, sig;

    voices = Array.fill(nVoices, { |i|
        var fund, numHarm, jit, ensemble, src, breathNoise, bankIn;
        var vowelIdx, nextIdx, pos, regScale, ringGain, vocal;
        var plateFreqs, plateRings, plateNorm, plate, voiceOut, breathing, shimGain, pan;

        fund    = funds[i].clip(20, nyq);
        numHarm = (nyq / fund).max(1);
        jit     = io.node(\jit, 1 + (LFDNoise3.ar(7 + (i * 0.9)) * jitter));

        ensemble = Mix(Array.fill(nSubs, { |j|
            var cents = (subOffsets[i][j] * detune)
                + (LFNoise2.ar(driftRate * (0.6 + (j * 0.17) + (i * 0.023))) * (detune * 0.4));
            Blip.ar(fund * jit * (2 ** (cents / 1200)), numHarm)
        })) * (1 / nSubs);
        src = LPF.ar(ensemble, (fund * bright).clip(40, nyq));
        src = src * (numHarm * 0.016).clip(0.3, 3);
        breathNoise = HPF.ar(PinkNoise.ar, 250);
        bankIn = (src * voiced) + (breathNoise * breath) + feed;

        vowelIdx = baseVowel[i];
        nextIdx  = (vowelIdx + 1) % 5;
        pos      = io.node(\pos, (vowelSel + (LFNoise2.ar(vowelDriftRates[i]) * vowelDrift * 0.5)).clip(0, 1));
        regScale = (fund * (1/282)) ** formTrack;
        ringGain = ring.linlin(0, 1, 0.3, 1.6);
        vocal = Mix(Array.fill(nForms, { |k|
            var ff   = pos.linlin(0, 1, vowFreqs[vowelIdx][k], vowFreqs[nextIdx][k]) * regScale;
            var bw   = io.node(\bw, pos.linlin(0, 1, vowBws[vowelIdx][k], vowBws[nextIdx][k]));
            var ampF = pos.linlin(0, 1, vowAmps[vowelIdx][k], vowAmps[nextIdx][k]);
            var beat = io.node(\beat, LFNoise2.ar(beatRate * (0.6 + (k * 0.22) + (i * 0.07))).range(0.55, 1.0));
            var gainK = if(k >= 2) { ringGain } { 1.0 };
            if(k == 0) { ff = max(ff, fund * 1.05) };
            ff = io.node(\ff, ff.clip(40, nyq));
            BPF.ar(bankIn, ff, (bw * formWidth / ff).clip(0.001, 2)) * ampF * formComp[k] * beat * gainK
        })) * (1 / nForms) * formWidth.sqrt.reciprocal * b1Trim;

        plateFreqs = (fund * plateRatios).clip(20, nyq);
        plateRings = io.node(\plate, plateQ * (1 + ((i - 2) * plateSpread)) * plateRingScale);
        plateNorm  = 0.25 / (1 + (plateQ * 0.7));
        plate = Mix(Ringz.ar(bankIn, plateFreqs, plateRings) * plateModeAmps) * plateNorm * b2Trim;

        voiceOut = XFade2.ar(vocal, plate, (metal * 2) - 1);
        voiceOut = voiceOut + (breathNoise * breath * 0.15);

        breathing = io.node(\breathing,
            LFNoise2.ar(breathRate * (0.7 + (i * 0.13))).range(1 - (breathDepth * 0.5), 1.0));
        shimGain  = LFNoise2.ar(4.3 + (i * 0.6)).range(1 - shimmer, 1.0);
        voiceOut  = voiceOut * breathing * shimGain * (1 - (i * 0.07));

        pan = io.node(\pan, LFNoise1.ar(panRate * (0.5 + (i * 0.21))) * panWidth);
        Pan2.ar(voiceOut, pan)
    });

    sig = Mix(voices) * (1 / nVoices.sqrt) * voiceLevel * makeup;
    sig = HPF.ar(sig, 40) * amp;
    io.emit(Limiter.ar(LeakDC.ar(sig), 0.95))
}));

~netRewire.value;
)
