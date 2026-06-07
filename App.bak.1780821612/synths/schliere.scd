// =====================================================================
// App/synths/schliere.scd
// UNGRUND · звуковой класс 5/8 — `schliere` (drifting comb-filtered noise)
//
// СТАТУС: ЗАГЛУШКА — минимальный, но СЛЫШИМЫЙ слой.  // TODO: iterate this layer
//   Премиса §C.5: allpass-сеть диффузии (6 AllpassC с LFNoise2-
//   модулированными временами) -> дрейфующий CombC (период 20–240 с,
//   несоизмеримые медленные LFN, никогда не чистая синусоида) -> мягкий
//   DelayC-шиммер. Медленный спектральный штрих; фейд-ин ≥ 4 с.
// =====================================================================


// ===== CONFIG — edit here ============================================
(
~cfg_schliere = (
    freqLo: 200,    // нижняя точка дрейфа гребёнки, Hz
    freqHi: 800,    // верхняя точка дрейфа, Hz (200 Hz – 2 kHz)
    period: 90,     // период дрейфа, s (20–240)
    amp:    0.14    // §K.4: было 0.18
);
)


// ===== LOGIC — synthesis =============================================
(
Ndef(\schliere, { |freqLo = 200, freqHi = 800, period = 90, amp = 0.14|
    var src, diff, sweepHz, combTime, sig, shimmer;
    src  = WhiteNoise.ar(0.3);

    // 6 AllpassC — дымка диффузии («комната внутри звука»)
    diff = src;
    6.do { |i|
        diff = AllpassC.ar(diff, 0.06,
            LFNoise2.kr(0.15 + (i * 0.05)).range(0.008, 0.06), 1.0);
    };

    // дрейф гребёнки: сумма несоизмеримых медленных LFN, не чистый синус
    sweepHz = (LFNoise2.kr(1 / period.clip(20, 240))
                + (LFNoise2.kr(1 / (period * 1.37)) * 0.5)).range(
                    freqLo.lag(1).clip(50, 2000), freqHi.lag(1).clip(50, 2000));
    combTime = (1 / sweepHz).clip(0.0005, 0.05);
    sig = CombC.ar(diff, 0.05, combTime, 0.2);

    // мягкий хорус-шиммер
    shimmer = DelayC.ar(sig, 0.01, LFNoise2.kr(0.3).range(0.0, 0.002));
    sig = (sig + shimmer) * 0.5;

    sig = sig * amp.lag(0.05);
    sig = LeakDC.ar(sig);
    Pan2.ar(sig, 0)                        // §C.5: центр
});

Ndef(\schliere).set(
    \freqLo, ~cfg_schliere.freqLo, \freqHi, ~cfg_schliere.freqHi,
    \period, ~cfg_schliere.period, \amp, ~cfg_schliere.amp
);
Ndef(\schliere).fadeTime = 6;   // §C.5: фейд-ин ≥ 4 с
)
