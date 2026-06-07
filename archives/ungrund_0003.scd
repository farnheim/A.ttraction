// ungrund_0003.scd
// UNGRUND etude no. 0003 — schichtung / 94 Hz pool / pseudo-organic field
//
// Iteration 3 — addresses 0002's instrument-like schliere and dis-coherent
// events. The cluster IS the piece; events emerge from active voices.
//
// 12-voice just-intoned pool around 94 Hz; 5–8 voices active at any time
// with slow rotation (crossfades 22–38 s). No schliere, no continuous
// firnis, no separate flockung/kratzer.
//
// Pseudo-organic life from:
//   – double-LFN amplitude breath per voice (fast ~0.03 Hz × slow ~0.006 Hz)
//   – freq micro-jitter (±0.005 Hz) modulating beat phase, sub-audible as pitch
//   – detuned pairs producing 0.04–0.09 Hz beats (11–25 s cycles)
//   – continuous voice rotation; the cluster set drifts, never freezes
//
// Emergent events (sparse, tonally bound to active voices):
//   – bloom    : an active voice momentarily swells (internal EnvGen via .tr)
//   – glimmer  : Resonz ping at a harmonic/sum of an active voice
//   – subshade : deep subharmonic body tone (47 / 47.04 / 70.5 Hz)
//   – topglint : a single ultrasonic sine with bell envelope
//
// ~8 min, no sections, no zäsur, no climax.


// =====================================================================
// 0. Reset
// =====================================================================

~ung3Reset = { |verbose = true|
    if(~ung3R.notNil)         { ~ung3R.stop;         ~ung3R = nil };
    if(~ung3UiTask.notNil)    { ~ung3UiTask.stop;    ~ung3UiTask = nil };
    if(~ung3Rotation.notNil)  { ~ung3Rotation.stop;  ~ung3Rotation = nil };
    if(~ung3Events.notNil)    { ~ung3Events.stop;    ~ung3Events = nil };
    if(~ung3GrpSrc.notNil)    { ~ung3GrpSrc.freeAll; ~ung3GrpSrc.free; ~ung3GrpSrc = nil };
    if(~ung3GrpFx.notNil)     { ~ung3GrpFx.freeAll;  ~ung3GrpFx.free;  ~ung3GrpFx  = nil };
    if(~ung3BusMaster.notNil) { ~ung3BusMaster.free; ~ung3BusMaster = nil };
    ~ung3Mst = nil;
    ~ung3Voices = nil;
    ~ung3ActiveIdx = nil;
    Pdef.all.do(_.clear);
    if(verbose) { "ungrund.0003 — reset complete.".postln };
};
~ung3Reset.value(false);


// =====================================================================
// 1. UI helpers
// =====================================================================

~ung3SetStatus = { |state|
    {
        if(~ung3StatusLabel.notNil) { ~ung3StatusLabel.string = "UNGRUND 0003 — " ++ state };
        if(~ung3StartBtn.notNil)    { ~ung3StartBtn.enabled_(state == "stopped") };
        if(~ung3StopBtn.notNil)     { ~ung3StopBtn.enabled_(state != "stopped") };
    }.defer;
};

~ung3DurTotal = 480;

~ung3UpdateTime = { |elapsed|
    var rem, mm, ss, rmm, rss;
    elapsed = elapsed.clip(0, ~ung3DurTotal);
    rem = (~ung3DurTotal - elapsed).max(0);
    mm  = (elapsed/60).floor.asInteger;
    ss  = (elapsed % 60).floor.asInteger.asString.padLeft(2, "0");
    rmm = (rem/60).floor.asInteger;
    rss = (rem % 60).floor.asInteger.asString.padLeft(2, "0");
    {
        if(~ung3TimeLabel.notNil) {
            ~ung3TimeLabel.string = "% : %  /  -%:%".format(mm, ss, rmm, rss);
        };
        if(~ung3ActiveLabel.notNil and: { ~ung3ActiveIdx.notNil }) {
            ~ung3ActiveLabel.string = "active voices: %".format(~ung3ActiveIdx.size);
        };
    }.defer;
};


// =====================================================================
// 2. Voice pool — 12 just-intoned positions around 94 Hz with detuned pairs
//    [freq, amp_baseline, pan, breath_rate_a]
// =====================================================================

