// App/synths/gamma.scd — UNGRUND class 3/8 `gamma` (granular cluster of sines).
// STUB — minimal but audible.  // TODO: iterate this layer
// Premise §C.3: countable cloud of short sine grains on neighbouring
// harmonic positions (partials 5,7,9,11,13 × fund, ±3% jitter), slow
// breathing crossfade; should read as 3–8 distinct grains.


// ===== CONFIG — edit here ============================================
(
~cfg_gamma = (
    fund:     220,                  // fundamental, Hz (80 Hz – 1.2 kHz)
    partials: [5, 7, 9, 11, 13],    // §C.3 harmonic positions
    rate:     6,                    // grain density, /s
    grainDur: 0.12,                 // grain duration, s (60–180 ms)
    amp:      0.14                  // 0.05–0.25 per grain
);


// ===== LOGIC — synthesis =============================================
Ndef(\gamma, { |fund = 220, rate = 6, grainDur = 0.12, amp = 0.14|
    var partials, breathe, sig;
    partials = #[5, 7, 9, 11, 13];
    breathe  = LFNoise2.kr(0.6).range(0.3, 1.0);   // cloud breathing
    sig = Mix(partials.collect { |h, i|
        var trig, jit, freq;
        trig = Dust.ar(rate.lag(0.5).clip(0.5, 16) / partials.size);
        jit  = LFNoise1.kr(0.7).range(0.97, 1.03);  // ±3% jitter
        freq = (fund.lag(0.3) * h * jit).clip(20, SampleRate.ir * 0.45);
        GrainSin.ar(2, trig, grainDur.clip(0.02, 0.2), freq,
            LFNoise1.kr(3).range(-0.5, 0.5));
    });
    sig = sig * breathe * amp.lag(0.05);
    sig = LeakDC.ar(sig);
    sig
});

Ndef(\gamma).set(
    \fund, ~cfg_gamma.fund, \rate, ~cfg_gamma.rate,
    \grainDur, ~cfg_gamma.grainDur, \amp, ~cfg_gamma.amp
);
Ndef(\gamma).fadeTime = 1;
)
