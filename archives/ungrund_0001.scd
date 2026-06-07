// ungrund_0001.scd
// UNGRUND etude no. 0001 — schicht / substratumwalk / 94 Hz
// See docs/reference.md (§H) and docs/task.md for the design.
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
    if(~ungR.notNil) { ~ungR.stop; ~ungR = nil };
    OSCdef(\ung_threshold).notNil.if({ OSCdef(\ung_threshold).free });
    if(~watcher.notNil) { ~watcher.free; ~watcher = nil };
    if(~mst.notNil)     { ~mst.free;     ~mst = nil };
    if(~monade.notNil)  { ~monade.free;  ~monade = nil };
    if(~firnis.notNil)  { ~firnis.free;  ~firnis = nil };
    if(~grpSrc.notNil)  { ~grpSrc.freeAll; ~grpSrc.free; ~grpSrc = nil };
    if(~grpAnl.notNil)  { ~grpAnl.freeAll; ~grpAnl.free; ~grpAnl = nil };
    if(~grpFx.notNil)   { ~grpFx.freeAll;  ~grpFx.free;  ~grpFx  = nil };
    if(~busMaster.notNil) { ~busMaster.free; ~busMaster = nil };
    if(~busMonade.notNil) { ~busMonade.free; ~busMonade = nil };
    Pdef.all.do(_.clear);
    Ndef.all.do(_.clear);
    if(verbose) { "ungrund.0001 — reset complete.".postln };
};


// =====================================================================
// 1. UI updates — all GUI mutations go through .defer.
// =====================================================================

~ungrundSetStatus = { |state|
    {
        if(~statusLabel.notNil) { ~statusLabel.string = "UNGRUND 0001 — " ++ state };
        if(~startBtn.notNil)    { ~startBtn.enabled_(state == "stopped") };
        if(~stopBtn.notNil)     { ~stopBtn.enabled_(state != "stopped") };
    }.defer;
};