~ung3VoicePool = [
    [ 47.00, 0.10, -0.10, 0.018 ],  //  0  sub octave
    [ 47.04, 0.10,  0.10, 0.023 ],  //  1  sub detune (0.04 Hz beat, 25 s)
    [ 94.00, 0.14, -0.30, 0.030 ],  //  2  fundamental
    [ 94.07, 0.14,  0.30, 0.041 ],  //  3  detune (0.07 Hz beat, 14 s)
    [117.50, 0.12, -0.18, 0.053 ],  //  4  5:4 major third
    [117.55, 0.12,  0.18, 0.062 ],  //  5  detune (0.05 Hz beat, 20 s)
    [141.00, 0.10, -0.10, 0.071 ],  //  6  3:2 fifth
    [141.08, 0.10,  0.10, 0.083 ],  //  7  detune (0.08 Hz beat, 12.5 s)
    [164.50, 0.08,  0.00, 0.091 ],  //  8  7:4 harmonic seventh
    [188.00, 0.09, -0.20, 0.029 ],  //  9  2:1 octave
    [235.00, 0.07,  0.20, 0.037 ],  // 10  5:2
    [282.00, 0.06,  0.15, 0.044 ]   // 11  3:1
];

~ung3HarmonicRatios = [1, 5/4, 3/2, 7/4, 2, 5/2, 3, 7/2];


// =====================================================================
// 3. Voice-management helpers (closures over ~ung3 env vars)
// =====================================================================

~ung3IsActive = { |idx| ~ung3Voices.notNil and: { ~ung3Voices[idx].notNil } };

~ung3StartVoice = { |idx|
    var row;
    if(~ung3IsActive.value(idx).not) {
        row = ~ung3VoicePool[idx];
        ~ung3Voices[idx] = Synth(\ung3_monade, [
            \out,           ~ung3BusMaster.index,
            \freq,          row[0],
            \amp,           row[1],
            \pan,           row[2],
            \atk,           rrand(22.0, 38.0),
            \rel,           rrand(26.0, 40.0),
            \breath_rate_a, row[3],
            \breath_depth_a, rrand(0.30, 0.45),
            \breath_rate_b, rrand(0.0040, 0.0095),
            \breath_depth_b, rrand(0.25, 0.40),
            \freq_jitter,   rrand(0.003, 0.008),
            \bloom_strength, 0.8
        ], ~ung3GrpSrc);
        ~ung3ActiveIdx.add(idx);
    };
};

~ung3StopVoice = { |idx|
    if(~ung3IsActive.value(idx)) {
        ~ung3Voices[idx].set(\gate, 0);
        ~ung3Voices[idx] = nil;
        ~ung3ActiveIdx.remove(idx);
    };
};


// =====================================================================
// 4. Start / Stop
// =====================================================================

