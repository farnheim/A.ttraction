// App/synths/epsilon.scd — UNGRUND class 5/8 `epsilon`, §C.5 `schliere`
// (amended 2026-07-16, cave bed): низкое тональное поле мод, возбуждаемое
// диффузным потоком, + одна медленная полоса-формант. Три страты, без событий;
// identity: spectral flatness 20–300 Hz ≤ 0.2.
// Reference + implementation notes: docs/features/epsilon/cave-reference.md.
// ~spec_epsilon — source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — streak drift endpoints + the four held lattice modes +
// LPF ceiling; MIDI defaults are exact cpsmidi of the Hz lattice
// (47 / 70.5 / 141 / 188 Hz = 94 ÷2, ×3/4, ×3/2, ×2).
// group \tone — mode field / flow excitation / streak / surface / space.
~spec_epsilon = (
    name: \epsilon,
    params: [
        // --- group \freq: streak endpoints + held modes (MIDI notes, 47–1504 Hz) ---
        ( key: \freqLo, label: "низ дрейфа",   group: \freq, disp: \note,             spec: ControlSpec(30.28, 90.28, \lin, 0, 30.28) ),  // 47 Hz ÷2
        ( key: \freqHi, label: "верх дрейфа",   group: \freq, disp: \note,             spec: ControlSpec(30.28, 90.28, \lin, 0, 49.30) ),  // 141 Hz ×3/2
        ( key: \m1, label: "мода 1",       group: \freq, disp: \note,             spec: ControlSpec(30.28, 90.28, \lin, 0, 30.28) ),  // 47 Hz ÷2
        ( key: \m2, label: "мода 2",       group: \freq, disp: \note,             spec: ControlSpec(30.28, 90.28, \lin, 0, 37.30) ),  // 70.5 Hz ×3/4
        ( key: \m3, label: "мода 3",       group: \freq, disp: \note,             spec: ControlSpec(30.28, 90.28, \lin, 0, 49.30) ),  // 141 Hz ×3/2
        ( key: \m4, label: "мода 4",       group: \freq, disp: \note,             spec: ControlSpec(30.28, 90.28, \lin, 0, 54.28) ),  // 188 Hz ×2
        ( key: \flowCeil, label: "потолок потока", group: \freq, unit: " Hz", disp: \hz,  spec: ControlSpec(1200, 5000, \exp, 0, 2500)   ),  // amendment (e): 1.2–5 kHz

        // --- group \tone: mode field (the principal stratum) ---
        ( key: \mLevel, label: "уровень мод",      group: \tone,              spec: ControlSpec(0.0,  0.5,  \lin, 0, 0.35) ),  // up to +6 dB over the flow (inverted)
        ( key: \mWidth, label: "ширина мод",      group: \tone,              spec: ControlSpec(0.02, 0.3,  \exp, 0, 0.06) ),  // mode rq — drives the flatness metric
        ( key: \mBreath, label: "дыхание мод",     group: \tone, unit: " Hz", spec: ControlSpec(0.02, 0.1,  \exp, 0, 0.04) ),  // per-mode breathing base rate

        // --- group \tone: flow (excitation, subordinate) ---
        ( key: \flowLevel, label: "уровень потока",   group: \tone,              spec: ControlSpec(0.0,  0.5,  \lin, 0, 0.15) ),  // the modes' medium
        ( key: \diffDepth, label: "диффузия",   group: \tone,              spec: ControlSpec(0.0,  1.0,  \lin, 0, 0.6)  ),  // AllpassC delay-mod depth

        // --- group \tone: streak (the §C.5 motion identity) ---
        ( key: \streakLevel, label: "уровень полосы", group: \tone,              spec: ControlSpec(0.0,  0.5,  \lin, 0, 0.20) ),  // audible, not dominant
        ( key: \streakWidth, label: "ширина полосы", group: \tone,              spec: ControlSpec(0.1,  1.5,  \exp, 0, 0.45) ),  // band formant rq (softness)
        ( key: \driftPeriod, label: "период дрейфа", group: \tone, unit: " s",  spec: ControlSpec(20,   240,  \exp, 0, 180)  ),  // §C.5 two-LFN law period T

        // --- group \tone: surface + space ---
        ( key: \surfDepth, label: "глуб. поверхн.",   group: \tone, unit: " dB", spec: ControlSpec(0.0,  6.0,  \lin, 0, 3.0)  ),  // a cave's air is not still
        ( key: \surfRate, label: "част. поверхн.",    group: \tone, unit: " Hz", spec: ControlSpec(0.05, 0.3,  \exp, 0, 0.09) ),  // aperiodic by UGen choice
        ( key: \decorrWidth, label: "декорреляция", group: \tone,              spec: ControlSpec(0.0,  0.3,  \lin, 0, 0.2)  ),  // L/R decorrelation, centre fixed

        // --- group \tone: master ---
        ( key: \amp, label: "громкость",         group: \tone,              spec: ControlSpec(0.0,  0.3,  \lin, 0, 0.14) )   // §K.4 schliere level
    ]
);


