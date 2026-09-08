// App/0_lib.scd — UNGRUND · LIB: spec registry ~ungSpecs, values ~ungVals,
// ~setParam, randomizers, project presets, UI kit (~ui*), tuner GUI (~openTuner).
// Loads FIRST. Spec format: docs/architecture/app/README.md.

(
// ----- registries (idempotent: reloading does not reset) -------------
~ungSpecs        = ~ungSpecs        ? ();   // \layer -> spec event
~ungVals         = ~ungVals         ? ();   // \layer -> ( key: value )
~ungTuner        = ~ungTuner        ? ();   // \layer -> Window
~ungTunerEz      = ~ungTunerEz      ? ();   // \layer -> ( key -> ruler ~uiRuler )
~ungTunerNoteTxt = ~ungTunerNoteTxt ? ();   // \layer -> ( key -> StaticText )
~ungTunerSync    = ~ungTunerSync    ? ();   // \layer -> { |key, v| ... }
~ungTunerOffset  = 0;                        // window position stagger

~ungPresetRoot = ((~appDir ? (thisProcess.nowExecutingPath !? (_.dirname))) ? "")
    +/+ "presets";


// ----- spec / values --------------------------------------------------
~ungSpecOf = { |layer| ~ungSpecs[layer.asSymbol] };


// ----- set parameter: Ndef + store + GUI sync -------------------------
~setParam = { |layer, key, v|
    var accepted;
    layer = layer.asSymbol; key = key.asSymbol;
    // a koppelfeld node owns the control: Ndef.set would drop its mapping
    // silently (n_set evicts n_mapa). Module off -> ~kfRestSet nil -> old path.
    // The return is the value the node ACCEPTED (a destination rest is clamped
    // into the scheme window) and that is what gets stored: otherwise ~ungVals,
    // the tuner and the preset would carry something other than what sounds
    accepted = ~kfRestSet !? { ~kfRestSet.(layer, key, v) };
    if(accepted.isNumber) { v = accepted } { Ndef(layer).set(key, v) };
    ~ungValsSet.(layer, key, v);
};

// the tail of ~setParam without the write to the control: for a caller that has
// already written the value in the NORMALIZED space of its node. It may not go
// back through ~setParam, because `unmap(map(x))` on an exp ControlSpec is not
// idempotent — one ULP per pass, and a preset would stop restoring bit for bit
~ungValsSet = { |layer, key, v|
    layer = layer.asSymbol; key = key.asSymbol;
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
// ONE file = the whole project state (layers/mixer/fx); every section is
// optional — a partial preset leaves the rest alone
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
    // §8.2: the topology. The module owns the format down to the number of
    // digits (round(0.0001) above would push a cable out of its band); here it
    // is one string, and nil when koppelfeld is off or holds no scheme
    ~kfPresetSection !? { |f| f.value !? { |txt| sections.add(txt) } };
    text = "// UNGRUND project preset · " ++ name ++ " · " ++ Date.getDate.stamp
        ++ "\n(\n" ++ sections.join(",\n") ++ "\n)\n";
    File.use(path, "w", { |f| f.write(text) });
    ("preset saved -> " ++ path).postln;
    ~ungRefreshPresets.value;
    path;
};

~loadPreset = { |name|
    var path, e, patch, patchOn = false, armT;
    path = ~ungPresetDir.value +/+ (name.asString ++ ".scd");
    if(File.exists(path).not) {
        ("preset не найден: " ++ path).warn; nil
    } {
        e = path.load;                       // event literal from file
        if(e.isKindOf(Event)) {
            // §8.2, strict order: disarm — layers/mixer/fx — apply. The section
            // ABSENT leaves the topology alone entirely (partial-preset rule);
            // present with the module off is a loud refusal, not a silent skip
            patch = e[\patch];
            patch !? {
                if(~kfApply.isNil or: { ~kfSchemeFromPreset.isNil }) {
                    ("preset " ++ name ++ " несёт секцию patch, но koppelfeld ВЫКЛ "
                        ++ "(enableKoppelfeld=false) — топология не тронута").warn;
                } {
                    patchOn = true;
                    armT = patch[\armTime] ? ~cfg_kf.armTime;
                    // hand released: a preset is a full restore of the state, and
                    // a live deviation surviving it would make the field lie
                    ~kfDisarm.(armT);
                };
            };
            e[\layers] !? { |ls|
                ls.keysValuesDo { |layer, vals|
                    var spec = ~ungSpecOf.(layer);
                    // spec present = layer loaded; unknown keys are skipped
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
                            // routed layers only: ~mixSet on a foreign name
                            // would spawn an empty mix_<layer> proxy
                            if((~mixerLayers ? []).includes(layer.asSymbol)) {
                                lv.keysValuesDo { |which, v|
                                    ~mixSet.(layer.asSymbol, which, v);
                                };
                            };
                        };
                    };
                    m[\master] !? { |v| ~masterSet.(v) };
                    // the presence of `muted` gates all mute/solo state: older
                    // presets without it touch nothing (partial-preset rule)
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
                    [
                        [\rev_mode, \mode,   [\space_echo_rev], [\rev_mode]],
                        [\dly_mode, \mode,   [\space_echo_dly], [\dly_mode]],
                        [\bass,     \bass,   [\space_echo_rev, \space_echo_dly], [\rev_bass, \dly_bass]],
                        [\treble,   \treble, [\space_echo_rev, \space_echo_dly], [\rev_treble, \dly_treble]]
                    ].do { |row|
                        fx[row[0]] !? { |v|
                            row[2].do { |n| Ndef(n).set(row[1], v) };
                            row[3].do { |k| ~cfg_effects[k] = v };
                        };
                    };
                    {
                        ~mixerFx !? { |wid|
                            ~uiPopupSet.(wid[\revMode], (~cfg_effects.rev_mode - 1).clip(0, 11));
                            ~uiPopupSet.(wid[\dlyMode], (~cfg_effects.dly_mode - 1).clip(0, 11));
                            wid[\bass]   !? { |r| ~uiRulerSet.(r, ~cfg_effects.rev_bass) };
                            wid[\treble] !? { |r| ~uiRulerSet.(r, ~cfg_effects.rev_treble) };
                            wid[\dlyGlyph] !? { |uv| uv.refresh };
                            wid[\revGlyph] !? { |uv| uv.refresh };
                        };
                    }.defer;
                };
            };
            // last, and after the layers: the destination rests of the scheme
            // travel INSIDE it, and the `layers` section must not overwrite them
            if(patchOn) {
                if(~kfApply.(~kfSchemeFromPreset.(patch), armT).isNil) {
                    // the validator refused: the live topology is untouched, so
                    // the disarm above must be taken back — a preset that fails
                    // may not leave the field silent behind a valid scheme
                    ("preset " ++ name ++ ": секция patch отвергнута валидатором — "
                        ++ "прежняя схема остаётся, поле взводится обратно").warn;
                    ~kfArm.(armT);
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


// ----- UI kit: monochrome paper/ink; layouts and notation: docs/architecture/app/ui/ -----
~uiPal = (
    paper:  Color.new255(241, 236, 226),
    paper2: Color.new255(231, 224, 209),
    ink:    Color.new255(27, 25, 21),
    ink2:   Color.new255(91, 86, 77),
    rule:   Color.new255(185, 176, 159),
    hi:     Color.new255(221, 215, 201)
);
~uiMono  = { |size = 11, bold = false| Font("Menlo", size, bold) };
~uiSerif = { |size = 26| Font("Georgia", size) };
~uiPremise = (
    alpha: "§C.1 · Grund", delta: "§C.4 · binde", epsilon: "§C.5 · schliere",
    zeta: "§C.6 · surface", theta: "§C.8 · splitter"
);
~uiSupMap = Dictionary.newFrom([
    $0, "⁰", $1, "¹", $2, "²", $3, "³", $4, "⁴", $5, "⁵", $6, "⁶", $7, "⁷", $8, "⁸", $9, "⁹", $-, "⁻"
]);
~uiSup = { |n| n.asString.collectAs({ |c| ~uiSupMap[c] ? c.asString }, Array).join };

~uiText = { |parent, rect, string, size = 11, color, bold = false, align = \left|
    StaticText(parent, rect).string_(string).font_(~uiMono.(size, bold))
        .stringColor_(color ? ~uiPal.ink).align_(align);
};
~uiCap   = { |parent, rect, string| ~uiText.(parent, rect, string.toUpper, 9, ~uiPal.ink2) };
~uiTitle = { |parent, rect, string|
    StaticText(parent, rect).string_(string).font_(~uiSerif.(26)).stringColor_(~uiPal.ink);
};
~uiRule  = { |parent, rect| UserView(parent, rect).background_(~uiPal.ink) };
// fixed number of decimals (round(0.01).asString drops trailing zeros)
~uiFmt = { |v, d = 2|
    var m = (10 ** d).asInteger, n = (v * m).round.asInteger;
    if(n < 0, "−", "") ++ (n.abs div: m).asString ++ "." ++ (n.abs mod: m).asString.padLeft(d, "0");
};
// a button is a layout frame; Qt Button draws in the OS style (rounded
// gradient) and ignores the palette, so it is drawn by hand. label is a string
// or [off, on]; on = inverted (pressed state OR a permanently inverted primary)
~uiBtn = { |parent, rect, label, action, on = false|
    var labels = if(label.isKindOf(String)) { [label, label] } { label };
    var b = ( on: on, enabled: true, pressed: false, act: action, labels: labels );
    var uv = UserView(parent, rect).background_(~uiPal.paper);
    b[\view] = uv;
    uv.drawFunc_({ |u|
        var w = u.bounds.width, h = u.bounds.height;
        var font = ~uiMono.(11), str = b[\labels][if(b[\on]) { 1 } { 0 }];
        var inv  = b[\enabled] and: { b[\on] or: { b[\pressed] } };
        var line = if(b[\enabled]) { ~uiPal.ink } { ~uiPal.rule };
        Pen.fillColor = if(inv) { ~uiPal.ink } { ~uiPal.paper };
        Pen.fillRect(Rect(0, 0, w, h));
        Pen.strokeColor = line; Pen.width = 1;
        Pen.strokeRect(Rect(0.5, 0.5, w - 1, h - 1));
        ~uiPenText.(str, w / 2, (h - str.bounds(font).height) / 2, font,
            if(inv) { ~uiPal.paper } { line }, \middle);
    });
    uv.mouseDownAction_({ if(b[\enabled]) { b[\pressed] = true; uv.refresh } });
    uv.mouseUpAction_({ |u, x, y|
        var hit = (x >= 0) and: { y >= 0 } and: { x <= u.bounds.width } and: { y <= u.bounds.height };
        b[\pressed] = false;
        uv.refresh;
        // only the sync hooks move `on` (~mixerRefreshMute and friends) — the
        // button never toggles it itself, or model and view drift apart
        if(b[\enabled] and: hit) { b[\act].value(b) };
    });
    b;
};
~uiBtnSet    = { |b, on| b !? { b[\on] = on; { b[\view].refresh }.defer } };
~uiBtnEnable = { |b, flag| b !? { b[\enabled] = flag; { b[\view].refresh }.defer } };

// a popup is a layout frame plus its own drop layer; PopUpMenu draws in the OS
// style. The layer lives IN THE SAME window (creation order = stacking order),
// so no second window needs focus; a transparent backdrop catches outside clicks
~uiPopup = { |parent, rect, items, index = 0, action|
    var p = ( items: items, index: index, act: action, enabled: true, hover: -1 );
    var uv = UserView(parent, rect).background_(~uiPal.paper);
    p[\view] = uv;
    p[\parent] = parent;
    uv.drawFunc_({ |u|
        var w = u.bounds.width, h = u.bounds.height, font = ~uiMono.(11);
        var str = ((p[\items] ? [])[p[\index]] ? "—").asString;
        var col = if(p[\enabled]) { ~uiPal.ink } { ~uiPal.rule };
        var cy = h / 2;
        Pen.strokeColor = col; Pen.width = 1;
        Pen.strokeRect(Rect(0.5, 0.5, w - 1, h - 1));
        ~uiPenText.(str, 9, cy - (str.bounds(font).height / 2), font, col);
        Pen.fillColor = col;
        Pen.moveTo((w - 17)@(cy - 2.5)); Pen.lineTo((w - 9)@(cy - 2.5));
        Pen.lineTo((w - 13)@(cy + 3)); Pen.fill;
    });
    uv.mouseDownAction_({ if(p[\enabled]) { ~uiPopupOpen.(p) } });
    p;
};
~uiPopupOpen = { |p|
    var rect = p[\view].bounds, items = p[\items] ? [], n = items.size.max(1);
    var rowH = 22, listH = (n * rowH) + 2, font = ~uiMono.(11);
    var host = if(p[\parent].isKindOf(Window)) { p[\parent].view } { p[\parent] };
    var top = rect.top + rect.height, scrim, list;
    if(p[\close].notNil) { p[\close].value };
    if(items.isEmpty) { nil } {
        if(top + listH > host.bounds.height) { top = (rect.top - listH).max(0) };
        // the backdrop is slightly opaque: a fully transparent widget gets no click
        scrim = UserView(p[\parent], Rect(0, 0, host.bounds.width, host.bounds.height))
            .background_(Color(0, 0, 0, 0.01));
        list = UserView(p[\parent], Rect(rect.left, top, rect.width, listH))
            .background_(~uiPal.paper);
        p[\close] = { scrim.remove; list.remove; p[\close] = nil; p[\hover] = -1 };
        scrim.mouseDownAction_({ p[\close].value });
        list.drawFunc_({ |u|
            var w = u.bounds.width;
            Pen.strokeColor = ~uiPal.ink; Pen.width = 1;
            Pen.strokeRect(Rect(0.5, 0.5, w - 1, u.bounds.height - 1));
            items.do { |it, i|
                var y = 1 + (i * rowH), sel = (i == p[\index]), hov = (i == p[\hover]);
                if(sel or: hov) {
                    Pen.fillColor = if(sel) { ~uiPal.ink } { ~uiPal.hi };
                    Pen.fillRect(Rect(1, y, w - 2, rowH));
                };
                ~uiPenText.(it.asString, 9, y + ((rowH - it.asString.bounds(font).height) / 2),
                    font, if(sel) { ~uiPal.paper } { ~uiPal.ink });
            };
        });
        list.mouseMoveAction_({ |u, x, y|
            var h = ((y - 1) / rowH).floor.clip(0, n - 1);
            if(h != p[\hover]) { p[\hover] = h; u.refresh };
        });
        list.mouseUpAction_({ |u, x, y|
            var idx = ((y - 1) / rowH).floor;
            if((idx >= 0) and: { idx < n } and: { x >= 0 } and: { x <= u.bounds.width }) {
                p[\index] = idx;
                p[\close].value;
                p[\view].refresh;
                p[\act].value(idx, p);
            } { p[\close].value };
        });
    };
};
~uiPopupSet    = { |p, idx| p !? { p[\index] = idx; { p[\view].refresh }.defer } };
~uiPopupItems  = { |p, items| p !? { p[\items] = items; p[\index] = p[\index].clip(0, items.size - 1); { p[\view].refresh }.defer } };
~uiPopupEnable = { |p, flag| p !? { p[\enabled] = flag; { p[\view].refresh }.defer } };

// layout dot raster: structure-grid panel (dither) + field card
~uiDrawDither = { |u, cardRect|
    var w = u.bounds.width, h = u.bounds.height;
    Pen.fillColor = ~uiPal.paper2; Pen.fillRect(Rect(0, 0, w, h));
    Pen.fillColor = ~uiPal.ink.copy.alpha_(0.55);
    (0, 4 .. w).do { |x| (0, 4 .. h).do { |y| Pen.fillRect(Rect(x, y, 1, 1)) } };
    Pen.strokeColor = ~uiPal.ink; Pen.width = 1;
    Pen.strokeRect(Rect(0.5, 0.5, w - 1, h - 1));
    cardRect !? { |r| Pen.fillColor = ~uiPal.paper; Pen.fillRect(r) };
};
// coupling depth reads as stroke LENGTH: line weight stays constant, else a
// strong coupling floods the field and the weak ones next to it vanish
~uiLineWidth = 1.1;
~uiLineDash = { |depth, shape|
    var on = 1.5 + (depth.clip(0, 1) * 14);
    if(shape == \noise) { FloatArray[on, 3, on * 0.35, 3] } { FloatArray[on, 3] };
};

~uiPenText = { |str, x, y, font, color, anchor = \left|
    var bw = str.bounds(font).width;
    var ax = switch(anchor, \right, { x - bw }, \middle, { x - (bw / 2) }, { x });
    Pen.stringAtPoint(str, ax@y, font, color);
};

~uiRuler = { |parent, rect, spec, v0, action|
    var uv = UserView(parent, rect).background_(~uiPal.paper);
    var r = (
        view: uv, spec: spec, norm: spec.unmap(v0 ? spec.default).clip(0, 1),
        act: action, enabled: true, fmt: { |v| ~uiFmt.(v, 3) }
    );
    // r[\spec], never the captured argument: ~uiRulerSet/~uiRulerGet already read
    // the slot, so a ruler whose spec was swapped (koppelfeld gain strips, whose
    // ceiling is the class of the CURRENT destination) would otherwise report and
    // act through the spec it was born with while drawing the new one
    var apply = { |px|
        if(r[\enabled]) {
            r[\norm] = ((px - 4) / (uv.bounds.width - 8)).clip(0, 1);
            uv.refresh;
            r[\valTxt] !? { |t| t.string_(r[\fmt].(r[\spec].map(r[\norm]))) };
            r[\act].value(r[\spec].map(r[\norm]));
        };
    };
    uv.drawFunc_({ |u|
        var w = u.bounds.width, y = (u.bounds.height * 0.5).round, x = 4 + (r[\norm] * (w - 8));
        var col = if(r[\enabled]) { ~uiPal.ink } { ~uiPal.rule };
        Pen.width = 1; Pen.strokeColor = col;
        Pen.line(4@y, (w - 4)@y); Pen.stroke;
        Pen.strokeColor = ~uiPal.rule;
        11.do { |i|
            var tx = 4 + (i * (w - 8) / 10);
            Pen.line(tx@(y - if(i % 5 == 0, 6, 3)), tx@y);
        };
        Pen.stroke;
        Pen.strokeColor = col; Pen.width = 2.5;
        Pen.line(4@y, x@y); Pen.stroke;
        Pen.fillColor = col;
        Pen.moveTo((x - 4.5)@(y + 7)); Pen.lineTo(x@(y + 1)); Pen.lineTo((x + 4.5)@(y + 7));
        Pen.fill;
    });
    uv.mouseDownAction_({ |u, x| apply.(x) });
    uv.mouseMoveAction_({ |u, x| apply.(x) });
    r;
};
~uiRulerRow = { |parent, x, y, labelW, rulerW, label, spec, v0, action, fmt|
    var r, txt;
    fmt = fmt ? { |v| ~uiFmt.(v, 3) };
    if(labelW > 0) { ~uiText.(parent, Rect(x, y, labelW, 20), label, 10.5, ~uiPal.ink2) };
    r = ~uiRuler.(parent, Rect(x + labelW, y, rulerW, 20), spec, v0, action);
    txt = ~uiText.(parent, Rect(x + labelW + rulerW + 6, y, 64, 20), fmt.(v0 ? spec.default), 10.5);
    r[\valTxt] = txt; r[\fmt] = fmt;
    r;
};
~uiRulerSet = { |r, v|
    r[\norm] = r[\spec].unmap(v).clip(0, 1);
    { r[\view].refresh; r[\valTxt] !? { |t| t.string_(r[\fmt].(v)) } }.defer;
};
~uiRulerGet    = { |r| r[\spec].map(r[\norm]) };
~uiRulerEnable = { |r, on| r[\enabled] = on; { r[\view].refresh }.defer };

// |b| ≤ 3: beyond that the fifths coordinate stops reading and the pitch drifts
// into a cent tail anyway (lattice — docs/architecture/system/composition.md)
~uiLattice = { |hz|
    var c = 1200 * log2(hz / 94), best;
    (-3..3).do { |b|
        (-8..8).do { |a|
            var d = c - (1200 * a) - (1901.955 * b);
            if(best.isNil or: { d.abs < best[2].abs }) { best = [a, b, d] };
        };
    };
    ( a: best[0], b: best[1], dev: best[2].round.asInteger );
};
~uiCoordStr = { |lat|
    "⟨" ++ lat[\a] ++ ", " ++ lat[\b] ++ "⟩ " ++ if(lat[\dev] >= 0, "+", "−") ++ lat[\dev].abs ++ "¢";
};
~ungHzOf = { |p, v| switch(p[\disp], \note, { v.midicps }, \hz, { v }, { nil }) };
~ungDispLabel = { |p, v|
    var hz = ~ungHzOf.(p, v);
    if(hz.isNil or: { hz <= 0 }) { "" } {
        ~uiCoordStr.(~uiLattice.(hz)) ++ "  " ++ hz.round(0.1) ++ " Hz"
    };
};

~uiDrawLattice = { |u, points|
    var w = u.bounds.width, h = u.bounds.height, aMin = -8, aMax = 8, bMin = -3, bMax = 3;
    var px = { |a| 30 + ((a - aMin) * (w - 60) / (aMax - aMin)) };
    var py = { |b| h - 26 - ((b - bMin) * (h - 52) / (bMax - bMin)) };
    var f9 = ~uiMono.(8.5), cell = (w - 60) / (aMax - aMin);
    (bMin..bMax).do { |b|
        Pen.strokeColor = ~uiPal.rule; Pen.width = if(b == 0, 1.2, 0.6);
        Pen.line(px.(aMin)@py.(b), px.(aMax)@py.(b)); Pen.stroke;
        ~uiPenText.("3" ++ ~uiSup.(b), px.(aMin) - 6, py.(b) - 6, f9, ~uiPal.ink2, \right);
    };
    (aMin..aMax).do { |a|
        Pen.strokeColor = ~uiPal.rule; Pen.width = if(a == 0, 1.2, 0.6);
        Pen.line(px.(a)@py.(bMax), px.(a)@py.(bMin)); Pen.stroke;
        ~uiPenText.("2" ++ ~uiSup.(a), px.(a), h - 22, f9, ~uiPal.ink2, \middle);
    };
    Pen.strokeColor = ~uiPal.ink; Pen.width = 1.2;
    Pen.addOval(Rect(px.(0) - 5, py.(0) - 5, 10, 10)); Pen.stroke;
    points.do { |pt, i|
        var lat, x, y, dx;
        if(pt[\hz].notNil and: { pt[\hz] > 0 }) {
            lat = ~uiLattice.(pt[\hz]);
            x = px.(lat[\a]); y = py.(lat[\b]); dx = lat[\dev] / 100 * cell * 0.5;
            Pen.strokeColor = ~uiPal.ink; Pen.width = 2;
            Pen.line(x@y, (x + dx)@y); Pen.stroke;
            Pen.width = 1.5; Pen.line((x + dx)@(y - 5), (x + dx)@(y + 5)); Pen.stroke;
            Pen.fillColor = ~uiPal.ink;
            Pen.moveTo(x@(y - 6)); Pen.lineTo((x + 6)@y); Pen.lineTo(x@(y + 6)); Pen.lineTo((x - 6)@y);
            Pen.fill;
            ~uiPenText.(pt[\key].asString, x + 7, y + if(i.odd, -14, 3), f9, ~uiPal.ink);
        };
    };
};

~uiDrawRose = { |u, items|
    var w = u.bounds.width, h = u.bounds.height, cx = w / 2, cy = h / 2;
    var rad = (min(w, h) / 2) - 66, n = items.size.max(1), f = ~uiMono.(8.5), pts;
    Pen.strokeColor = ~uiPal.rule; Pen.width = 1;
    Pen.addOval(Rect(cx - rad, cy - rad, 2 * rad, 2 * rad)); Pen.stroke;
    Pen.use {
        Pen.lineDash = FloatArray[2, 3];
        Pen.addOval(Rect(cx - (rad / 2), cy - (rad / 2), rad, rad)); Pen.stroke;
    };
    pts = items.collect { |it, i|
        var ang = (i * 2pi / n) - 0.5pi;
        (cx + (cos(ang) * rad * it[\norm]))@(cy + (sin(ang) * rad * it[\norm]));
    };
    if(pts.size > 2) {
        Pen.fillColor = ~uiPal.ink.copy.alpha_(0.07);
        Pen.moveTo(pts[0]); pts.drop(1).do { |p| Pen.lineTo(p) }; Pen.lineTo(pts[0]);
        Pen.fill;
    };
    items.do { |it, i|
        var ang = (i * 2pi / n) - 0.5pi, c = cos(ang), s = sin(ang), p = pts[i];
        var lx = cx + (c * (rad + 12)), ly = cy + (s * (rad + 12));
        var anchor = if(c.abs < 0.2) { \middle } { if(c > 0) { \left } { \right } };
        Pen.strokeColor = ~uiPal.rule; Pen.width = 0.6;
        Pen.line(cx@cy, (cx + (c * rad))@(cy + (s * rad))); Pen.stroke;
        Pen.strokeColor = ~uiPal.ink; Pen.width = 2;
        Pen.line(cx@cy, p); Pen.stroke;
        Pen.fillColor = ~uiPal.ink; Pen.addOval(Rect(p.x - 3, p.y - 3, 6, 6)); Pen.fill;
        ~uiPenText.(it[\label].asString, lx, ly - 6, f, ~uiPal.ink2, anchor);
    };
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
        ~uiPopupItems.(~mixerPresetPop, if(items.isEmpty) { ["—"] } { items });
    };
};

// ----- GUI: authoritative resync of ALL layer rulers from ~ungVals — after
// bulk operations (preset/random), bypassing per-key ~ungTunerSync
~ungTunerRefresh = ~ungTunerRefresh ? ();   // \layer -> { lattice/rose refresh }
~ungSyncAll = { |layer|
    layer = layer.asSymbol;
    if(~ungTuner[layer].notNil and: { ~ungTunerEz[layer].notNil }) {
        var spec = ~ungSpecOf.(layer);
        if(spec.notNil) {
            spec.params.do { |p|
                var v = (~ungVals[layer] !? { ~ungVals[layer][p.key] }) ? p.spec.default;
                var r = ~ungTunerEz[layer][p.key];
                var t = ~ungTunerNoteTxt[layer] !? { ~ungTunerNoteTxt[layer][p.key] };
                if(r.notNil) { ~uiRulerSet.(r, v) };
                if(t.notNil) { { t.string_(~ungDispLabel.(p, v)) }.defer };
            };
            ~ungTunerRefresh[layer] !? { |f| f.value };
        };
    };
};


// ----- GUI: layer tuner window (layout: docs/architecture/app/ui/Station.dc.html) -----
~ungBuildTuner = { |layer|
    var spec, freqs, tones, w, h, off, scr, winRect, win;
    var x0 = 28, top = 84, latH = 200, rowH = 22, colW = 460, roseS = 340, midX, rightX, by;
    var latView, roseView, valOf, normOf;
    layer = layer.asSymbol;
    spec  = ~ungSpecOf.(layer);
    freqs = spec.params.select { |p| p[\group] == \freq };
    tones = spec.params.select { |p| p[\group] == \tone };
    valOf  = { |p| (~ungVals[layer] !? { ~ungVals[layer][p.key] }) ? p.spec.default };
    normOf = { |p| p.spec.unmap(valOf.(p)).clip(0, 1) };
    midX   = x0 + colW + 40;
    rightX = midX + roseS + 40;
    by = top + max(latH + 14 + (freqs.size * rowH), max(roseS + 8, tones.size * rowH)) + 14;
    w = rightX + 118 + 150 + 70 + 28;
    h = by + 26 + 18;

    // close the previous window best-effort (a dead Qt object — §6) and reset
    // ALL layer slots: during the rebuild nobody may touch the old widgets
    if(~ungTuner[layer].notNil) { try { ~ungTuner[layer].close } };
    ~ungTuner[layer]        = nil;
    ~ungTunerEz[layer]      = ();
    ~ungTunerNoteTxt[layer] = ();
    ~ungTunerSync[layer]    = nil;
    ~ungTunerRefresh[layer] = nil;

    // wrap AND clamp the window position to the screen — otherwise the offset
    // grows all session and the window "opens" off screen
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
    // do NOT chain `win = dict[k] = Window(...)` — that returns the dict (§6)
    win = Window("UNGRUND · " ++ layer, winRect).background_(~uiPal.paper);
    ~ungTuner[layer] = win;

    ~uiCap.(win, Rect(x0, 12, 700, 14), "ungrund · tuner · " ++ (~uiPremise[layer] ? "") ++ " · live Ndef");
    ~uiTitle.(win, Rect(x0, 26, 500, 36), (~uiPhi[layer] ? "") ++ " " ++ layer);
    ~uiText.(win, Rect(w - 348, 32, 320, 16),
        spec.params.size.asString ++ " params · " ++ freqs.size ++ " pitch · " ++ tones.size ++ " tone",
        10.5, ~uiPal.ink2, false, \right);
    ~uiRule.(win, Rect(0, 68, w, 1));
    ~uiRule.(win, Rect(midX - 20, 69, 1, h - 69));
    ~uiRule.(win, Rect(rightX - 20, 69, 1, h - 69));

    ~uiCap.(win, Rect(x0, top - 16, colW, 14), "pitch · lattice 94 Hz · 2ᵃ · 3ᵇ");
    latView = UserView(win, Rect(x0, top, colW, latH)).background_(~uiPal.paper);
    latView.drawFunc_({ |u|
        ~uiDrawLattice.(u, freqs.collect { |p| ( key: p.key, hz: ~ungHzOf.(p, valOf.(p)) ) });
    });
    freqs.do { |p, i|
        var y = top + latH + 14 + (i * rowH), r, t;
        ~uiText.(win, Rect(x0, y, 64, 20), p.key.asString, 10.5, ~uiPal.ink, true);
        t = ~uiText.(win, Rect(x0 + 68, y, 212, 20), ~ungDispLabel.(p, valOf.(p)), 10.5);
        r = ~uiRuler.(win, Rect(x0 + 284, y, 150, 20), p.spec, valOf.(p),
            { |v| ~setParam.(layer, p.key, v) });
        ~ungTunerEz[layer][p.key]      = r;
        ~ungTunerNoteTxt[layer][p.key] = t;
    };
    if(freqs.notEmpty) { ~uiBtn.(win, Rect(x0, by, 130, 26), "random pitch", { ~rndFreq.(layer) }) };

    // rose + tone rulers
    ~uiCap.(win, Rect(midX, top - 16, roseS, 14), "rose · tone");
    roseView = UserView(win, Rect(midX, top, roseS, roseS)).background_(~uiPal.paper);
    roseView.drawFunc_({ |u|
        ~uiDrawRose.(u, tones.collect { |p| ( label: p.key, norm: normOf.(p) ) });
    });
    if(tones.notEmpty) { ~uiBtn.(win, Rect(midX, by, 110, 26), "random rose", { ~rndParams.(layer) }) };
    ~uiBtn.(win, Rect(midX + 118, by, 90, 26), "defaults", { ~ungApplyDefaults.(layer) });

    ~uiCap.(win, Rect(rightX, top - 16, 300, 14), "tone");
    tones.do { |p, i|
        var y = top + (i * rowH);
        var r = ~uiRulerRow.(win, rightX, y, 118, 150, p.key.asString ++ (p[\unit] ? ""),
            p.spec, valOf.(p), { |v| ~setParam.(layer, p.key, v) });
        if(~isMapped.(layer, p.key)) {
            ~uiText.(win, Rect(rightX + 118 + 150 + 58, y, 14, 20), "⟳", 11, ~uiPal.ink2);
        };
        ~ungTunerEz[layer][p.key] = r;
    };
    ~uiBtn.(win, Rect(w - 100, by, 72, 26), "close", { if(win.notNil) { win.close } });

    ~ungTunerRefresh[layer] = { { latView.refresh; roseView.refresh }.defer };
    // GUI sync hook <- ~setParam (random/presets)
    ~ungTunerSync[layer] = { |key, v|
        var r = ~ungTunerEz[layer] !? { ~ungTunerEz[layer][key] };
        var t = ~ungTunerNoteTxt[layer] !? { ~ungTunerNoteTxt[layer][key] };
        var p = ~ungSpecOf.(layer).params.detect { |e| e.key == key };
        if(r.notNil) { ~uiRulerSet.(r, v) };
        if(t.notNil and: { p.notNil }) { { t.string_(~ungDispLabel.(p, v)) }.defer };
        ~ungTunerRefresh[layer] !? { |f| f.value };
    };

    // guard: a deferred onClose of the OLD window must not wipe the registries
    // of the NEW one (§6)
    win.onClose_({
        if(~ungTuner[layer] === win) {
            ~ungTuner[layer]        = nil;
            ~ungTunerEz[layer]      = nil;
            ~ungTunerNoteTxt[layer] = nil;
            ~ungTunerSync[layer]    = nil;
            ~ungTunerRefresh[layer] = nil;
        };
    });
    // one .defer(0.3) after layout: an immediate .front on a heavy Qt window
    // outruns layout and the window stays invisible (§6)
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
