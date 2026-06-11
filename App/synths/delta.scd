// App/synths/delta.scd — UNGRUND class 4/8 `delta` (formant-cluster wind /
// metal plates). REAL LAYER (rewritten from stub per docs/task.md,
// 2026-06-10). Premise §C.4 `binde`, EXTENDED: 5 wind streams, each
// exciting a metal plate (Ringz bank) plus a 3-formant vowel BPF bank;
// tones from the 3-limit 94 Hz lattice. §C.4 bans kept: no central-pitch
// glide, band-identity modulation ≤ 0.25 Hz (supersede flag in docs/task.md).
// Tuning via 0_lib.scd; ~spec_delta is the single source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — 5 voice fundamentals (MIDI notes); group \tone — wind /
// plates / vowels / space. Tone defaults on the 3-limit lattice from 94 Hz:
// 141/188/282/376/564 Hz.
~spec_delta = (
    name: \delta,
    params: [
        // --- group \freq: 5 voice fundamentals (MIDI notes) ---
        ( key: \f1, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 48.71) ),  // 141 Hz
        ( key: \f2, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 53.71) ),  // 188 Hz
        ( key: \f3, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 60.72) ),  // 282 Hz
        ( key: \f4, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 65.71) ),  // 376 Hz
        ( key: \f5, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 72.72) ),  // 564 Hz

        // --- group \tone: wind ---
        ( key: \amp,        group: \tone,              spec: ControlSpec(0.0, 0.5, \lin, 0, 0.18)  ),  // layer level (§K.4)
        ( key: \windForce,  group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.6)   ),  // stream force
        ( key: \turbulence, group: \tone,              spec: ControlSpec(0.0, 0.9, \lin, 0, 0.45)  ),  // gust depth
        ( key: \gustRate,   group: \tone, unit: " Hz",  spec: ControlSpec(0.02, 0.25, \exp, 0, 0.08) ),  // gust rate (§C.4 ≤0.25)
        ( key: \flutter,    group: \tone,              spec: ControlSpec(0.0, 0.3, \lin, 0, 0.12)  ),  // fast small air flutter
        ( key: \edge,       group: \tone,              spec: ControlSpec(0.0, 0.6, \lin, 0, 0.18)  ),  // edge whistle
        ( key: \edgeRatio,  group: \tone,              spec: ControlSpec(3.0, 12.0, \exp, 0, 7.0)  ),  // whistle = fund × edgeRatio

        // --- group \tone: metal plates ---
        ( key: \metal,      group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.55)  ),  // plate resonance vs raw wind
        ( key: \plateQ,     group: \tone,              spec: ControlSpec(0.05, 3.0, \exp, 0, 0.9)  ),  // plate ring time
        ( key: \plateBright,group: \tone,              spec: ControlSpec(0.3, 2.0, \lin, 0, 1.0)   ),  // excitation brightness
        ( key: \plateSpread,group: \tone,              spec: ControlSpec(0.0, 0.05, \lin, 0, 0.015)),  // ring detune across voices

        // --- group \tone: formant "human" filter ---
        ( key: \vowelMix,   group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.7)   ),  // vowel prominence (§C.4)
        ( key: \vowelSel,   group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.5)   ),  // vowel-set shift (a-e-i-o-u)
        ( key: \formRq,     group: \tone,              spec: ControlSpec(0.03, 0.3, \exp, 0, 0.09)  ),  // formant width
        ( key: \formScale,  group: \tone,              spec: ControlSpec(0.6, 1.6, \lin, 0, 1.0)   ),  // formant pitch vs fundamental
        ( key: \beatRate,   group: \tone, unit: " Hz",  spec: ControlSpec(0.05, 0.25, \exp, 0, 0.15) ),  // §C.4 formant beating (≤0.25 Hz)

        // --- group \tone: levels and space ---
        ( key: \voiceLevel, group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.7)   ),  // voice-sum level (pre master amp)
        ( key: \panWidth,   group: \tone,              spec: ControlSpec(0.0, 0.3, \lin, 0, 0.22)  ),  // §F: pan ≤ ±0.3
        ( key: \panRate,    group: \tone, unit: " Hz",  spec: ControlSpec(0.01, 0.5, \exp, 0, 0.06) )   // §F: slow pan drift
    ]
);


