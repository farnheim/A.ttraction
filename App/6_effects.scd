// App/6_effects.scd — UNGRUND · EFFECTS (§K, Space Echo model): one Roland
// RE-201 body (~spaceEchoBody) instantiated twice. \space_echo_rev (§K.1,
// reverb-forward) reads ~busFxSendRev; \space_echo_dly (§K.2, multi-tap echo)
// reads ~busFxSendDly — separate buses, so the §K.1/§K.2 send tables stay
// independent. Both write their returns to ~busFxReturn (read by the master in
// 2_mixer.scd). Buses are created by 1_app.scd. Spec: docs/features/effects/dsp-spec.md.


// ===== CONFIG — edit here ============================================
(
~cfg_effects = (
    // --- space echo · reverb-forward (§K.1, ~busFxSendRev) ---
    rev_mode: 11, rev_tapTime: 0.20, rev_intensity: 0.45,
    rev_echoVol: 0.35, rev_reverbVol: 0.90, rev_wet: 0.85,
    rev_drive: 0.35, rev_bias: 0.10, rev_wow: 0.35, rev_flutter: 0.20,
    rev_age: 0.25, rev_headBump: 0.45, rev_headSpread: 0.15,
    rev_bass: 0.0, rev_treble: -0.15,
    rev_springDecay: 3.0, rev_springTone: 0.50, rev_hiss: 0.04,

    // --- space echo · multi-tap echo (§K.2, ~busFxSendDly) ---
    dly_mode: 4, dly_tapTime: 0.19, dly_intensity: 0.55,
    dly_echoVol: 0.90, dly_reverbVol: 0.00, dly_wet: 0.50,
    dly_drive: 0.40, dly_bias: 0.12, dly_wow: 0.30, dly_flutter: 0.22,
    dly_age: 0.20, dly_headBump: 0.35, dly_headSpread: 0.32,
    dly_bass: 0.0, dly_treble: -0.10,
    dly_springDecay: 2.0, dly_springTone: 0.50, dly_hiss: 0.05
);


// ===== LOGIC — RE-201 Space Echo body + two proxies ==================
// One mono tape/regeneration loop, stereo reconstructed at the taps + springs.
// Every knob is a NamedControl.kr; the ONLY per-instance difference is the
// input send-bus index, captured from the closure at build time. Tape
// saturation + head losses live INSIDE the LocalIn/LocalOut loop, so each
// regenerated pass darkens as it recedes.
~spaceEchoBody = { |inBusIndex|
    var mode, tapTime, intensity, echoVol, reverbVol, wet, drive, bias,
        wow, flutter, age, headBump, headSpread, bass, treble,
        springDecay, springTone, hiss;
    var in, fb, rec, g, mem, preEmph, sat;
    var gapCorner, bumpCenter, tape, dropTrig, dip, click, loopRate;
    var maxDelay = 1.5, wowDepth, flutDepth, mod1, mod2, mod3, tt1, tt2, tt3, t1, t2, t3;
    var maskH1, maskH2, maskH3, revTab, midx, g1, g2, g3, revEnable, tapSum;
    var toneFn, p1, p2, p3, echoStereo, springIn, springFn, sp1, sp2, sp3;
    var reverbStereo, hissSig, out;

    mode        = \mode.kr(11);
    tapTime     = \tapTime.kr(0.20).lag(0.2).clip(0.045, 0.30);
    intensity   = \intensity.kr(0.45).lag(0.2).clip(0, 1.1);
    echoVol     = \echoVol.kr(0.35).lag(0.1);
    reverbVol   = \reverbVol.kr(0.90).lag(0.1);
    wet         = \wet.kr(0.85).lag(0.1);
    drive       = \drive.kr(0.35).lag(0.1).clip(0, 1);
    bias        = \bias.kr(0.10).lag(0.1);
    wow         = \wow.kr(0.35).lag(0.2);
    flutter     = \flutter.kr(0.20).lag(0.2);
    age         = \age.kr(0.25).lag(0.2).clip(0, 1);
    headBump    = \headBump.kr(0.45).lag(0.2);
    headSpread  = \headSpread.kr(0.15).lag(0.2).clip(0, 0.4);
    bass        = \bass.kr(0.0).lag(0.2);
    treble      = \treble.kr(-0.15).lag(0.2);
    springDecay = \springDecay.kr(3.0).lag(0.2).clip(0.5, 6);
    springTone  = \springTone.kr(0.50).lag(0.2);
    hiss        = \hiss.kr(0.04).lag(0.1);

    // --- S0  input / record head + regeneration --------------------------
    in  = Mix(InFeedback.ar(inBusIndex, 2)) * 0.5;
    fb  = LocalIn.ar(1);
    rec = (in * drive.linlin(0, 1, 0.5, 4.0)) + (intensity * fb);
    // tanh soft-clip = runaway self-oscillation guard: near intensity 1.0 the
    // loop must saturate, not diverge — the master Limiter is the last line.
    rec = tanh(rec);

    // --- S1  record pre-emphasis (HF boost, net-flat vs S6 de-emphasis) ---
    preEmph = BHiShelf.ar(rec, 3000, 1.0, 4.0);

    // --- S2  hysteresis saturation (asym, memoryful — J-A approximation) --
    // memory term = one-pole of the previous loop output (fb); bias sets the
    // asymmetric minor-loop onset. In-graph shaper (no oversampling island);
    // the S3 head-gap LPF doubles as reconstruction filter.
    // /g.max(1) normalisation keeps the saturator's SMALL-signal gain ≈ 1 as
    // drive rises (tanh(g·x)/g has unit slope at 0), so drive adds saturation
    // without adding loop gain — otherwise the in-loop stage amplifies the hiss
    // floor and the regeneration loop self-oscillates from silence. mem is a
    // small hysteresis-lag flavour, NOT a regeneration path.
    g   = drive.linlin(0, 1, 1.0, 4.0);
    mem = LPF.ar(fb, 1500) * 0.08;
    sat = tanh(g * (preEmph + bias + mem)) / g.max(1.0);
    // kill the DC the bias/asymmetry inject before it accumulates in the loop
    sat = LeakDC.ar(sat);

    // --- S3  head-gap HF loss (speed + age dependent) --------------------
    gapCorner = (tapTime.explin(0.045, 0.30, 8000, 2500) * age.linlin(0, 1, 1.0, 0.6))
        .clip(500, SampleRate.ir * 0.45);
    tape = LPF.ar(sat, gapCorner);

    // --- S4  head bump (LF resonant boost, center falls as tape slows) ----
    // max boost capped at +4 dB (realistic RE-201 head bump, not +6): this stage
    // is INSIDE the regeneration loop, and +6 dB let the LF ring dominate the
    // self-oscillation onset; +4 keeps the seeded LF-osc onset in the 0.95–1.05
    // target and makes near-self-osc broadband rather than a LF boom.
    bumpCenter = tapTime.explin(0.045, 0.30, 120, 55).clip(20, SampleRate.ir * 0.45);
    tape = MidEQ.ar(tape, bumpCenter, 1.0, headBump.linlin(0, 1, 0, 4));

    // --- S5  aging: dropouts (in-loop multiplier, injects no energy) ------
    // the splice click is NOT added here: an additive Impulse inside the
    // feedback loop is a perpetual, self-regenerating source — the loop could
    // never return to silence when the input was removed (muting all layers
    // still left it "ringing"). It moves to the OUTPUT path (S7b) as a
    // playback-head artefact that ticks once per loop without regenerating.
    loopRate = (tapTime * 3).reciprocal;
    dropTrig = Dust.kr(age * 0.8);
    dip      = 1 - (Decay2.kr(dropTrig, 0.005, 0.06) * (age * 0.5));
    tape     = tape * dip;

    // --- S7  taps + wow/flutter (fractional delay-time deviation ≪ 1 %) ---
    wowDepth  = wow * 0.004 * age.linlin(0, 1, 0.6, 1.4);
    flutDepth = flutter * 0.001 * age.linlin(0, 1, 0.6, 1.4);
    mod1 = ((SinOsc.kr(0.7, 0.0) + (SinOsc.kr(loopRate) * 0.5)) * wowDepth) + (LFNoise2.kr(9)  * flutDepth);
    mod2 = ((SinOsc.kr(1.1, 0.5) + (SinOsc.kr(loopRate) * 0.5)) * wowDepth) + (LFNoise2.kr(13) * flutDepth);
    mod3 = ((SinOsc.kr(0.9, 1.0) + (SinOsc.kr(loopRate) * 0.5)) * wowDepth) + (LFNoise2.kr(17) * flutDepth);
    // per-head detune [1.00, 1.98, 3.05] — imperfect tape, not a clean tap bank
    tt1 = (tapTime * 1.00 * (1 + mod1)).clip(0.001, maxDelay);
    tt2 = (tapTime * 1.98 * (1 + mod2)).clip(0.001, maxDelay);
    tt3 = (tapTime * 3.05 * (1 + mod3)).clip(0.001, maxDelay);
    t1 = DelayC.ar(tape, maxDelay, tt1);
    t2 = DelayC.ar(tape, maxDelay, tt2);
    t3 = DelayC.ar(tape, maxDelay, tt3);

    // --- S8  head masks (mode) — live-switchable, lagged to avoid clicks --
    maskH1 = [1, 0, 1, 1,  1, 0, 0, 1,  0, 1, 1, 0];
    maskH2 = [0, 1, 1, 1,  0, 1, 0, 1,  1, 0, 1, 0];
    maskH3 = [0, 0, 0, 1,  0, 0, 1, 0,  1, 1, 1, 0];
    revTab = [0, 0, 0, 0,  1, 1, 1, 1,  1, 1, 1, 1];
    midx = (mode - 1).clip(0, 11);
    g1 = Select.kr(midx, maskH1).lag(0.05);
    g2 = Select.kr(midx, maskH2).lag(0.05);
    g3 = Select.kr(midx, maskH3).lag(0.05);
    revEnable = Select.kr(midx, revTab).lag(0.05);
    tapSum = (t1 * g1) + (t2 * g2) + (t3 * g3);

    // feedback tap: the masked, loss-shaped mono sum feeds the next pass,
    // normalised by the active-head count so a 3-head mode does not multiply
    // the regeneration gain by 3 and self-oscillate from the hiss floor —
    // intensity alone must set the self-oscillation threshold.
    LocalOut.ar(tapSum / (g1 + g2 + g3).max(1.0));

    // --- S6  playback de-emphasis + RE-201 Bass/Treble tone (output path) -
    toneFn = { |s|
        s = BHiShelf.ar(s, 3000, 1.0, -4.0);
        s = BLowShelf.ar(s, 200,  1.0, bass.linlin(-1, 1, -15, 15));
        s = BHiShelf.ar(s, 3500,  1.0, treble.linlin(-1, 1, -15, 15));
        s;
    };
    p1 = toneFn.(t1); p2 = toneFn.(t2); p3 = toneFn.(t3);

    // --- S7b  head panning across ±headSpread (ping-pong-like motion) -----
    echoStereo = Pan2.ar(p1 * g1, headSpread.neg)
        + Pan2.ar(p2 * g2, 0)
        + Pan2.ar(p3 * g3, headSpread);
    // splice click on the OUTPUT path only (playback-head artefact, once per
    // tape loop) — see S5: keeping it out of the feedback tap lets the loop
    // decay to true silence when input stops
    click = BPF.ar(Impulse.ar(loopRate), 2500, 0.5) * age * 0.3;
    echoStereo = echoStereo + Pan2.ar(click, 0);

    // --- S9  3-spring reverb tank (dispersive allpass + comb + band) ------
    springIn = tapSum + (in * 0.2);
    springFn = { |sig, seed, baseDelay|
        var s = sig;
        [0.0047, 0.0071, 0.0093, 0.0113, 0.0137].do { |apt|
            var mt = ((apt + (seed * 0.0007)) * LFNoise2.kr(0.3 + seed).range(0.97, 1.03))
                .clip(0.001, 0.05);
            s = AllpassC.ar(s, 0.05, mt, 0.08);
        };
        s = CombC.ar(s, 0.2, baseDelay, springDecay);
        // tone = HF rolloff (keeps full low + low-mid body) plus a light resonant
        // spring emphasis. A narrow band-pass here (old: Resonz 800–3000 Hz)
        // stripped the low end and made the reverb return thin on the bottom.
        s = LPF.ar(s, springTone.linexp(0, 1, 1800, 6000).clip(300, SampleRate.ir * 0.45));
        s = s + (Resonz.ar(s, springTone.linexp(0, 1, 600, 2200).clip(200, SampleRate.ir * 0.45), 0.5) * 0.9);
        s;
    };
    sp1 = springFn.(springIn, 0, 0.031);
    sp2 = springFn.(springIn, 1, 0.037);
    sp3 = springFn.(springIn, 2, 0.041);
    reverbStereo = [sp1 + (sp2 * 0.5), sp3 + (sp2 * 0.5)] * 0.3 * revEnable;

    // --- S10  mix / condition --------------------------------------------
    // fixed makeup (outside the feedback loop, so it cannot affect stability)
    // so the return lands near the §K.4 budget (wash RMS ≈ −22 dBFS, peak with
    // headroom) at nominal send levels; NOT a CONFIG knob.
    out = wet * 3.5 * ((echoVol * echoStereo) + (reverbVol * reverbStereo));
    hissSig = PinkNoise.ar([1, 1]) * (hiss * (0.5 + age) * 0.01);
    out = out + hissSig;
    out = LeakDC.ar(out);
    out;
};

// two persistent proxies, one shared body; each reads exactly one send bus
Ndef(\space_echo_rev, { ~spaceEchoBody.(~busFxSendRev.index) });
Ndef(\space_echo_dly, { ~spaceEchoBody.(~busFxSendDly.index) });

// apply CONFIG
Ndef(\space_echo_rev).set(
    \mode, ~cfg_effects.rev_mode, \tapTime, ~cfg_effects.rev_tapTime,
    \intensity, ~cfg_effects.rev_intensity, \echoVol, ~cfg_effects.rev_echoVol,
    \reverbVol, ~cfg_effects.rev_reverbVol, \wet, ~cfg_effects.rev_wet,
    \drive, ~cfg_effects.rev_drive, \bias, ~cfg_effects.rev_bias,
    \wow, ~cfg_effects.rev_wow, \flutter, ~cfg_effects.rev_flutter,
    \age, ~cfg_effects.rev_age, \headBump, ~cfg_effects.rev_headBump,
    \headSpread, ~cfg_effects.rev_headSpread, \bass, ~cfg_effects.rev_bass,
    \treble, ~cfg_effects.rev_treble, \springDecay, ~cfg_effects.rev_springDecay,
    \springTone, ~cfg_effects.rev_springTone, \hiss, ~cfg_effects.rev_hiss
);
Ndef(\space_echo_dly).set(
    \mode, ~cfg_effects.dly_mode, \tapTime, ~cfg_effects.dly_tapTime,
    \intensity, ~cfg_effects.dly_intensity, \echoVol, ~cfg_effects.dly_echoVol,
    \reverbVol, ~cfg_effects.dly_reverbVol, \wet, ~cfg_effects.dly_wet,
    \drive, ~cfg_effects.dly_drive, \bias, ~cfg_effects.dly_bias,
    \wow, ~cfg_effects.dly_wow, \flutter, ~cfg_effects.dly_flutter,
    \age, ~cfg_effects.dly_age, \headBump, ~cfg_effects.dly_headBump,
    \headSpread, ~cfg_effects.dly_headSpread, \bass, ~cfg_effects.dly_bass,
    \treble, ~cfg_effects.dly_treble, \springDecay, ~cfg_effects.dly_springDecay,
    \springTone, ~cfg_effects.dly_springTone, \hiss, ~cfg_effects.dly_hiss
);
Ndef(\space_echo_rev).fadeTime = 2;
Ndef(\space_echo_dly).fadeTime = 2;

// effect returns -> ~busFxReturn (two writers summing into the return is §K.3)
Ndef(\space_echo_rev).play(out: ~busFxReturn.index, numChannels: 2);
Ndef(\space_echo_dly).play(out: ~busFxReturn.index, numChannels: 2);
)
