// ungrund_0005.scd
// UNGRUND etude no. 0001 — v2 (warm/enveloping timbral revision)
// schicht / substratumwalk / 94 Hz
//
// Spec: docs/task_v2.md (authoritative)
// Reference: docs/reference_v2.md (Sections A.Amendment, C, H, K)
// Structural baseline: ungrund_0001.scd (plumbing only; v2 SynthDefs are wholly new)
//
// Evaluate the whole file (Cmd-A, Shift-Return).
//   - The server boots, SynthDefs are added, a small control window opens.
//   - Click "start" to begin the 360 s piece.
//   - Click "stop / reset" at any time for a clean teardown.
//   - The Routine auto-resets at t = 360 s.
//   - Cmd-. is safe.
//   - The cleanup paragraph at the bottom is idempotent (run for a hard reset).


// =====================================================================
// 0. Reset (idempotent teardown) — frees the piece, leaves SynthDefs.
// =====================================================================

~ungrundReset = { |verbose = true|
    if(~ungR.notNil)     { ~ungR.stop; ~ungR = nil };
    OSCdef(\ung_threshold).notNil.if({ OSCdef(\ung_threshold).free });
    if(~watcher.notNil)  { ~watcher.free;  ~watcher = nil };
    if(~mst.notNil)      { ~mst.free;      ~mst = nil };
    if(~rev.notNil)      { ~rev.free;      ~rev = nil };
    if(~dly.notNil)      { ~dly.free;      ~dly = nil };
    if(~monade.notNil)   { ~monade.free;   ~monade = nil };
    if(~firnis.notNil)   { ~firnis.free;   ~firnis = nil };
    if(~grpSrc.notNil)   { ~grpSrc.freeAll; ~grpSrc.free; ~grpSrc = nil };
    if(~grpAnl.notNil)   { ~grpAnl.freeAll; ~grpAnl.free; ~grpAnl = nil };
    if(~grpFx.notNil)    { ~grpFx.freeAll;  ~grpFx.free;  ~grpFx  = nil };
    if(~busMaster.notNil)   { ~busMaster.free;   ~busMaster   = nil };
    if(~busMonade.notNil)   { ~busMonade.free;   ~busMonade   = nil };
    if(~busFxSend.notNil)   { ~busFxSend.free;   ~busFxSend   = nil };
    if(~busFxReturn.notNil) { ~busFxReturn.free; ~busFxReturn = nil };
    Pdef.all.do(_.clear);
    Ndef.all.do(_.clear);
    if(verbose) { "ungrund.0001 v2 — reset complete.".postln };
};


// =====================================================================
// 1. UI updates — all GUI mutations go through .defer.
// =====================================================================

~ungrundSetStatus = { |state|
    {
        if(~statusLabel.notNil) { ~statusLabel.string = "UNGRUND 0001 v2 — " ++ state };
        if(~startBtn.notNil)    { ~startBtn.enabled_(state == "stopped") };
        if(~stopBtn.notNil)     { ~stopBtn.enabled_(state != "stopped") };
    }.defer;
};

~ungrundUpdateTime = { |elapsed|
    var remaining, mm, ss, rmm, rss;
    elapsed   = elapsed.clip(0, 360);
    remaining = (360 - elapsed).max(0);
    mm  = (elapsed/60).floor.asInteger;
    ss  = (elapsed % 60).floor.asInteger.asString.padLeft(2, "0");
    rmm = (remaining/60).floor.asInteger;
    rss = (remaining % 60).floor.asInteger.asString.padLeft(2, "0");
    {
        if(~timeLabel.notNil) {
            ~timeLabel.string = "% : %  /  -%:%".format(mm, ss, rmm, rss);
        };
    }.defer;
};


// =====================================================================
// 2. Setup — groups, buses, persistent fx synths, amp_watcher, OSCdef.
//    Assumes SynthDefs are already on the server.
// =====================================================================

