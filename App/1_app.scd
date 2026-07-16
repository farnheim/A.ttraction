// App/1_app.scd — UNGRUND · APP: single entry point (boot, buses, module
// loading by ~cfg_app flags, auto-presets, master cleanup ~appCleanup).
// Run the whole block; stop with Cmd-., full reset: ~appCleanup.value(true).
// Load order, signal flow, conventions: docs/architecture/app/README.md.


// ===== CONFIG — edit here ============================================
(
~cfg_app = (
    layers:          nil,     // nil = all synths/*.scd; or e.g. [\alpha, \theta]
    autoPreset:      true,    // auto-load preset "default" per layer if present
    enableEffects:   true,    // 6_effects.scd
    enableMixer:     true,    // 2_mixer.scd
    enableMixerGui:  true,    // open mixer window after load
    enableLfo:       false,   // 3_lfo.scd
    enableControl:   false,   // 5_control.scd (MIDI)
    enableSequencer: false,   // 4_sequencer.scd
    enableVizGui:    false,    // 7_viz.scd (only useful with enableLfo/Sequencer)
    autostart:       false,    // start timeline automatically
    sortSynths:      true      // load synths/*.scd alphabetically
);


// ===== LOGIC — boot, load, wire, start ===============================
~appDir = thisProcess.nowExecutingPath.dirname;

// master cleanup (idempotent)
~appCleanup = { |verbose = true|
    if(~mixRecOn == true) { s.stopRecording; ~mixRecOn = false };
    if(~ungCloseTuners.notNil) { ~ungCloseTuners.value };
    if(~vizClose.notNil)       { ~vizClose.value };
    if(~mixerWin.notNil)       { { ~mixerWin.close }.defer; ~mixerWin = nil };
    Tdef.all.do(_.clear);
    Pdef.all.do(_.clear);
    MIDIdef.all.do(_.free);
    Ndef.all.do(_.clear);
    // the sequencer TempoClock is permanent (survives Cmd-.) — stop it
    // explicitly, otherwise clocks would pile up run after run
    if(~seqClock.notNil) {
        ~seqClock.clear;
        ~seqClock.permanent_(false);
        ~seqClock.stop;
        ~seqClock = nil;
    };
    if(~busDry.notNil)      { ~busDry.free;      ~busDry = nil };
    if(~busFxSend.notNil)   { ~busFxSend.free;   ~busFxSend = nil };
    if(~busFxReturn.notNil) { ~busFxReturn.free; ~busFxReturn = nil };
    s.freeAll;
    if(verbose) { "UNGRUND app — очистка выполнена.".postln };
};

s.waitForBoot({

    // 0a. tuning infrastructure first: synths/*.scd register specs in ~ungSpecs
    (~appDir +/+ "0_lib.scd").load;

    // 0b. clean start
    ~appCleanup.value(false);

    // 1. buses
    ~busDry      = Bus.audio(s, 2);   // dry layer sum -> master
    ~busFxSend   = Bus.audio(s, 2);   // layer sends -> effects (§K)
    ~busFxReturn = Bus.audio(s, 2);   // effect returns -> master (§K)
    s.sync;

    // 2. synth layers (optional filter via ~cfg_app.layers)
    ~synthFiles = (~appDir +/+ "synths" +/+ "*.scd").pathMatch;
    if(~cfg_app.sortSynths) { ~synthFiles = ~synthFiles.sort };

    if(~cfg_app.layers.notNil) {
        var want = ~cfg_app.layers.collect(_.asSymbol);
        var have = ~synthFiles.collect { |p| PathName(p).fileNameWithoutExtension.asSymbol };
        want.do { |l|
            if(have.includes(l).not) {
                ("UNGRUND app — запрошен слой без файла: " ++ l).warn;
            };
        };
        ~synthFiles = ~synthFiles.select { |p|
            want.includes(PathName(p).fileNameWithoutExtension.asSymbol);
        };
    };

    if(~synthFiles.isEmpty) {
        "UNGRUND app — НЕ найдено ни одного синт-слоя для загрузки.".warn;
    };

    // ~activeLayers — single source of truth about loaded layers; mixer and
    // viz read it, so set it BEFORE loading the mixer
    ~activeLayers = ~synthFiles.collect { |p|
        PathName(p).fileNameWithoutExtension.asSymbol;
    };

    ~synthFiles.do { |path|
        ("  load synth: " ++ path.basename).postln;
        path.load;
    };
    s.sync;

    // 2b. auto-load per-layer preset "default" if present
    if(~cfg_app.autoPreset) {
        ~activeLayers.do { |layer|
            // .any with == (value compare), NOT .includes: Array:includes
            // compares by identity (===) and two equal Strings are not identical
            if(~listPresets.(layer).any { |n| n == "default" }) {
                ~loadPreset.(layer, "default");
            };
        };
    };

    // 3. effects (read ~busFxSend, write ~busFxReturn)
    if(~cfg_app.enableEffects) {
        (~appDir +/+ "6_effects.scd").load;
        s.sync;
    } {
        "UNGRUND app — эффекты ВЫКЛ (enableEffects=false).".postln;
    };

    // 4. mixer (routes layers + master)
    if(~cfg_app.enableMixer) {
        (~appDir +/+ "2_mixer.scd").load;
        s.sync;
        if(~cfg_app.enableMixerGui and: { ~openMixer.notNil }) {
            { ~openMixer.value }.defer;
        };
    } {
        "UNGRUND app — микшер ВЫКЛ (enableMixer=false) — слои не маршрутизированы.".warn;
    };

    // 5. lfo (after mixer)
    if(~cfg_app.enableLfo) {
        (~appDir +/+ "3_lfo.scd").load;
        s.sync;
    } {
        "UNGRUND app — LFO ВЫКЛ (enableLfo=false).".postln;
    };

    // 6. control (MIDI — after mixer/lfo)
    if(~cfg_app.enableControl) {
        (~appDir +/+ "5_control.scd").load;
        s.sync;
    } {
        "UNGRUND app — MIDI ВЫКЛ (enableControl=false).".postln;
    };

    // 7. sequencer (last)
    if(~cfg_app.enableSequencer) {
        (~appDir +/+ "4_sequencer.scd").load;
        s.sync;
    } {
        "UNGRUND app — секвенсор ВЫКЛ (enableSequencer=false).".postln;
    };

    // 8. visualization (optional, very last)
    if(~cfg_app.enableVizGui and: { ~cfg_app.enableLfo or: { ~cfg_app.enableSequencer } }) {
        (~appDir +/+ "7_viz.scd").load;
        s.sync;
        if(~openViz.notNil) { { ~openViz.value }.defer };
    };

    "UNGRUND app — все слои загружены и смаршрутизированы.".postln;

    // 9. start timeline (only if sequencer enabled AND autostart)
    if(~cfg_app.enableSequencer and: { ~cfg_app.autostart } and: { ~seqStart.notNil }) {
        ~seqStart.value;
        "UNGRUND app — таймлайн запущен (~seqStop для остановки).".postln;
    } {
        "UNGRUND app — таймлайн не запущен (саунд-дизайн). ~openMixer — окно микшера.".postln;
    };
});
)


// ===== CLEANUP — run separately for a full reset =====================

// (
// ~appCleanup.value(true);
// )
