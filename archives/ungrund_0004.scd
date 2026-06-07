// ungrund_0004.scd
// UNGRUND etude no. 0004 — schichtung / 94 Hz pool / multi-plane / density-weather
//
// Iteration 4 — responds to 0003 critique: events were too quiet and the dry-
// space dogma kept the piece flat. This iteration deliberately relaxes the
// reference's "spatial dryness" axiom and uses two reverb sends (plate, hall)
// to create three perceptual planes (close / mid / far), plus feedback-based
// synthesis (Karplus-Strong, DynKlank), seven event types, and a density-
// weather scheduler that creates concentration centres and rarefaction zones.
//
// Spatial planes:
//   close  : cluster (dry), bloom, friction, subpulse                   — direct
//   mid    : glimmer, fbring (Karplus-Strong feedback)                  — plate
//   far    : cloud (spectral, FM-modulated), plate_hit, spark           — hall
//
// Total: 6:00. Density evolves slowly; rare events cluster in concentration
// centres; subpulse fills quiet periods.


// =====================================================================
// 0. Reset
// =====================================================================

~ung4Reset = { |verbose = true|
    if(~ung4R.notNil)         { ~ung4R.stop;         ~ung4R = nil };
    if(~ung4UiTask.notNil)    { ~ung4UiTask.stop;    ~ung4UiTask = nil };
    if(~ung4Rotation.notNil)  { ~ung4Rotation.stop;  ~ung4Rotation = nil };
    if(~ung4Events.notNil)    { ~ung4Events.stop;    ~ung4Events = nil };
    if(~ung4DensityR.notNil)  { ~ung4DensityR.stop;  ~ung4DensityR = nil };
    if(~ung4GrpSrc.notNil)    { ~ung4GrpSrc.freeAll; ~ung4GrpSrc.free; ~ung4GrpSrc = nil };
    if(~ung4GrpRev.notNil)    { ~ung4GrpRev.freeAll; ~ung4GrpRev.free; ~ung4GrpRev = nil };
    if(~ung4GrpMst.notNil)    { ~ung4GrpMst.freeAll; ~ung4GrpMst.free; ~ung4GrpMst = nil };
    if(~ung4BusMaster.notNil) { ~ung4BusMaster.free; ~ung4BusMaster = nil };
    if(~ung4BusPlate.notNil)  { ~ung4BusPlate.free;  ~ung4BusPlate  = nil };
    if(~ung4BusHall.notNil)   { ~ung4BusHall.free;   ~ung4BusHall   = nil };
    ~ung4Mst = nil; ~ung4Voices = nil; ~ung4ActiveIdx = nil;
    ~ung4Density = 0.5;
    Pdef.all.do(_.clear);
    if(verbose) { "ungrund.0004 — reset complete.".postln };
};
~ung4Reset.value(false);


// =====================================================================
// 1. UI
// =====================================================================

~ung4DurTotal = 360;
~ung4Density  = 0.5;

~ung4SetStatus = { |state|
    {
        if(~ung4StatusLabel.notNil) { ~ung4StatusLabel.string = "UNGRUND 0004 — " ++ state };
        if(~ung4StartBtn.notNil)    { ~ung4StartBtn.enabled_(state == "stopped") };
        if(~ung4StopBtn.notNil)     { ~ung4StopBtn.enabled_(state != "stopped") };
    }.defer;
};

~ung4UpdateTime = { |elapsed|
    var rem, mm, ss, rmm, rss, densBar;
    elapsed = elapsed.clip(0, ~ung4DurTotal);
    rem = (~ung4DurTotal - elapsed).max(0);
    mm  = (elapsed/60).floor.asInteger;
    ss  = (elapsed % 60).floor.asInteger.asString.padLeft(2, "0");
    rmm = (rem/60).floor.asInteger;
    rss = (rem % 60).floor.asInteger.asString.padLeft(2, "0");
    densBar = String.fill((~ung4Density * 24).floor.asInteger, $|);
    {
        if(~ung4TimeLabel.notNil) {
            ~ung4TimeLabel.string = "% : %  /  -%:%".format(mm, ss, rmm, rss);
        };
        if(~ung4ActiveLabel.notNil and: { ~ung4ActiveIdx.notNil }) {
            ~ung4ActiveLabel.string = "voices: %  ·  density: %"
                .format(~ung4ActiveIdx.size, densBar);
        };
    }.defer;
};


