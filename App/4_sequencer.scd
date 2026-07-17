// App/4_sequencer.scd — UNGRUND · SEQUENCER: block timeline as a Tdef on
// a TempoClock. ~seqStart / ~seqStop. The demo timeline (~80 s) sketches
// ungrund.0001; it ends itself via the finish flag. Load last.


// ===== CONFIG — edit here ============================================
(
~cfg_seq = (
    tempo: 1.0,    // TempoClock beats per second (1 = time in seconds)

    // Each block: t (start, s), active (layers raised to working volume),
    // gone (layers muted), set (optional [\layer, \param, value] triples).
    // Layers not mentioned keep their previous state.
    timeline: [
        ( t: 0,   active: [\alpha],                 gone: [\delta, \epsilon, \zeta, \theta],
          set: [[\alpha, \amp, 0.22]] ),
        ( t: 4,   active: [\theta],                 gone: [] ),
        ( t: 36,  active: [\delta],                  gone: [],
          set: [[\delta, \freq, 188]] ),
        ( t: 52,  active: [\epsilon],               gone: [\delta] ),
        ( t: 68,  active: [],                         gone: [\epsilon, \theta] ),
        ( t: 72,  active: [],                         gone: [\alpha] ),
        ( t: 80,  active: [],                         gone: [], finish: true )
    ]
);


// ===== LOGIC — Tdef scheduler ========================================
// ONE clock per session: re-running the file must NOT create another
// (a permanent clock survives Cmd-.). Only ~appCleanup frees it.
~seqClock = ~seqClock ?? { TempoClock.new(~cfg_seq.tempo).permanent_(true) };
~seqClock.tempo = ~cfg_seq.tempo;

// set layer volume DIRECTLY on the router Ndef, NOT via ~mixSet: ~mixSet
// writes into ~cfg_mixer.levels and a sequencer run would overwrite the
// original mix with zeros (runtime volume vs CONFIG mix, as in ~mixSolo)
~seqSetVol = { |layer, v|
    Ndef(("mix_" ++ layer).asSymbol).set(\vol, v);
    if(~mixerGuiSync.notNil) { ~mixerGuiSync.(layer, \vol, v) };
};
~seqRaise = { |layer|
    var lv = ~cfg_mixer.levels[layer];
    if(lv.notNil) { ~seqSetVol.(layer, lv.vol) };
};
~seqMute = { |layer| ~seqSetVol.(layer, 0) };

// apply one timeline block
~seqApplyBlock = { |block|
    (block.active   ? []).do { |l| ~seqRaise.(l) };
    (block.gone     ? []).do { |l| ~seqMute.(l) };
    // block[\set] (NOT block.set): .set is an Event method shadowing the key
    (block[\set]    ? []).do { |triple|
        Ndef(triple[0].asSymbol).set(triple[1], triple[2]);
    };
};

// state for the viz window (7_viz.scd): current block index + start time
~seqCurrentBlock = ~seqCurrentBlock ? nil;
~seqStartTime    = ~seqStartTime    ? nil;

Tdef(\ung_sequencer, {
    var line = ~cfg_seq.timeline;
    var prevT = 0;
    line.do { |block, i|
        var wait = (block.t - prevT).max(0);
        if(wait > 0) { wait.wait };
        prevT = block.t;
        ~seqCurrentBlock = i;
        ("seq @ " ++ block.t ++ "s  block " ++ i).postln;
        ~seqApplyBlock.(block);
        if(block.finish == true) {
            "seq — таймлайн завершён.".postln;
            { ~seqStop.value }.defer(0.1);
        };
    };
}).clock_(~seqClock).quant_(0);

// --- start / stop -----------------------------------------------------
~seqStart = {
    // initial state: mute all layers, block t=0 raises the needed ones
    ~mixerLayers.do { |l| ~seqMute.(l) };
    ~seqCurrentBlock = nil;
    ~seqStartTime    = Main.elapsedTime;     // wall-clock mark for viz playhead
    Tdef(\ung_sequencer).stop;
    Tdef(\ung_sequencer).play(~seqClock);
    "seq — старт таймлайна.".postln;
};

~seqStop = {
    Tdef(\ung_sequencer).stop;
    ~mixerLayers.do { |l| ~seqMute.(l) };
    ~seqStartTime    = nil;
    ~seqCurrentBlock = nil;
    "seq — стоп, слои погашены.".postln;
};

"4_sequencer — готов (~seqStart / ~seqStop).".postln;
)