~ungrundUpdateTime = { |elapsed|
    var remaining, mm, ss, rmm, rss;
    elapsed  = elapsed.clip(0, 360);
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
// 2. Setup — groups, buses, master limiter, amp_watcher, OSCdef.
//    Assumes SynthDefs are already on the server.
// =====================================================================

~ungrundSetup = {
    ~grpSrc    = Group.new(s, \addToHead);
    ~grpAnl    = Group.after(~grpSrc);
    ~grpFx     = Group.after(~grpAnl);
    ~busMaster = Bus.audio(s, 2);
    ~busMonade = Bus.audio(s, 1);
    s.sync;

    ~mst = Synth(\ung_master, [
        \in,         ~busMaster.index,
        \out,        0,
        \master_amp, 1.0
    ], ~grpFx);

    ~ungLastRiss    = -inf;
    ~ungMinInterval = 8.0;
    ~ungRissActive  = false;

    OSCdef(\ung_threshold, { |msg, time|
        var now = thisThread.seconds;
        if(~ungRissActive and: { (now - ~ungLastRiss) >= ~ungMinInterval }) {
            ~ungLastRiss = now;
            Synth(\rissz, [
                \out, ~busMaster.index,
                \amp, exprand(0.4, 0.85),
                \pan, rrand(-0.6, 0.6),
                \hpf, 100,
                \rel, rrand(0.04, 0.07)
            ], ~grpSrc);
        };
    }, '/ung/threshold');
};


// =====================================================================
// 3. Start / Stop.
// =====================================================================

~ungrundStart = {
    if(~ungR.notNil) {
        "ungrund.0001 — already playing.".postln;
    } {
        ~ungrundReset.value(false);
        ~ungrundSetStatus.value("starting…");
        s.waitForBoot({
            ~ungrundSetup.value;

            ~ungR = Routine({
                var t0 = thisThread.seconds;
                var uiTask;

                // t = 0
                ~monade = Synth(\monade, [
                    \out,     ~busMaster.index,
                    \mon_bus, ~busMonade.index,
                    \freq,    94,
                    \amp,     0.4,
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
                    \out, ~busMaster.index,
                    \amp, 1.0,
                    \atk, 8.0,
                    \rel, 8.0
                ], ~grpSrc);

                ~watcher = Synth(\amp_watcher, [
                    \mon_bus,   ~busMonade.index,
                    \threshold, 0.30,
                    \lag,       1.5,
                    \id,        100
                ], ~grpAnl);

                ~ungRissActive = true;

                // t = 4..348 — substratumwalk
                344.wait;

                // t = 348 — gate off the sustained voices
                ~ungRissActive = false;
                ~monade.set(\gate, 0);
                ~firnis.set(\gate, 0);
                ~ungrundSetStatus.value("releasing…");

                // t = 348..360 — envelope tails
                12.wait;

                // t = 360 — done
                uiTask.stop;
                ~ungrundUpdateTime.value(360);
                ~ungrundReset.value(true);
                ~ungrundSetStatus.value("stopped");
                "ungrund.0001 — done.".postln;

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
// 4. Boot + add SynthDefs (the eight UNGRUND classes + master + watcher).
// =====================================================================

s.waitForBoot({

    // 1. \monade — sustained sine, the Grund.
    SynthDef(\monade, { |out = 0, mon_bus = 16,
                        freq = 94, amp = 0.4,
                        atk = 6.0, rel = 12.0,
                        gate = 1, pan = 0|
        var env, sig, fSafe;
        env   = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
        fSafe = freq.clip(20, SampleRate.ir * 0.45);
        sig   = SinOsc.ar(fSafe) * env * amp.lag(0.05);
        Out.ar(mon_bus, sig);
        Out.ar(out, Pan2.ar(sig, pan.lag(0.05)));
    }).add;

    // 2. \rissz — broadband impulse.
    SynthDef(\rissz, { |out = 0,
                       amp = 0.6,
                       atk = 0.001, rel = 0.05,
                       hpf = 100, pan = 0|
        var env, sig, fSafe;
        env   = EnvGen.kr(Env.perc(atk, rel, curve: -4), doneAction: 2);
        fSafe = hpf.clip(20, SampleRate.ir * 0.45);
        sig   = HPF.ar(WhiteNoise.ar, fSafe) * env * amp;
        Out.ar(out, Pan2.ar(sig, pan));
    }).add;

    // 3. \flockung — granular cluster of detuned partials.
    SynthDef(\flockung, { |out = 0,
                          fund = 220, amp = 0.15,
                          atk = 0.01, rel = 0.4,
                          jitter = 0.02, pan = 0|
        var env, partials, grains, sig, fSafe;
        env      = EnvGen.kr(Env.linen(0, rel * 1.1, 0.01), doneAction: 2);
        fSafe    = fund.clip(20, SampleRate.ir * 0.1);
        partials = [5, 7, 9, 11, 13];
        grains   = partials.collect { |p, i|
            var jit      = LFNoise2.kr(2 + i).range(1 - jitter, 1 + jitter);
            var grainEnv = EnvGen.kr(Env.perc(atk + (i * 0.005), rel * (1 - (i * 0.04)), curve: -4));
            SinOsc.ar(fSafe * p * jit) * grainEnv
        };
        sig = Mix(grains) * (1 / partials.size) * amp;
        Out.ar(out, Pan2.ar(sig * env, pan));
    }).add;

    // 4. \binde — narrow-band noise.
    SynthDef(\binde, { |out = 0,
                       freq = 1100, rq = 0.02, amp = 0.25,
                       atk = 1.5, rel = 4.0,
                       gate = 1, pan = 0|
        var env, sig, fSafe, comp;
        env   = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
        fSafe = freq.clip(20, SampleRate.ir * 0.45);
        comp  = rq.reciprocal.sqrt * 0.4;
        sig   = BPF.ar(PinkNoise.ar, fSafe, rq) * comp * env * amp.lag(0.05);
        Out.ar(out, Pan2.ar(sig, pan.lag(0.05)));
    }).add;

    // 5. \schliere — comb-filtered noise with slow incommensurate drift.
    SynthDef(\schliere, { |out = 0,
                          freq_lo = 200, freq_hi = 1800,
                          amp = 0.18,
                          atk = 6.0, rel = 6.0,
                          gate = 1, pan = 0|
        var env, drift1, drift2, combFreq, delayT, sig, loSafe, hiSafe;
        env      = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
        loSafe   = freq_lo.clip(20, SampleRate.ir * 0.45);
        hiSafe   = freq_hi.clip(20, SampleRate.ir * 0.45);
        drift1   = LFNoise2.kr(0.013).range(0, 1);
        drift2   = LFNoise2.kr(0.019).range(0, 1);
        combFreq = ((drift1 * 0.6) + (drift2 * 0.4)).linexp(0, 1, loSafe, hiSafe);
        delayT   = combFreq.reciprocal.clip(0.0001, 0.01);
        sig      = CombC.ar(WhiteNoise.ar * 0.5, 0.01, delayT, 6.0) * env * amp;
        Out.ar(out, Pan2.ar(sig, pan));
    }).add;

    // 6. \kratzer — dry granulated noise burst, high band.
    SynthDef(\kratzer, { |out = 0,
                         amp = 0.2,
                         atk = 0.01, rel = 0.3,
                         hpf = 5000,
                         gate_rate = 40,
                         pan = 0|
        var env, gate_lfn, sig, fSafe;
        env      = EnvGen.kr(Env.perc(atk, rel, curve: -4), doneAction: 2);
        fSafe    = hpf.clip(1000, SampleRate.ir * 0.45);
        gate_lfn = LFNoise0.kr(gate_rate).range(0.2, 1.0);
        sig      = HPF.ar(WhiteNoise.ar, fSafe) * gate_lfn * env * amp;
        Out.ar(out, Pan2.ar(sig, pan));
    }).add;

    // 7. \firnis — ultrasonic shimmer, five fixed pitches.
    SynthDef(\firnis, { |out = 0,
                        amp = 1.0,
                        atk = 8.0, rel = 8.0,
                        gate = 1|
        var env, freqs, voices, sig;
        env    = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
        freqs  = [12640, 13110, 14790, 16030, 17880];
        voices = freqs.collect { |f, i|
            var modAmp = LFNoise2.kr(0.12 + (i * 0.011)).range(0.2, 1.0);
            SinOsc.ar(f) * 0.015 * modAmp
        };
        sig = Splay.ar(voices, 0.5);
        sig = LPF.ar(sig, 20000);
        Out.ar(out, sig * env * amp.lag(0.1));
    }).add;

    // 8. \zäsur — no SynthDef. Silence is a clock advance.

    // \ung_master — limiter at the tail of the chain.
    SynthDef(\ung_master, { |in = 16, out = 0, master_amp = 1.0|
        var sig;
        sig = In.ar(in, 2);
        sig = LeakDC.ar(sig);
        sig = Limiter.ar(sig, 0.95, 0.01);
        sig = sig * master_amp.lag(0.05);
        Out.ar(out, sig);
    }).add;

    // \amp_watcher — server-side rising-edge detector for substratumwalk.
    SynthDef(\amp_watcher, { |mon_bus = 18, threshold = 0.30, lag = 1.5, id = 100|
        var sig, rms, above, trig;
        sig   = In.ar(mon_bus, 1);
        rms   = Amplitude.kr(sig, attackTime: lag, releaseTime: lag);
        above = (rms > threshold);
        trig  = Trig1.kr(above, 0.001);
        SendReply.kr(trig, '/ung/threshold', [rms], id);
    }).add;

    s.sync;
    "ungrund.0001 — synthdefs ready.".postln;
});


// =====================================================================
// 5. Control window — Start / Stop / status / elapsed-remaining time.
// =====================================================================

(
    if(~win.notNil) { ~win.close };

    ~ungrundReset.value(false);

    ~win = Window("UNGRUND 0001", Rect(120, 120, 380, 180))
        .background_(Color.gray(0.10))
        .alwaysOnTop_(false);

    ~statusLabel = StaticText(~win, Rect(20, 16, 340, 22))
        .string_("UNGRUND 0001 — stopped")
        .stringColor_(Color.gray(0.92))
        .font_(Font("Menlo", 13, true));

    ~hintLabel = StaticText(~win, Rect(20, 40, 340, 18))
        .string_("schicht / substratumwalk / 94 Hz · 6 min")
        .stringColor_(Color.gray(0.5))
        .font_(Font("Menlo", 10));

    ~timeLabel = StaticText(~win, Rect(20, 62, 340, 22))
        .string_("0 : 00  /  -6:00")
        .stringColor_(Color.gray(0.7))
        .font_(Font("Menlo", 11));

    ~startBtn = Button(~win, Rect(20, 100, 165, 56))
        .states_([["start", Color.gray(0.95), Color.gray(0.22)]])
        .font_(Font("Menlo", 15, true))
        .action_({ ~ungrundStart.value });

    ~stopBtn = Button(~win, Rect(195, 100, 165, 56))
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
