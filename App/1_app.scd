// App/1_app.scd — UNGRUND · APP: single entry point (boot, buses, module
// loading by ~cfg_app flags, auto-presets, master cleanup ~appCleanup).
// Run the whole block; stop with Cmd-., full reset: ~appCleanup.value(true).
// Load order, signal flow, conventions: docs/architecture/app/README.md.


// ===== CONFIG — edit here ============================================
(
~cfg_app = (
    layers:          nil,     // nil = all synths/*.scd; or e.g. [\alpha, \theta]
    autoPreset:      true,    // auto-load project preset "default" (layers+mixer+fx) if present
    enableEffects:   true,    // 6_effects.scd
    enableMixer:     true,    // 2_mixer.scd
    enableMixerGui:  true,    // open mixer window after load
    enableLfo:       false,   // 3_lfo.scd
    enableModMatrix: true,    // 8_modmatrix.scd (cross-layer coupling; loads before mixer)
    enableControl:   false,   // 5_control.scd (MIDI)
    enableSequencer: true,    // 4_sequencer.scd
    enableKonstruktion: true, // 9_konstruktion.scd (форма §E.6; ТРЕБУЕТ enableSequencer + enableModMatrix)
    enableVizGui:    false,    // 7_viz.scd (only useful with enableLfo/Sequencer)
    autostart:       false,    // start timeline automatically
    sortSynths:      true      // load synths/*.scd alphabetically
);


// ===== LOGIC — boot, load, wire, start ===============================
~appDir = thisProcess.nowExecutingPath.dirname;

// дефолтных 64 wire-буферов графу theta мало — слой падает МОЛЧА (тихий
// "SynthDef not found"); действует только с БУТА. docs/architecture/app/README.md §5
s.options.numWireBufs = 512;

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
    // клок секвенсора permanent (переживает Cmd-.) — гасить явно, иначе копятся
    if(~seqClock.notNil) {
        ~seqClock.clear;
        ~seqClock.permanent_(false);
        ~seqClock.stop;
        ~seqClock = nil;
    };
    // состояние акта Konstruktion; nil у ~seqDriveVols вернёт дефолт true
    ~seqTimeline  = nil;
    ~seqDriveVols = nil;
    ~konActive    = false;
    ~konCurrent   = nil;
    if(~busDry.notNil)        { ~busDry.free;        ~busDry = nil };
    if(~busFxSendRev.notNil)  { ~busFxSendRev.free;  ~busFxSendRev = nil };
    if(~busFxSendDly.notNil)  { ~busFxSendDly.free;  ~busFxSendDly = nil };
    if(~busFxReturn.notNil)   { ~busFxReturn.free;   ~busFxReturn = nil };
    s.freeAll;
    if(verbose) { "UNGRUND app — очистка выполнена.".postln };
};

s.waitForBoot({

    // 0a. сначала инфраструктура: слои регистрируют spec'и в ~ungSpecs, окно
    // микшера (шаг 4) читает ~gridGenerate
    (~appDir +/+ "0_lib.scd").load;
    (~appDir +/+ "0_grid.scd").load;

    // 0b. clean start
    ~appCleanup.value(false);

    // 1. buses; посылов ДВА, не один — таблицы §K.1/§K.2 независимы по канону
    ~busDry       = Bus.audio(s, 2);   // dry layer sum -> master
    ~busFxSendRev = Bus.audio(s, 2);   // layer sends -> \space_echo_rev (§K.1)
    ~busFxSendDly = Bus.audio(s, 2);   // layer sends -> \space_echo_dly (§K.2)
    ~busFxReturn  = Bus.audio(s, 2);   // effect returns -> master (§K)
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

    // ~activeLayers — source of truth о загруженных слоях; ставится ДО микшера
    ~activeLayers = ~synthFiles.collect { |p|
        PathName(p).fileNameWithoutExtension.asSymbol;
    };

    ~synthFiles.do { |path|
        ("  load synth: " ++ path.basename).postln;
        path.load;
    };
    s.sync;

    // 3. effects (read ~busFxSendRev/~busFxSendDly, write ~busFxReturn)
    if(~cfg_app.enableEffects) {
        (~appDir +/+ "6_effects.scd").load;
        s.sync;
    } {
        "UNGRUND app — эффекты ВЫКЛ (enableEffects=false).".postln;
    };

    // 3b. modulation matrix — ДО микшера (окно строит 16 фейдеров по ~modKeys)
    if(~cfg_app.enableModMatrix) {
        (~appDir +/+ "8_modmatrix.scd").load;
        s.sync;
    } {
        // выключена: снять остатки прежнего включённого прогона, иначе окно
        // покажет мёртвые фейдеры вместо заглушки
        (~modActive ? []).do { |e| Ndef(e[\target]).unmap(e[\param]) };
        ~modKeys = nil; ~modActive = nil;
        "UNGRUND app — модуляционная матрица ВЫКЛ (enableModMatrix=false).".postln;
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

    // 4b. авто-пресет "default" — ПОСЛЕ микшера (его mixer-секция идёт через
    // ~mixSet/~masterSet); загрузчик nil-safe по секциям
    if(~cfg_app.autoPreset) {
        // .any с ==, не .includes: String-членство — identity-ловушка (контракт §6)
        if(~listPresets.value.any { |n| n == "default" }) {
            ~loadPreset.("default");
        };
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

    // 7. sequencer (last of the sound modules)
    if(~cfg_app.enableSequencer) {
        (~appDir +/+ "4_sequencer.scd").load;
        s.sync;
    } {
        "UNGRUND app — секвенсор ВЫКЛ (enableSequencer=false).".postln;
    };

    // 7b. konstruktion (форма §E.6): требует оба модуля-исполнителя
    if(~cfg_app.enableKonstruktion) {
        if(~cfg_app.enableSequencer and: { ~cfg_app.enableModMatrix }) {
            (~appDir +/+ "9_konstruktion.scd").load;
            s.sync;
        } {
            ("UNGRUND app — Konstruktion пропущен: нужны "
                ++ if(~cfg_app.enableSequencer, "", "enableSequencer ")
                ++ if(~cfg_app.enableModMatrix, "", "enableModMatrix")).warn;
        };
    } {
        "UNGRUND app — Konstruktion ВЫКЛ (enableKonstruktion=false).".postln;
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
