// App/app.scd — NET entry point: run the whole block; docs: docs/architecture/app/code-notes.md

// ===== CONFIG — edit here ============================================
(
~cfg_app = (
    layers:       nil,     // nil = every synths/*.scd; or e.g. [\alpha, \theta]
    autoPreset:   true,    // load presets/project/default.scd if present
    openMatrix:   true,
    openMachines: true,
    openMixer:    true,
    enableEffects: true,   // effects.scd — two Space Echo instances on the sends
    enableTape:   true,    // tape.scd — the master tape stage (§K.6) before the Limiter
    enableMixer:  true,    // mixer.scd — vol/sends/mute/solo/rec + master
    dice:         false    // throw a random matrix at start
);

// ===== LOGIC =========================================================
~appDir = thisProcess.nowExecutingPath.dirname;

// server headroom for ar ports, cells and delay lines: see code-notes, app.scd
s.options.numWireBufs = 2048;
s.options.memSize = 2 ** 18;
s.options.maxNodes = 2 ** 14;

~appCleanup = { |verbose = true|
    ~netDrift !? { |f| f.(false) };
    ~netCloseViews !? { |f| f.value };
    ~netClear !? { |f| f.(false) };
    Ndef.all.do(_.clear);
    ~netBus !? { |d| d.do { |b| b[\tap].free; b[\mod].free } };
    ~netBus = ();
    if(~mixRecOn == true) { s.stopRecording; ~mixRecOn = false };
    // ~mixerWin stays set: its onClose resets the globals only while they still point at it
    ~mixerWin !? { |w| { try { w.close } }.defer };
    [~busDry, ~busFxSendRev, ~busFxSendDly, ~busFxReturn, ~busTape].do { |b| b !? { b.free } };
    ~busDry = nil; ~busFxSendRev = nil; ~busFxSendDly = nil; ~busFxReturn = nil; ~busTape = nil;
    ~tapeStage = nil; ~tapeGui = nil; ~mixerRebuildMaster = nil;
    ~cfg_mixer = nil; ~cfg_tape = nil; ~mixMuted = nil; ~mixSoloCur = nil;
    ~netGroup = nil;
    ~netLive = nil; ~netHooks = (); ~netViews = ();
    ~fpCurrent = nil; ~fpLive = nil; ~fpViews = ();
    ~graphLive = nil;
    ~ungSpecs = (); ~ungVals = ();
    s.freeAll;
    if(verbose) { "NET — очистка выполнена.".postln };
};

s.waitForBoot({
    var files;

    ~appCleanup.value(false);
    #["lib", "lines", "fingerprint", "cells", "graph", "ui", "presets"].do { |f| (~appDir +/+ f ++ ".scd").load };
    s.sync;

    files = (~appDir +/+ "synths" +/+ "*.scd").pathMatch.sort;
    ~cfg_app.layers !? { |want|
        want = want.collect(_.asSymbol);
        files = files.select { |p| want.includes(PathName(p).fileNameWithoutExtension.asSymbol) };
    };
    ~activeLayers = files.collect { |p| PathName(p).fileNameWithoutExtension.asSymbol };
    files.do { |p| ("  machine: " ++ p.basename).postln; p.load };
    s.sync;

    ~busDry       = Bus.audio(s, 2);
    ~busFxSendRev = Bus.audio(s, 2);
    ~busFxSendDly = Bus.audio(s, 2);
    ~busFxReturn  = Bus.audio(s, 2);
    s.sync;
    if(~cfg_app.enableEffects) { (~appDir +/+ "effects.scd").load; s.sync };
    if(~cfg_app.enableTape) { (~appDir +/+ "tape.scd").load; s.sync };
    (~appDir +/+ "matrix.scd").load;
    if(~cfg_app.enableMixer) { (~appDir +/+ "mixer.scd").load; s.sync };
    ~netRewire.value;

    if(~cfg_app.autoPreset and: { ~preset.names(\project).includesEqual("default") }) {
        ~preset.load(\project, "default");
    };
    if(~cfg_app.dice) { ~netDice.value };

    if(~cfg_app.enableMixer and: { ~cfg_app.openMixer }) { ~openMixer.value };
    if(~cfg_app.openMatrix)   { ~openMatrix.value };
    if(~cfg_app.openMachines) { ~openMachines.value };

    ("NET — " ++ ~activeLayers.size ++ " машин, "
        ++ ~netAllPorts.(\src).size ++ " источников × "
        ++ ~netAllPorts.(\dst).size ++ " назначений.").postln;
});
)

// full reset: ~appCleanup.value(true);
