// =====================================================================
// App/synths/firnis.scd
// UNGRUND · звуковой класс 8/8 — `firnis` (ultrasonic shimmer / ceiling)
//
// СТАТУС: ЗАГЛУШКА — минимальный, но СЛЫШИМЫЙ слой.  // TODO: iterate this layer
//   Премиса §C.8: 9-голосный шиммер на фикс. ультразвуковых частотах,
//   каждый голос с независимой медленной AM (LFNoise2 0.05–0.16 Hz),
//   мягкая кросс-AM между соседними парами (сцинтилляция), LPF 20 kHz,
//   Splay.ar(width: 0.55). Очень тихо — глазурь поверх спектра.
//
//   ВНИМАНИЕ: частоты строго 12–19 kHz. На системах с роллоффом выше
//   14 kHz слой может быть неслышим — это допустимо (§0001 perf notes).
// =====================================================================


// ===== CONFIG — edit here ============================================
(
~cfg_firnis = (
    freqs:   [12640, 13110, 14790, 16030, 17880, 12900, 13500, 15200, 16800], // 9 голосов, Hz
    ampEach: 0.010,    // §K.4: было 0.015 — на голос
    lfnRate: 0.12,     // базовая частота AM, Hz (0.05–0.16)
    width:   0.55      // Splay ширина
);


// ===== LOGIC — synthesis =============================================
Ndef(\firnis, { |ampEach = 0.010, lfnRate = 0.12, width = 0.55|
    var freqs, voices, sig;
    freqs = #[12640, 13110, 14790, 16030, 17880, 12900, 13500, 15200, 16800];
    voices = freqs.collect { |f, i|
        var rate = lfnRate.lag(1) * (0.7 + (i * 0.07));   // 0.05–0.16 Hz разброс
        var am   = LFNoise2.kr(rate.clip(0.02, 0.3)).range(0.15, 1.0);
        SinOsc.ar(f.clip(12000, 19000)) * am;
    };
    // мягкая кросс-AM между парами i / i+2 (сцинтилляция, depth < 0.025)
    voices = voices.collect { |v, i|
        var partner = voices[(i + 2) % voices.size];
        v * (1 - (0.025 * partner.abs));
    };
    sig = Splay.ar(voices, width.clip(0, 1)) * ampEach.lag(0.1);
    sig = LPF.ar(sig, 20000);
    sig = LeakDC.ar(sig);
    sig
});

Ndef(\firnis).set(
    \ampEach, ~cfg_firnis.ampEach, \lfnRate, ~cfg_firnis.lfnRate,
    \width, ~cfg_firnis.width
);
Ndef(\firnis).fadeTime = 8;   // §F: attack ≥ 8 s
)
