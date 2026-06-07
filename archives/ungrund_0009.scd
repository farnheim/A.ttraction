// ungrund_0009.scd
// UNGRUND extended etude — variant 0009 ("organism")
// Major architectural revision of 0008:
//   - three control buses (pulse, tension, duck) wire the voices into a
//     single cross-modulated network rather than isolated layers.
//   - monade writes its RMS-pulse, schliere reads it (modulates formant
//     bands + event-layer amplitude) and writes its mid-formant tension,
//     firnis reads tension (gentle amp lift), schliere reads duck (a
//     persistent \ducker synth pulled low briefly by event triggers).
//   - schliere is paused-and-backgrounded: ~28% silent via an internal
//     LFNoise2 pauseGate, dry path heavily LPF'd, fx send strengthened.
//   - kratzer is now a click/granule design (Impulse + Decay2 + tone +
//     filtered noise + free env) replacing the WhiteNoise/LFNoise2 v8.
//   - OSC threshold dispatches rissz OR kratzer (70/30) and triggers
//     a brief duck on the schliere bus.
//   - Routine .waits jittered ±3 s; cumulative drift absorbed on the
//     last internal wait of each part so t=180 and t=360 land exactly.
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
//    Extended vs 0008 to also free ~duck and the three control buses.
// =====================================================================

~ungrundReset = { |verbose = true|
    // Recording is intentionally NOT stopped here.  Playback state and
    // recording state are orthogonal: pressing start/stop must not kill an
    // active recording.  Recording is toggled only by the rec button and by
    // window close (see ~win.onClose_).
    if(~ungR.notNil)     { ~ungR.stop; ~ungR = nil };
    OSCdef(\ung_threshold).notNil.if({ OSCdef(\ung_threshold).free });
    if(~watcher.notNil)  { ~watcher.free;  ~watcher = nil };
    if(~mst.notNil)      { ~mst.free;      ~mst = nil };
    if(~rev.notNil)      { ~rev.free;      ~rev = nil };
    if(~dly.notNil)      { ~dly.free;      ~dly = nil };
    if(~duck.notNil)     { ~duck.free;     ~duck = nil };
    if(~monade.notNil)   { ~monade.free;   ~monade = nil };
    if(~firnis.notNil)   { ~firnis.free;   ~firnis = nil };
    if(~binde.notNil)    { ~binde.free;    ~binde  = nil };
    if(~schliere.notNil) { ~schliere.free; ~schliere = nil };
    if(~grpSrc.notNil)   { ~grpSrc.freeAll; ~grpSrc.free; ~grpSrc = nil };
    if(~grpAnl.notNil)   { ~grpAnl.freeAll; ~grpAnl.free; ~grpAnl = nil };
    if(~grpFx.notNil)    { ~grpFx.freeAll;  ~grpFx.free;  ~grpFx  = nil };
    if(~busMaster.notNil)   { ~busMaster.free;   ~busMaster   = nil };
    if(~busMonade.notNil)   { ~busMonade.free;   ~busMonade   = nil };
    if(~busFxSend.notNil)   { ~busFxSend.free;   ~busFxSend   = nil };
    if(~busFxReturn.notNil) { ~busFxReturn.free; ~busFxReturn = nil };
    if(~busPulse.notNil)    { ~busPulse.free;    ~busPulse    = nil };
    if(~busTension.notNil)  { ~busTension.free;  ~busTension  = nil };
    if(~busDuck.notNil)     { ~busDuck.free;     ~busDuck     = nil };
    Pdef.all.do(_.clear);
    Ndef.all.do(_.clear);
    if(verbose) { "ungrund.0009 — reset complete.".postln };
};


// =====================================================================
// 1. UI updates — all GUI mutations go through .defer.
// =====================================================================