~ungrundSetup = {
    ~grpSrc      = Group.new(s, \addToHead);
    ~grpAnl      = Group.after(~grpSrc);
    ~grpFx       = Group.after(~grpAnl);
    ~busMaster   = Bus.audio(s, 2);
    ~busMonade   = Bus.audio(s, 1);
    ~busFxSend   = Bus.audio(s, 2);
    ~busFxReturn = Bus.audio(s, 2);
    s.sync;

    // Persistent effect synths.  Use Synth.tail so EXECUTION order matches
    // spawn order: tape_reverb -> ping_delay -> ung_master.  With default
    // \addToHead, the order would be reversed and ung_master would read a
    // zero ~busFxReturn on every block (audio buses are zeroed per-block).
    ~rev = Synth.tail(~grpFx, \tape_reverb, [
        \in,  ~busFxSend.index,
        \out, ~busFxReturn.index,
        \wet, 0.85
    ]);

    ~dly = Synth.tail(~grpFx, \ping_delay, [
        \in,       ~busFxSend.index,
        \out,      ~busFxReturn.index,
        \wet,      0.5,
        \feedback, 0.52
    ]);

    ~mst = Synth.tail(~grpFx, \ung_master, [
        \in_dry,     ~busMaster.index,
        \in_fx,      ~busFxReturn.index,
        \out,        0,
        \master_amp, 1.0
    ]);

    ~ungLastRiss    = -inf;
    ~ungMinInterval = 8.0;
    ~ungRissActive  = false;

    OSCdef(\ung_threshold, { |msg, time|
        var now = thisThread.seconds;
        if(~ungRissActive and: { (now - ~ungLastRiss) >= ~ungMinInterval }) {
            ~ungLastRiss = now;
            Synth(\rissz, [
                \out,    ~busMaster.index,
                \fx_bus, ~busFxSend.index,
                \amp,    exprand(0.25, 0.55),       // K.4 revision
                \pan,    rrand(-0.6, 0.6),
                \hpf,    200,                        // K.1 / C.2
                \rel,    rrand(0.30, 0.40)
            ], ~grpSrc);
        };
    }, '/ung/threshold');
};


// =====================================================================
// 3. Start / Stop.
// =====================================================================

~ungrundStart = {
    if(~ungR.notNil) {
        "ungrund.0001 v2 — already playing.".postln;
    } {
        ~ungrundReset.value(false);
        ~ungrundSetStatus.value("starting…");
        s.waitForBoot({
            ~ungrundSetup.value;

            ~ungR = Routine({
                var t0 = thisThread.seconds;
                var uiTask;

                // t = 0 — monade (K.4: amp 0.25, was 0.4)
                ~monade = Synth(\monade, [
                    \out,     ~busMaster.index,
                    \mon_bus, ~busMonade.index,
                    \fx_bus,  ~busFxSend.index,
                    \freq,    94,
                    \amp,     0.25,
                    \atk,     6.0,
                    \rel,     12.0,
                    \pan,     0
                ], ~grpSrc);

                ~ungrundSetStatus.value("playing");

                // UI timer — separate task on AppClock, ticks every 0.5 s
                uiTask = Routine({
                    loop {
                        ~ungrundUpdateTime.value(thisThread.seconds - t0);
                        0.5.wait;
                    };
                }).play(AppClock);

                4.wait;

                // t = 4 — firnis + watcher
                ~firnis = Synth(\firnis, [
                    \out,    ~busMaster.index,
                    \fx_bus, ~busFxSend.index,
                    \amp,    1.0,
                    \atk,    8.0,
                    \rel,    8.0
                ], ~grpSrc);

                // Threshold recalibrated for v2 monade cluster: the
                // Mix(7voices) * (1/7) * amp(0.25) chain peaks ≈ 0.06 at
                // steady state, breathing in ~[0.04, 0.08] via per-voice
                // AM.  0.30 (v1 single-sine value) was unreachable.
                ~watcher = Synth(\amp_watcher, [
                    \mon_bus,   ~busMonade.index,
                    \threshold, 0.05,
                    \lag,       1.5,
                    \id,        100
                ], ~grpAnl);

                ~ungRissActive = true;

                // t = 4..348 — substratumwalk
                344.wait;

                // t = 348 — gate off the sustained voices
                ~ungRissActive = false;
                if(~monade.notNil) { ~monade.set(\gate, 0) };
                if(~firnis.notNil) { ~firnis.set(\gate, 0) };
                ~ungrundSetStatus.value("releasing…");

                // t = 348..360 — envelope tails
                12.wait;

                // t = 360 — done
                uiTask.stop;
                ~ungrundUpdateTime.value(360);
                ~ungrundReset.value(true);
                ~ungrundSetStatus.value("stopped");
                "ungrund.0001 v2 — done.".postln;

            }).play;
        });
    };
};