// =====================================================================
// 2. Voice pool — 8 positions (smaller than 0003, leaves room for events)
//    [freq, amp_baseline, pan, breath_rate_a]
// =====================================================================

~ung4VoicePool = [
    [ 47.00, 0.10, -0.10, 0.020 ],  //  0  sub
    [ 94.00, 0.13, -0.28, 0.032 ],  //  1  fundamental
    [ 94.07, 0.13,  0.28, 0.043 ],  //  2  detune (0.07 Hz beat)
    [117.50, 0.11, -0.16, 0.055 ],  //  3  5:4 major third
    [117.55, 0.11,  0.16, 0.064 ],  //  4  detune
    [141.00, 0.09, -0.08, 0.073 ],  //  5  3:2 fifth
    [141.08, 0.09,  0.08, 0.085 ],  //  6  detune
    [188.00, 0.08,  0.00, 0.029 ]   //  7  octave
];

~ung4HarmonicRatios = [1, 5/4, 3/2, 7/4, 2, 5/2, 3];


// =====================================================================
// 3. Voice management
// =====================================================================

~ung4IsActive = { |idx| ~ung4Voices.notNil and: { ~ung4Voices[idx].notNil } };

~ung4StartVoice = { |idx|
    var row, plateSend, hallSend, hasPartial;
    if(~ung4IsActive.value(idx).not) {
        row        = ~ung4VoicePool[idx];
        plateSend  = if(0.35.coin) { rrand(0.05, 0.18) } { 0 };
        hallSend   = if(plateSend > 0 and: { 0.40.coin }) { rrand(0.02, 0.08) } { 0 };
        hasPartial = if(0.30.coin) { rrand(0.06, 0.14) } { 0 };
        ~ung4Voices[idx] = Synth(\ung4_cluster_voice, [
            \out,            ~ung4BusMaster.index,
            \plate_out,      ~ung4BusPlate.index,
            \hall_out,       ~ung4BusHall.index,
            \freq,           row[0],
            \amp,            row[1],
            \pan,            row[2],
            \atk,            rrand(16.0, 26.0),
            \rel,            rrand(20.0, 30.0),
            \breath_rate_a,  row[3],
            \breath_depth_a, rrand(0.30, 0.45),
            \breath_rate_b,  rrand(0.0045, 0.0095),
            \breath_depth_b, rrand(0.25, 0.40),
            \freq_jitter,    rrand(0.003, 0.008),
            \bloom_strength, 0.9,
            \partial_amount, hasPartial,
            \plate_send,     plateSend,
            \hall_send,      hallSend
        ], ~ung4GrpSrc);
        ~ung4ActiveIdx.add(idx);
    };
};

~ung4StopVoice = { |idx|
    if(~ung4IsActive.value(idx)) {
        ~ung4Voices[idx].set(\gate, 0);
        ~ung4Voices[idx] = nil;
        ~ung4ActiveIdx.remove(idx);
    };
};


// =====================================================================
// 4. Start / Stop
// =====================================================================

