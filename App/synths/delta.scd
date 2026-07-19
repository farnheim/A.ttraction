// App/synths/delta.scd — UNGRUND class 4/8 `delta`, §C.4 `binde` (amended
// 2026-07-19): 5 глоттальных голосов решётки 94 Hz, каждый ПАРАЛЛЕЛЬНО в
// 5-формантный вокальный BPF-банк и 4-модовый Ringz-банк пластин; `metal` —
// кроссфейд голос<->пластина. Запреты §C.4 в силе: без глайда, модуляции ≤ 0.25 Hz.
// Спека + Post-tuning deviations: docs/features/delta/dsp-spec.md.
// ~spec_delta — source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — 5 voice fundamentals (MIDI notes) on the 3-limit lattice
// from 94 Hz; group \tone — glottal source / vowel bank / plates /
// breathing / space.
~spec_delta = (
    name: \delta,
    params: [
        // --- group \freq: 5 voice fundamentals (MIDI notes) ---
        ( key: \f1, label: "нота 1", group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 48.71) ),  // 141 Hz ×3/2
        ( key: \f2, label: "нота 2", group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 53.71) ),  // 188 Hz ×2
        ( key: \f3, label: "нота 3", group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 60.72) ),  // 282 Hz ×3
        ( key: \f4, label: "нота 4", group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 65.71) ),  // 376 Hz ×4
        ( key: \f5, label: "нота 5", group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 72.72) ),  // 564 Hz ×6

        // --- group \tone: glottal source ---
        ( key: \amp,        label: "громкость",        group: \tone,               spec: ControlSpec(0.0, 0.5, \lin, 0, 0.18)     ),  // layer level (§K.4)
        ( key: \voiced,     label: "голос",            group: \tone,               spec: ControlSpec(0.0, 1.0, \lin, 0, 0.8)      ),  // phonation level
        ( key: \breath,     label: "дыхание",          group: \tone,               spec: ControlSpec(0.0, 1.0, \lin, 0, 0.3)      ),  // aspiration level
        ( key: \bright,     label: "яркость истока",   group: \tone,               spec: ControlSpec(3.0, 20.0, \exp, 0, 9.0)     ),  // glottal tilt (LPF = fund×bright)

        ( key: \detune,     label: "расстройка",       group: \tone, unit: " ct",  spec: ControlSpec(0.0, 15.0, \lin, 0, 6.0)     ),  // unison scatter
        ( key: \driftRate,  label: "дрейф хора",       group: \tone, unit: " Hz",  spec: ControlSpec(0.02, 0.2, \exp, 0, 0.07)    ),  // detune wander (§C.4 ≤0.25)
        ( key: \jitter,     label: "дрожь тона",       group: \tone,               spec: ControlSpec(0.0, 0.004, \lin, 0, 0.0015) ),  // aperiodic micro-jitter ≤0.4%
        ( key: \shimmer,    label: "мерцание",         group: \tone,               spec: ControlSpec(0.0, 0.2, \lin, 0, 0.06)     ),  // fast shallow amp flutter

        // --- group \tone: vowel bank ---
        ( key: \vowelSel,   label: "выбор гласной",    group: \tone,               spec: ControlSpec(0.0, 1.0, \lin, 0, 0.5)      ),  // interpolate to next vowel
        ( key: \vowelDrift, label: "дрейф гласной",    group: \tone,               spec: ControlSpec(0.0, 0.3, \lin, 0, 0.1)      ),  // slow vowel wander (≤0.1 Hz)
        ( key: \formWidth,  label: "ширина формант",   group: \tone,               spec: ControlSpec(0.7, 2.0, \lin, 0, 1.0)      ),  // bandwidth scale (static)
        ( key: \formTrack,  label: "форм. за высотой", group: \tone,               spec: ControlSpec(0.0, 0.7, \lin, 0, 0.35)     ),  // formant register tracking
        ( key: \ring,       label: "певч. форманта",   group: \tone,               spec: ControlSpec(0.0, 1.0, \lin, 0, 0.4)      ),  // 2.6–3.6 kHz cluster gain
        ( key: \beatRate,   label: "биения",           group: \tone, unit: " Hz",  spec: ControlSpec(0.05, 0.25, \exp, 0, 0.15)   ),  // §C.4 formant beating (≤0.25)

        // --- group \tone: metal plates ---
        ( key: \metal,      label: "голос/металл",     group: \tone,               spec: ControlSpec(0.0, 1.0, \lin, 0, 0.35)     ),  // bank crossfade (0 = choir)
        ( key: \plateQ,     label: "звон пластины",    group: \tone,               spec: ControlSpec(0.05, 3.0, \exp, 0, 0.9)     ),  // plate ring time
        ( key: \plateSpread,label: "разброс звона",    group: \tone,               spec: ControlSpec(0.0, 0.05, \lin, 0, 0.015)   ),  // ring detune across voices

        // --- group \tone: breathing ---
        ( key: \breathDepth,label: "глуб. дыхания",    group: \tone,               spec: ControlSpec(0.0, 1.0, \lin, 0, 0.5)      ),  // dip ≤ −6 dB (§C.4)
        ( key: \breathRate, label: "част. дыхания",    group: \tone, unit: " Hz",  spec: ControlSpec(0.02, 0.25, \exp, 0, 0.08)   ),  // §C.4 period ≥ 4 s

        // --- group \tone: levels and space ---
        ( key: \voiceLevel, label: "уровень голосов",  group: \tone,               spec: ControlSpec(0.0, 1.0, \lin, 0, 0.7)      ),  // voice-sum level (pre amp)
        ( key: \panWidth,   label: "ширина пан.",      group: \tone,               spec: ControlSpec(0.0, 0.3, \lin, 0, 0.22)     ),  // §F: pan ≤ ±0.3
        ( key: \panRate,    label: "част. пан.",       group: \tone, unit: " Hz",  spec: ControlSpec(0.01, 0.5, \exp, 0, 0.06)    )   // §F: slow pan drift
    ]
);