~ungrundStop = {
    ~ungrundReset.value(true);
    ~ungrundUpdateTime.value(0);
    ~ungrundSetStatus.value("stopped");
};


// =====================================================================
// 4. Boot + add SynthDefs (11 total).
//    Voice classes: monade, rissz, flockung, binde, schliere, kratzer, firnis
//    Effects:        tape_reverb, ping_delay
//    Infrastructure: ung_master, amp_watcher
//    (\zäsur is not a SynthDef — it is a clock advance.)
// =====================================================================

s.waitForBoot({

    // 1. \monade — 7-voice warm cluster (the Grund).
    SynthDef(\monade, { |out = 0, mon_bus = 16, fx_bus = 18,
                        freq = 94, amp = 0.25,
                        atk = 6.0, rel = 12.0,
                        gate = 1, pan = 0|
        var env, fSafe, voices, sig, detuneRates, ampRates;
        env         = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
        fSafe       = freq.clip(20, SampleRate.ir * 0.45);
        detuneRates = [0.011, 0.015, 0.019, 0.013, 0.022, 0.017, 0.009];
        ampRates    = [0.023, 0.031, 0.041, 0.027, 0.035, 0.029, 0.019];
        voices = Array.fill(7, { |i|
            var detune   = LFNoise2.kr(detuneRates[i]).range(-0.005, 0.005);
            var voiceAmp = LFNoise2.kr(ampRates[i]).range(0.3, 1.0);
            var crossAM  = (1 + LFNoise2.kr(0.017 + (i * 0.003)).range(-0.04, 0.04));
            SinOsc.ar(fSafe * (1 + detune)) * voiceAmp * crossAM
        });
        sig = Mix(voices) * (1/7);
        sig = LPF.ar(sig, 900);
        sig = sig * env * amp.lag(0.05);
        Out.ar(mon_bus, sig);                                     // mono pre-pan for amp_watcher
        Out.ar(out,    Pan2.ar(sig,         pan.lag(0.05)));      // dry to master
        Out.ar(fx_bus, Pan2.ar(sig * 0.55,  pan.lag(0.05)));      // K.1: monade -> reverb/delay 0.55
    }).add;

    // 2. \rissz — soft granular burst (GrainSin).
    SynthDef(\rissz, { |out = 0, fx_bus = 18,
                       amp = 0.45,
                       atk = 0.01, rel = 0.35,
                       hpf = 200, pan = 0|
        var env, fSafe, density, trigger, dur, freqGrain, panGrain, sig;
        env       = EnvGen.kr(Env.perc(atk, rel, curve: -4), doneAction: 2);
        fSafe     = hpf.clip(20, SampleRate.ir * 0.45);
        density   = LFNoise2.kr(4).range(60, 100);
        trigger   = Impulse.ar(density);
        dur       = LFNoise1.kr(3).range(0.015, 0.04);
        freqGrain = fSafe * LFNoise0.kr(12).range(0.8, 2.5);
        panGrain  = LFNoise1.kr(5).range(-0.5, 0.5);
        sig       = GrainSin.ar(1, trigger, dur, freqGrain, panGrain, -1);
        sig       = HPF.ar(sig, fSafe);
        Out.ar(out,    Pan2.ar(sig * env * amp,        pan));
        Out.ar(fx_bus, Pan2.ar(sig * env * amp * 0.30, pan));     // K.1: rissz 0.30
    }).add;

    // 3. \flockung — 12-voice harmonic-partial cloud.
    SynthDef(\flockung, { |out = 0, fx_bus = 18,
                          fund = 220, amp = 0.12,
                          atk = 0.01, rel = 0.6,
                          jitter = 0.03, pan = 0|
        // onsetOffsets: per-instance constants, rrand fires once per Synth(\flockung) call.
        var onsetOffsets = Array.fill(12, { rrand(0.0, 0.015) });
        var partials     = [5, 7, 9, 11, 13];
        var fSafe        = fund.clip(20, SampleRate.ir * 0.1);
        var outerEnv, voices, sig;
        outerEnv = EnvGen.kr(Env.linen(0.01, rel * 1.2, 0.02), doneAction: 2);
        voices = Array.fill(12, { |i|
            var partial   = partials[i % 5];
            var jit       = LFNoise2.kr(1.5 + (i * 0.1)).range(1 - jitter, 1 + jitter);
            var voiceFreq = fSafe * partial * jit;
            var grainEnv  = EnvGen.kr(Env.perc(atk + (i * 0.007) + onsetOffsets[i],
                                               rel * (0.7 + (i * 0.02)),
                                               curve: -4));
            var voiceAmp  = LFNoise2.kr(0.8 + (i * 0.06)).range(0.3, 1.0);
            SinOsc.ar(voiceFreq) * grainEnv * voiceAmp
        });
        sig = Mix(voices) * (1/12);
        sig = sig * outerEnv * amp;
        Out.ar(out,    Pan2.ar(sig,        pan));
        Out.ar(fx_bus, Pan2.ar(sig * 0.35, pan));                 // K.1: flockung 0.35
    }).add;

    // 4. \binde — narrow-band noise / formant cluster (4 parallel BPF on shared PinkNoise).
    SynthDef(\binde, { |out = 0, fx_bus = 18,
                       freq = 1100, rq = 0.021, amp = 0.18,
                       atk = 1.5, rel = 4.0,
                       gate = 1, pan = 0|
        var env, noise, freqs, rqs, mods, bands, sig;
        env   = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
        noise = PinkNoise.ar;
        freqs = [freq, freq * 1.003, freq * 0.998, freq * 1.005].clip(20, SampleRate.ir * 0.45);
        rqs   = [rq, rq * 1.22, rq * 0.88, rq * 1.07];
        // Multichannel expansion: result is an Array of 4 LFNoise2 instances.
        mods  = LFNoise2.kr([0.13, 0.19, 0.11, 0.17]).range(0.5, 1.0);
        bands = (0..3).collect { |i|
            BPF.ar(noise, freqs[i], rqs[i]) * mods[i] * (rqs[i].reciprocal.sqrt * 0.35)
        };
        sig = Mix(bands);
        sig = sig * env * amp.lag(0.05);
        Out.ar(out,    Pan2.ar(sig,        pan.lag(0.05)));
        Out.ar(fx_bus, Pan2.ar(sig * 0.45, pan.lag(0.05)));       // K.1: binde 0.45
    }).add;

    // 5. \schliere — 6 AllpassC diffusion + drifting CombC + chorus shimmer.
    SynthDef(\schliere, { |out = 0, fx_bus = 18,
                          freq_lo = 200, freq_hi = 1800,
                          amp = 0.14,
                          atk = 6.0, rel = 6.0,
                          gate = 1, pan = 0|
        var env, noise, diffRates, sig, loSafe, hiSafe,
            drift1, drift2, combFreq, delayT, shimmer;
        env       = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
        noise     = WhiteNoise.ar * 0.5;
        diffRates = [0.17, 0.23, 0.31, 0.19, 0.27, 0.21];        // ≤ 0.5 Hz
        sig       = noise;
        diffRates.do { |rate|
            var dt = LFNoise2.kr(rate).range(0.008, 0.06);
            sig = AllpassC.ar(sig, 0.08, dt, 0.6);
        };
        loSafe   = freq_lo.clip(20, SampleRate.ir * 0.45);
        hiSafe   = freq_hi.clip(20, SampleRate.ir * 0.45);
        drift1   = LFNoise2.kr(0.013).range(0, 1);
        drift2   = LFNoise2.kr(0.019).range(0, 1);
        combFreq = ((drift1 * 0.6) + (drift2 * 0.4)).linexp(0, 1, loSafe, hiSafe);
        delayT   = combFreq.reciprocal.clip(0.0001, 0.01);
        sig      = CombC.ar(sig, 0.01, delayT, 6.0);
        shimmer  = DelayC.ar(sig, 0.005, LFNoise2.kr(0.33).range(0.001, 0.004));
        sig      = sig + (shimmer * 0.3);
        Out.ar(out,    Pan2.ar(sig * env * amp,        pan));
        Out.ar(fx_bus, Pan2.ar(sig * env * amp * 0.15, pan));     // K.1: schliere 0.15
    }).add;

    // 6. \kratzer — soft high-band texture (WhiteNoise with smooth amplitude gating).
    //    Note: GrainNoise is NOT a stock SC UGen (only GrainSin/FM/Buf/In are).
    //    Per task_v2.md §C.6 fallback: smooth LFNoise2-gated WhiteNoise, never LFNoise0.
    SynthDef(\kratzer, { |out = 0, fx_bus = 18,
                         amp = 0.15,
                         atk = 0.015, rel = 0.25,
                         hpf = 5000, pan = 0|
        var env, fSafe, sig;
        env   = EnvGen.kr(Env.perc(atk, rel, curve: -4), doneAction: 2);
        fSafe = hpf.clip(1000, SampleRate.ir * 0.45);
        sig   = WhiteNoise.ar * LFNoise2.kr(8).range(0.2, 1.0);    // smooth-noise gating
        sig   = HPF.ar(sig, fSafe);
        Out.ar(out,    Pan2.ar(sig * env * amp,        pan));
        Out.ar(fx_bus, Pan2.ar(sig * env * amp * 0.15, pan));      // K.1: kratzer 0.15
    }).add;

    // 7. \firnis — 9-voice ultrasonic shimmer, cross-AM, Splay 0.55, LPF 20 kHz.
    SynthDef(\firnis, { |out = 0, fx_bus = 18,
                        amp = 1.0,
                        atk = 8.0, rel = 8.0,
                        gate = 1|
        var env, freqs, amRates, voices, sig;
        env     = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
        freqs   = [12640, 13110, 14790, 16030, 17880, 12900, 13500, 15200, 16800];
        amRates = [0.052, 0.073, 0.061, 0.089, 0.043, 0.067, 0.055, 0.081, 0.048];
        voices  = freqs.collect { |f, i|
            var perVoiceAM = LFNoise2.kr(amRates[i]).range(0.15, 1.0);
            var crossAM    = (1 + LFNoise2.kr(0.021 + (i * 0.003)).range(-0.025, 0.025));
            SinOsc.ar(f) * 0.010 * perVoiceAM * crossAM
        };
        sig = Splay.ar(voices, 0.55);
        sig = LPF.ar(sig, 20000);                                  // aliasing guard
        // firnis writes stereo (Splay) — no Pan2.
        Out.ar(out,    sig * env * amp.lag(0.1));
        Out.ar(fx_bus, sig * env * amp.lag(0.1) * 0.60);           // K.1: firnis 0.60
    }).add;

    // 8. \tape_reverb — pre-delay + 8 AllpassC (4L / 4R) + 2 CombC + LPF rolloff.
    SynthDef(\tape_reverb, { |in = 18, out = 20, wet = 0.85|
        var sig, ratesL, ratesR, diffL, diffR, combL, combR, rolloff, procL, procR;
        sig    = In.ar(in, 2);
        sig    = DelayC.ar(sig, 0.05, 0.012);                      // 12 ms tape pre-delay
        ratesL = [0.17, 0.24, 0.19, 0.31];
        ratesR = [0.21, 0.16, 0.28, 0.23];
        diffL  = sig[0];
        diffR  = sig[1];
        ratesL.do { |r| diffL = AllpassC.ar(diffL, 0.08, LFNoise2.kr(r).range(0.010, 0.070), 1.2) };
        ratesR.do { |r| diffR = AllpassC.ar(diffR, 0.08, LFNoise2.kr(r).range(0.010, 0.070), 1.2) };
        combL   = CombC.ar(diffL, 0.5, 0.087 + LFNoise2.kr(0.21).range(-0.002, 0.002), 2.5);
        combR   = CombC.ar(diffR, 0.5, 0.113 + LFNoise2.kr(0.17).range(-0.002, 0.002), 2.8);
        rolloff = 3500 + LFNoise2.kr(0.09).range(-300, 300);
        procL   = LPF.ar(combL, rolloff);
        procR   = LPF.ar(combR, rolloff);
        Out.ar(out, [procL, procR] * wet);
    }).add;

    // 9. \ping_delay — LocalIn/LocalOut ping-pong, LPF 2 kHz in feedback.
    SynthDef(\ping_delay, { |in = 18, out = 20, wet = 0.5, feedback = 0.52|
        var stereoIn, mono, delayL, delayR, fb, echoL, echoR, outL, outR;
        stereoIn = In.ar(in, 2);
        mono     = Mix(stereoIn) * 0.5;
        delayL   = 0.37 + LFNoise2.kr(0.11).range(-0.004, 0.004);
        delayR   = 0.53 + LFNoise2.kr(0.09).range(-0.004, 0.004);
        fb       = LocalIn.ar(2);                                  // [fbL, fbR]
        echoL    = mono + (LPF.ar(fb[1], 2000) * feedback);        // R -> L
        echoR    = mono + (LPF.ar(fb[0], 2000) * feedback);        // L -> R
        outL     = DelayC.ar(echoL, 0.6, delayL);
        outR     = DelayC.ar(echoR, 0.6, delayR);
        LocalOut.ar([outL, outR]);
        Out.ar(out, [outL, outR] * wet);
    }).add;

    // 10. \ung_master — sums dry + fx return, LeakDC, Limiter.
    //     Breaking change vs v1: now takes in_dry AND in_fx (was single \in).
    SynthDef(\ung_master, { |in_dry = 16, in_fx = 20, out = 0, master_amp = 1.0|
        var dry, fx, sig;
        dry = In.ar(in_dry, 2);
        fx  = In.ar(in_fx,  2);
        sig = dry + fx;
        sig = LeakDC.ar(sig);
        sig = Limiter.ar(sig, 0.95, 0.01);
        sig = sig * master_amp.lag(0.05);
        Out.ar(out, sig);
    }).add;

    // 11. \amp_watcher — unchanged from v1 baseline.
    SynthDef(\amp_watcher, { |mon_bus = 18, threshold = 0.30, lag = 1.5, id = 100|
        var sig, rms, above, trig;
        sig   = In.ar(mon_bus, 1);
        rms   = Amplitude.kr(sig, attackTime: lag, releaseTime: lag);
        above = (rms > threshold);
        trig  = Trig1.kr(above, 0.001);
        SendReply.kr(trig, '/ung/threshold', [rms], id);
    }).add;

    s.sync;
    "ungrund.0001 v2 — synthdefs ready.".postln;
});


