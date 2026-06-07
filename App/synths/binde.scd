// =====================================================================
// App/synths/binde.scd
// UNGRUND · звуковой класс 4/8 — `binde` (narrow-band noise)
//
// СТАТУС: ЗАГЛУШКА — минимальный, но СЛЫШИМЫЙ слой.  // TODO: iterate this layer
//   Премиса §C.4: формантный кластер — PinkNoise через 4 параллельных
//   BPF с центрами [f, f×1.003, f×0.998, f×1.005] и разными rq; каждый
//   BPF с независимой медленной AM (LFNoise2 0.1–0.25 Hz) => внутреннее
//   биение, хоровое качество без смены центральной высоты.
// =====================================================================


// ===== CONFIG — edit here ============================================
(
~cfg_binde = (
    freq:  1100,    // центр, Hz (100 Hz – 6 kHz)
    rq:    0.02,    // базовая добротность (0.005–0.05)
    amp:   0.18     // §K.4: было 0.25
);


// ===== LOGIC — synthesis =============================================
Ndef(\binde, { |freq = 1100, rq = 0.02, amp = 0.18|
    var src, mults, rqs, rates, bands, sig;
    src   = PinkNoise.ar;
    mults = #[1.0, 1.003, 0.998, 1.005];
    rqs   = #[0.020, 0.025, 0.018, 0.022];
    rates = #[0.12, 0.18, 0.10, 0.22];
    bands = mults.collect { |m, i|
        var cf  = (freq.lag(0.5) * m).clip(40, SampleRate.ir * 0.45);
        var thisRq = (rq.lag(0.3) * (rqs[i] / 0.02)).clip(0.001, 0.1);
        var am  = LFNoise2.kr(rates[i]).range(0.4, 1.0);   // медленное биение
        BPF.ar(src, cf, thisRq) * am;
    };
    sig = Mix(bands) * 6;                  // компенсация усиления после BPF
    sig = sig * amp.lag(0.05);
    sig = LeakDC.ar(sig);
    Pan2.ar(sig, 0)                        // §C.4: ≤ ±0.3, держим центр
});

Ndef(\binde).set(\freq, ~cfg_binde.freq, \rq, ~cfg_binde.rq, \amp, ~cfg_binde.amp);
Ndef(\binde).fadeTime = 3;
)
