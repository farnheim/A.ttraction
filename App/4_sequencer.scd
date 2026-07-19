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
// ОДИН клок на сессию (permanent переживает Cmd-.); освобождает только ~appCleanup
~seqClock = ~seqClock ?? { TempoClock.new(~cfg_seq.tempo).permanent_(true) };
~seqClock.tempo = ~cfg_seq.tempo;

// громкость ПРЯМО на роутер-Ndef, не через ~mixSet: тот пишет в
// ~cfg_mixer.levels и прогон перетёр бы сведение нулями (runtime vs CONFIG)
~seqSetVol = { |layer, v|
    Ndef(("mix_" ++ layer).asSymbol).set(\vol, v);
    if(~mixerGuiSync.notNil) { ~mixerGuiSync.(layer, \vol, v) };
};
~seqRaise = { |layer|
    var lv = ~cfg_mixer.levels[layer];
    if(lv.notNil) { ~seqSetVol.(layer, lv.vol) };
};
~seqMute = { |layer| ~seqSetVol.(layer, 0) };

// runtime-слот акта: Tdef играет ~seqTimeline, иначе CONFIG-демо
~seqTimeline = ~seqTimeline;

// override 2026-07-18: false = секвенсор НЕ дирижирует громкостями (set:
// остаётся) — громкости у исполнителя; демо всегда возвращает true
~seqDriveVols = ~seqDriveVols ? true;

~seqApplyBlock = { |block|
    if(~seqDriveVols == true) {
        // block[\vols]: [[\layer, rel]] — уровень ОТНОСИТЕЛЬНО живого сведения
        (block[\vols]   ? []).do { |pair|
            var lv = ~cfg_mixer.levels[pair[0]];
            if(lv.notNil) { ~seqSetVol.(pair[0], pair[1] * lv.vol) };
        };
        (block.active   ? []).do { |l| ~seqRaise.(l) };
        (block.gone     ? []).do { |l| ~seqMute.(l) };
    };
    // block[\set] (NOT block.set): .set is an Event method shadowing the key
    (block[\set]    ? []).do { |triple|
        Ndef(triple[0].asSymbol).set(triple[1], triple[2]);
    };
};

// state for the viz window (7_viz.scd): current block index + start time
~seqCurrentBlock = ~seqCurrentBlock;
~seqStartTime    = ~seqStartTime;

Tdef(\ung_sequencer, {
    var line, prevT = 0;
    if(~seqTimeline.isNil) { ~seqDriveVols = true };
    line = ~seqTimeline ? ~cfg_seq.timeline;
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
    // демо всегда дирижирует: false акта не переживает возврат к демо
    if(~seqTimeline.isNil) { ~seqDriveVols = true };
    // старт: заглушить все слои, блок t=0 поднимет нужные
    if(~seqDriveVols == true) { ~mixerLayers.do { |l| ~seqMute.(l) } };
    ~seqCurrentBlock = nil;
    ~seqStartTime    = Main.elapsedTime;     // wall-clock mark for viz playhead
    Tdef(\ung_sequencer).stop;
    Tdef(\ung_sequencer).play(~seqClock);
    "seq — старт таймлайна.".postln;
};

~seqStop = {
    Tdef(\ung_sequencer).stop;
    if(~seqDriveVols == true) {
        ~mixerLayers.do { |l| ~seqMute.(l) };
        "seq — стоп, слои погашены.".postln;
    } {
        "seq — стоп (громкости у исполнителя, слои не тронуты).".postln;
    };
    ~seqStartTime    = nil;
    ~seqCurrentBlock = nil;
};

"4_sequencer — готов (~seqStart / ~seqStop).".postln;
)
