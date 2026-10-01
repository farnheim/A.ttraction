// App/app.scd — NET: boot, the field, the machines, the out, the two pages.
// Run the whole block. Stop: Cmd-. · full reset: ~appCleanup.value(true).


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

// an ar port holds a wire buffer for the life of the graph; the default 64 makes
// a machine SILENT with only a quiet "SynthDef not found"; takes effect from boot
s.options.numWireBufs = 2048;
// every cell and every delay line of the field lives in real-time memory; the
// default 8 MB runs out at a few hundred cells with a loud "alloc failed"
s.options.memSize = 2 ** 18;
// one cell is one node: the default 1024 caps the matrix at ~1000 cells silently
s.options.maxNodes = 2 ** 14;

~appCleanup = { |verbose = true|
    ~netDrift !? { |f| f.(false) };
    ~netCloseViews !? { |f| f.value };
    ~netClear !? { |f| f.(false) };
    Ndef.all.do(_.clear);
    ~netBus !? { |d| d.do { |b| b[\tap].free; b[\mod].free } };
    ~netBus = ();
    if(~mixRecOn == true) { s.stopRecording; ~mixRecOn = false };
    ~mixerWin !? { |w| { try { w.close } }.defer; ~mixerWin = nil };
    [~busDry, ~busFxSendRev, ~busFxSendDly, ~busFxReturn, ~busTape].do { |b| b !? { b.free } };
    ~busDry = nil; ~busFxSendRev = nil; ~busFxSendDly = nil; ~busFxReturn = nil; ~busTape = nil;
    ~tapeStage = nil; ~tapeGui = nil; ~mixerRebuildMaster = nil;
    ~netGroup = nil;
    ~netLive = nil;
    ~fpCurrent = nil; ~fpLive = nil; ~fpViews = ();
    ~graphLive = nil;
    ~ungSpecs = ();
    s.freeAll;
    if(verbose) { "NET — очистка выполнена.".postln };
};

s.waitForBoot({
    var files;

    ~appCleanup.value(false);
    (~appDir +/+ "lib.scd").load;
    (~appDir +/+ "lines.scd").load;
    (~appDir +/+ "fingerprint.scd").load;
    (~appDir +/+ "cells.scd").load;
    (~appDir +/+ "graph.scd").load;
    (~appDir +/+ "ui.scd").load;
    (~appDir +/+ "presets.scd").load;
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

    if(~cfg_app.autoPreset and: { ~preset.names(\project).any { |n| n == "default" } }) {
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


// ===== CLEANUP — run separately for a full reset =====================

// (
// ~appCleanup.value(true);
// )