// ===== LOGIC — synthesis =============================================
// brown -> диффузия `diff` -> моды и полоса = BAND-PASS'ы от diff, поток =
// diff выше мод; сумма -> AM -> 2x LPF -> декорреляция -> makeup -> LeakDC -> Limiter
Ndef(\epsilon, { |amp = 0.14,
    freqLo = 30.28, freqHi = 49.30,
    m1 = 30.28, m2 = 37.30, m3 = 49.30, m4 = 54.28,
    flowCeil = 2500,
    mLevel = 0.35, mWidth = 0.06, mBreath = 0.04,
    flowLevel = 0.15, diffDepth = 0.6,
    streakLevel = 0.20, streakWidth = 0.45, driftPeriod = 180,
    surfDepth = 3.0, surfRate = 0.09, decorrWidth = 0.2|

    var nyq;
    var diffCentres = #[0.011, 0.019, 0.028, 0.037, 0.046, 0.055];
    var diffRates   = #[0.15, 0.21, 0.27, 0.33, 0.39, 0.45];
    // несоизмеримы и все ≤ 1.0: поправка ограничивает дыхание моды 0.1 Hz
    var breathMults = #[1.0, 0.83, 0.67, 0.91];
    // поток слышен ТОЛЬКО выше поля мод — полный brown утопил бы 20–300 Hz и
    // сломал flatness-гарантию (cave-reference, implementation note 1)
    var flowFloor = 250;
    // мода = каскадная пара BPF (12 dB/окт скаты) + трекинг-потолок обеих
    // полосных страт: одиночный BPF маскировал 250–800 Hz (note 2)
    var modeCeilRatio   = 2.2;
    var streakCeilRatio = 2.5;
    // +3 dB/окт против −6 dB/окт наклона источника: четыре моды равногромки (note 3)
    var modeTilt = 0.5;
    // тримы измерены по-стратно в solo-рендерах (band RMS), не аналитически
    var modeTrim   = 1.0;
    var flowTrim   = 0.7;
    var streakTrim = 0.5;
    var makeup     = 3.3;
    var freqLoL, freqHiL, flowCeilL, mLevelL, mWidthL, mBreathL;
    var flowLevelL, diffDepthL, streakLevelL, streakWidthL, driftT;
    var surfDepthL, surfRateL, wL;
    var src, diff, drift, sweepHz, mFreqs, mCeil, modes, flow, streak;
    var sum, apL, apR, sig;

    nyq = SampleRate.ir * 0.45;

    freqLoL      = freqLo.lag(0.2);
    freqHiL      = freqHi.lag(0.2);
    flowCeilL    = flowCeil.lag(0.2).clip(1200, nyq);
    mLevelL      = mLevel.lag(0.2).clip(0, 0.5);
    mWidthL      = mWidth.lag(0.2).clip(0.02, 0.3);
    flowLevelL   = flowLevel.lag(0.2).clip(0, 0.5);
    diffDepthL   = diffDepth.lag(0.2).clip(0, 1);
    streakLevelL = streakLevel.lag(0.2).clip(0, 0.5);
    streakWidthL = streakWidth.lag(0.2).clip(0.1, 1.5);
    surfDepthL   = surfDepth.lag(0.2).clip(0, 6);
    wL           = decorrWidth.lag(0.2).clip(0, 0.3);
    // rate-аргументы LFN: clip без lag — lag на частоте бесполезен
    driftT       = driftPeriod.clip(20, 240);
    surfRateL    = surfRate.clip(0.05, 0.3);
    mBreathL     = mBreath.clip(0.02, 0.1);

    // Stage 0: brown = white с наклоном −6 dB/окт (§C.5 (a)); HPF 40 — суб-гул
    // ниже §F-пола 40 Hz не тратит запас фильтров
    src = HPF.ar(BrownNoise.ar, 40);

    // Stage 1: диффузионная дымка; rates LFN фиксированы на build (diffDepth
    // маппит только глубину движения)
    diff = src;
    diffCentres.do { |c, i|
        diff = AllpassC.ar(diff, 0.06,
            (c + (LFNoise2.kr(diffRates[i]) * c * 0.6 * diffDepthL))
                .clip(0.008, 0.06),
            1.0);
    };

    // Stage 2: поле мод — 4 статичные узкие шумовые полосы решётки (не comb:
    // без обертонов и звона), нормализованы против f×rq; дыхание не доходит
    // до 0 — континуум не гейтится
    mFreqs = [m1, m2, m3, m4].collect { |n|
        n.lag(0.2).midicps.clip(47, nyq)
    };
    modes = Mix(mFreqs.collect { |f, i|
        var breath = LFNoise2.kr(mBreathL * breathMults[i]).range(0.45, 1.0);
        var band = BPF.ar(BPF.ar(diff, f, mWidthL), f, mWidthL);
        band
            * (150 / (f * mWidthL)).sqrt.clip(0.2, 8)
            * (f / 47).pow(modeTilt)
            * breath;
    }) * mLevelL * modeTrim;
    mCeil = (mFreqs.reduce(\max) * modeCeilRatio).clip(80, nyq);
    modes = LPF.ar(LPF.ar(modes, mCeil), mCeil);

    // Stage 3: поток — среда мод, только выше их области; лишний LPF темнит
    // к измеренному крутому верхнему спаду пещеры (2500–6000 ≤ −40 rel)
    flow = HPF.ar(diff, flowFloor);
    flow = LPF.ar(flow, flowCeilL) * flowLevelL * flowTrim;

    // Stage 4: ОДНА дрейфующая полоса — две несоизмеримые LFN (не синус),
    // маппинг в MIDI-пространстве; band-pass-формант, не comb (§C.5 (a))
    drift = LFNoise2.kr(driftT.reciprocal)
        + (LFNoise2.kr((driftT * 1.37).reciprocal) * 0.5);
    sweepHz = drift.range(freqLoL, freqHiL).midicps.clip(47, nyq);
    // нормализация: RMS BPF-на-шуме растёт как sqrt(cf×rq) — без неё полоса
    // вздувалась бы при дрейфе вверх
    streak = BPF.ar(diff, sweepHz, streakWidthL)
        * (150 / (sweepHz * streakWidthL)).sqrt.clip(0.2, 5);
    streak = LPF.ar(streak, (sweepHz * streakCeilRatio).clip(80, nyq))
        * streakLevelL * streakTrim;

    // Stage 5: поверхностная AM всего поля — воздух пещеры не неподвижен
    sum = modes + flow + streak;
    sum = sum * LFNoise2.kr(surfRateL).range(surfDepthL.neg.dbamp, 1);

    // Stage 6: ceiling — 2x LPF (-24 dB/oct)
    sum = LPF.ar(LPF.ar(sum, flowCeilL), flowCeilL);

    // Stage 7: equal-power декорреляция, центр энергии фиксирован в 0 (§F) —
    // ни Pan2, ни pan-LFO в слое нет
    apL = AllpassC.ar(sum, 0.02, LFNoise2.kr(0.19).range(0.004, 0.016), 0.8);
    apR = AllpassC.ar(sum, 0.02, LFNoise2.kr(0.27).range(0.005, 0.018), 0.8);
    sig = [
        XFade2.ar(sum, apL, (wL * 2) - 1),
        XFade2.ar(sum, apR, (wL * 2) - 1)
    ];

    // Stage 8: makeup кладёт RMS −24 dBFS при amp 0.14 (прецедент delta:
    // тюнить внутренности, не спек-дефолты)
    sig = sig * makeup * amp.lag(0.05);
    sig = LeakDC.ar(sig);
    sig = Limiter.ar(sig, 0.95);
    sig
});

// register spec + apply defaults (self-sufficient: 0_lib only needed for
// interactive random/presets/GUI after the full App load)
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\epsilon] = ~spec_epsilon;
~ungVals[\epsilon]  = ();
~spec_epsilon.params.do { |p|
    Ndef(\epsilon).set(p.key, p.spec.default);
    ~ungVals[\epsilon][p.key] = p.spec.default;
};
Ndef(\epsilon).fadeTime = 6;   // §C.5: onset ≥ 4 s; a schliere recedes, never cut

("synths/epsilon — spec зарегистрирован ("
    ++ ~spec_epsilon.params.size ++ " параметров); ~openTuner.(\\epsilon)").postln;
)
