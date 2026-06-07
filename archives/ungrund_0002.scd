// ungrund_0002.scd
// UNGRUND etude no. 0002 — kontakt / kontaktmenge / 94 Hz cluster
//
// Iteration 2 — addresses 0001's bug (Trig1 on sustained ground never re-fires)
// and conceptual thinness (3 of 8 classes used).
//
// Two sections (A: tight cluster · zäsur · B: open cluster + binde scans),
// six-voice just-intoned cluster around 94 Hz with detuning beats, slow
// LFN amplitude breathing per voice, continuous schliere drift, periodic
// flockung / kratzer events, firnis ceiling.  ~9 min.
//
// Evaluate the whole file. Click "start" in the window that opens.


// =====================================================================
// 0. Reset (idempotent teardown)
// =====================================================================

~ung2Reset = { |verbose = true|
    if(~ung2R.notNil)         { ~ung2R.stop;         ~ung2R = nil };
    if(~ung2UiTask.notNil)    { ~ung2UiTask.stop;    ~ung2UiTask = nil };
    if(~ung2EventLoop.notNil) { ~ung2EventLoop.stop; ~ung2EventLoop = nil };
    if(~ung2GrpSrc.notNil)    { ~ung2GrpSrc.freeAll; ~ung2GrpSrc.free; ~ung2GrpSrc = nil };
    if(~ung2GrpFx.notNil)     { ~ung2GrpFx.freeAll;  ~ung2GrpFx.free;  ~ung2GrpFx  = nil };
    if(~ung2BusMaster.notNil) { ~ung2BusMaster.free; ~ung2BusMaster = nil };
    ~ung2Mst = nil; ~ung2Monades = nil; ~ung2Schliere = nil; ~ung2Firnis = nil;
    Pdef.all.do(_.clear);
    if(verbose) { "ungrund.0002 — reset complete.".postln };
};
~ung2Reset.value(false);


// =====================================================================
// 1. UI helpers — all GUI mutations via .defer
// =====================================================================

~ung2SetStatus = { |state|
    {
        if(~ung2StatusLabel.notNil) { ~ung2StatusLabel.string = "UNGRUND 0002 — " ++ state };
        if(~ung2StartBtn.notNil)    { ~ung2StartBtn.enabled_(state == "stopped") };
        if(~ung2StopBtn.notNil)     { ~ung2StopBtn.enabled_(state != "stopped") };
    }.defer;
};

~ung2UpdateTime = { |elapsed|
    var rem, mm, ss, rmm, rss;
    elapsed = elapsed.clip(0, 540);
    rem = (540 - elapsed).max(0);
    mm  = (elapsed/60).floor.asInteger;
    ss  = (elapsed % 60).floor.asInteger.asString.padLeft(2, "0");
    rmm = (rem/60).floor.asInteger;
    rss = (rem % 60).floor.asInteger.asString.padLeft(2, "0");
    {
        if(~ung2TimeLabel.notNil) {
            ~ung2TimeLabel.string = "% : %  /  -%:%".format(mm, ss, rmm, rss);
        };
    }.defer;
};


// =====================================================================
// 2. Cluster definitions  [freq, amp, pan, breath_rate, breath_depth]
//    Detuned pairs in section A produce 0.04–0.09 Hz beats (11–25 s cycles).
// =====================================================================

~ung2ClusterA = [
    [ 94.00, 0.18, -0.30, 0.030, 0.55],
    [ 94.07, 0.18,  0.30, 0.041, 0.55],
    [117.50, 0.15, -0.15, 0.053, 0.60],
    [117.54, 0.15,  0.15, 0.067, 0.60],
    [141.00, 0.13, -0.05, 0.083, 0.62],
    [141.09, 0.13,  0.05, 0.097, 0.62]
];

~ung2ClusterB = [
    [ 94.00, 0.20, -0.20, 0.035, 0.55],
    [112.80, 0.16,  0.20, 0.048, 0.60],   // 6:5 minor third
    [141.00, 0.15, -0.10, 0.062, 0.55],
    [141.05, 0.15,  0.10, 0.079, 0.55],
    [188.00, 0.13,  0.00, 0.091, 0.65]    // 2:1 octave
];

