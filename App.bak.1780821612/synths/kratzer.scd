// =====================================================================
// App/synths/kratzer.scd
// UNGRUND · звуковой класс 6/8 — `kratzer` (dry granulated noise burst)
//
// СТАТУС: ЗАГЛУШКА — минимальный, но СЛЫШИМЫЙ слой.  // TODO: iterate this layer
//   Премиса §C.6: высокочастотное мягкое облако шумовых зёрен (GrainNoise,
//   зерно 5–20 мс, плотность 40–80 /s), HPF выше 5 кГц, плотность зёрен
//   модулируется LFNoise2(1 Hz) — текстура без механического чоппинга.
//   Мягкий высокочастотный шорох, не жёсткое царапанье. Яркость хрупкая
//   (§C.6: reverb send низкий).
// =====================================================================


// ===== CONFIG — edit here ============================================
(
~cfg_kratzer = (
    hpf:     5000,   // нижняя граница, Hz (3 kHz – 12 kHz)
    density: 60,     // плотность зёрен, /s (40–80)
    grainDur: 0.012, // длительность зерна, s (5–20 мс)
    amp:     0.16    // 0.05–0.3
);
)


// ===== LOGIC — synthesis =============================================
(
Ndef(\kratzer, { |hpf = 5000, density = 60, grainDur = 0.012, amp = 0.16|
    var densMod, trig, sig;
    densMod = LFNoise2.kr(1).range(0.5, 1.0);          // модуляция плотности
    trig    = Dust.ar((density.lag(0.3) * densMod).clip(5, 120));
    sig     = GrainNoise.ar(2, trig, grainDur.clip(0.003, 0.03),
                LFNoise1.kr(4).range(-0.4, 0.4));        // §F: pan ≤ ±0.4
    sig     = HPF.ar(sig, hpf.lag(0.3).clip(1000, 14000));
    sig     = sig * amp.lag(0.05);
    sig     = LeakDC.ar(sig);
    sig
});

Ndef(\kratzer).set(
    \hpf, ~cfg_kratzer.hpf, \density, ~cfg_kratzer.density,
    \grainDur, ~cfg_kratzer.grainDur, \amp, ~cfg_kratzer.amp
);
Ndef(\kratzer).fadeTime = 0.5;
)
