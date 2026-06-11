// App/synths/epsilon.scd — UNGRUND class 5/8 `epsilon` (drifting
// comb-filtered noise). STUB — minimal but audible.  // TODO: iterate this layer
// Premise §C.5: allpass diffusion net -> drifting CombC (period 20–240 s,
// incommensurate slow LFNs, never a pure sine) -> soft DelayC shimmer.
// Slow spectral stroke; fade-in ≥ 4 s.


// ===== CONFIG — edit here ============================================
(
~cfg_epsilon = (
    freqLo: 200,    // comb drift low point, Hz
    freqHi: 800,    // comb drift high point, Hz (200 Hz – 2 kHz)
    period: 90,     // drift period, s (20–240)
    amp:    0.14    // §K.4
);


// ===== LOGIC — synthesis =============================================
Ndef(\epsilon, { |freqLo = 200, freqHi = 800, period = 90, amp = 0.14|
    var src, diff, sweepHz, combTime, sig, shimmer;
    src  = WhiteNoise.ar(0.3);

    // 6 AllpassC — diffusion haze
    diff = src;
    6.do { |i|
        diff = AllpassC.ar(diff, 0.06,
            LFNoise2.kr(0.15 + (i * 0.05)).range(0.008, 0.06), 1.0);
    };

    // comb drift: sum of incommensurate slow LFNs, not a pure sine
    sweepHz = (LFNoise2.kr(1 / period.clip(20, 240))
                + (LFNoise2.kr(1 / (period * 1.37)) * 0.5)).range(
                    freqLo.lag(1).clip(50, 2000), freqHi.lag(1).clip(50, 2000));
    combTime = (1 / sweepHz).clip(0.0005, 0.05);
    sig = CombC.ar(diff, 0.05, combTime, 0.2);

    // soft chorus shimmer
    shimmer = DelayC.ar(sig, 0.01, LFNoise2.kr(0.3).range(0.0, 0.002));
    sig = (sig + shimmer) * 0.5;

    sig = sig * amp.lag(0.05);
    sig = LeakDC.ar(sig);
    Pan2.ar(sig, 0)                        // §C.5: centre
});

Ndef(\epsilon).set(
    \freqLo, ~cfg_epsilon.freqLo, \freqHi, ~cfg_epsilon.freqHi,
    \period, ~cfg_epsilon.period, \amp, ~cfg_epsilon.amp
);
Ndef(\epsilon).fadeTime = 6;   // §C.5: fade-in ≥ 4 s
)