~ung2BindeFreqs = [188, 282, 376, 470, 564, 705, 940];   // multiples of 94


// =====================================================================
// 3. Start / Stop
// =====================================================================

~ung2Start = {
    if(~ung2R.notNil) {
        "ungrund.0002 — already playing.".postln;
    } {
        ~ung2Reset.value(false);
        ~ung2SetStatus.value("starting…");

        s.waitForBoot({

            // ----- SynthDefs (idempotent .add) ---------------------

            SynthDef(\ung2_monade, { |out = 0,
                                     freq = 94, amp = 0.2,
                                     atk = 10, rel = 14, gate = 1,
                                     pan = 0,
                                     breath_rate = 0.04, breath_depth = 0.5|
                var env, sig, fSafe, breath, ampM;
                env    = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
                fSafe  = freq.clip(20, SampleRate.ir * 0.45);
                breath = LFNoise2.kr(breath_rate.max(0.001)).range(1 - breath_depth, 1);
                ampM   = amp.lag(0.05) * breath;
                sig    = SinOsc.ar(fSafe) * env * ampM;
                Out.ar(out, Pan2.ar(sig, pan.lag(0.05)));
            }).add;

            // \ung2_binde — self-timed: lifetime = dur seconds, then frees.
            //               Removes the need to track gate-offs externally.
            SynthDef(\ung2_binde, { |out = 0, dur = 20,
                                    freq = 470, rq = 0.022, amp = 0.2,
                                    atk = 8, rel = 10,
                                    pan = 0,
                                    breath_rate = 0.03, breath_depth = 0.4|
                var env, sig, fSafe, comp, breath, ampM;
                var atkS, relS, susD;
                atkS = atk.clip(0.001, dur * 0.45);
                relS = rel.clip(0.001, dur * 0.45);
                susD = (dur - atkS - relS).max(0.1);
                env  = EnvGen.kr(Env([0, 1, 1, 0], [atkS, susD, relS], curve: -4), doneAction: 2);
                fSafe  = freq.clip(20, SampleRate.ir * 0.45);
                comp   = rq.reciprocal.sqrt * 0.4;
                breath = LFNoise2.kr(breath_rate.max(0.001)).range(1 - breath_depth, 1);
                ampM   = amp.lag(0.05) * breath;
                sig    = BPF.ar(PinkNoise.ar, fSafe, rq) * comp * env * ampM;
                Out.ar(out, Pan2.ar(sig, pan.lag(0.05)));
            }).add;

            SynthDef(\ung2_schliere, { |out = 0,
                                       freq_lo = 200, freq_hi = 1400, amp = 0.15,
                                       atk = 12, rel = 8, gate = 1,
                                       pan = 0,
                                       drift_rate = 1.0|
                var env, drift1, drift2, combFreq, delayT, sig, loSafe, hiSafe;
                env      = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
                loSafe   = freq_lo.clip(20, SampleRate.ir * 0.45);
                hiSafe   = freq_hi.clip(20, SampleRate.ir * 0.45);
                drift1   = LFNoise2.kr(0.011 * drift_rate).range(0, 1);
                drift2   = LFNoise2.kr(0.017 * drift_rate).range(0, 1);
                combFreq = ((drift1 * 0.6) + (drift2 * 0.4)).linexp(0, 1, loSafe, hiSafe);
                delayT   = combFreq.reciprocal.clip(0.0001, 0.01);
                sig      = CombC.ar(WhiteNoise.ar * 0.5, 0.01, delayT, 5.0) * env * amp;
                Out.ar(out, Pan2.ar(sig, pan));
            }).add;

            SynthDef(\ung2_flockung, { |out = 0,
                                       fund = 220, amp = 0.15,
                                       atk = 0.01, rel = 0.5,
                                       jitter = 0.02, pan = 0|
                var env, partials, grains, sig, fSafe;
                env      = EnvGen.kr(Env.linen(0, rel * 1.1, 0.05), doneAction: 2);
                fSafe    = fund.clip(20, SampleRate.ir * 0.1);
                partials = [3, 5, 7, 9, 11];
                grains   = partials.collect { |p, i|
                    var jit      = LFNoise2.kr(2 + i).range(1 - jitter, 1 + jitter);
                    var grainEnv = EnvGen.kr(Env.perc(atk + (i * 0.008), rel * (1 - (i * 0.05)), curve: -4));
                    SinOsc.ar(fSafe * p * jit) * grainEnv
                };
                sig = Mix(grains) * (1 / partials.size) * amp;
                Out.ar(out, Pan2.ar(sig * env, pan));
            }).add;

            SynthDef(\ung2_kratzer, { |out = 0,
                                      amp = 0.15,
                                      atk = 0.015, rel = 0.4,
                                      hpf = 5000,
                                      gate_rate = 45,
                                      pan = 0|
                var env, gate_lfn, sig, fSafe;
                env      = EnvGen.kr(Env.perc(atk, rel, curve: -4), doneAction: 2);
                fSafe    = hpf.clip(1000, SampleRate.ir * 0.45);
                gate_lfn = LFNoise0.kr(gate_rate).range(0.2, 1.0);
                sig      = HPF.ar(WhiteNoise.ar, fSafe) * gate_lfn * env * amp;
                Out.ar(out, Pan2.ar(sig, pan));
            }).add;

            SynthDef(\ung2_firnis, { |out = 0,
                                     amp = 1.0,
                                     atk = 14, rel = 12,
                                     gate = 1|
                var env, freqs, voices, sig;
                env    = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
                freqs  = [12390, 13270, 14140, 15510, 16730, 17920, 19010];
                voices = freqs.collect { |f, i|
                    var modAmp = LFNoise2.kr(0.08 + (i * 0.014)).range(0.15, 1.0);
                    SinOsc.ar(f) * 0.011 * modAmp
                };
                sig = Splay.ar(voices, 0.7);
                sig = LPF.ar(sig, 20000);
                Out.ar(out, sig * env * amp.lag(0.1));
            }).add;

            SynthDef(\ung2_master, { |in = 16, out = 0, master_amp = 1.0|
                var sig;
                sig = In.ar(in, 2);
                sig = LeakDC.ar(sig);
                sig = Limiter.ar(sig, 0.95, 0.01);
                sig = sig * master_amp.lag(0.05);
                Out.ar(out, sig);
            }).add;

            s.sync;

            // ----- Groups + buses + master -------------------------

            ~ung2GrpSrc    = Group.new(s, \addToHead);
            ~ung2GrpFx     = Group.after(~ung2GrpSrc);
            ~ung2BusMaster = Bus.audio(s, 2);
            s.sync;

            ~ung2Mst = Synth(\ung2_master, [
                \in,         ~ung2BusMaster.index,
                \out,        0,
                \master_amp, 1.0
            ], ~ung2GrpFx);

            // ----- Main Routine -----------------------------------

            ~ung2R = Routine({
                var t0 = thisThread.seconds;

                // UI timer
                ~ung2UiTask = Routine({
                    loop {
                        ~ung2UpdateTime.value(thisThread.seconds - t0);
                        0.5.wait;
                    };
                }).play(AppClock);

                // ============ Section A (0..200) ============
                ~ung2SetStatus.value("section A — tight cluster");

                ~ung2Schliere = Synth(\ung2_schliere, [
                    \out, ~ung2BusMaster.index,
                    \freq_lo, 200, \freq_hi, 1400,
                    \amp, 0.16, \atk, 12, \rel, 8,
                    \pan, 0, \drift_rate, 1.0
                ], ~ung2GrpSrc);

                ~ung2Firnis = Synth(\ung2_firnis, [
                    \out, ~ung2BusMaster.index,
                    \amp, 1.0, \atk, 14, \rel, 12
                ], ~ung2GrpSrc);

                ~ung2Monades = List.new;
                ~ung2ClusterA.do { |row, i|
                    if(i > 0) { 2.5.wait };
                    ~ung2Monades.add(Synth(\ung2_monade, [
                        \out, ~ung2BusMaster.index,
                        \freq, row[0], \amp, row[1], \pan, row[2],
                        \atk, 10, \rel, 14,
                        \breath_rate, row[3], \breath_depth, row[4]
                    ], ~ung2GrpSrc));
                };
                // t ≈ 12.5

                ~ung2EventLoop = Routine({
                    var nextFlock = rrand(15.0, 25.0);
                    var nextKratz = rrand(35.0, 55.0);
                    loop {
                        var dt = min(nextFlock, nextKratz);
                        dt.wait;
                        nextFlock = nextFlock - dt;
                        nextKratz = nextKratz - dt;
                        if(nextFlock <= 0.01) {
                            Synth(\ung2_flockung, [
                                \out, ~ung2BusMaster.index,
                                \fund, ~ung2ClusterA.choose[0] * rrand(2, 4),
                                \amp, exprand(0.09, 0.20),
                                \pan, rrand(-0.55, 0.55),
                                \rel, rrand(0.35, 0.7),
                                \jitter, rrand(0.015, 0.03)
                            ], ~ung2GrpSrc);
                            nextFlock = rrand(15.0, 28.0);
                        };
                        if(nextKratz <= 0.01) {
                            Synth(\ung2_kratzer, [
                                \out, ~ung2BusMaster.index,
                                \amp, rrand(0.12, 0.22),
                                \hpf, rrand(4500, 9000),
                                \rel, rrand(0.25, 0.5),
                                \pan, rrand(-0.55, 0.55)
                            ], ~ung2GrpSrc);
                            nextKratz = rrand(35.0, 60.0);
                        };
                    };
                }).play;

                // hold to t = 200
                187.5.wait;

                // ============ Zäsur (200..221) ============
                ~ung2SetStatus.value("releasing…");
                ~ung2EventLoop.stop; ~ung2EventLoop = nil;
                ~ung2Monades.do { |syn| syn.set(\gate, 0) };
                ~ung2Schliere.set(\gate, 0);
                ~ung2Firnis.set(\gate, 0);
                ~ung2Monades = nil; ~ung2Schliere = nil; ~ung2Firnis = nil;

                // longest release is monade 14 s — wait 15 for true silence
                15.wait;

                ~ung2SetStatus.value("— zäsur —");
                6.wait;

                // ============ Section B (221..520) ============
                ~ung2SetStatus.value("section B — open cluster + bindes");

                ~ung2Schliere = Synth(\ung2_schliere, [
                    \out, ~ung2BusMaster.index,
                    \freq_lo, 350, \freq_hi, 1800,
                    \amp, 0.14, \atk, 10, \rel, 12,
                    \pan, 0, \drift_rate, 0.7
                ], ~ung2GrpSrc);

                ~ung2Firnis = Synth(\ung2_firnis, [
                    \out, ~ung2BusMaster.index,
                    \amp, 0.95, \atk, 12, \rel, 14
                ], ~ung2GrpSrc);

                ~ung2Monades = List.new;
                ~ung2ClusterB.do { |row, i|
                    if(i > 0) { 3.0.wait };
                    ~ung2Monades.add(Synth(\ung2_monade, [
                        \out, ~ung2BusMaster.index,
                        \freq, row[0], \amp, row[1], \pan, row[2],
                        \atk, 12, \rel, 16,
                        \breath_rate, row[3], \breath_depth, row[4]
                    ], ~ung2GrpSrc));
                };
                // t ≈ 233

                ~ung2EventLoop = Routine({
                    var nextFlock = rrand(20.0, 32.0);
                    var nextKratz = rrand(40.0, 65.0);
                    var nextBinde = rrand(6.0, 12.0);
                    var bindeIdx  = 0;
                    loop {
                        var dt = min(nextFlock, min(nextKratz, nextBinde));
                        dt.wait;
                        nextFlock = nextFlock - dt;
                        nextKratz = nextKratz - dt;
                        nextBinde = nextBinde - dt;
                        if(nextFlock <= 0.01) {
                            Synth(\ung2_flockung, [
                                \out, ~ung2BusMaster.index,
                                \fund, ~ung2ClusterB.choose[0] * rrand(2, 5),
                                \amp, exprand(0.09, 0.20),
                                \pan, rrand(-0.6, 0.6),
                                \rel, rrand(0.4, 0.8),
                                \jitter, rrand(0.015, 0.03)
                            ], ~ung2GrpSrc);
                            nextFlock = rrand(20.0, 35.0);
                        };
                        if(nextKratz <= 0.01) {
                            Synth(\ung2_kratzer, [
                                \out, ~ung2BusMaster.index,
                                \amp, rrand(0.12, 0.22),
                                \hpf, rrand(5500, 11000),
                                \rel, rrand(0.25, 0.5),
                                \pan, rrand(-0.6, 0.6)
                            ], ~ung2GrpSrc);
                            nextKratz = rrand(40.0, 70.0);
                        };
                        if(nextBinde <= 0.01) {
                            Synth(\ung2_binde, [
                                \out, ~ung2BusMaster.index,
                                \dur,  rrand(22.0, 34.0),
                                \freq, ~ung2BindeFreqs[bindeIdx % ~ung2BindeFreqs.size],
                                \rq,   rrand(0.018, 0.028),
                                \amp,  rrand(0.16, 0.24),
                                \atk,  rrand(7, 11),
                                \rel,  rrand(9, 14),
                                \pan,  rrand(-0.45, 0.45),
                                \breath_rate, rrand(0.025, 0.05),
                                \breath_depth, 0.45
                            ], ~ung2GrpSrc);
                            bindeIdx  = bindeIdx + 1;
                            nextBinde = rrand(14.0, 22.0);
                        };
                    };
                }).play;

                // hold to t = 520
                287.wait;

                // ============ Tail (520..540) ============
                ~ung2SetStatus.value("releasing…");
                ~ung2EventLoop.stop; ~ung2EventLoop = nil;
                ~ung2Monades.do { |syn| syn.set(\gate, 0) };
                ~ung2Schliere.set(\gate, 0);
                ~ung2Firnis.set(\gate, 0);

                // monade 16 s release — wait 17, then pad to clean end
                17.wait;
                3.wait;

                // ============ Done ============
                ~ung2UiTask.stop; ~ung2UiTask = nil;
                ~ung2UpdateTime.value(540);
                ~ung2Reset.value(true);
                ~ung2SetStatus.value("stopped");
                "ungrund.0002 — done.".postln;

            }).play;
        });
    };
};

