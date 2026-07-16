// App/6_effects.scd — UNGRUND · EFFECTS (§K reference_v2): \tape_reverb
// (§K.1) reads ~busFxSendRev, \ping_delay (§K.2) reads ~busFxSendDly —
// separate buses, so the §K.1/§K.2 send tables stay independent. Both
// write their returns to ~busFxReturn (read by the master in 2_mixer.scd).
// Buses are created by 1_app.scd.


// ===== CONFIG — edit here ============================================
(
~cfg_effects = (
    // --- tape reverb (§K.1) ---
    rev_wet:      0.85,    // return level
    rev_decay:    0.95,    // CombC decay, s (§K.1 amended 2026-07-16: 0.9–4)
    rev_rolloff:  3500,    // tail LPF (tape rolloff), Hz

    // --- ping-pong delay (§K.2) ---
    dly_wet:      0.5,     // return level
    dly_timeL:    0.37,    // L time, s
    dly_timeR:    0.53,    // R time, s (incommensurate with L)
    dly_fb:       0.55,    // feedback
    dly_lpf:      1800     // LPF in the feedback loop, Hz
);


// ===== LOGIC — effect proxies ========================================
// --- K.1  tape reverb -------------------------------------------------
Ndef(\tape_reverb, { |wet = 0.85, decay = 0.95, rolloff = 3500|
    var sig, ratesL, ratesR, diffL, diffR, combL, combR, roll;
    sig    = InFeedback.ar(~busFxSendRev.index, 2);
    sig    = DelayC.ar(sig, 0.05, 0.012);
    ratesL = [0.17, 0.24, 0.19, 0.31];
    ratesR = [0.21, 0.16, 0.28, 0.23];
    diffL  = sig[0];
    diffR  = sig[1];
    ratesL.do { |r| diffL = AllpassC.ar(diffL, 0.08, LFNoise2.kr(r).range(0.010, 0.070), 1.2) };
    ratesR.do { |r| diffR = AllpassC.ar(diffR, 0.08, LFNoise2.kr(r).range(0.010, 0.070), 1.2) };
    // §K.1 decay range 0.9–4 s (floor extended from 2 s, 2026-07-16: the
    // send is the system's ONLY mechanism for space — no class may bake a
    // tail in — so any tail a piece needs must be reachable here)
    combL  = CombC.ar(diffL, 0.5, 0.087 + LFNoise2.kr(0.21).range(-0.002, 0.002), decay.clip(0.9, 4.0));
    combR  = CombC.ar(diffR, 0.5, 0.113 + LFNoise2.kr(0.17).range(-0.002, 0.002), decay.clip(0.9, 4.0));
    roll   = (rolloff.lag(0.3) + LFNoise2.kr(0.09).range(-300, 300)).clip(500, 12000);
    sig    = LPF.ar([combL, combR], roll);
    sig    = LeakDC.ar(sig);
    sig * wet.lag(0.1)
});

// --- K.2  ping-pong delay ---------------------------------------------
Ndef(\ping_delay, { |wet = 0.5, timeL = 0.37, timeR = 0.53, fb = 0.55, lpf = 1800|
    var in, dL, dR, sig;
    in = InFeedback.ar(~busFxSendDly.index, 2);
    in = Mix(in) * 0.5;                              // mono into the ping-pong
    dL = LocalIn.ar(2);
    // L gets input + decayed right tail; R gets the left tail
    sig = [
        in + (dL[1] * fb.clip(0, 0.9)),
        dL[0] * fb.clip(0, 0.9)
    ];
    sig = LPF.ar(sig, lpf.lag(0.3).clip(300, 8000));  // filter in the loop
    sig = [
        DelayC.ar(sig[0], 1.0, timeL.clip(0.05, 1.0)),
        DelayC.ar(sig[1], 1.0, timeR.clip(0.05, 1.0))
    ];
    LocalOut.ar(sig);
    sig = LeakDC.ar(sig);
    sig * wet.lag(0.1)
});

// apply CONFIG
Ndef(\tape_reverb).set(
    \wet, ~cfg_effects.rev_wet, \decay, ~cfg_effects.rev_decay,
    \rolloff, ~cfg_effects.rev_rolloff
);
Ndef(\ping_delay).set(
    \wet, ~cfg_effects.dly_wet, \timeL, ~cfg_effects.dly_timeL,
    \timeR, ~cfg_effects.dly_timeR, \fb, ~cfg_effects.dly_fb,
    \lpf, ~cfg_effects.dly_lpf
);
Ndef(\tape_reverb).fadeTime = 2;
Ndef(\ping_delay).fadeTime = 2;

// effect returns -> ~busFxReturn
Ndef(\tape_reverb).play(out: ~busFxReturn.index, numChannels: 2);
Ndef(\ping_delay).play(out: ~busFxReturn.index, numChannels: 2);
)