~ung4Start = {
    if(~ung4R.notNil) {
        "ungrund.0004 — already playing.".postln;
    } {
        ~ung4Reset.value(false);
        ~ung4SetStatus.value("starting…");

        s.waitForBoot({

            // ----- SynthDefs --------------------------------------

            // Cluster voice: sine (with optional 5th partial at -16 dB),
            //                double-LFN breath, freq micro-jitter, internal
            //                bloom EnvGen, three outputs (dry / plate / hall).
            SynthDef(\ung4_cluster_voice, { |out = 0, plate_out = 16, hall_out = 18,
                                            freq = 94, amp = 0.12,
                                            atk = 18, rel = 24, gate = 1, pan = 0,
                                            breath_rate_a = 0.030, breath_depth_a = 0.40,
                                            breath_rate_b = 0.006, breath_depth_b = 0.30,
                                            freq_jitter   = 0.005,
                                            bloom_strength = 0.9,
                                            partial_amount = 0.0,
                                            plate_send = 0.0, hall_send = 0.0|
                var env, fSafe, fWobble, breathA, breathB, ampM, sig, partial;
                var bloomTrig, bloomEnv;
                env       = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
                fSafe     = freq.clip(20, SampleRate.ir * 0.45);
                fWobble   = LFNoise2.kr(0.011) * freq_jitter;
                breathA   = LFNoise2.kr(breath_rate_a.max(0.001)).range(1 - breath_depth_a, 1);
                breathB   = LFNoise2.kr(breath_rate_b.max(0.001)).range(1 - breath_depth_b, 1);
                bloomTrig = \bloom_t.tr(0);
                bloomEnv  = EnvGen.kr(Env([0, 1, 0], [1.5, 2.0], \sin), gate: bloomTrig);
                ampM      = amp.lag(0.05) * breathA * breathB * (1 + (bloomEnv * bloom_strength));
                sig       = SinOsc.ar(fSafe + fWobble);
                partial   = SinOsc.ar((fSafe + fWobble) * 5) * partial_amount;
                sig       = (sig + partial) * env * ampM;
                sig       = Pan2.ar(sig, pan.lag(0.05));
                Out.ar(out,       sig);
                Out.ar(plate_out, sig * plate_send.lag(0.1));
                Out.ar(hall_out,  sig * hall_send.lag(0.1));
            }).add;

            // Karplus-Strong feedback ring — short tonal "звон"
            SynthDef(\ung4_fbring, { |out = 0, plate_out = 16, hall_out = 18,
                                     freq = 235, amp = 0.18,
                                     decay = 3.0, coef = 0.35,
                                     pan = 0,
                                     plate_send = 0.55, hall_send = 0.15|
                var sig, fSafe, exc, env;
                fSafe = freq.clip(60, 4000);
                exc   = WhiteNoise.ar * EnvGen.kr(Env.perc(0.001, 0.005)) * 0.5;
                sig   = Pluck.ar(exc, 1, 0.05, fSafe.reciprocal, decay, coef) * amp;
                env   = EnvGen.kr(Env([1, 1, 0], [decay * 0.75, decay * 0.25], curve: \sin), doneAction: 2);
                sig   = sig * env;
                sig   = Pan2.ar(sig, pan);
                Out.ar(out,       sig);
                Out.ar(plate_out, sig * plate_send);
                Out.ar(hall_out,  sig * hall_send);
            }).add;

            // Plate hit — DynKlank metallic resonance, sent heavily to plate/hall
            SynthDef(\ung4_plate_hit, { |out = 0, plate_out = 16, hall_out = 18,
                                        fund = 470, amp = 0.16,
                                        decay_base = 2.5,
                                        pan = 0,
                                        plate_send = 0.7, hall_send = 0.35|
                var sig, exc, env, fSafe;
                fSafe = fund.clip(60, 4000);
                exc   = WhiteNoise.ar * EnvGen.kr(Env.perc(0.001, 0.01)) * 0.3;
                sig   = DynKlank.ar(
                    `[ [fSafe, fSafe*1.6, fSafe*2.3, fSafe*3.1, fSafe*4.7],
                       [1.0, 0.7, 0.5, 0.3, 0.2],
                       [decay_base, decay_base*0.8, decay_base*0.6, decay_base*0.4, decay_base*0.3] ],
                    exc
                ) * amp;
                env   = EnvGen.kr(Env([1, 1, 0], [decay_base * 0.7, decay_base * 0.3], curve: \sin), doneAction: 2);
                sig   = sig * env;
                sig   = Pan2.ar(sig, pan);
                Out.ar(out,       sig);
                Out.ar(plate_out, sig * plate_send);
                Out.ar(hall_out,  sig * hall_send);
            }).add;

            // Spectral cloud — 5 high partials with subtle internal FM, heavy hall
            SynthDef(\ung4_cloud, { |out = 0, plate_out = 16, hall_out = 18,
                                    fund = 235, amp = 0.10,
                                    dur = 8.0, fm_idx = 0.004,
                                    plate_send = 0.35, hall_send = 0.55|
                var env, voices, sig, fSafe;
                fSafe  = fund.clip(20, SampleRate.ir * 0.1);
                env    = EnvGen.kr(Env([0, 1, 1, 0], [dur * 0.3, dur * 0.4, dur * 0.3], curve: \sin), doneAction: 2);
                voices = [7, 9, 11, 13, 17].collect { |p, i|
                    var fm     = SinOsc.ar(fSafe * 0.27 + (i * 0.05)) * fSafe * fm_idx;
                    var vEnv   = LFNoise2.kr(0.15 + (i * 0.04)).range(0.2, 1.0);
                    SinOsc.ar((fSafe * p) + fm) * 0.04 * vEnv
                };
                sig = Splay.ar(voices, 0.7);
                sig = sig * env * amp;
                Out.ar(out,       sig);
                Out.ar(plate_out, sig * plate_send);
                Out.ar(hall_out,  sig * hall_send);
            }).add;

            // Friction — slowly modulated BPF on noise, organic rustle
            SynthDef(\ung4_friction, { |out = 0, plate_out = 16, hall_out = 18,
                                       dur = 2.0, amp = 0.16,
                                       cf_lo = 400, cf_hi = 2400, rq = 0.55,
                                       pan = 0,
                                       plate_send = 0.20, hall_send = 0.40|
                var sig, env, cf;
                env = EnvGen.kr(Env([0, 1, 1, 0], [dur * 0.25, dur * 0.4, dur * 0.35], curve: \sin), doneAction: 2);
                cf  = LFNoise2.kr(0.7).range(cf_lo, cf_hi);
                sig = BPF.ar(PinkNoise.ar, cf, rq) * env * amp * 3;
                sig = Pan2.ar(sig, pan);
                Out.ar(out,       sig);
                Out.ar(plate_out, sig * plate_send);
                Out.ar(hall_out,  sig * hall_send);
            }).add;

            // Glimmer — Resonz ping at a cluster harmonic, plate send
            SynthDef(\ung4_glimmer, { |out = 0, plate_out = 16, hall_out = 18,
                                      freq = 470, rq = 0.018, amp = 0.10,
                                      atk = 0.18, rel = 0.95,
                                      pan = 0,
                                      plate_send = 0.45, hall_send = 0.20|
                var env, sig, fSafe;
                env   = EnvGen.kr(Env.perc(atk, rel, curve: -4), doneAction: 2);
                fSafe = freq.clip(20, SampleRate.ir * 0.45);
                sig   = Resonz.ar(WhiteNoise.ar * 0.6, fSafe, rq) * env * amp * 5;
                sig   = Pan2.ar(sig, pan);
                Out.ar(out,       sig);
                Out.ar(plate_out, sig * plate_send);
                Out.ar(hall_out,  sig * hall_send);
            }).add;

            // Subpulse — deep sub-harmonic, dry only
            SynthDef(\ung4_subpulse, { |out = 0,
                                       freq = 47, amp = 0.045,
                                       atk = 2.0, sus = 4.0, rel = 4.0,
                                       pan = 0|
                var env, sig, fSafe;
                fSafe = freq.clip(20, SampleRate.ir * 0.45);
                env   = EnvGen.kr(Env([0, 1, 1, 0], [atk, sus, rel], curve: \sin), doneAction: 2);
                sig   = SinOsc.ar(fSafe) * env * amp;
                Out.ar(out, Pan2.ar(sig, pan));
            }).add;

            // Spark — single ultrasonic with bell envelope, hall only
            SynthDef(\ung4_spark, { |out = 0, hall_out = 18,
                                    freq = 15000, amp = 0.014,
                                    atk = 2.0, sus = 2.0, rel = 2.5,
                                    pan = 0,
                                    hall_send = 1.0|
                var env, sig, fSafe;
                fSafe = freq.clip(8000, 20000);
                env   = EnvGen.kr(Env([0, 1, 1, 0], [atk, sus, rel], curve: \sin), doneAction: 2);
                sig   = SinOsc.ar(fSafe) * env * amp;
                sig   = LPF.ar(sig, 20000);
                sig   = Pan2.ar(sig, pan);
                Out.ar(out, sig);
                Out.ar(hall_out, sig * hall_send);
            }).add;

            // Plate reverb (FreeVerb on stereo input, multichannel-expanded)
            SynthDef(\ung4_plate_verb, { |in = 16, out = 0, amp = 0.85, room = 0.55, damp = 0.40|
                var sig, wet;
                sig = In.ar(in, 2);
                wet = FreeVerb.ar(sig, 1.0, room, damp);
                wet = wet * amp.lag(0.1);
                wet = LeakDC.ar(wet);
                Out.ar(out, wet);
            }).add;

            // Hall reverb — larger room, LPF for distant character
            SynthDef(\ung4_hall_verb, { |in = 18, out = 0, amp = 0.65, room = 0.88, damp = 0.22|
                var sig, wet;
                sig = In.ar(in, 2);
                wet = FreeVerb.ar(sig, 1.0, room, damp);
                wet = LPF.ar(wet, 6500);
                wet = wet * amp.lag(0.1);
                wet = LeakDC.ar(wet);
                Out.ar(out, wet);
            }).add;

            // Master
            SynthDef(\ung4_master, { |in = 16, out = 0, master_amp = 1.0|
                var sig;
                sig = In.ar(in, 2);
                sig = LeakDC.ar(sig);
                sig = Limiter.ar(sig, 0.95, 0.01);
                sig = sig * master_amp.lag(0.05);
                Out.ar(out, sig);
            }).add;

            s.sync;

            // ----- Groups + buses + reverbs + master -------------

            ~ung4GrpSrc    = Group.new(s, \addToHead);
            ~ung4GrpRev    = Group.after(~ung4GrpSrc);
            ~ung4GrpMst    = Group.after(~ung4GrpRev);
            ~ung4BusMaster = Bus.audio(s, 2);
            ~ung4BusPlate  = Bus.audio(s, 2);
            ~ung4BusHall   = Bus.audio(s, 2);
            s.sync;

            // Reverb returns into BusMaster (alongside dry sources)
            ~ung4PlateRev = Synth(\ung4_plate_verb, [
                \in,  ~ung4BusPlate.index,
                \out, ~ung4BusMaster.index,
                \amp, 0.85
            ], ~ung4GrpRev);

            ~ung4HallRev = Synth(\ung4_hall_verb, [
                \in,  ~ung4BusHall.index,
                \out, ~ung4BusMaster.index,
                \amp, 0.65
            ], ~ung4GrpRev);

            ~ung4Mst = Synth(\ung4_master, [
                \in,         ~ung4BusMaster.index,
                \out,        0,
                \master_amp, 1.0
            ], ~ung4GrpMst);

            // ----- Voice tracking + density init -----------------

            ~ung4Voices    = Array.fill(8, nil);
            ~ung4ActiveIdx = List.new;
            ~ung4Density   = 0.5;

            // ----- Main Routine -----------------------------------

            ~ung4R = Routine({
                var t0 = thisThread.seconds;
                var initialIdx = [1, 3, 5];   // 94, 117.5, 141 — coherent chord

                ~ung4UiTask = Routine({
                    loop {
                        ~ung4UpdateTime.value(thisThread.seconds - t0);
                        0.5.wait;
                    };
                }).play(AppClock);

                ~ung4SetStatus.value("entering");

                // Initial 3 voices, staggered
                initialIdx.do { |idx, i|
                    if(i > 0) { rrand(4.5, 7.0).wait };
                    ~ung4StartVoice.value(idx);
                };
                // t ≈ 12

                // Wait for cluster to settle
                15.wait;
                // t ≈ 27

                ~ung4SetStatus.value("breathing");

                // Voice rotation
                ~ung4Rotation = Routine({
                    var action;
                    loop {
                        rrand(22.0, 40.0).wait;
                        action = case
                            { ~ung4ActiveIdx.size < 4 } { \add }
                            { ~ung4ActiveIdx.size > 6 } { \remove }
                            { [\add, \remove, \swap].wchoose([0.40, 0.30, 0.30]) };
                        switch(action,
                            \add, {
                                var inact = (0..7).reject({ |i| ~ung4IsActive.value(i) });
                                if(inact.notEmpty) { ~ung4StartVoice.value(inact.choose) };
                            },
                            \remove, {
                                if(~ung4ActiveIdx.notEmpty) { ~ung4StopVoice.value(~ung4ActiveIdx.choose) };
                            },
                            \swap, {
                                var inact = (0..7).reject({ |i| ~ung4IsActive.value(i) });
                                if(inact.notEmpty and: { ~ung4ActiveIdx.notEmpty }) {
                                    ~ung4StartVoice.value(inact.choose);
                                    ~ung4StopVoice.value(~ung4ActiveIdx.choose);
                                };
                            }
                        );
                    };
                }).play;

                // Density walk — smoothed random target
                ~ung4DensityR = Routine({
                    var d = 0.5, target = 0.5, step = 0;
                    loop {
                        3.wait;
                        step = step + 1;
                        if(step % 10 == 0) {
                            target = (target + rrand(-0.45, 0.45)).clip(0.15, 0.95);
                        };
                        d = d + ((target - d) * 0.18);
                        ~ung4Density = d;
                    };
                }).play;

                // Wait, then events
                8.wait;
                // t ≈ 35

                ~ung4Events = Routine({
                    var nextBloom    = rrand(15.0, 30.0);
                    var nextGlimmer  = rrand(20.0, 45.0);
                    var nextFbring   = rrand(35.0, 70.0);
                    var nextPlateHit = rrand(45.0, 90.0);
                    var nextCloud    = rrand(50.0, 100.0);
                    var nextFriction = rrand(25.0, 55.0);
                    var nextSubpulse = rrand(80.0, 140.0);
                    var nextSpark    = rrand(60.0, 110.0);

                    loop {
                        var dt = [nextBloom, nextGlimmer, nextFbring, nextPlateHit,
                                  nextCloud, nextFriction, nextSubpulse, nextSpark].minItem;
                        var densMul = (~ung4Density * 1.5) + 0.3;   // 0.45..1.725
                        dt.wait;
                        nextBloom    = nextBloom - dt;
                        nextGlimmer  = nextGlimmer - dt;
                        nextFbring   = nextFbring - dt;
                        nextPlateHit = nextPlateHit - dt;
                        nextCloud    = nextCloud - dt;
                        nextFriction = nextFriction - dt;
                        nextSubpulse = nextSubpulse - dt;
                        nextSpark    = nextSpark - dt;

                        // BLOOM — always fires
                        if(nextBloom <= 0.01) {
                            if(~ung4ActiveIdx.notEmpty) {
                                var idx = ~ung4ActiveIdx.choose;
                                if(~ung4IsActive.value(idx)) {
                                    ~ung4Voices[idx].set(\bloom_t, 1);
                                };
                            };
                            nextBloom = rrand(15.0, 35.0) / densMul;
                        };

                        // GLIMMER — fires above density 0.20
                        if(nextGlimmer <= 0.01) {
                            if(~ung4Density > 0.20 and: { ~ung4ActiveIdx.notEmpty }) {
                                var srcIdx  = ~ung4ActiveIdx.choose;
                                var srcFreq = ~ung4VoicePool[srcIdx][0];
                                var freq = (srcFreq * ~ung4HarmonicRatios.choose).clip(180, 4500);
                                Synth(\ung4_glimmer, [
                                    \out,        ~ung4BusMaster.index,
                                    \plate_out,  ~ung4BusPlate.index,
                                    \hall_out,   ~ung4BusHall.index,
                                    \freq,       freq,
                                    \rq,         rrand(0.012, 0.024),
                                    \amp,        exprand(0.08, 0.16),
                                    \atk,        rrand(0.12, 0.28),
                                    \rel,        rrand(0.7, 1.3),
                                    \pan,        rrand(-0.5, 0.5),
                                    \plate_send, rrand(0.35, 0.55),
                                    \hall_send,  rrand(0.15, 0.30)
                                ], ~ung4GrpSrc);
                            };
                            nextGlimmer = rrand(20.0, 50.0) / densMul;
                        };

                        // FBRING — Karplus-Strong, fires above density 0.45
                        if(nextFbring <= 0.01) {
                            if(~ung4Density > 0.45 and: { ~ung4ActiveIdx.notEmpty }) {
                                var srcIdx  = ~ung4ActiveIdx.choose;
                                var srcFreq = ~ung4VoicePool[srcIdx][0];
                                var freq = (srcFreq * [2, 3, 4, 5, 6, 8].choose).clip(120, 1800);
                                Synth(\ung4_fbring, [
                                    \out,        ~ung4BusMaster.index,
                                    \plate_out,  ~ung4BusPlate.index,
                                    \hall_out,   ~ung4BusHall.index,
                                    \freq,       freq,
                                    \amp,        rrand(0.14, 0.22),
                                    \decay,      rrand(2.5, 4.5),
                                    \coef,       rrand(0.20, 0.45),
                                    \pan,        rrand(-0.55, 0.55),
                                    \plate_send, rrand(0.45, 0.65),
                                    \hall_send,  rrand(0.10, 0.25)
                                ], ~ung4GrpSrc);
                            };
                            nextFbring = rrand(40.0, 80.0) / densMul;
                        };

                        // PLATE_HIT — DynKlank, fires above density 0.40
                        if(nextPlateHit <= 0.01) {
                            if(~ung4Density > 0.40 and: { ~ung4ActiveIdx.notEmpty }) {
                                var srcIdx  = ~ung4ActiveIdx.choose;
                                var srcFreq = ~ung4VoicePool[srcIdx][0];
                                var fund    = (srcFreq * [3, 4, 5].choose).clip(180, 1200);
                                Synth(\ung4_plate_hit, [
                                    \out,        ~ung4BusMaster.index,
                                    \plate_out,  ~ung4BusPlate.index,
                                    \hall_out,   ~ung4BusHall.index,
                                    \fund,       fund,
                                    \amp,        rrand(0.12, 0.18),
                                    \decay_base, rrand(2.0, 3.5),
                                    \pan,        rrand(-0.5, 0.5),
                                    \plate_send, rrand(0.55, 0.75),
                                    \hall_send,  rrand(0.25, 0.45)
                                ], ~ung4GrpSrc);
                            };
                            nextPlateHit = rrand(45.0, 100.0) / densMul;
                        };

                        // CLOUD — spectral, fires above density 0.50
                        if(nextCloud <= 0.01) {
                            if(~ung4Density > 0.50 and: { ~ung4ActiveIdx.notEmpty }) {
                                var srcIdx  = ~ung4ActiveIdx.choose;
                                var srcFreq = ~ung4VoicePool[srcIdx][0];
                                Synth(\ung4_cloud, [
                                    \out,        ~ung4BusMaster.index,
                                    \plate_out,  ~ung4BusPlate.index,
                                    \hall_out,   ~ung4BusHall.index,
                                    \fund,       srcFreq,
                                    \amp,        rrand(0.08, 0.13),
                                    \dur,        rrand(6.0, 12.0),
                                    \fm_idx,     rrand(0.002, 0.007),
                                    \plate_send, rrand(0.30, 0.45),
                                    \hall_send,  rrand(0.45, 0.65)
                                ], ~ung4GrpSrc);
                            };
                            nextCloud = rrand(60.0, 110.0) / densMul;
                        };

                        // FRICTION — BPF noise, fires above density 0.25
                        if(nextFriction <= 0.01) {
                            if(~ung4Density > 0.25) {
                                Synth(\ung4_friction, [
                                    \out,        ~ung4BusMaster.index,
                                    \plate_out,  ~ung4BusPlate.index,
                                    \hall_out,   ~ung4BusHall.index,
                                    \dur,        rrand(1.5, 3.0),
                                    \amp,        rrand(0.12, 0.20),
                                    \cf_lo,      rrand(300, 700),
                                    \cf_hi,      rrand(1500, 2800),
                                    \rq,         rrand(0.4, 0.8),
                                    \pan,        rrand(-0.55, 0.55),
                                    \plate_send, rrand(0.15, 0.30),
                                    \hall_send,  rrand(0.30, 0.50)
                                ], ~ung4GrpSrc);
                            };
                            nextFriction = rrand(30.0, 65.0) / densMul;
                        };

                        // SUBPULSE — fires ONLY in low-density periods
                        if(nextSubpulse <= 0.01) {
                            if(~ung4Density < 0.40) {
                                Synth(\ung4_subpulse, [
                                    \out,  ~ung4BusMaster.index,
                                    \freq, [47.00, 47.04, 70.50, 31.33].choose,
                                    \amp,  rrand(0.030, 0.050),
                                    \atk,  rrand(2.0, 3.4),
                                    \sus,  rrand(3.0, 5.5),
                                    \rel,  rrand(3.5, 5.5),
                                    \pan,  rrand(-0.12, 0.12)
                                ], ~ung4GrpSrc);
                            };
                            nextSubpulse = rrand(90.0, 160.0);
                        };

                        // SPARK — always fires
                        if(nextSpark <= 0.01) {
                            Synth(\ung4_spark, [
                                \out,       ~ung4BusMaster.index,
                                \hall_out,  ~ung4BusHall.index,
                                \freq,      [12640, 13980, 15310, 16720, 17880, 19000].choose,
                                \amp,       exprand(0.007, 0.015),
                                \atk,       rrand(2.0, 3.4),
                                \sus,       rrand(2.0, 4.0),
                                \rel,       rrand(2.5, 4.0),
                                \pan,       rrand(-0.55, 0.55),
                                \hall_send, rrand(0.80, 1.0)
                            ], ~ung4GrpSrc);
                            nextSpark = rrand(60.0, 120.0) / densMul;
                        };
                    };
                }).play;

                // Body: from t≈35 to t≈320 (285 s); outro adds ~40 s → ~6:00 total
                285.wait;

                // ============ Outro (325..360) ============
                ~ung4SetStatus.value("dissolving");
                ~ung4Rotation.stop;  ~ung4Rotation  = nil;
                ~ung4Events.stop;    ~ung4Events    = nil;
                ~ung4DensityR.stop;  ~ung4DensityR  = nil;

                ~ung4ActiveIdx.copy.do { |idx, i|
                    if(i > 0) { 1.5.wait };
                    ~ung4StopVoice.value(idx);
                };

                // longest rel ~30 s + reverb tails (5 s); wait then small final
                32.wait;
                3.wait;

                ~ung4UiTask.stop; ~ung4UiTask = nil;
                ~ung4UpdateTime.value(~ung4DurTotal);
                ~ung4Reset.value(true);
                ~ung4SetStatus.value("stopped");
                "ungrund.0004 — done.".postln;

            }).play;
        });
    };
};

~ung4Stop = {
    ~ung4Reset.value(true);
    ~ung4UpdateTime.value(0);
    ~ung4SetStatus.value("stopped");
};


// =====================================================================
// 5. Control window
// =====================================================================

(
    if(~ung4Win.notNil) { ~ung4Win.close };
    ~ung4Reset.value(false);

    ~ung4Win = Window("UNGRUND 0004", Rect(560, 380, 460, 250))
        .background_(Color.gray(0.10));

    ~ung4StatusLabel = StaticText(~ung4Win, Rect(20, 14, 420, 22))
        .string_("UNGRUND 0004 — stopped")
        .stringColor_(Color.gray(0.92))
        .font_(Font("Menlo", 13, true));

    ~ung4HintLabel = StaticText(~ung4Win, Rect(20, 38, 420, 18))
        .string_("schichtung · multi-plane · 94 Hz pool · feedback · 6 min")
        .stringColor_(Color.gray(0.50))
        .font_(Font("Menlo", 10));

    ~ung4InfoLabel = StaticText(~ung4Win, Rect(20, 56, 420, 18))
        .string_("close (dry) / mid (plate) / far (hall) · density-weather")
        .stringColor_(Color.gray(0.45))
        .font_(Font("Menlo", 9));

    ~ung4TimeLabel = StaticText(~ung4Win, Rect(20, 84, 420, 22))
        .string_("0 : 00  /  -6:00")
        .stringColor_(Color.gray(0.70))
        .font_(Font("Menlo", 11));

    ~ung4ActiveLabel = StaticText(~ung4Win, Rect(20, 108, 420, 18))
        .string_("voices: 0  ·  density: ")
        .stringColor_(Color.gray(0.55))
        .font_(Font("Menlo", 10));

    ~ung4StartBtn = Button(~ung4Win, Rect(20, 156, 205, 70))
        .states_([["start", Color.gray(0.95), Color.gray(0.22)]])
        .font_(Font("Menlo", 15, true))
        .action_({ ~ung4Start.value });

    ~ung4StopBtn = Button(~ung4Win, Rect(235, 156, 205, 70))
        .states_([["stop / reset", Color.gray(0.95), Color.gray(0.22)]])
        .font_(Font("Menlo", 15, true))
        .enabled_(false)
        .action_({ ~ung4Stop.value });

    ~ung4Win.onClose_({ ~ung4Reset.value(false) });
    ~ung4Win.front;
)


// =====================================================================
// 6. Cleanup paragraph — evaluate alone for a hard reset
// =====================================================================

(
    Routine.run({ s.bind { ~ung4Reset.value(true) } });
)
