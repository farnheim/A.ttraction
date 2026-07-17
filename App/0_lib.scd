// App/0_lib.scd — UNGRUND · LIB: shared layer-tuning infrastructure.
// Spec registry ~ungSpecs, live values ~ungVals, ~setParam, randomizers,
// presets (save/load/list), per-layer tuner GUI (~openTuner).
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
~ungTunerPop     = ~ungTunerPop     ? ();   // \layer -> PopUpMenu (presets)
~ungTunerName    = ~ungTunerName    ? ();   // \layer -> TextField (preset name)
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


// ----- presets: dir, save, load, list ---------------------------------
~ungPresetDir = { |layer|
    var root = ~ungPresetRoot, d;
    if(File.exists(root).not) { File.mkdir(root) };
    d = root +/+ layer.asString;
    if(File.exists(d).not) { File.mkdir(d) };
    d;
};

~savePreset = { |layer, name|
    var spec, path, pairs, text;
    layer = layer.asSymbol;
    name  = name.asString;
    if(name.isEmpty) { name = "preset_" ++ Date.getDate.stamp };
    spec = ~ungSpecOf.(layer);
    if(spec.isNil) { ("savePreset: нет spec для " ++ layer).warn; nil } {
        path  = ~ungPresetDir.(layer) +/+ (name ++ ".scd");
        pairs = spec.params.collect { |p|
            var v = (~ungVals[layer] !? { ~ungVals[layer][p.key] }) ? p.spec.default;
            p.key.asString ++ ": " ++ v.round(0.0001);
        };
        text = "// UNGRUND preset · " ++ layer ++ " · " ++ name
            ++ " · " ++ Date.getDate.stamp ++ "\n(\n    "
            ++ pairs.join(",\n    ") ++ "\n)\n";
        File.use(path, "w", { |f| f.write(text) });
        ("preset saved -> " ++ path).postln;
        ~ungRefreshPresets.(layer);
        path;
    };
};

~loadPreset = { |layer, name|
    var path, e;
    layer = layer.asSymbol;
    path  = ~ungPresetDir.(layer) +/+ (name.asString ++ ".scd");
    if(File.exists(path).not) {
        ("preset не найден: " ++ path).warn; nil
    } {
        e = path.load;                       // event literal from file
        if(e.isKindOf(Event)) {
            e.keysValuesDo { |k, v| ~setParam.(layer, k, v) };
            ~ungSyncAll.(layer);
            ("preset loaded <- " ++ path.basename).postln;
            e;
        } {
            ("preset повреждён (не event): " ++ path).warn; nil
        };
    };
};

~listPresets = { |layer|
    (~ungPresetDir.(layer.asSymbol) +/+ "*.scd").pathMatch
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


// ----- GUI: refresh preset list in an open window ---------------------
~ungRefreshPresets = { |layer|
    layer = layer.asSymbol;
    if(~ungTunerPop[layer].notNil) {
        var items = ~listPresets.(layer);
        { ~ungTunerPop[layer].items_(if(items.isEmpty) { ["—"] } { items }) }.defer;
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
    var spec, freqs, tones, rows, y0, rowH, slBottom, by, py, w, h, off, mkSlider;
    var nameField, popMenu, win;   // local capture: closures must not read the registry
    var scr, winRect;
    layer = layer.asSymbol;
    spec  = ~ungSpecOf.(layer);

    freqs = spec.params.select { |p| p[\group] == \freq };
    tones = spec.params.select { |p| p[\group] == \tone };
    rows  = max(freqs.size, tones.size);

    y0 = 92; rowH = 26;
    slBottom = y0 + (rows * rowH);
    by = slBottom + 16;             // randomizer row
    py = by + 46;                   // preset row
    w  = 964; h = py + 24 + 16;

    // close previous window best-effort: the reference may point to an
    // already destroyed Qt object (.close without try would abort the build)
    if(~ungTuner[layer].notNil) { try { ~ungTuner[layer].close } };
    // reset ALL layer slots consistently so nothing touches widgets of the
    // OLD window during the rebuild gap
    ~ungTuner[layer]        = nil;
    ~ungTunerEz[layer]      = ();
    ~ungTunerNoteTxt[layer] = ();
    ~ungTunerSync[layer]    = nil;
    ~ungTunerPop[layer]     = nil;
    ~ungTunerName[layer]    = nil;

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

    // ----- presets: name | save | list | load | refresh -----
    StaticText(~ungTuner[layer], Rect(18, py + 2, 58, 22))
        .string_("preset:").stringColor_(Color.gray(0.75)).font_(Font("Menlo", 11));
    // separate assignment (see comment at win): chaining via [k]= returns the Event
    nameField = TextField(~ungTuner[layer], Rect(80, py, 168, 24))
        .string_("").font_(Font("Menlo", 11));
    ~ungTunerName[layer] = nameField;
    Button(~ungTuner[layer], Rect(254, py, 90, 24))
        .states_([["save", Color.white, Color(0.20, 0.40, 0.24)]])
        .font_(Font("Menlo", 11, true))
        .action_({ if(nameField.notNil) { ~savePreset.(layer, nameField.string) } });
    popMenu = PopUpMenu(~ungTuner[layer], Rect(352, py, 200, 24))
        .font_(Font("Menlo", 11));
    ~ungTunerPop[layer] = popMenu;
    Button(~ungTuner[layer], Rect(560, py, 90, 24))
        .states_([["load", Color.white, Color(0.20, 0.34, 0.44)]])
        .font_(Font("Menlo", 11, true))
        .action_({
            var items = ~listPresets.(layer);
            var idx = popMenu !? { popMenu.value };
            if(idx.notNil and: { items.notEmpty } and: { idx < items.size }) {
                ~loadPreset.(layer, items[idx]);
            };
        });
    Button(~ungTuner[layer], Rect(658, py, 90, 24))
        .states_([["обновить", Color.gray(0.9), Color.gray(0.28)]])
        .font_(Font("Menlo", 11))
        .action_({ ~ungRefreshPresets.(layer) });
    Button(~ungTuner[layer], Rect(w - 90, py, 72, 24))
        .states_([["закрыть", Color.gray(0.9), Color(0.4, 0.18, 0.18)]])
        .font_(Font("Menlo", 11))
        .action_({ if(win.notNil) { win.close } });

    ~ungRefreshPresets.(layer);

    // clear the registry ONLY if this is still the layer's current window —
    // otherwise the deferred onClose of the OLD window (close->reopen) would
    // wipe slots registered by the NEW window
    win.onClose_({
        if(~ungTuner[layer] === win) {
            ~ungTuner[layer]        = nil;
            ~ungTunerEz[layer]      = nil;
            ~ungTunerNoteTxt[layer] = nil;
            ~ungTunerSync[layer]    = nil;
            ~ungTunerPop[layer]     = nil;
            ~ungTunerName[layer]    = nil;
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
