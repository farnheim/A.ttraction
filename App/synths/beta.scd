// =====================================================================
// App/synths/beta.scd
// UNGRUND · звуковой класс 2/8 — `beta` (broadband impulse)
//
// СТАТУС: ЗАГЛУШКА — минимальный, но СЛЫШИМЫЙ слой.  // TODO: iterate this layer
//   Премиса §C.2: мягкое гранулярное облако коротких синус-зёрен,
//   рассеянных по окну 150–300 мс, без жёсткой атаки. Здесь — упрощённо:
//   облако зёрен (GrainSin), запускаемое внутренним триггером для
//   слышимости в скелете. Полная событийная логика (RMS-порог,
//   refractory) живёт в 4_sequencer.scd / процессе substratumwalk.
//
//   Этот слой держится тихо и редко стреляет — он событийный, не дрон.
// =====================================================================


// ===== CONFIG — edit here ============================================
(
~cfg_beta = (
    rate:     0.18,    // частота вспышек, /s (анти-ритм; в реале — по порогу)
    centre:   520,     // центр частоты зёрен, Hz
    scatter:  4,       // разброс ±полутонов
    grainDur: 0.025,   // длительность зерна, s (15–40 мс)
    amp:      0.32,    // §K.4: пик 0.25–0.55
    hpf:      200      // §C.2: HPF грейн-шины
);


// ===== LOGIC — synthesis =============================================
Ndef(\beta, { |rate = 0.18, centre = 520, scatter = 4, grainDur = 0.025,
               amp = 0.32, hpf = 200|
    var trig, swell, freq, sig;
    trig  = Dust.ar(rate.lag(0.5).clip(0.01, 8));
    // мягкая густота: разброс зёрен по полутонам вокруг центра
    freq  = (centre.cpsmidi + LFNoise1.kr(20).range(scatter.neg, scatter)).midicps
                .clip(20, SampleRate.ir * 0.45);
    swell = Decay2.ar(trig, 0.08, 0.18);   // breath, не crack
    sig   = GrainSin.ar(2, trig, grainDur.clip(0.005, 0.08), freq, LFNoise1.kr(5).range(-0.6, 0.6));
    sig   = sig * swell * amp.lag(0.05);
    sig   = HPF.ar(sig, hpf.clip(50, 12000));
    sig   = LeakDC.ar(sig);
    sig
});

Ndef(\beta).set(
    \rate, ~cfg_beta.rate, \centre, ~cfg_beta.centre, \scatter, ~cfg_beta.scatter,
    \grainDur, ~cfg_beta.grainDur, \amp, ~cfg_beta.amp, \hpf, ~cfg_beta.hpf
);
Ndef(\beta).fadeTime = 1;
)