// ===== LOGIC — synthesis =============================================
// 5 voices: wind (Stage A) -> plate Ringz (Stage B) -> vowel formant bank
// (Stage C). Sum -> pan -> LeakDC -> Limiter.
Ndef(\delta, { |amp = 0.18,
    f1 = 48.71, f2 = 53.71, f3 = 60.72, f4 = 65.71, f5 = 72.72,
    windForce = 0.6, turbulence = 0.45, gustRate = 0.08, flutter = 0.12,
    edge = 0.18, edgeRatio = 7.0,
    metal = 0.55, plateQ = 0.9, plateBright = 1.0, plateSpread = 0.015,
    vowelMix = 0.7, vowelSel = 0.5, formRq = 0.09, formScale = 1.0, beatRate = 0.15,
    voiceLevel = 0.7, panWidth = 0.22, panRate = 0.06|

    var nyq, funds, fundMid, nVoices = 5;
    var windForceL, turbL, gustRateL, flutterL, edgeL, edgeRatioL;
    var metalL, plateQL, plateBrightL, plateSpreadL;
    var vowelMixL, vowelSelL, formRqL, formScaleL, beatRateL;
    var voiceLevelL, panWidthL, panRateL;
    // invariant inharmonic templates (idiophone-like, NOT integer ratios)
    var plateRatios = #[1.0, 2.76, 5.40, 8.93, 13.34];
    var plateModAmps = #[0.55, 0.7, 0.6, 0.45, 0.3];
    // classic vowel formants (3 lowest, Hz): a e i o u
    var vowelTable = [
        [ 730, 1090, 2440 ],  // a
        [ 530, 1840, 2480 ],  // e
        [ 270, 2290, 3010 ],  // i
        [ 570,  840, 2410 ],  // o
        [ 300,  870, 2240 ]   // u
    ];
    var formGains = #[1.0, 0.95, 0.75];
    var voices, sig, fieldDrift;

    nyq = SampleRate.ir * 0.45;

    // control lags
    windForceL   = windForce.lag(0.2).clip(0, 1);
    turbL        = turbulence.lag(0.2).clip(0, 0.9);
    gustRateL    = gustRate.clip(0.02, 0.25);
    flutterL     = flutter.lag(0.2).clip(0, 0.3);
    edgeL        = edge.lag(0.2).clip(0, 0.6);
    edgeRatioL   = edgeRatio.lag(0.2).clip(3, 12);
    metalL       = metal.lag(0.2).clip(0, 1);
    plateQL      = plateQ.lag(0.2).clip(0.05, 3.0);
    plateBrightL = plateBright.lag(0.2).clip(0.3, 2.0);
    plateSpreadL = plateSpread.lag(0.2).clip(0, 0.05);
    vowelMixL    = vowelMix.lag(0.2).clip(0, 1);
    vowelSelL    = vowelSel.lag(0.2).clip(0, 1);
    formRqL      = formRq.lag(0.2).clip(0.03, 0.3);
    formScaleL   = formScale.lag(0.2).clip(0.6, 1.6);
    beatRateL    = beatRate.clip(0.05, 0.25);
    voiceLevelL  = voiceLevel.lag(0.1).clip(0, 1);
    panWidthL    = panWidth.lag(0.2).clip(0, 0.3);
    panRateL     = panRate.clip(0.01, 0.5);

    // voice fundamentals (MIDI -> Hz, Nyquist clamp after lag)
    funds   = [f1, f2, f3, f4, f5].collect { |n| n.lag(0.2).midicps.clip(40, nyq) };
    fundMid = funds[2];   // f3 as reference register for formant scaling

    voices = Array.fill(nVoices, { |i|
        var fund, wind, gust, flut, gustRi, edgeFreq, edgeWhistle;
        var plateFreqs, plateRings, plate, voiceSig;
        var vowelIdx, vowelLo, vowelHi, regScale, formant;
        var plateNorm;

        fund = funds[i];

        // Stage A: wind stream
        wind = PinkNoise.ar;
        // slow gust (≤0.25 Hz), incommensurate rate per voice
        gustRi = gustRateL * (0.7 + (i * 0.13));
        gust   = LFNoise2.kr(gustRi.clip(0.01, 0.25)).range(1 - turbL, 1.0);
        flut   = LFNoise2.kr(2.5 + (i * 0.9)).range(1 - flutterL, 1.0);
        wind   = wind * windForceL * gust * flut;

        // edge whistle: narrow Resonz on a high harmonic
        edgeFreq    = (fund * edgeRatioL * (1 + (i * 0.08))).clip(40, nyq);
        edgeWhistle = Resonz.ar(PinkNoise.ar, edgeFreq, 0.03)
                        * gust * windForceL * edgeL * 6;
        wind = wind + edgeWhistle;

        // Stage B: metal-plate resonance (inharmonic bank; clamp the whole
        // freq array under Nyquist)
        plateFreqs = (fund * plateRatios * (1 + ((i - 2) * plateBrightL * 0.04)))
                        .clip(40, nyq);
        plateRings = plateQL * (1 + ((i - 2) * plateSpreadL))
                        * #[1.0, 0.85, 0.72, 0.6, 0.5];
        plateRings = plateRings.clip(0.02, 4.0);
        // Q compensation: normalize by mode count AND ring time so plateQ
        // changes TIMBRE, not loudness
        plateNorm = (1 / plateRatios.size) / (1 + (plateQL * 0.7));
        plate = Mix(Ringz.ar(wind, plateFreqs, plateRings) * plateModAmps)
                    * plateNorm * 2.0;

        voiceSig = XFade2.ar(wind * 0.9, plate, (metalL * 2) - 1);

        // Stage C: vowel formant bank. Base vowel chosen at BUILD time
        // (voices spread over a-o-e-u-i); vowelSel live-INTERPOLATES formant
        // freqs towards the next vowel — a UGen cannot be an array index.
        vowelIdx = #[0, 3, 1, 4, 2][i];          // build-time Integer
        vowelLo  = vowelTable.at(vowelIdx);
        vowelHi  = vowelTable.at((vowelIdx + 1) % 5);
        // register scale: higher voice -> higher formants
        regScale = (fund / fundMid).clip(0.7, 1.6) * formScaleL;
        // 3 parallel BPFs, each with independent slow beating (§C.4);
        // formants are excited by BROADBAND wind (the plate-filtered voice
        // has no energy left in the vowel zone)
        formant = Mix(Array.fill(3, { |k|
            var ffLo  = vowelLo[k];
            var ffHi  = vowelHi[k];
            var ff    = (vowelSelL.linlin(0, 1, ffLo, ffHi) * regScale).clip(40, nyq);
            var beat  = LFNoise2.kr(beatRateL * (0.6 + (k * 0.3) + (i * 0.07)))
                        .range(0.4, 1.0);
            BPF.ar(voiceSig + (wind * 1.1), ff, formRqL) * formGains[k] * beat;
        }));
        // Q compensation: normalize by formant count and rq narrowness
        formant = formant * (1 / formGains.size) * (formRqL / 0.09).sqrt * 13.0;

        voiceSig = XFade2.ar(voiceSig, formant, (vowelMixL * 2) - 1);

        // per-voice trim: higher voices slightly quieter
        voiceSig * (1 - (i * 0.07));
    });

    // incommensurate slow pan drift per voice within ±panWidth
    voices = voices.collect { |v, i|
        var pan = LFNoise1.kr(panRateL * (0.5 + (i * 0.21)))
                    .range(panWidthL.neg, panWidthL);
        Pan2.ar(v, pan);
    };
    // voices are partially decorrelated -> the sum grows ~√N; normalize by
    // √N so voice count neither pumps nor starves loudness
    sig = Mix(voices) * (1 / nVoices.sqrt) * voiceLevelL;

    // very slow whole-field drift within ±0.3 (§F)
    fieldDrift = LFNoise1.kr(0.03).range(-0.12, 0.12);
    sig = Balance2.ar(sig[0], sig[1], fieldDrift);

    // internal makeup gain compensating the normalization cascade; sits
    // BEFORE master amp so amp stays the §K.4 layer level (0.18)
    sig = sig * 3.3;

    // §C.4 register 100 Hz – 6 kHz: 3 cascaded HPFs (~36 dB/oct) cut the
    // residual Ringz sub below the lowest fundamental (141 Hz)
    sig = HPF.ar(HPF.ar(HPF.ar(sig, 125), 125), 125);

    sig = sig * amp.lag(0.05);
    sig = LeakDC.ar(sig);                 // §DSP: after sum + high-Q content
    sig = Limiter.ar(sig, 0.95);          // §DSP: ±1.0 guarantee under random high Q
    sig
});

// register spec + apply defaults (self-sufficient: 0_lib only needed for
// interactive random/presets/GUI after the full App load)
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\delta] = ~spec_delta;
~ungVals[\delta]  = ();
~spec_delta.params.do { |p|
    Ndef(\delta).set(p.key, p.spec.default);
    ~ungVals[\delta][p.key] = p.spec.default;
};
Ndef(\delta).fadeTime = 4;   // §F sustained register: soft in/out 4 s

("synths/delta — spec зарегистрирован ("
    ++ ~spec_delta.params.size ++ " параметров); ~openTuner.(\\delta)").postln;
)