~ung3Start = {
    if(~ung3R.notNil) {
        "ungrund.0003 — already playing.".postln;
    } {
        ~ung3Reset.value(false);
        ~ung3SetStatus.value("starting…");

        s.waitForBoot({

            // ----- SynthDefs ---------------------------------------

            // \ung3_monade — the heart. Pure sine with:
            //   – ASR gated envelope (self-frees on gate=0)
            //   – two-rate amplitude breath (fast × slow LFN)
            //   – freq micro-jitter (sub-audible as pitch, modulates beat phase)
            //   – internal bloom EnvGen triggered by \bloom_t (no extra synth needed)
            SynthDef(\ung3_monade, { |out = 0,
                                     freq = 94, amp = 0.12,
                                     atk = 25, rel = 30, gate = 1,
                                     pan = 0,
                                     breath_rate_a = 0.030, breath_depth_a = 0.40,
                                     breath_rate_b = 0.006, breath_depth_b = 0.30,
                                     freq_jitter   = 0.005,
                                     bloom_strength = 0.8|
                var env, sig, fSafe, fWobble, breathA, breathB, ampM;
                var bloomTrig, bloomEnv;
                env     = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);
                fSafe   = freq.clip(20, SampleRate.ir * 0.45);
                fWobble = LFNoise2.kr(0.011) * freq_jitter;
                breathA = LFNoise2.kr(breath_rate_a.max(0.001)).range(1 - breath_depth_a, 1);
                breathB = LFNoise2.kr(breath_rate_b.max(0.001)).range(1 - breath_depth_b, 1);
                bloomTrig = \bloom_t.tr(0);
                bloomEnv  = EnvGen.kr(Env([0, 1, 0], [1.8, 2.5], \sin), gate: bloomTrig);
                ampM    = amp.lag(0.05) * breathA * breathB * (1 + (bloomEnv * bloom_strength));
                sig     = SinOsc.ar(fSafe + fWobble) * env * ampM;
                Out.ar(out, Pan2.ar(sig, pan.lag(0.05)));
            }).add;

            // \ung3_glimmer — brief Resonz ping at a cluster harmonic.
            //   Feels like a tonal "memory" emerging from the field.
            SynthDef(\ung3_glimmer, { |out = 0,
                                      freq = 470, rq = 0.018, amp = 0.10,
                                      atk = 0.18, rel = 0.95,
                                      pan = 0|
                var env, sig, fSafe;
                env   = EnvGen.kr(Env.perc(atk, rel, curve: -4), doneAction: 2);
                fSafe = freq.clip(20, SampleRate.ir * 0.45);
                sig   = Resonz.ar(WhiteNoise.ar * 0.6, fSafe, rq) * env * amp * 5;
                Out.ar(out, Pan2.ar(sig, pan));
            }).add;

            // \ung3_subshade — slow bell-enveloped deep sine.
            SynthDef(\ung3_subshade, { |out = 0,
                                       freq = 47, amp = 0.035,
                                       atk = 2.5, sus = 4.0, rel = 4.5,
                                       pan = 0|
                var env, sig, fSafe;
                env   = EnvGen.kr(Env([0, 1, 1, 0], [atk, sus, rel], curve: \sin), doneAction: 2);
                fSafe = freq.clip(20, SampleRate.ir * 0.45);
                sig   = SinOsc.ar(fSafe) * env * amp;
                Out.ar(out, Pan2.ar(sig, pan));
            }).add;

            // \ung3_topglint — slow ultrasonic appearance.
            SynthDef(\ung3_topglint, { |out = 0,
                                       freq = 16000, amp = 0.012,
                                       atk = 2.2, sus = 2.5, rel = 3.2,
                                       pan = 0|
                var env, sig, fSafe;
                env   = EnvGen.kr(Env([0, 1, 1, 0], [atk, sus, rel], curve: \sin), doneAction: 2);
                fSafe = freq.clip(20, SampleRate.ir * 0.45);
                sig   = SinOsc.ar(fSafe) * env * amp;
                sig   = LPF.ar(sig, 20000);
                Out.ar(out, Pan2.ar(sig, pan));
            }).add;

            SynthDef(\ung3_master, { |in = 16, out = 0, master_amp = 1.0|
                var sig;
                sig = In.ar(in, 2);
                sig = LeakDC.ar(sig);
                sig = Limiter.ar(sig, 0.95, 0.01);
                sig = sig * master_amp.lag(0.05);
                Out.ar(out, sig);
            }).add;

            s.sync;

            // ----- Groups + buses + master ------------------------

            ~ung3GrpSrc    = Group.new(s, \addToHead);
            ~ung3GrpFx     = Group.after(~ung3GrpSrc);
            ~ung3BusMaster = Bus.audio(s, 2);
            s.sync;

            ~ung3Mst = Synth(\ung3_master, [
                \in,         ~ung3BusMaster.index,
                \out,        0,
                \master_amp, 1.0
            ], ~ung3GrpFx);

            // ----- Voice tracking ---------------------------------

            ~ung3Voices    = Array.fill(12, nil);
            ~ung3ActiveIdx = List.new;

            // ----- Main Routine -----------------------------------

            ~ung3R = Routine({
                var t0 = thisThread.seconds;
                var initialIdx = [2, 4, 6, 9];   // 94, 117.5, 141, 188 — coherent chord

                // UI timer
                ~ung3UiTask = Routine({
                    loop {
                        ~ung3UpdateTime.value(thisThread.seconds - t0);
                        0.5.wait;
                    };
                }).play(AppClock);

                ~ung3SetStatus.value("entering");

                // Initial 4 voices, staggered 6 s apart
                initialIdx.do { |idx, i|
                    if(i > 0) { rrand(5.5, 8.0).wait };
                    ~ung3StartVoice.value(idx);
                };
                // t ≈ 20

                // Let cluster settle before any rotation/events
                22.wait;
                // t ≈ 42

                ~ung3SetStatus.value("breathing");

                // Voice rotation Routine — slow drift through the pool.
                ~ung3Rotation = Routine({
                    var action;
                    loop {
                        rrand(28.0, 52.0).wait;
                        action = case
                            { ~ung3ActiveIdx.size < 5 } { \add }
                            { ~ung3ActiveIdx.size > 7 } { \remove }
                            { [\add, \remove, \swap].wchoose([0.40, 0.30, 0.30]) };
                        switch(action,
                            \add, {
                                var inact = (0..11).reject({ |i| ~ung3IsActive.value(i) });
                                if(inact.notEmpty) { ~ung3StartVoice.value(inact.choose) };
                            },
                            \remove, {
                                if(~ung3ActiveIdx.notEmpty) { ~ung3StopVoice.value(~ung3ActiveIdx.choose) };
                            },
                            \swap, {
                                var inact = (0..11).reject({ |i| ~ung3IsActive.value(i) });
                                if(inact.notEmpty and: { ~ung3ActiveIdx.notEmpty }) {
                                    ~ung3StartVoice.value(inact.choose);
                                    ~ung3StopVoice.value(~ung3ActiveIdx.choose);
                                };
                            }
                        );
                    };
                }).play;

                // Wait a little more before events start
                18.wait;
                // t ≈ 60

                // Event Routine — emergent micro-events.
                ~ung3Events = Routine({
                    var nextBloom    = rrand(35.0, 70.0);
                    var nextGlimmer  = rrand(55.0, 110.0);
                    var nextSubshade = rrand(110.0, 200.0);
                    var nextTopglint = rrand(80.0, 160.0);
                    loop {
                        var dt = [nextBloom, nextGlimmer, nextSubshade, nextTopglint].minItem;
                        dt.wait;
                        nextBloom    = nextBloom - dt;
                        nextGlimmer  = nextGlimmer - dt;
                        nextSubshade = nextSubshade - dt;
                        nextTopglint = nextTopglint - dt;

                        // BLOOM — internal swell of one currently active voice
                        if(nextBloom <= 0.01) {
                            if(~ung3ActiveIdx.notEmpty) {
                                var idx = ~ung3ActiveIdx.choose;
                                if(~ung3IsActive.value(idx)) {
                                    ~ung3Voices[idx].set(\bloom_t, 1);
                                };
                            };
                            nextBloom = rrand(35.0, 75.0);
                        };

                        // GLIMMER — Resonz ping at a harmonic OR sum of an active voice
                        if(nextGlimmer <= 0.01) {
                            if(~ung3ActiveIdx.notEmpty) {
                                var srcIdx = ~ung3ActiveIdx.choose;
                                var srcFreq = ~ung3VoicePool[srcIdx][0];
                                var freq;
                                if(0.30.coin and: { ~ung3ActiveIdx.size >= 2 }) {
                                    // sum tone of two active voices
                                    var srcIdx2 = ~ung3ActiveIdx.reject({ |i| i == srcIdx }).choose;
                                    freq = (srcFreq + ~ung3VoicePool[srcIdx2][0]).clip(180, 4500);
                                } {
                                    // harmonic of one active voice
                                    freq = (srcFreq * ~ung3HarmonicRatios.choose).clip(180, 4500);
                                };
                                Synth(\ung3_glimmer, [
                                    \out, ~ung3BusMaster.index,
                                    \freq, freq,
                                    \rq,   rrand(0.012, 0.024),
                                    \amp,  exprand(0.07, 0.14),
                                    \atk,  rrand(0.12, 0.28),
                                    \rel,  rrand(0.65, 1.25),
                                    \pan,  rrand(-0.5, 0.5)
                                ], ~ung3GrpSrc);
                            };
                            nextGlimmer = rrand(55.0, 115.0);
                        };

                        // SUBSHADE — deep body
                        if(nextSubshade <= 0.01) {
                            Synth(\ung3_subshade, [
                                \out, ~ung3BusMaster.index,
                                \freq, [47.00, 47.04, 70.50, 31.33].choose,   // sub & subsub
                                \amp,  rrand(0.025, 0.045),
                                \atk,  rrand(2.0, 3.4),
                                \sus,  rrand(3.0, 5.5),
                                \rel,  rrand(3.5, 5.5),
                                \pan,  rrand(-0.12, 0.12)
                            ], ~ung3GrpSrc);
                            nextSubshade = rrand(110.0, 220.0);
                        };

                        // TOPGLINT — single ultrasonic appearance
                        if(nextTopglint <= 0.01) {
                            Synth(\ung3_topglint, [
                                \out, ~ung3BusMaster.index,
                                \freq, [12640, 13980, 15310, 16720, 17880, 19000].choose,
                                \amp,  exprand(0.007, 0.016),
                                \atk,  rrand(2.0, 3.4),
                                \sus,  rrand(2.0, 4.0),
                                \rel,  rrand(2.5, 4.0),
                                \pan,  rrand(-0.55, 0.55)
                            ], ~ung3GrpSrc);
                            nextTopglint = rrand(80.0, 170.0);
                        };
                    };
                }).play;

                // Body of the piece: from t≈60 to t≈430 (~6 min of activity)
                370.wait;

                // ============ Outro ============
                ~ung3SetStatus.value("dissolving");
                ~ung3Rotation.stop; ~ung3Rotation = nil;
                ~ung3Events.stop;   ~ung3Events   = nil;

                // Gate off all active voices in a staggered sweep over ~12 s.
                // copy() guards against mutation of ~ung3ActiveIdx by ~ung3StopVoice.
                ~ung3ActiveIdx.copy.do { |idx, i|
                    if(i > 0) { 1.5.wait };
                    ~ung3StopVoice.value(idx);
                };

                // Longest release is ~40 s; wait then small tail of pure silence
                40.wait;
                3.wait;

                // ============ Done ============
                ~ung3UiTask.stop; ~ung3UiTask = nil;
                ~ung3UpdateTime.value(~ung3DurTotal);
                ~ung3Reset.value(true);
                ~ung3SetStatus.value("stopped");
                "ungrund.0003 — done.".postln;
            }).play;
        });
    };
};

