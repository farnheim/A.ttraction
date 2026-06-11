// App/synths/theta.scd — UNGRUND class 8/8 `theta` (ultrasonic shimmer).
// STUB — minimal but audible.  // TODO: iterate this layer
// Premise §C.8: 9-voice shimmer on fixed ultrasonic frequencies, each with
// independent slow AM, soft cross-AM between pairs (scintillation),
// LPF 20 kHz, Splay. Very quiet — glaze on top of the spectrum.
// NOTE: frequencies strictly 12–19 kHz; may be inaudible on systems
// rolling off above 14 kHz — acceptable (§0001 perf notes).


// ===== CONFIG — edit here ============================================
(
~cfg_theta = (
    freqs:   [12640, 13110, 14790, 16030, 17880, 12900, 13500, 15200, 16800], // 9 voices, Hz
    ampEach: 0.010,    // §K.4: per voice
    lfnRate: 0.12,     // base AM rate, Hz (0.05–0.16)
    width:   0.55      // Splay width
);


// ===== LOGIC — synthesis =============================================
Ndef(\theta, { |ampEach = 0.010, lfnRate = 0.12, width = 0.55|
    var freqs, voices, sig;
    freqs = #[12640, 13110, 14790, 16030, 17880, 12900, 13500, 15200, 16800];
    voices = freqs.collect { |f, i|
        var rate = lfnRate.lag(1) * (0.7 + (i * 0.07));   // 0.05–0.16 Hz spread
        var am   = LFNoise2.kr(rate.clip(0.02, 0.3)).range(0.15, 1.0);
        SinOsc.ar(f.clip(12000, 19000)) * am;
    };
    // soft cross-AM between pairs i / i+2 (scintillation, depth < 0.025)
    voices = voices.collect { |v, i|
        var partner = voices[(i + 2) % voices.size];
        v * (1 - (0.025 * partner.abs));
    };
    sig = Splay.ar(voices, width.clip(0, 1)) * ampEach.lag(0.1);
    sig = LPF.ar(sig, 20000);
    sig = LeakDC.ar(sig);
    sig
});

Ndef(\theta).set(
    \ampEach, ~cfg_theta.ampEach, \lfnRate, ~cfg_theta.lfnRate,
    \width, ~cfg_theta.width
);
Ndef(\theta).fadeTime = 8;   // §F: attack ≥ 8 s
)