// =====================================================================
// 5. Control window — Start / Stop / status / elapsed-remaining time.
// =====================================================================

(
    if(~win.notNil) { ~win.close };

    ~ungrundReset.value(false);

    ~win = Window("ungrund.0001 — v2 / schicht / substratumwalk / 94 Hz",
                  Rect(120, 120, 460, 180))
        .background_(Color.gray(0.10))
        .alwaysOnTop_(false);

    ~statusLabel = StaticText(~win, Rect(20, 16, 420, 22))
        .string_("UNGRUND 0001 v2 — stopped")
        .stringColor_(Color.gray(0.92))
        .font_(Font("Menlo", 13, true));

    ~hintLabel = StaticText(~win, Rect(20, 40, 420, 18))
        .string_("v2 — warm cluster · tape reverb · ping-pong delay · 6 min")
        .stringColor_(Color.gray(0.5))
        .font_(Font("Menlo", 10));

    ~timeLabel = StaticText(~win, Rect(20, 62, 420, 22))
        .string_("0 : 00  /  -6:00")
        .stringColor_(Color.gray(0.7))
        .font_(Font("Menlo", 11));

    ~startBtn = Button(~win, Rect(20, 100, 205, 56))
        .states_([["start", Color.gray(0.95), Color.gray(0.22)]])
        .font_(Font("Menlo", 15, true))
        .action_({ ~ungrundStart.value });

    ~stopBtn = Button(~win, Rect(235, 100, 205, 56))
        .states_([["stop / reset", Color.gray(0.95), Color.gray(0.22)]])
        .font_(Font("Menlo", 15, true))
        .enabled_(false)
        .action_({ ~ungrundStop.value });

    ~win.onClose_({ ~ungrundReset.value(false) });
    ~win.front;
)


// =====================================================================
// 6. Cleanup paragraph — evaluate this alone for a hard reset.
// =====================================================================

(
    Routine.run({ s.bind { ~ungrundReset.value(true) } });
)