~ungrundSetStatus = { |state|
    {
        if(~statusLabel.notNil) { ~statusLabel.string = "UNGRUND 0009 — " ++ state };
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
// 2. Setup — groups, audio + control buses, persistent fx/ducker, OSCdef.
//    The amp_watcher is spawned by the Routine at the start of Part A and
//    again at the start of Part B, so the silent zäsur cannot generate any
//    rissz triggers from the still-resonant fx tails.
// =====================================================================

~ungrundSetup = {
    ~grpSrc      = Group.new(s, \addToHead);
    ~grpAnl      = Group.after(~grpSrc);
    ~grpFx       = Group.after(~grpAnl);
    ~busMaster   = Bus.audio(s, 2);
    ~busMonade   = Bus.audio(s, 1);
    ~busFxSend   = Bus.audio(s, 2);
    ~busFxReturn = Bus.audio(s, 2);
    // Cross-modulation control buses (allocated AFTER audio buses, BEFORE
    // persistent fx/ducker spawn).
    ~busPulse    = Bus.control(s, 1);   // monade RMS-pulse, 0..1
    ~busTension  = Bus.control(s, 1);   // schliere mid-formant activity, 0..1
    ~busDuck     = Bus.control(s, 1);   // ducker maintained, 0..1 (1 normal)
    s.sync;

    // Persistent effect synths.  Synth.tail so EXECUTION order matches
    // spawn order: tape_reverb -> ping_delay -> ung_master.  Their
    // tails ring through the 6 s zäsur — this is musically intended.
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

    // Ducker synth — maintains ~busDuck at \target (default 1.0) with a
    // 0.15 s lag.  Lives in ~grpAnl so it runs alongside amp_watcher.
    ~duck = Synth.tail(~grpAnl, \ducker, [
        \bus,    ~busDuck.index,
        \target, 1.0
    ]);

    ~ungLastRiss    = -inf;
    ~ungMinInterval = 12.0;                  // sparser than 0005 (8 s)
    ~ungRissActive  = false;

    OSCdef(\ung_threshold, { |msg, time|
        var now = thisThread.seconds;
        if(~ungRissActive and: { (now - ~ungLastRiss) >= ~ungMinInterval }) {
            var eventType = if(1.0.rand < 0.7, \rissz, \kratzer);
            ~ungLastRiss = now;
            if(eventType == \rissz) {
                Synth(\rissz, [
                    \out,    ~busMaster.index,
                    \fx_bus, ~busFxSend.index,
                    \amp,    exprand(0.25, 0.55),
                    \pan,    rrand(-0.6, 0.6),
                    \hpf,    200,
                    \rel,    rrand(0.30, 0.40)
                ], ~grpSrc);
            } {
                Synth(\kratzer, [
                    \out,    ~busMaster.index,
                    \fx_bus, ~busFxSend.index,
                    \amp,    rrand(0.10, 0.25),
                    \hpf,    exprand(3500, 9000),
                    \pan,    rrand(-0.6, 0.6)
                ], ~grpSrc);
            };
            // Duck schliere briefly: pull ~busDuck low then restore.
            if(~duck.notNil) {
                ~duck.set(\target, 0.3);
                AppClock.sched(0.25, { ~duck.set(\target, 1.0); nil });
            };
        };
    }, '/ung/threshold');
};


// =====================================================================
// 3. Start / Stop.
//    Single Routine, relative t.wait deltas computed from the absolute
//    schedule in the task brief.  Total = 360.0 s exactly.
//    Intermediate waits are jittered by ±3 s; cumulative drift is
//    absorbed on the last internal wait of each part (the 18.wait at
//    the end of Part A and the 18.wait near the end of Part B) so the
//    t=180 zäsur pivot and the t=360 end-of-piece land exactly.
// =====================================================================

~ungrundStart = {
    if(~ungR.notNil) {
        "ungrund.0009 — already playing.".postln;
    } {
        ~ungrundReset.value(false);
        ~ungrundSetStatus.value("starting…");
        s.waitForBoot({
            ~ungrundSetup.value;

            ~ungR = Routine({
                var t0 = thisThread.seconds;
                var uiTask;

                // ----- pre-roll randomisation --------------------------------
                // Frequency pools (kept fixed for harmonic structure):
                var bindeFreqs    = [188, 564];                          // A, B
                // Flockung pool (larger than v8's 220/277, 349/415):
                var flockungPool  = [220, 247, 277, 311, 349, 392, 415];
                var kratzerHpfs   = [4500, 5000, 5500, 6500, 7500, 8500, 9500];
                var flockA        = flockungPool.scramble.keep(2);
                var flockB        = flockungPool.scramble.keep(2);
                var kratzerOrder  = kratzerHpfs.scramble;
                // ----- Part A jittered .waits + drift correction --------------
                // Targets (post-firnis): 26, 30, 30, 30, 30 then absorb on 18.
                var aJit1 = rrand(-3.0, 3.0);
                var aJit2 = rrand(-3.0, 3.0);
                var aJit3 = rrand(-3.0, 3.0);
                var aJit4 = rrand(-3.0, 3.0);
                var aJit5 = rrand(-3.0, 3.0);
                var aDrift = aJit1 + aJit2 + aJit3 + aJit4 + aJit5;
                var aWait1 = 26 + aJit1;                                 // -> ~t=30
                var aWait2 = 30 + aJit2;                                 // -> ~t=60
                var aWait3 = 30 + aJit3;                                 // -> ~t=90
                var aWait4 = 30 + aJit4;                                 // -> ~t=120
                var aWait5 = 30 + aJit5;                                 // -> ~t=150
                var aWait6 = 18 - aDrift;                                // -> t=168 exact
                // ----- Part B jittered .waits + drift correction --------------
                // Targets (post-firnis-B): 10, 30, 10, 30, 10, 30, 20 then absorb on 18.
                var bJit1 = rrand(-3.0, 3.0);
                var bJit2 = rrand(-3.0, 3.0);
                var bJit3 = rrand(-3.0, 3.0);
                var bJit4 = rrand(-3.0, 3.0);
                var bJit5 = rrand(-3.0, 3.0);
                var bJit6 = rrand(-3.0, 3.0);
                var bJit7 = rrand(-3.0, 3.0);
                var bDrift = bJit1 + bJit2 + bJit3 + bJit4 + bJit5 + bJit6 + bJit7;
                var bWait1 = 10 + bJit1;                                 // -> ~t=200
                var bWait2 = 30 + bJit2;                                 // -> ~t=230
                var bWait3 = 10 + bJit3;                                 // -> ~t=240
                var bWait4 = 30 + bJit4;                                 // -> ~t=270
                var bWait5 = 10 + bJit5;                                 // -> ~t=280
                var bWait6 = 30 + bJit6;                                 // -> ~t=310
                var bWait7 = 20 + bJit7;                                 // -> ~t=330
                var bWait8 = 18 - bDrift;                                // -> t=348 exact

                ("ungrund.0009 — flockA = % | flockB = % | kratzer-hpfs = %"
                    .format(flockA, flockB, kratzerOrder.keep(3))).postln;

                // ----- PART A (0–180 s) -----------------------------------

                // t = 0 — monade A (94 Hz, the Grund) — writes ~busPulse
                ~monade = Synth(\monade, [
                    \out,       ~busMaster.index,
                    \mon_bus,   ~busMonade.index,
                    \fx_bus,    ~busFxSend.index,
                    \pulse_bus, ~busPulse.index,
                    \freq,      94,
                    \amp,       0.25,
                    \atk,       6.0,
                    \rel,       12.0,
                    \pan,       0
                ], ~grpSrc);

                ~ungrundSetStatus.value("playing — part A");

                // UI timer — AppClock, ticks every 0.5 s
                uiTask = Routine({
                    loop {
                        ~ungrundUpdateTime.value(thisThread.seconds - t0);
                        0.5.wait;
                    };
                }).play(AppClock);

                4.wait;                                  // -> t = 4 (fixed)

                // t = 4 — firnis + amp_watcher + arm rissz — reads ~busTension
                ~firnis = Synth(\firnis, [
                    \out,         ~busMaster.index,
                    \fx_bus,      ~busFxSend.index,
                    \tension_bus, ~busTension.index,
                    \amp,         1.0,
                    \atk,         8.0,
                    \rel,         8.0
                ], ~grpSrc);

                ~watcher = Synth(\amp_watcher, [
                    \mon_bus,   ~busMonade.index,
                    \threshold, 0.05,
                    \lag,       1.5,
                    \id,        100
                ], ~grpAnl);

                ~ungRissActive = true;

                aWait1.wait;                             // -> ~t = 30

                // t ≈ 30 — binde A (188 Hz = 94 × 2)
                ~binde = Synth(\binde, [
                    \out,    ~busMaster.index,
                    \fx_bus, ~busFxSend.index,
                    \freq,   bindeFreqs[0],
                    \rq,     0.021,
                    \amp,    0.18,
                    \atk,    1.5,
                    \rel,    4.0,
                    \pan,    0
                ], ~grpSrc);

                aWait2.wait;                             // -> ~t = 60

                // t ≈ 60 — schliere A — reads pulse/duck, writes tension
                ~schliere = Synth(\schliere, [
                    \out,         ~busMaster.index,
                    \fx_bus,      ~busFxSend.index,
                    \pulse_bus,   ~busPulse.index,
                    \duck_bus,    ~busDuck.index,
                    \tension_bus, ~busTension.index,
                    \freq_lo,     200,
                    \freq_hi,     1800,
                    \amp,         0.08,
                    \atk,         6.0,
                    \rel,         6.0,
                    \pan,         0
                ], ~grpSrc);

                aWait3.wait;                             // -> ~t = 90

                // t ≈ 90 — flockung (Part-A scrambled pool, voice 0)
                Synth(\flockung, [
                    \out,    ~busMaster.index,
                    \fx_bus, ~busFxSend.index,
                    \fund,   flockA[0],
                    \amp,    0.12,
                    \atk,    0.01,
                    \rel,    0.6,
                    \pan,    0
                ], ~grpSrc);

                aWait4.wait;                             // -> ~t = 120

                // t ≈ 120 — kratzer (scrambled HPF, slot 0)
                Synth(\kratzer, [
                    \out,    ~busMaster.index,
                    \fx_bus, ~busFxSend.index,
                    \amp,    0.15,
                    \hpf,    kratzerOrder[0],
                    \pan,    0
                ], ~grpSrc);

                aWait5.wait;                             // -> ~t = 150

                // t ≈ 150 — flockung (Part-A scrambled pool, voice 1)
                Synth(\flockung, [
                    \out,    ~busMaster.index,
                    \fx_bus, ~busFxSend.index,
                    \fund,   flockA[1],
                    \amp,    0.12,
                    \atk,    0.01,
                    \rel,    0.6,
                    \pan,    0
                ], ~grpSrc);

                aWait6.wait;                             // -> t = 168 (drift absorbed)

                // t = 168 — release the Part-A sustained voices.
                ~ungRissActive = false;
                if(~binde.notNil)   { ~binde.set(\gate, 0) };
                if(~monade.notNil)  { ~monade.set(\gate, 0) };
                if(~firnis.notNil)  { ~firnis.set(\gate, 0) };
                if(~watcher.notNil) { ~watcher.free; ~watcher = nil };
                ~ungrundSetStatus.value("releasing — part A");

                6.wait;                                  // -> t = 174 (fixed)

                // t = 174 — schliere has the longest tail; release last.
                if(~schliere.notNil) { ~schliere.set(\gate, 0) };

                // ----- ZÄSUR (180–186 s) ----------------------------------

                6.wait;                                  // -> t = 180 (fixed pivot)
                ~ungrundSetStatus.value("zäsur");
                6.wait;                                  // -> t = 186 (fixed)

                // Nil-out the spent A-part holders.
                ~monade   = nil;
                ~firnis   = nil;
                ~binde    = nil;
                ~schliere = nil;

                // ----- PART B (186–360 s) ---------------------------------

                // t = 186 — monade B (still 94 Hz) — writes ~busPulse
                ~monade = Synth(\monade, [
                    \out,       ~busMaster.index,
                    \mon_bus,   ~busMonade.index,
                    \fx_bus,    ~busFxSend.index,
                    \pulse_bus, ~busPulse.index,
                    \freq,      94,
                    \amp,       0.25,
                    \atk,       6.0,
                    \rel,       12.0,
                    \pan,       0
                ], ~grpSrc);

                ~ungrundSetStatus.value("playing — part B");

                4.wait;                                  // -> t = 190 (fixed)

                // t = 190 — firnis + fresh amp_watcher + re-arm rissz
                ~firnis = Synth(\firnis, [
                    \out,         ~busMaster.index,
                    \fx_bus,      ~busFxSend.index,
                    \tension_bus, ~busTension.index,
                    \amp,         1.0,
                    \atk,         8.0,
                    \rel,         8.0
                ], ~grpSrc);

                ~watcher = Synth(\amp_watcher, [
                    \mon_bus,   ~busMonade.index,
                    \threshold, 0.05,
                    \lag,       1.5,
                    \id,        100
                ], ~grpAnl);

                ~ungRissActive = true;

                bWait1.wait;                             // -> ~t = 200

                // t ≈ 200 — binde B (564 Hz = 94 × 6, sixth harmonic)
                ~binde = Synth(\binde, [
                    \out,    ~busMaster.index,
                    \fx_bus, ~busFxSend.index,
                    \freq,   bindeFreqs[1],
                    \rq,     0.021,
                    \amp,    0.18,
                    \atk,    1.5,
                    \rel,    4.0,
                    \pan,    0
                ], ~grpSrc);

                bWait2.wait;                             // -> ~t = 230

                // t ≈ 230 — schliere B — reads pulse/duck, writes tension
                ~schliere = Synth(\schliere, [
                    \out,         ~busMaster.index,
                    \fx_bus,      ~busFxSend.index,
                    \pulse_bus,   ~busPulse.index,
                    \duck_bus,    ~busDuck.index,
                    \tension_bus, ~busTension.index,
                    \freq_lo,     600,
                    \freq_hi,     1400,
                    \amp,         0.08,
                    \atk,         6.0,
                    \rel,         6.0,
                    \pan,         0
                ], ~grpSrc);

                bWait3.wait;                             // -> ~t = 240

                // t ≈ 240 — flockung (Part-B scrambled pool, voice 0)
                Synth(\flockung, [
                    \out,    ~busMaster.index,
                    \fx_bus, ~busFxSend.index,
                    \fund,   flockB[0],
                    \amp,    0.12,
                    \atk,    0.01,
                    \rel,    0.6,
                    \pan,    0
                ], ~grpSrc);

                bWait4.wait;                             // -> ~t = 270

                // t ≈ 270 — release binde B early.
                if(~binde.notNil) { ~binde.set(\gate, 0) };

                bWait5.wait;                             // -> ~t = 280

                // t ≈ 280 — kratzer (scrambled HPF, slot 1)
                Synth(\kratzer, [
                    \out,    ~busMaster.index,
                    \fx_bus, ~busFxSend.index,
                    \amp,    0.15,
                    \hpf,    kratzerOrder[1],
                    \pan,    0
                ], ~grpSrc);

                bWait6.wait;                             // -> ~t = 310

                // t ≈ 310 — flockung (Part-B scrambled pool, voice 1)
                Synth(\flockung, [
                    \out,    ~busMaster.index,
                    \fx_bus, ~busFxSend.index,
                    \fund,   flockB[1],
                    \amp,    0.12,
                    \atk,    0.01,
                    \rel,    0.6,
                    \pan,    0
                ], ~grpSrc);

                bWait7.wait;                             // -> ~t = 330

                // t ≈ 330 — kratzer (scrambled HPF, slot 2) + release schliere B
                Synth(\kratzer, [
                    \out,    ~busMaster.index,
                    \fx_bus, ~busFxSend.index,
                    \amp,    0.15,
                    \hpf,    kratzerOrder[2],
                    \pan,    0
                ], ~grpSrc);
                if(~schliere.notNil) { ~schliere.set(\gate, 0) };

                bWait8.wait;                             // -> t = 348 (drift absorbed)

                // t = 348 — disarm rissz, release monade + firnis,
                // free watcher and the threshold OSCdef.
                ~ungRissActive = false;
                if(~monade.notNil)  { ~monade.set(\gate, 0) };
                if(~firnis.notNil)  { ~firnis.set(\gate, 0) };
                if(~watcher.notNil) { ~watcher.free; ~watcher = nil };
                OSCdef(\ung_threshold).notNil.if({ OSCdef(\ung_threshold).free });
                ~ungrundSetStatus.value("releasing — part B");

                12.wait;                                 // -> t = 360 (fixed end)

                // t = 360 — done.
                uiTask.stop;
                ~ungrundUpdateTime.value(360);
                ~ungrundReset.value(true);
                ~ungrundSetStatus.value("stopped");
                "ungrund.0009 — done.".postln;

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
// 4. Boot + add SynthDefs (12 total) — 0009 revises monade, schliere,
//    firnis, kratzer, and adds \ducker.
//    Voice classes: monade, rissz, flockung, binde, schliere, kratzer, firnis
//    Effects:        tape_reverb, ping_delay
//    Infrastructure: ung_master, amp_watcher, ducker
//    (\zäsur is not a SynthDef — it is a clock advance, t=180..186.)
// =====================================================================

s.waitForBoot({

    // 1. \monade — 7-voice warm cluster (the Grund) — writes ~busPulse.
    SynthDef(\monade, { |out = 0, mon_bus = 16, fx_bus = 18, pulse_bus = 0,
                        freq = 94, amp = 0.25,
                        atk = 6.0, rel = 12.0,
                        gate = 1, pan = 0|
        var env, fSafe, voices, sig, detuneRates, ampRates, pulse;
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
        // Cross-mod write: RMS-pulse 0..1, scaled against amp * 0.2.
        pulse = Amplitude.kr(sig, 0.05, 0.3);
        pulse = pulse.linlin(0, amp * 0.2, 0, 1).clip(0, 1);
        Out.kr(pulse_bus, pulse);
        Out.ar(mon_bus, sig);                                     // mono pre-pan for amp_watcher
        Out.ar(out,    Pan2.ar(sig,         pan.lag(0.05)));      // dry to master
        Out.ar(fx_bus, Pan2.ar(sig * 0.55,  pan.lag(0.05)));      // K.1: monade -> reverb/delay 0.55
    }).add;

    // 2. \rissz — soft granular burst (GrainSin).  Unchanged from 0008.
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

    // 3. \flockung — 12-voice harmonic-partial cloud.  Unchanged from 0008.
    SynthDef(\flockung, { |out = 0, fx_bus = 18,
                          fund = 220, amp = 0.12,
                          atk = 0.01, rel = 0.6,
                          jitter = 0.03, pan = 0|
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

    // 4. \binde — narrow-band noise / formant cluster.  Unchanged from 0008.
    SynthDef(\binde, { |out = 0, fx_bus = 18,
                       freq = 1100, rq = 0.021, amp = 0.18,
                       atk = 1.5, rel = 4.0,
                       gate = 1, pan = 0|
        var env, noise, freqs, rqs, mods, bands, sig;
        env   = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
        noise = PinkNoise.ar;
        freqs = [freq, freq * 1.003, freq * 0.998, freq * 1.005].clip(20, SampleRate.ir * 0.45);
        rqs   = [rq, rq * 1.22, rq * 0.88, rq * 1.07];
        mods  = LFNoise2.kr([0.13, 0.19, 0.11, 0.17]).range(0.5, 1.0);
        bands = (0..3).collect { |i|
            BPF.ar(noise, freqs[i], rqs[i]) * mods[i] * (rqs[i].reciprocal.sqrt * 0.35)
        };
        sig = Mix(bands);
        sig = sig * env * amp.lag(0.05);
        Out.ar(out,    Pan2.ar(sig,        pan.lag(0.05)));
        Out.ar(fx_bus, Pan2.ar(sig * 0.45, pan.lag(0.05)));       // K.1: binde 0.45
    }).add;

    // 5. \ducker — maintains a control bus at \target (lagged 0.15 s).
    //    Added BEFORE \schliere in the batch.  Persistent in ~grpAnl.
    SynthDef(\ducker, { |bus = 0, target = 1.0|
        Out.kr(bus, Lag.kr(target, 0.15));
    }).add;

    // 6. \schliere — v9: organism rewrite.
    //    Reads pulse + duck control buses; modulates mid-formant bands and
    //    event amplitude by pulse, gates with an internal LFNoise2 pause
    //    (~28% silent), writes mid-formant activity to tension bus, and
    //    routes filtered dry + strong fx send (backgrounded character).
    //    Keeps 11-formant 750-1750 / 150 Hz BPF / HF body / two slowMods.
    SynthDef(\schliere, { |out = 0, fx_bus = 18,
                          pulse_bus = 0, duck_bus = 0, tension_bus = 0,
                          freq_lo = 200, freq_hi = 1800,
                          amp = 0.08,
                          atk = 6.0, rel = 6.0,
                          gate = 1, pan = 0|
        var env, pulse, duck, pauseGate,
            noise, lowRes, midResFreqs, midResBands, midResMix,
            hf, slowMod1, slowMod2,
            eventGate, eventEnv, eventNoise,
            tension, sig, dryFiltered;
        env = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
        // ----- cross-mod inputs --------------------------------------------
        pulse = In.kr(pulse_bus, 1).clip(0, 1);
        duck  = In.kr(duck_bus,  1).clip(0, 1);
        // ----- internal pause gate (~28% silent, smooth transitions) -------
        pauseGate = LFNoise2.kr(0.13).range(-0.4, 1.0).clip(0, 1);
        // ----- base noise: pink+white blend for mid-bright character -------
        noise = (PinkNoise.ar * 0.7) + (WhiteNoise.ar * 0.3);
        // ----- strong narrow band at 150 Hz (dominant low peak) ------------
        lowRes = BPF.ar(noise, 150, 0.15) * 5;
        // ----- multi-formant cluster — 11 BPFs, modulated by pulse ---------
        midResFreqs = [750, 850, 950, 1050, 1150, 1250, 1350, 1450, 1550, 1650, 1750];
        midResBands = midResFreqs.collect { |f, i|
            var modRate = 0.07 + (i * 0.012);
            var bandMod = LFNoise2.kr(modRate).range(0.3, 1.0) * (0.7 + (pulse * 0.6));
            BPF.ar(noise, f, 0.04) * bandMod * 4
        };
        midResMix = Mix(midResBands) * (1/11) * 3;
        // ----- HF body to match centroid ~4.9 kHz --------------------------
        hf = HPF.ar(noise, 4000);
        hf = LPF.ar(hf, 10000);
        hf = hf * 0.5;
        // ----- slow cross-modulators ---------------------------------------
        slowMod1 = LFNoise2.kr(0.07).range(0.4, 1.0);
        slowMod2 = LFNoise2.kr(0.09).range(0.4, 1.0);
        // ----- Poisson event layer, amplitude modulated by pulse -----------
        eventGate  = Dust.ar(2.0);
        eventEnv   = Decay2.ar(eventGate, 0.001, 0.025);
        eventNoise = WhiteNoise.ar * eventEnv * (0.5 + pulse);
        eventNoise = HPF.ar(eventNoise, 500);
        eventNoise = LPF.ar(eventNoise, 8000);
        eventNoise = eventNoise * 0.8;
        // ----- write tension (mid-formant activity) ------------------------
        tension = Amplitude.kr(midResMix, 0.3, 0.3);
        Out.kr(tension_bus, tension.clip(0, 1));
        // ----- sum ---------------------------------------------------------
        sig = (lowRes * slowMod1) + (midResMix * slowMod2) + hf + eventNoise;
        // ----- dual output: filtered dry (backgrounded) + heavy fx send ----
        dryFiltered = LPF.ar(sig, 3500);
        sig         = sig         * env * amp * pauseGate * duck;
        dryFiltered = dryFiltered * env * amp * pauseGate * duck;
        Out.ar(out,    Pan2.ar(dryFiltered,  pan));               // backgrounded dry
        Out.ar(fx_bus, Pan2.ar(sig * 0.65,   pan));               // strong fx send
    }).add;

    // 7. \kratzer — v9 click/granule design.  Replaces the v8 WhiteNoise +
    //    LFNoise2 perc texture entirely.  Single Impulse at start, decay
    //    envelope, sine tone at hpf * 1.4 (with per-instance freq jitter)
    //    plus filtered BrownNoise, free env to release.
    SynthDef(\kratzer, { |out = 0, fx_bus = 18,
                         amp = 0.15, hpf = 5000, pan = 0|
        var trig, clickEnv, freqJitter, tone, noise, sig, freeEnv;
        trig       = Impulse.ar(0);                       // single shot at start
        clickEnv   = Decay2.ar(trig, 0.0008, 0.012);
        freqJitter = Rand(0.85, 1.15);                    // per-instance random
        tone       = SinOsc.ar(hpf * freqJitter * 1.4) * clickEnv;
        noise      = HPF.ar(BrownNoise.ar, hpf) * clickEnv * 0.4;
        sig        = (tone * 0.7) + noise;
        freeEnv    = EnvGen.kr(Env([1, 1, 0], [0.05, 0.001]), doneAction: 2);
        sig        = sig * freeEnv;
        Out.ar(out,    Pan2.ar(sig * amp,        pan));
        Out.ar(fx_bus, Pan2.ar(sig * amp * 0.30, pan));
    }).add;

    // 8. \firnis — 9-voice ultrasonic shimmer — reads ~busTension.
    SynthDef(\firnis, { |out = 0, fx_bus = 18, tension_bus = 0,
                        amp = 1.0,
                        atk = 8.0, rel = 8.0,
                        gate = 1|
        var env, freqs, amRates, voices, sig, tension, tensionBoost;
        env     = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
        freqs   = [12640, 13110, 14790, 16030, 17880, 12900, 13500, 15200, 16800];
        amRates = [0.052, 0.073, 0.061, 0.089, 0.043, 0.067, 0.055, 0.081, 0.048];
        voices  = freqs.collect { |f, i|
            var perVoiceAM = LFNoise2.kr(amRates[i]).range(0.15, 1.0);
            var crossAM    = (1 + LFNoise2.kr(0.021 + (i * 0.003)).range(-0.025, 0.025));
            SinOsc.ar(f) * 0.010 * perVoiceAM * crossAM
        };
        sig = Splay.ar(voices, 0.55);
        sig = LPF.ar(sig, 20000);
        // Cross-mod read: tension 0..0.3 -> boost 1.0..1.4
        tension      = In.kr(tension_bus, 1).clip(0, 1);
        tensionBoost = tension.linlin(0, 0.3, 1.0, 1.4);
        sig = sig * env * amp.lag(0.1) * tensionBoost;
        Out.ar(out,    sig);
        Out.ar(fx_bus, sig * 0.60);                                // K.1: firnis 0.60
    }).add;

    // 9. \tape_reverb — pre-delay + 8 AllpassC (4L / 4R) + 2 CombC + LPF rolloff.
    SynthDef(\tape_reverb, { |in = 18, out = 20, wet = 0.85|
        var sig, ratesL, ratesR, diffL, diffR, combL, combR, rolloff, procL, procR;
        sig    = In.ar(in, 2);
        sig    = DelayC.ar(sig, 0.05, 0.012);
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

    // 10. \ping_delay — LocalIn/LocalOut ping-pong, LPF 2 kHz in feedback.
    SynthDef(\ping_delay, { |in = 18, out = 20, wet = 0.5, feedback = 0.52|
        var stereoIn, mono, delayL, delayR, fb, echoL, echoR, outL, outR;
        stereoIn = In.ar(in, 2);
        mono     = Mix(stereoIn) * 0.5;
        delayL   = 0.37 + LFNoise2.kr(0.11).range(-0.004, 0.004);
        delayR   = 0.53 + LFNoise2.kr(0.09).range(-0.004, 0.004);
        fb       = LocalIn.ar(2);
        echoL    = mono + (LPF.ar(fb[1], 2000) * feedback);
        echoR    = mono + (LPF.ar(fb[0], 2000) * feedback);
        outL     = DelayC.ar(echoL, 0.6, delayL);
        outR     = DelayC.ar(echoR, 0.6, delayR);
        LocalOut.ar([outL, outR]);
        Out.ar(out, [outL, outR] * wet);
    }).add;

    // 11. \ung_master — sums dry + fx return, LeakDC, Limiter.
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

    // 12. \amp_watcher.
    SynthDef(\amp_watcher, { |mon_bus = 18, threshold = 0.30, lag = 1.5, id = 100|
        var sig, rms, above, trig;
        sig   = In.ar(mon_bus, 1);
        rms   = Amplitude.kr(sig, attackTime: lag, releaseTime: lag);
        above = (rms > threshold);
        trig  = Trig1.kr(above, 0.001);
        SendReply.kr(trig, '/ung/threshold', [rms], id);
    }).add;

    s.sync;
    "ungrund.0009 — synthdefs ready.".postln;
});


// =====================================================================
// 5. Control window — Start / Stop / status / elapsed-remaining time.
// =====================================================================

(
    if(~win.notNil) { ~win.close };

    // Recording config — applies server-wide; safe to set repeatedly.
    s.recHeaderFormat = "wav";
    s.recSampleFormat = "int16";
    ~recording = false;
    ~recDir    = thisProcess.platform.recordingsDir;

    ~ungrundReset.value(false);

    ~win = Window("ungrund.0009 — organism / cross-mod / variant",
                  Rect(120, 120, 460, 230))
        .background_(Color.gray(0.10))
        .alwaysOnTop_(false);

    ~statusLabel = StaticText(~win, Rect(20, 16, 420, 22))
        .string_("UNGRUND 0009 — stopped")
        .stringColor_(Color.gray(0.92))
        .font_(Font("Menlo", 13, true));

    ~hintLabel = StaticText(~win, Rect(20, 40, 420, 18))
        .string_("buses: pulse · tension · duck · 70% rissz / 30% kratzer · randomised timings")
        .stringColor_(Color.gray(0.5))
        .font_(Font("Menlo", 10));

    ~timeLabel = StaticText(~win, Rect(20, 62, 420, 22))
        .string_("0 : 00  /  -6:00")
        .stringColor_(Color.gray(0.7))
        .font_(Font("Menlo", 11));

    ~recLabel = StaticText(~win, Rect(20, 88, 420, 18))
        .string_("rec idle — files save to " ++ ~recDir)
        .stringColor_(Color.gray(0.45))
        .font_(Font("Menlo", 10));

    ~startBtn = Button(~win, Rect(20, 112, 205, 50))
        .states_([["start", Color.gray(0.95), Color.gray(0.22)]])
        .font_(Font("Menlo", 15, true))
        .action_({ ~ungrundStart.value });

    ~stopBtn = Button(~win, Rect(235, 112, 205, 50))
        .states_([["stop / reset", Color.gray(0.95), Color.gray(0.22)]])
        .font_(Font("Menlo", 15, true))
        .enabled_(false)
        .action_({ ~ungrundStop.value });

    ~recBtn = Button(~win, Rect(20, 174, 420, 38))
        .states_([
            ["● record",          Color.gray(0.95), Color.gray(0.22)],
            ["■ stop recording",  Color.gray(0.95), Color(0.55, 0.13, 0.13)]
        ])
        .font_(Font("Menlo", 13, true))
        .action_({ |btn|
            if(btn.value == 1) {
                // s.waitForBoot is idempotent: runs immediately if booted,
                // boots the server first if not.  Robust against the case
                // where s.serverRunning hasn't been confirmed via status yet.
                ~recLabel.string_("preparing…");
                ~recLabel.stringColor_(Color.gray(0.6));
                s.waitForBoot({
                    ~recPath = ~recDir +/+ ("ungrund_0009_" ++ Date.getDate.stamp ++ ".wav");
                    s.record(~recPath);
                    ~recording = true;
                    {
                        ~recLabel.string_("REC → " ++ ~recPath.basename);
                        ~recLabel.stringColor_(Color(0.85, 0.30, 0.30));
                    }.defer;
                });
            } {
                if(~recording == true) {
                    s.stopRecording;
                    ~recording = false;
                    ~recLabel.string_("saved → " ++ ~recPath.basename);
                    ~recLabel.stringColor_(Color.gray(0.45));
                };
            };
        });

    ~win.onClose_({ ~ungrundReset.value(false) });
    ~win.front;
);


// =====================================================================
// 6. Cleanup paragraph — evaluate this alone for a hard reset.
// =====================================================================

(
    Routine.run({ s.bind { ~ungrundReset.value(true) } });
)