~ung2Stop = {
    ~ung2Reset.value(true);
    ~ung2UpdateTime.value(0);
    ~ung2SetStatus.value("stopped");
};


// =====================================================================
// 4. Control window
// =====================================================================

(
    if(~ung2Win.notNil) { ~ung2Win.close };
    ~ung2Reset.value(false);

    ~ung2Win = Window("UNGRUND 0002", Rect(120, 340, 420, 210))
        .background_(Color.gray(0.10));

    ~ung2StatusLabel = StaticText(~ung2Win, Rect(20, 14, 380, 22))
        .string_("UNGRUND 0002 — stopped")
        .stringColor_(Color.gray(0.92))
        .font_(Font("Menlo", 13, true));

    ~ung2HintLabel = StaticText(~ung2Win, Rect(20, 38, 380, 18))
        .string_("kontakt / kontaktmenge · 94 Hz cluster · 9 min")
        .stringColor_(Color.gray(0.50))
        .font_(Font("Menlo", 10));

    ~ung2InfoLabel = StaticText(~ung2Win, Rect(20, 56, 380, 18))
        .string_("A: tight cluster (200s) · zäsur (6s) · B: open + binde scans (300s)")
        .stringColor_(Color.gray(0.45))
        .font_(Font("Menlo", 9));

    ~ung2TimeLabel = StaticText(~ung2Win, Rect(20, 84, 380, 22))
        .string_("0 : 00  /  -9:00")
        .stringColor_(Color.gray(0.70))
        .font_(Font("Menlo", 11));

    ~ung2StartBtn = Button(~ung2Win, Rect(20, 124, 185, 64))
        .states_([["start", Color.gray(0.95), Color.gray(0.22)]])
        .font_(Font("Menlo", 15, true))
        .action_({ ~ung2Start.value });

    ~ung2StopBtn = Button(~ung2Win, Rect(215, 124, 185, 64))
        .states_([["stop / reset", Color.gray(0.95), Color.gray(0.22)]])
        .font_(Font("Menlo", 15, true))
        .enabled_(false)
        .action_({ ~ung2Stop.value });

    ~ung2Win.onClose_({ ~ung2Reset.value(false) });
    ~ung2Win.front;
)


// =====================================================================
// 5. Cleanup paragraph — evaluate alone for a hard reset
// =====================================================================

(
    Routine.run({ s.bind { ~ung2Reset.value(true) } });
)
