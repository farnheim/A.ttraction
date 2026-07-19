// App/0_lib.scd — UNGRUND · LIB: shared layer-tuning infrastructure.
// Spec registry ~ungSpecs, live values ~ungVals, ~setParam, randomizers,
// project presets (save/load/list — one file covers all layers + mixer + fx),
// per-layer tuner GUI (~openTuner).
// Each synths/<layer>.scd registers its spec here; load this file FIRST.
// Spec format and details: docs/architecture/app/README.md.

(
// ----- registries (idempotent: reloading does not reset) -------------
~ungSpecs        = ~ungSpecs        ? ();   // \layer -> spec event
~ungVals         = ~ungVals         ? ();   // \layer -> ( key: value )
~ungTuner        = ~ungTuner        ? ();   // \layer -> Window
~ungTunerEz      = ~ungTunerEz      ? ();   // \layer -> ( key -> EZSlider )
~ungTunerNoteTxt = ~ungTunerNoteTxt ? ();   // \layer -> ( key -> StaticText )
~ungTunerSync    = ~ungTunerSync    ? ();   // \layer -> { |key, v| ... }
~ungTunerOffset  = 0;                        // window position stagger

~ungPresetRoot = ((~appDir ? (thisProcess.nowExecutingPath !? (_.dirname))) ? "")
    +/+ "presets";


// ----- spec / values --------------------------------------------------
~ungSpecOf = { |layer| ~ungSpecs[layer.asSymbol] };

~ungDefault = { |layer, key|
    var p = ~ungSpecOf.(layer).params.detect { |e| e.key == key.asSymbol };
    p !? { p.spec.default };
};


// ----- set parameter: Ndef + store + GUI sync -------------------------
~setParam = { |layer, key, v|
    layer = layer.asSymbol; key = key.asSymbol;
    Ndef(layer).set(key, v);
    if(~ungVals[layer].isNil) { ~ungVals[layer] = () };
    ~ungVals[layer][key] = v;
    if(~ungTuner[layer].notNil and: { ~ungTunerSync[layer].notNil }) {
        ~ungTunerSync[layer].(key, v);
    };
    v;
};

// apply spec defaults to the whole layer (called from synths/<layer>.scd)
~ungApplyDefaults = { |layer|
    layer = layer.asSymbol;
    ~ungSpecOf.(layer).params.do { |p| ~setParam.(layer, p.key, p.spec.default) };
    ~ungSyncAll.(layer);
};


// ----- randomizers by spec group --------------------------------------
~rndGroup = { |layer, group|
    layer = layer.asSymbol;
    ~ungSpecOf.(layer).params.do { |p|
        // p[\group] (NOT p.group): .group is an Object method shadowing the key
        if(p[\group] == group) { ~setParam.(layer, p.key, p.spec.map(1.0.rand)) };
    };
    ~ungSyncAll.(layer);
};
~rndFreq   = { |layer| ~rndGroup.(layer, \freq) };
~rndParams = { |layer| ~rndGroup.(layer, \tone) };


// ----- project presets: dir, save, load, list -------------------------
// ONE file = the whole project state: layers (all spec params), mixer
// (master + levels), fx (the four space-echo knobs of the mixer strip).
// Every section is optional — a partial preset leaves the rest untouched.
~ungPresetDir = {
    var root = ~ungPresetRoot;
    if(File.exists(root).not) { File.mkdir(root) };
    root;
};

~savePreset = { |name|
    var path, sections, layers, layerBlocks, mixRows, mutedList, text;
    name = (name ? "").asString;
    if(name.isEmpty) { name = "preset_" ++ Date.getDate.stamp };
    path     = ~ungPresetDir.value +/+ (name ++ ".scd");
    sections = List.new;
    layers   = (~activeLayers ? ~ungSpecs.keys.asArray.sort)
        .select { |l| ~ungSpecOf.(l).notNil };
    layerBlocks = layers.collect { |l|
        var pairs = ~ungSpecOf.(l).params.collect { |p|
            var v = (~ungVals[l] !? { ~ungVals[l][p.key] }) ? p.spec.default;
            p.key.asString ++ ": " ++ v.round(0.0001);
        };
        "        " ++ l ++ ": (\n            "
            ++ pairs.join(",\n            ") ++ "\n        )";
    };
    if(layerBlocks.notEmpty) {
        sections.add("    layers: (\n" ++ layerBlocks.join(",\n") ++ "\n    )");
    };
    if(~cfg_mixer.notNil) {
        mixRows = ~cfg_mixer.levels.keys.asArray.sort.collect { |l|
            var lv = ~cfg_mixer.levels[l];
            "            " ++ l ++ ": ( vol: " ++ lv.vol.round(0.0001)
                ++ ", sendRev: " ++ lv.sendRev.round(0.0001)
                ++ ", sendDly: " ++ lv.sendDly.round(0.0001) ++ " )";
        };
        mutedList = (~mixMuted ? ()).keys.asArray
            .select { |l| ~mixMuted[l] == true }.sort;
        sections.add("    mixer: (\n        master: "
            ++ ~cfg_mixer.master.round(0.0001)
            ++ ",\n        levels: (\n" ++ mixRows.join(",\n")
            ++ "\n        ),\n        muted: ["
            ++ mutedList.collect { |l| "\\" ++ l }.join(", ") ++ "]"
            ++ (~mixSoloCur !? { ",\n        solo: \\" ++ ~mixSoloCur } ? "")
            ++ "\n    )");
    };
    // the mixer fx strip keeps ~cfg_effects live for exactly these four knobs
    if(~cfg_effects.notNil) {
        sections.add("    fx: ( rev_mode: " ++ ~cfg_effects.rev_mode
            ++ ", dly_mode: " ++ ~cfg_effects.dly_mode
            ++ ", bass: " ++ ~cfg_effects.rev_bass.round(0.0001)
            ++ ", treble: " ++ ~cfg_effects.rev_treble.round(0.0001) ++ " )");
    };
    text = "// UNGRUND project preset · " ++ name ++ " · " ++ Date.getDate.stamp
        ++ "\n(\n" ++ sections.join(",\n") ++ "\n)\n";
    File.use(path, "w", { |f| f.write(text) });
    ("preset saved -> " ++ path).postln;
    ~ungRefreshPresets.value;
    path;
};

~loadPreset = { |name|
    var path, e;
    path = ~ungPresetDir.value +/+ (name.asString ++ ".scd");
    if(File.exists(path).not) {
        ("preset не найден: " ++ path).warn; nil
    } {
        e = path.load;                       // event literal from file
        if(e.isKindOf(Event)) {
            e[\layers] !? { |ls|
                ls.keysValuesDo { |layer, vals|
                    var spec = ~ungSpecOf.(layer);
                    // spec present = layer loaded this session; unknown keys
                    // (renamed/removed params) are skipped, not set blindly
                    if(spec.notNil) {
                        vals.keysValuesDo { |k, v|
                            if(spec.params.any { |p| p.key == k.asSymbol }) {
                                ~setParam.(layer, k, v);
                            };
                        };
                        ~ungSyncAll.(layer);
                    };
                };
            };
            e[\mixer] !? { |m|
                if(~mixSet.notNil and: { ~cfg_mixer.notNil }) {
                    m[\levels] !? { |rows|
                        rows.keysValuesDo { |layer, lv|
                            // only routed layers: ~mixSet on an unrouted name
                            // would spawn an empty mix_<layer> proxy
                            if((~mixerLayers ? []).includes(layer.asSymbol)) {
                                lv.keysValuesDo { |which, v|
                                    ~mixSet.(layer.asSymbol, which, v);
                                };
                            };
                        };
                    };
                    m[\master] !? { |v| ~masterSet.(v) };
                    // presence of `muted` gates the whole audibility state:
                    // presets saved before mute/solo entered the format leave
                    // the current mute/solo untouched (partial-preset rule)
                    m[\muted] !? { |ml|
                        ~mixMuted = ();
                        ml.do { |l| ~mixMuted[l.asSymbol] = true };
                        ~mixSoloCur = m[\solo] !? (_.asSymbol);
                        ~mixApplyLevels.value;
                        if(~mixerRefreshMute.notNil) { ~mixerRefreshMute.value };
                        if(~mixerRefreshSolo.notNil) { ~mixerRefreshSolo.value };
                    };
                };
            };
            e[\fx] !? { |fx|
                if(~cfg_effects.notNil) {
                    // ~cfg_effects is updated too, so a mixer window built
                    // AFTER the load still initializes its fx strip correctly
                    fx[\rev_mode] !? { |v|
                        Ndef(\space_echo_rev).set(\mode, v);
                        ~cfg_effects.rev_mode = v;
                    };
                    fx[\dly_mode] !? { |v|
                        Ndef(\space_echo_dly).set(\mode, v);
                        ~cfg_effects.dly_mode = v;
                    };
                    fx[\bass] !? { |v|
                        Ndef(\space_echo_rev).set(\bass, v);
                        Ndef(\space_echo_dly).set(\bass, v);
                        ~cfg_effects.rev_bass = v;
                        ~cfg_effects.dly_bass = v;
                    };
                    fx[\treble] !? { |v|
                        Ndef(\space_echo_rev).set(\treble, v);
                        Ndef(\space_echo_dly).set(\treble, v);
                        ~cfg_effects.rev_treble = v;
                        ~cfg_effects.dly_treble = v;
                    };
                    {
                        ~mixerFx !? { |wid|
                            wid[\revMode] !? { |p|
                                p.value_((~cfg_effects.rev_mode - 1).clip(0, 11));
                            };
                            wid[\dlyMode] !? { |p|
                                p.value_((~cfg_effects.dly_mode - 1).clip(0, 11));
                            };
                            wid[\bass]   !? { |sl| sl.value_(~cfg_effects.rev_bass) };
                            wid[\treble] !? { |sl| sl.value_(~cfg_effects.rev_treble) };
                        };
                    }.defer;
                };
            };
            ("preset loaded <- " ++ path.basename).postln;
            e;
        } {
            ("preset повреждён (не event): " ++ path).warn; nil
        };
    };
};

~listPresets = {
    (~ungPresetDir.value +/+ "*.scd").pathMatch
        .collect { |p| PathName(p).fileNameWithoutExtension }.sort;
};


// ----- notes: MIDI -> name / name+cents (for disp \note) --------------
~ungNoteName = { |midi|
    var names = #["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
    var n = midi.round.asInteger;
    names[n % 12] ++ (n.div(12) - 1);
};
~ungNoteLabel = { |midi|
    var cents = ((midi - midi.round) * 100).round.asInteger;
    ~ungNoteName.(midi) ++ if(cents == 0, { "" }, {
        " " ++ if(cents > 0, { "+" }, { "" }) ++ cents ++ "¢"
    });
};
// disp \note — value already in MIDI notes; disp \hz — value in Hz,
// converted via .cpsmidi (noise layers show the nearest note)
~ungDispNote = #[\note, \hz];
~ungDispLabel = { |p, v|
    switch(p[\disp],
        \note, { ~ungNoteLabel.(v) },
        \hz,   { if(v > 0) { ~ungNoteLabel.(v.cpsmidi) } { "" } },
        { "" }
    );
};

// is the parameter under an LFO mapping? (.set is ignored then — mark in GUI)
~isMapped = { |layer, key|
    ~cfg_lfo.notNil and: {
        ~cfg_lfo.lines.any { |l|
            (l.target == layer.asSymbol) and: { l.param == key.asSymbol }
        };
    };
};


// ----- GUI: refresh the project-preset list in the mixer window -------
~ungRefreshPresets = {
    if(~mixerPresetPop.notNil) {
        var items = ~listPresets.value;
        { ~mixerPresetPop.items_(if(items.isEmpty) { ["—"] } { items }) }.defer;
    };
};

// ----- GUI: authoritative pull-resync of ALL layer sliders from ~ungVals.
// Bypasses per-key ~ungTunerSync; called after any bulk operation
// (preset load / random) so sliders always end up matching the values.
~ungSyncAll = { |layer|
    layer = layer.asSymbol;
    if(~ungTuner[layer].notNil and: { ~ungTunerEz[layer].notNil }) {
        var spec = ~ungSpecOf.(layer);
        if(spec.notNil) {
            spec.params.do { |p|
                var v  = (~ungVals[layer] !? { ~ungVals[layer][p.key] }) ? p.spec.default;
                var ez = ~ungTunerEz[layer][p.key];
                var t  = ~ungTunerNoteTxt[layer] !? { ~ungTunerNoteTxt[layer][p.key] };
                {
                    if(ez.notNil) { ez.value_(v) };
                    if(t.notNil)  { t.string_(~ungDispLabel.(p, v)) };
                }.defer;
            };
        };
    };
};


// ----- GUI: build the per-layer tuner window --------------------------
~ungBuildTuner = { |layer|
    var spec, freqs, tones, rows, y0, rowH, slBottom, by, w, h, off, mkSlider;
    var win;   // local capture: closures must not read the registry
    var scr, winRect;
    layer = layer.asSymbol;
    spec  = ~ungSpecOf.(layer);

    freqs = spec.params.select { |p| p[\group] == \freq };
    tones = spec.params.select { |p| p[\group] == \tone };
    rows  = max(freqs.size, tones.size);

    y0 = 92; rowH = 26;
    slBottom = y0 + (rows * rowH);
    by = slBottom + 16;             // randomizer row
    w  = 964; h = by + 38 + 16;

    // close previous window best-effort: the reference may point to an
    // already destroyed Qt object (.close without try would abort the build)
    if(~ungTuner[layer].notNil) { try { ~ungTuner[layer].close } };
    // reset ALL layer slots consistently so nothing touches widgets of the
    // OLD window during the rebuild gap
    ~ungTuner[layer]        = nil;
    ~ungTunerEz[layer]      = ();
    ~ungTunerNoteTxt[layer] = ();
    ~ungTunerSync[layer]    = nil;

    // window position: wrap the stagger AND hard-clamp the rect into the
    // visible screen — otherwise the offset grows all session and the window
    // "opens" off-screen
    off = ((~ungTunerOffset % 12) * 26);
    ~ungTunerOffset = ~ungTunerOffset + 1;
    scr = Window.availableBounds;
    w   = w.min(scr.width);
    h   = h.min(scr.height);
    winRect = Rect(
        (70 + off).clip(scr.left, scr.left + scr.width  - w),
        (70 + off).clip(scr.top,  scr.top  + scr.height - h),
        w, h
    );
    // NOTE: do NOT chain `win = ~ungTuner[layer] = Window(...)` — in SC
    // `dict[k] = v` returns the DICT, so win would bind to the registry Event
    // (onClose/close become no-ops, buttons fail). Assign separately.
    win = Window(
        "UNGRUND · tuner — " ++ layer ++ " (живой Ndef в App)",
        winRect
    ).background_(Color.gray(0.12));
    ~ungTuner[layer] = win;

    StaticText(~ungTuner[layer], Rect(18, 10, w - 36, 22))
        .string_("отстройка слоя " ++ layer ++ " — слайдеры правят живой Ndef в общем App")
        .stringColor_(Color.gray(0.92)).font_(Font("Menlo", 13, true));

    StaticText(~ungTuner[layer], Rect(18, 34, w - 36, 18))
        .string_("⟳LFO — параметр под автоматизацией (3_lfo): .set перекрыт маппингом")
        .stringColor_(Color.gray(0.45)).font_(Font("Menlo", 9));

    StaticText(~ungTuner[layer], Rect(18, 70, 440, 16))
        .string_("ТОНЫ / ВЫСОТЫ (random «частоты»)")
        .stringColor_(Color.gray(0.62)).font_(Font("Menlo", 10, true));
    StaticText(~ungTuner[layer], Rect(470, 70, 460, 16))
        .string_("ТЕМБР И СРЕДА (random «параметры»)")
        .stringColor_(Color.gray(0.62)).font_(Font("Menlo", 10, true));

    // one-slider constructor (freq rows get a note label)
    mkSlider = { |p, x, y, sw, isFreq|
        var v0, lbl, mapped, ez;
        v0     = (~ungVals[layer] !? { ~ungVals[layer][p.key] }) ? p.spec.default;
        mapped = ~isMapped.(layer, p.key);
        lbl    = (p[\label] ? p.key.asString) ++ (p[\unit] ? "");
        if(mapped) { lbl = lbl ++ " ⟳LFO" };
        ez = EZSlider(~ungTuner[layer], Rect(x, y, sw, 24), lbl, p.spec, { |e|
            ~setParam.(layer, p.key, e.value);
        }, v0);
        ez.labelView.stringColor_(if(mapped) { Color(0.6, 0.6, 0.45) } { Color.white });
        ez.round_(0.001);
        ~ungTunerEz[layer][p.key] = ez;
        if(isFreq and: { ~ungDispNote.includes(p[\disp]) }) {
            var t = StaticText(~ungTuner[layer], Rect(x + sw + 8, y, 120, 24))
                .stringColor_(Color.gray(0.88)).font_(Font("Menlo", 11, true))
                .string_(~ungDispLabel.(p, v0));
            ~ungTunerNoteTxt[layer][p.key] = t;
        };
    };

    freqs.do { |p, i| mkSlider.(p, 18,  y0 + (i * rowH), 300, true) };
    tones.do { |p, i| mkSlider.(p, 470, y0 + (i * rowH), 470, false) };

    // GUI sync hook <- ~setParam (random/presets)
    ~ungTunerSync[layer] = { |key, v|
        {
            var ez = ~ungTunerEz[layer] !? { ~ungTunerEz[layer][key] };
            var t  = ~ungTunerNoteTxt[layer] !? { ~ungTunerNoteTxt[layer][key] };
            var p  = ~ungSpecOf.(layer).params.detect { |e| e.key == key };
            if(ez.notNil) { ez.value_(v) };
            if(t.notNil and: { p.notNil }) { t.string_(~ungDispLabel.(p, v)) };
        }.defer;
    };

    // ----- randomizers -----
    if(freqs.notEmpty) {
        Button(~ungTuner[layer], Rect(18, by, 220, 38))
            .states_([["random — частоты", Color.white, Color(0.18, 0.34, 0.44)]])
            .font_(Font("Menlo", 12, true))
            .action_({ ~rndFreq.(layer) });
    };
    if(tones.notEmpty) {
        Button(~ungTuner[layer], Rect(246, by, 220, 38))
            .states_([["random — параметры", Color.white, Color(0.40, 0.30, 0.18)]])
            .font_(Font("Menlo", 12, true))
            .action_({ ~rndParams.(layer) });
    };
    Button(~ungTuner[layer], Rect(474, by, 160, 38))
        .states_([["сброс -> defaults", Color.gray(0.95), Color.gray(0.28)]])
        .font_(Font("Menlo", 12, true))
        .action_({ ~ungApplyDefaults.(layer) });
    Button(~ungTuner[layer], Rect(w - 90, by + 7, 72, 24))
        .states_([["закрыть", Color.gray(0.9), Color(0.4, 0.18, 0.18)]])
        .font_(Font("Menlo", 11))
        .action_({ if(win.notNil) { win.close } });

    // clear the registry ONLY if this is still the layer's current window —
    // otherwise the deferred onClose of the OLD window (close->reopen) would
    // wipe slots registered by the NEW window
    win.onClose_({
        if(~ungTuner[layer] === win) {
            ~ungTuner[layer]        = nil;
            ~ungTunerEz[layer]      = nil;
            ~ungTunerNoteTxt[layer] = nil;
            ~ungTunerSync[layer]    = nil;
        };
    });
    // show as ONE deferred event: Qt lays the heavy window out asynchronously,
    // an immediate .front lands before layout and the window stays invisible;
    // a retry loop on AppClock starves Qt and never shows it either
    { ~ungTuner[layer].bounds_(winRect).front }.defer(0.3);
};

// open the layer tuner window (deferred to AppClock)
~openTuner = { |layer|
    layer = layer.asSymbol;
    if(~ungSpecOf.(layer).isNil) {
        ("openTuner: нет spec для " ++ layer ++ " — загружен ли слой?").warn;
    } {
        { ~ungBuildTuner.(layer) }.defer;
    };
};

// close all tuner windows (called from ~appCleanup)
~ungCloseTuners = {
    ~ungTuner.values.do { |win| if(win.notNil) { { win.close }.defer } };
};

"0_lib — инструментарий отстройки готов (~openTuner.(\\layer)).".postln;
)
