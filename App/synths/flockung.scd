// =====================================================================
// App/synths/flockung.scd
// UNGRUND · звуковой класс 3/8 — `flockung` (granular cluster of sines)
//
// СТАТУС: ЗАГЛУШКА — минимальный, но СЛЫШИМЫЙ слой.  // TODO: iterate this layer
//   Премиса §C.3: счётное облако коротких синус-зёрен в соседних
//   гармонических позициях (партиалы 5,7,9,11,13 × fund с джиттером ±3%).
//   Зёрна 60–180 мс, разброс онсета ±80 мс, медленный «дыхательный»
//   кросс-фейд всего облака. Должно читаться как 3–8 различимых зёрен.
// =====================================================================


// ===== CONFIG — edit here ============================================
(
~cfg_flockung = (
    fund:     220,                  // фундамент, Hz (80 Hz – 1.2 kHz)
    partials: [5, 7, 9, 11, 13],    // §C.3 гармонические позиции
    rate:     6,                    // плотность зёрен, /s
    grainDur: 0.12,                 // длительность зерна, s (60–180 мс)
    amp:      0.14                  // 0.05–0.25 на зерно
);


// ===== LOGIC — synthesis =============================================
Ndef(\flockung, { |fund = 220, rate = 6, grainDur = 0.12, amp = 0.14|
    var partials, breathe, sig;
    partials = #[5, 7, 9, 11, 13];
    breathe  = LFNoise2.kr(0.6).range(0.3, 1.0);   // дыхание облака
    sig = Mix(partials.collect { |h, i|
        var trig, jit, freq;
        trig = Dust.ar(rate.lag(0.5).clip(0.5, 16) / partials.size);
        jit  = LFNoise1.kr(0.7).range(0.97, 1.03);  // ±3% джиттер
        freq = (fund.lag(0.3) * h * jit).clip(20, SampleRate.ir * 0.45);
        GrainSin.ar(2, trig, grainDur.clip(0.02, 0.2), freq,
            LFNoise1.kr(3).range(-0.5, 0.5));
    });
    sig = sig * breathe * amp.lag(0.05);
    sig = LeakDC.ar(sig);
    sig
});

Ndef(\flockung).set(
    \fund, ~cfg_flockung.fund, \rate, ~cfg_flockung.rate,
    \grainDur, ~cfg_flockung.grainDur, \amp, ~cfg_flockung.amp
);
Ndef(\flockung).fadeTime = 1;
)