~ung3Stop = {
    ~ung3Reset.value(true);
    ~ung3UpdateTime.value(0);
    ~ung3SetStatus.value("stopped");
};


// =====================================================================
// 5. Control window
// =====================================================================

(
    if(~ung3Win.notNil) { ~ung3Win.close };
    ~ung3Reset.value(false);

    ~ung3Win = Window("UNGRUND 0003", Rect(560, 120, 440, 240))
        .background_(Color.gray(0.10));

    ~ung3StatusLabel = StaticText(~ung3Win, Rect(20, 14, 400, 22))
        .string_("UNGRUND 0003 — stopped")
        .stringColor_(Color.gray(0.92))
        .font_(Font("Menlo", 13, true));

    ~ung3HintLabel = StaticText(~ung3Win, Rect(20, 38, 400, 18))
        .string_("schichtung · 94 Hz pool · pseudo-organic field · 8 min")
        .stringColor_(Color.gray(0.50))
        .font_(Font("Menlo", 10));

    ~ung3InfoLabel = StaticText(~ung3Win, Rect(20, 56, 400, 18))
        .string_("12 voice pool · 5–8 active · slow rotation · emergent micro-events")
        .stringColor_(Color.gray(0.45))
        .font_(Font("Menlo", 9));

    ~ung3TimeLabel = StaticText(~ung3Win, Rect(20, 82, 400, 22))
        .string_("0 : 00  /  -8:00")
        .stringColor_(Color.gray(0.70))
        .font_(Font("Menlo", 11));

    ~ung3ActiveLabel = StaticText(~ung3Win, Rect(20, 104, 400, 18))
        .string_("active voices: 0")
        .stringColor_(Color.gray(0.55))
        .font_(Font("Menlo", 10));

    ~ung3StartBtn = Button(~ung3Win, Rect(20, 144, 195, 70))
        .states_([["start", Color.gray(0.95), Color.gray(0.22)]])
        .font_(Font("Menlo", 15, true))
        .action_({ ~ung3Start.value });

    ~ung3StopBtn = Button(~ung3Win, Rect(225, 144, 195, 70))
        .states_([["stop / reset", Color.gray(0.95), Color.gray(0.22)]])
        .font_(Font("Menlo", 15, true))
        .enabled_(false)
        .action_({ ~ung3Stop.value });

    ~ung3Win.onClose_({ ~ung3Reset.value(false) });
    ~ung3Win.front;
)


// =====================================================================
// 6. Cleanup paragraph — evaluate alone for a hard reset
// =====================================================================

(
    Routine.run({ s.bind { ~ung3Reset.value(true) } });
)