// ===== LOGIC — synthesis =============================================
// 5 голосов: A (Blip-ансамбль + дыхание) -> B1 || B2 -> XFade2 по `metal` ->
// C (дыхание/shimmer/pan); сумма -> LeakDC -> Limiter
Ndef(\delta, { |amp = 0.18,
    f1 = 48.71, f2 = 53.71, f3 = 60.72, f4 = 65.71, f5 = 72.72,
    voiced = 0.8, breath = 0.3, bright = 9.0,
    detune = 6.0, driftRate = 0.07, jitter = 0.0015, shimmer = 0.06,
    vowelSel = 0.5, vowelDrift = 0.1, formWidth = 1.0, formTrack = 0.35,
    ring = 0.4, beatRate = 0.15,
    metal = 0.35, plateQ = 0.9, plateSpread = 0.015,
    breathDepth = 0.5, breathRate = 0.08,
    voiceLevel = 0.7, panWidth = 0.22, panRate = 0.06|

    var nyq, funds, nVoices = 5, nSubs = 3, nForms = 5;
    var voicedL, breathL, brightL, detuneL, driftRateL, jitterL, shimmerL;
    var vowelSelL, vowelDriftL, formWidthL, formTrackL, ringL, beatRateL;
    var metalL, plateQL, plateSpreadL, breathDepthL, breathRateL;
    var voiceLevelL, panWidthL, panRateL;
    // теноровые формантные таблицы (5 гласных a-e-i-o-u × 5 формант)
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
    // базовая гласная на голос выбрана на BUILD (UGen не индекс массива);
    // vowelSel интерполирует к следующей
    var baseVowel = #[0, 3, 1, 4, 2];
    var vowelDriftRates = #[0.041, 0.053, 0.067, 0.079, 0.093];  // ≤ 0.1 Hz (§C.4)
    var subOffsets = Array.fill(5, { |i| [-1.0, 0.4, 1.0] * (0.82 + (i * 0.09)) });
    var subDriftIncom = Array.fill(5, { |i|
        Array.fill(3, { |j| 0.6 + (j * 0.17) + (i * 0.023) })
    });
    // инвариантный негармонический шаблон пластины (идиофон, НЕ целые)
    var plateRatios = #[1.0, 2.76, 5.40, 8.93];
    var plateModeAmps = #[0.35, 0.7, 0.6, 0.45];
    // срез ×1-моды двух нижних голосов: утечка в полосу 20–80 Hz (deviation спеки)
    var plateMode1Trim = #[0.4, 0.55, 1.0, 1.0, 1.0];
    var plateRingScale = #[1.0, 0.85, 0.72, 0.6];
    // измеренные тримы: `metal` меняет тембр, не громкость (Post-tuning deviations)
    var b1Trim = 360.0, b2Trim = 0.675, makeup = 5.0;
    // компенсация глоттального LPF-наклона на верхних формантах (deviation спеки)
    var formComp = #[1.0, 2.6, 2.4, 2.8, 3.2];
    var voices, sig, fieldDrift;

    nyq = SampleRate.ir * 0.45;

    // control lags + §C.4 rate guards
    voicedL      = voiced.lag(0.2).clip(0, 1);
    breathL      = breath.lag(0.2).clip(0, 1);
    brightL      = bright.lag(0.2).clip(3, 20);
    detuneL      = detune.lag(0.2).clip(0, 15);
    driftRateL   = driftRate.clip(0.02, 0.2);
    jitterL      = jitter.lag(0.2).clip(0, 0.004);
    shimmerL     = shimmer.lag(0.2).clip(0, 0.2);
    vowelSelL    = vowelSel.lag(0.2).clip(0, 1);
    vowelDriftL  = vowelDrift.lag(0.2).clip(0, 0.3);
    formWidthL   = formWidth.lag(0.2).clip(0.7, 2.0);
    formTrackL   = formTrack.lag(0.2).clip(0, 0.7);
    ringL        = ring.lag(0.2).clip(0, 1);
    beatRateL    = beatRate.clip(0.05, 0.25);
    metalL       = metal.lag(0.2).clip(0, 1);
    plateQL      = plateQ.lag(0.2).clip(0.05, 3.0);
    plateSpreadL = plateSpread.lag(0.2).clip(0, 0.05);
    breathDepthL = breathDepth.lag(0.2).clip(0, 1);
    breathRateL  = breathRate.clip(0.02, 0.25);
    voiceLevelL  = voiceLevel.lag(0.1).clip(0, 1);
    panWidthL    = panWidth.lag(0.2).clip(0, 0.3);
    panRateL     = panRate.clip(0.01, 0.5);

    // статичные фундаменты: только .set + .lag, никогда не свип (§C.4)
    funds = [f1, f2, f3, f4, f5].collect { |n| n.lag(0.2).midicps.clip(60, nyq) };

    voices = Array.fill(nVoices, { |i|
        var fund, numHarm, jit, ensemble, src, breathNoise, bankIn;
        var vowelIdx, nextIdx, pos, regScale, ringGain, vocal;
        var plateFreqs, plateRings, plateNorm, plate;
        var voiceOut, breathing, shimGain, pan;

        fund = funds[i];
        // numHarm от КЛАМПЛЕННОГО fund: без алиасинга, никогда не 0
        numHarm = (nyq / fund).max(1);
        jit = 1 + (LFDNoise3.kr(7 + (i * 0.9)) * jitterL);

        // Stage A: glottal unison ensemble (fixed scatter + slow drift)
        ensemble = Mix(Array.fill(nSubs, { |j|
            var cents = (subOffsets[i][j] * detuneL)
                + (LFNoise2.kr((driftRateL * subDriftIncom[i][j]).clip(0.01, 0.2))
                    * (detuneL * 0.4));
            Blip.ar(fund * jit * (2 ** (cents / 1200)), numHarm);
        })) * (1 / nSubs);
        src = LPF.ar(ensemble, (fund * brightL).clip(300, nyq));
        // отмена 1/numHarm-нормализации Blip: постоянный уровень гармоники по
        // регистрам — сопрано не исчезает и не кричит
        src = src * (numHarm * 0.016).clip(0.3, 3);
        breathNoise = HPF.ar(PinkNoise.ar, 250);
        bankIn = (src * voicedL) + (breathNoise * breathL);

        // Stage B1: вокальный банк (freq, bw И amp интерполируются вместе —
        // морф одних частот даёт неверные гласные)
        vowelIdx = baseVowel[i];
        nextIdx  = (vowelIdx + 1) % 5;
        pos      = (vowelSelL + (LFNoise2.kr(vowelDriftRates[i]) * vowelDriftL * 0.5))
                       .clip(0, 1);
        regScale = (fund * (1/282)) ** formTrackL;
        ringGain = ringL.linlin(0, 1, 0.3, 1.6);
        vocal = Mix(Array.fill(nForms, { |k|
            var ff   = pos.linlin(0, 1, vowFreqs[vowelIdx][k], vowFreqs[nextIdx][k]);
            var bw   = pos.linlin(0, 1, vowBws[vowelIdx][k], vowBws[nextIdx][k]);
            var ampF = pos.linlin(0, 1, vowAmps[vowelIdx][k], vowAmps[nextIdx][k]);
            var beat = LFNoise2.kr((beatRateL * (0.6 + (k * 0.22) + (i * 0.07)))
                           .clip(0.02, 0.25)).range(0.55, 1.0);
            var gainK = if(k >= 2) { ringGain } { 1.0 };
            ff = ff * regScale;
            // soprano F1 rule: F1 подтянут к фундаменту на высоких голосах
            if(k == 0) { ff = max(ff, fund * 1.05) };
            ff = ff.clip(60, nyq);
            BPF.ar(bankIn, ff, (bw * formWidthL / ff)) * ampF * formComp[k] * beat * gainK;
        })) * (1 / nForms) * formWidthL.sqrt.reciprocal * b1Trim;

        // Stage B2: банк пластин параллельно B1; частоты мод — чистые функции
        // статичных fund (кламп ВСЕГО массива)
        plateFreqs = (fund * plateRatios).clip(60, nyq);
        plateRings = (plateQL * (1 + ((i - 2) * plateSpreadL)) * plateRingScale)
                         .clip(0.02, 4.0);
        // Q-компенсация: plateQ меняет ТЕМБР, не громкость
        plateNorm = 0.25 / (1 + (plateQL * 0.7));
        plate = Mix(Ringz.ar(bankIn, plateFreqs, plateRings)
                    * (plateModeAmps * [plateMode1Trim[i], 1, 1, 1]))
                    * plateNorm * b2Trim;

        voiceOut = XFade2.ar(vocal, plate, (metalL * 2) - 1);
        voiceOut = voiceOut + (breathNoise * breathL * 0.15);

        // Stage C: некогерентное дыхание голоса (dip ≤ −6 dB) + shimmer
        breathing = LFNoise2.kr((breathRateL * (0.7 + (i * 0.13))).clip(0.02, 0.25))
                        .range(1 - (breathDepthL * 0.5), 1.0);
        shimGain  = LFNoise2.kr(4.3 + (i * 0.6)).range(1 - shimmerL, 1.0);
        voiceOut  = voiceOut * breathing * shimGain * (1 - (i * 0.07));

        pan = LFNoise1.kr((panRateL * (0.5 + (i * 0.21))).clip(0.01, 0.67))
                  .range(panWidthL.neg, panWidthL);
        Pan2.ar(voiceOut, pan);
    });

    // голоса частично декоррелированы (сумма растёт ~√N) — нормализация √N
    sig = Mix(voices) * (1 / nVoices.sqrt) * voiceLevelL;

    // очень медленный дрейф всего поля в ±0.3 (§F)
    fieldDrift = LFNoise1.kr(0.03).range(-0.12, 0.12);
    sig = Balance2.ar(sig[0], sig[1], fieldDrift);

    // makeup ДО мастер-amp: amp остаётся §K.4-уровнем слоя (0.18)
    sig = sig * makeup;

    // регистр §C.4 100 Hz – 6 kHz: тройной HPF (~36 dB/окт) под f1 = 141 Hz
    sig = HPF.ar(HPF.ar(HPF.ar(sig, 120), 120), 120);

    sig = sig * amp.lag(0.05);
    sig = LeakDC.ar(sig);                 // импульсные трейны и high-Q банки несут DC
    sig = Limiter.ar(sig, 0.95);          // §DSP: гарантия ±1.0 при рандом-экстремумах
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
