// App/synths/beta.scd — UNGRUND class 2/8 `beta` (broadband impulse).
// STUB — minimal but audible.  // TODO: iterate this layer
// Premise §C.2: soft granular cloud of short sine grains, no hard attack.
// Simplified here: internally triggered GrainSin cloud; full event logic
// (RMS threshold, refractory) lives in 4_sequencer.scd. Quiet and sparse —
// event layer, not a drone.


// ===== CONFIG — edit here ============================================
(
~cfg_beta = (
    rate:     0.18,    // burst rate, /s (anti-rhythm; threshold-driven in the real layer)
    centre:   520,     // grain centre frequency, Hz
    scatter:  4,       // spread, ±semitones
    grainDur: 0.025,   // grain duration, s (15–40 ms)
    amp:      0.32,    // §K.4: peak 0.25–0.55
    hpf:      200      // §C.2: grain-bus HPF
);


// ===== LOGIC — synthesis =============================================
Ndef(\beta, { |rate = 0.18, centre = 520, scatter = 4, grainDur = 0.025,
               amp = 0.32, hpf = 200|
    var trig, swell, freq, sig;
    trig  = Dust.ar(rate.lag(0.5).clip(0.01, 8));
    freq  = (centre.cpsmidi + LFNoise1.kr(20).range(scatter.neg, scatter)).midicps
                .clip(20, SampleRate.ir * 0.45);
    swell = Decay2.ar(trig, 0.08, 0.18);   // breath, not crack
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
