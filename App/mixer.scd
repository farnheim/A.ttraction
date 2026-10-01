// App/mixer.scd — MIXER: per-machine vol + two fx sends, one aggregator per
// bus, master (LeakDC + Limiter), solo/mute, recorder, mixer window (~openMixer).
// The output stage only: nothing here touches the field. The Deck also hosts
// the fingerprint block (fingerprint.scd), which only sets the law of dice.


// ===== CONFIG — edit here ============================================
(
// vol -> master; sendRev/sendDly -> §K.1/§K.2 tables (independent by canon).
// `? ()`: the live mix is STATE and survives a hot reload; the table only seeds
// a fresh session (the auto-preset then overrides it)
~cfg_mixer = ~cfg_mixer ? (
    master:  0.9,

    levels: (
        //            vol    sendRev (§K.1)  sendDly (§K.2)
        alpha:   ( vol: 0.85, sendRev: 0.0825, sendDly: 0.03 ),
        delta:   ( vol: 0.80, sendRev: 0.0675, sendDly: 0.0 ),   // §K.2: binde is not in the delay table
        epsilon: ( vol: 0.75, sendRev: 0.0225, sendDly: 0.0 ),   // §K.1: self-diffuse — low send; §K.2: no delay
        zeta:    ( vol: 0.75, sendRev: 0.0225, sendDly: 0.0 ),   // §K.2: kratzer is not in the delay table
        theta:   ( vol: 0.80, sendRev: 0.024, sendDly: 0.0 )    // §K.2 zero is a BAN, not taste: echo would refill what the class law exhausts
    )
);

// fallback levels for a layer missing from the table (new synths/*.scd)
~mixerDefaultLevel = ( vol: 0.7, sendRev: 0.0, sendDly: 0.0 );

// master-sum recorder: file format and dir (relative to project root)
~cfg_recorder = ( header: "wav", sample: "int24", dir: "recordings" );

// the fingerprint canvas of the deck: a cell holds one whole glyph card (5:6,
// so a line meets the glyph edge to edge); line width and the gap of a double
// line in px
~cfg_fpView = ( cell: 18 @ 22, line: 2, gap: 3 );


// ===== LOGIC — routers + master + GUI ================================
~mixerLayers = ~activeLayers ? ~ungSpecs.keys.asArray.sort;

// ensure a level entry for every active layer
~mixerLayers.do { |layer|
    if(~cfg_mixer.levels[layer].isNil) {
        ~cfg_mixer.levels[layer] = ~mixerDefaultLevel.copy;
    };
};

// layer router = the channel fader: dry -> ~busDry only (the aggregator below
// collects the sends — exactly ONE writer per bus); volumes belong to the
// performer (2026-07-18)
~mixerLayers.do { |layer|
    var routerKey = ("mix_" ++ layer).asSymbol;
    var lv = ~cfg_mixer.levels[layer];
    Ndef(routerKey, { |vol = 0|
        var src = Ndef(layer.asSymbol).ar(2);
        src * vol.lag(0.1)
    });
    Ndef(routerKey).set(\vol, lv.vol);
    Ndef(routerKey).fadeTime = 1;
    Ndef(routerKey).play(out: ~busDry.index, numChannels: 2);
};

// send aggregators: ONE PER BUS (the §K.1/§K.2 tables are independent), each the
// sole writer of its bus (ReplaceOut: no accumulation); the send_<layer> param
// names coincide — the Ndef tells them apart. Sends tap the ROUTER, not the
// layer: post-fader, as on a console — vol, mute and solo carry the echo along
~mixerSendMix = {
    Mix(~mixerLayers.collect { |layer|
        var amt = NamedControl.kr(("send_" ++ layer).asSymbol, 0);
        Ndef(("mix_" ++ layer).asSymbol).ar(2) * amt.lag(0.1);
    })
};

Ndef(\fxsendRev, { ReplaceOut.ar(~busFxSendRev.index, ~mixerSendMix.value) });
Ndef(\fxsendDly, { ReplaceOut.ar(~busFxSendDly.index, ~mixerSendMix.value) });

// which -> aggregator Ndef key (~mixSet/~mixSolo/~mixUnsolo lookup)
~mixerSendAgg = ( sendRev: \fxsendRev, sendDly: \fxsendDly );

~mixerSendAgg.keysValuesDo { |which, aggKey|
    ~mixerLayers.do { |layer|
        Ndef(aggKey).set(
            ("send_" ++ layer).asSymbol, ~cfg_mixer.levels[layer][which]
        );
    };
    Ndef(aggKey).fadeTime = 1;
    // NO .play: the body already writes via ReplaceOut, a monitor would be a SECOND writer
};

// master: (dry + fx return), LeakDC, tape (§K.6, tape.scd), Limiter. Everything
// before the Limiter is ONE function: render_master's no-limiter probe calls it
// too, so the probe cannot fall out of step with the master
~mixerMasterPre = { |sig|
    sig = LeakDC.ar(sig);
    ~tapeStage !? { |stage| sig = stage.(sig) };
    sig
};
~mixerMasterSource = { |amp = 0.9|
    var dry, fx, sig;
    // InFeedback, not In: reads the buses whatever the node order
    dry = InFeedback.ar(~busDry.index, 2);
    fx  = InFeedback.ar(~busFxReturn.index, 2);
    sig = ~mixerMasterPre.(dry + fx);
    sig = Limiter.ar(sig, 0.95, 0.01);               // §K.4: limiter 0.95
    sig = sig * amp.lag(0.05);
    sig
};
// a new source re-runs the function, so a reloaded tape.scd is picked up
~mixerRebuildMaster = { Ndef(\master, ~mixerMasterSource) };
~mixerRebuildMaster.value;
Ndef(\master).set(\amp, ~cfg_mixer.master);
Ndef(\master).fadeTime = 1;
Ndef(\master).play(out: 0, numChannels: 2);

// GUI sync hook <- ~mixSet (set by the mixer window; nil without GUI)
~mixerGuiSync = ~mixerGuiSync;

// live setters for editing / MIDI / sequencer:
// ~mixSet.(\alpha, \vol, 0.5) / ~mixSet.(\alpha, \sendRev, 0.8)
// / ~mixSet.(\alpha, \sendDly, 0.2) / ~masterSet.(v)
~mixSet = { |layer, which = \vol, value|
    var agg = ~mixerSendAgg[which];
    if(~cfg_mixer.levels[layer].isNil) { ~cfg_mixer.levels[layer] = ~mixerDefaultLevel.copy };
    ~cfg_mixer.levels[layer][which] = value;
    // for a muted / solo-hidden layer only the stored vol moves — unmute
    // restores the value the slider shows right now
    if(agg.notNil) {
        Ndef(agg).set(("send_" ++ layer).asSymbol, value);
    } {
        if(~mixLayerAudible.(layer)) { Ndef(("mix_" ++ layer).asSymbol).set(\vol, value) };
    };
    if(~mixerGuiSync.notNil) { ~mixerGuiSync.(layer, which, value) };
};
~masterSet = { |value|
    Ndef(\master).set(\amp, value); ~cfg_mixer.master = value;
    if(~mixerGuiSync.notNil) { ~mixerGuiSync.(\master, \amp, value) };
};

// mute and solo meet in ONE apply function; levels are read from ~cfg_mixer
// (never overwritten with zeros) — clearing mute/solo restores the original mix
~mixMuted = ~mixMuted ? ();   // layer -> true; survives reopen/reload
~mixLayerAudible = { |layer|
    (~mixMuted[layer] != true) and: { ~mixSoloCur.isNil or: { ~mixSoloCur == layer } }
};
~mixApplyLevels = {
    ~mixerLayers.do { |l|
        var on = ~mixLayerAudible.(l);
        var lv = ~cfg_mixer.levels[l];
        Ndef(("mix_" ++ l).asSymbol).set(\vol, on.if({ lv.vol }, 0));
        ~mixerSendAgg.keysValuesDo { |which, agg|
            Ndef(agg).set(("send_" ++ l).asSymbol, lv[which]);
        };
    };
};

~mixSolo = { |layer|
    ~mixSoloCur = layer; ~mixApplyLevels.value;
    if(~mixerRefreshSolo.notNil) { ~mixerRefreshSolo.value };
};
~mixUnsolo = {
    ~mixSoloCur = nil; ~mixApplyLevels.value;
    if(~mixerRefreshSolo.notNil) { ~mixerRefreshSolo.value };
};
~mixSoloToggle = { |layer|
    if(~mixSoloCur == layer) { ~mixUnsolo.value } { ~mixSolo.(layer) };
};

~mixMuteToggle = { |layer|
    ~mixMuted[layer] = (~mixMuted[layer] != true);
    ~mixApplyLevels.value;
    if(~mixerRefreshMute.notNil) { ~mixerRefreshMute.value };
};
~mixAllMuted = { ~mixerLayers.every { |l| ~mixMuted[l] == true } };
~mixMuteAllToggle = {
    var mute = ~mixAllMuted.value.not;
    ~mixerLayers.do { |l| ~mixMuted[l] = mute };
    ~mixApplyLevels.value;
    if(~mixerRefreshMute.notNil) { ~mixerRefreshMute.value };
};

// restore mute/solo on freshly built routers/aggregators
~mixApplyLevels.value;

// the recorder writes bus 0 from the TAIL of the root group (after
// Ndef(\master)) — the file gets exactly what is heard
~mixRecOn   = ~mixRecOn ? false;   // survives reload
~mixRecPath = ~mixRecPath;

~mixRecToggle = {
    if(~mixRecOn) {
        s.stopRecording;
        ~mixRecOn = false;
        ("MIXER rec — запись остановлена: " ++ ~mixRecPath).postln;
    } {
        var dir = ~appDir.dirname +/+ ~cfg_recorder.dir;
        if(File.exists(dir).not) { File.mkdir(dir) };
        ~mixRecPath = dir +/+
            ("ungrund_" ++ Date.localtime.stamp ++ "." ++ ~cfg_recorder.header);
        s.recHeaderFormat = ~cfg_recorder.header;
        s.recSampleFormat = ~cfg_recorder.sample;
        s.record(~mixRecPath, bus: 0, numChannels: 2);
        ~mixRecOn = true;
        ("MIXER rec — пишу мастер-сумму: " ++ ~mixRecPath).postln;
    };
    ~mixerRecSync.value;
};

// update record-button visual from ~mixRecOn (no-op without window)


// ===== GUI — Ungrund window (ui kit) ================================
~mixerEz = ~mixerEz ? (); ~mixerSoloBtn = ~mixerSoloBtn ? (); ~mixerMuteBtn = ~mixerMuteBtn ? ();
~mixerFx = ~mixerFx ? (); ~mixerFp = ~mixerFp ? ();

// the fingerprint: its field on a canvas of cells, the three knobs of the
// next generation, generate, the switch of the law, a status line
~mixerFpHeight = { (~cfg_fp.rows * ~cfg_fpView.cell.y) + 20 };
// the model stands in the middle of the canvas, whatever corner it grew in
// and whatever field it was drawn on (a preset keeps its own text)
~mixerFpCentre = { |cells, rows, cols|
    var r0 = inf, r1 = -inf, c0 = inf, c1 = -inf;
    cells.do { |row, r| row.do { |sym, c|
        if(sym != " ") { r0 = r0.min(r); r1 = r1.max(r); c0 = c0.min(c); c1 = c1.max(c) };
    } };
    if(r1 < 0) { [0, 0] } {
        [((rows - (r1 - r0 + 1)) div: 2) - r0, ((cols - (c1 - c0 + 1)) div: 2) - c0]
    }
};
~mixerFpStatus = {
    ~fpCurrent !? { |fp| "seed " ++ fp[\seed] } ? "no fingerprint — generate one"
};
~mixerFpBuild = { |page, x, y|
    var cw = ~cfg_fpView.cell.x, ch = ~cfg_fpView.cell.y, cols = ~cfg_fp.cols, rows = ~cfg_fp.rows;
    var cx = x + (cols * cw) + 28, fmt2 = { |v| ~uiFmt.(v, 2) }, wid = ();
    ~uiCap.(page, Rect(x, y, 400, 14), "fingerprint");
    wid[\canvas] = UserView(page, Rect(x, y + 20, cols * cw, rows * ch)).background_(~uiPal.paper).drawFunc_({ |u|
        var live = ~netLayers.value;
        Pen.strokeColor = ~uiPal.grey; Pen.width = 1;
        Pen.strokeRect(Rect(0.5, 0.5, u.bounds.width - 1, u.bounds.height - 1));
        Pen.fillColor = ~uiPal.grey;
        (0 .. cols).do { |i| (0 .. rows).do { |j| Pen.addRect(Rect(i * cw, j * ch, 1, 1)) } };
        Pen.fill;
        ~fpCurrent !? { |fp|
            var dim = if(~fpLive[\on] == true) { ~uiPal.ink } { ~uiPal.grey };
            var cells = fp[\text].collect { |row| ~fpCellsOf.(row) }, off = ~mixerFpCentre.(cells, rows, cols);
            cells.do { |row, r|
                row.do { |sym, c|
                    var l = ~fpLayerOf[sym], x = (c + off[1]) * cw, y = (r + off[0]) * ch;
                    if(l.notNil) {
                        ~uiGlyphPen.(x, y, ch, l, if(live.includes(l)) { ~uiPal.ink } { ~uiPal.grey });
                    } { ~uiBoxPen.(x, y, cw, ch, sym, dim, ~cfg_fpView.line, ~cfg_fpView.gap) };
                };
            };
        };
    });
    [\complexity, \links, \symmetry].do { |k, i|
        wid[k] = ~uiRulerRow.(page, cx, y + 20 + (i * 28), 90, 190, k.asString, ControlSpec(0, 1), ~fpLive[k],
            { |v| ~fpLive[k] = v }, fmt2);
    };
    wid[\generate] = ~uiBtn.(page, Rect(cx, y + 116, 84, 24), "generate", { ~fpGenerate.(nil, nil, nil, Date.seed) });
    wid[\dice] = ~uiBtn.(page, Rect(cx + 90, y + 116, 84, 24), "→ dice", { ~fpSet.((~fpLive[\on] == true).not) },
        ~fpLive[\on] == true);
    wid[\dice][\enabled] = ~fpCurrent.notNil;
    wid[\status] = ~uiText.(page, Rect(cx, y + 152, 560, 20), ~mixerFpStatus.value, nil, ~uiPal.grey);
    ~mixerFp = wid;
    ~fpViews[\deck] = {
        {
            if(wid[\canvas].isClosed.not) {
                wid[\canvas].refresh;
                wid[\status].string_(~mixerFpStatus.value);
                ~uiBtnSet.(wid[\dice], ~fpLive[\on] == true);
                ~uiBtnEnable.(wid[\dice], ~fpCurrent.notNil);
                [\complexity, \links, \symmetry].do { |k| ~uiRulerSet.(wid[k], ~fpLive[k]) };
            };
        }.defer
    };
};

~mixerBuild = {
    var pal = ~uiPal, layers = ~mixerLayers, rowH = 28, tableY = 110;
    var footY = tableY + (layers.size * rowH) + 6, fpY = footY + 44;
    var fpBottom = if(~fpLive.notNil) { fpY + 20 + (~cfg_fp.rows * ~cfg_fpView.cell.y) };
    var barH = (~cfg_presets.btnH * 2) + ~cfg_presets.gap;
    // the presets stand in a column beside the fingerprint, the master and the
    // tape stage over it on the right: both end on the canvas's lower edge.
    // Without a fingerprint they stand in its place and under the echo
    var presetX = if(fpBottom.notNil) { 28 + (~cfg_fp.cols * ~cfg_fpView.cell.x) + 28 } { 28 };
    var presetY = fpBottom !? { |b| b - (108 + barH) } ? fpY;
    var fxX = 1010, fxY = 84, echoEnd = fxY + if(~cfg_effects.notNil) { 158 } { 0 };
    var tapeH = ~tapeGui !? { (~tapeGuiHeight ? 0) + 42 } ? 0;
    var masterY = fpBottom !? { |b| (b - 44).max(echoEnd + tapeH) } ? (echoEnd + tapeH);
    var tapeY = masterY - tapeH;
    var leftH = fpBottom !? { |b| b + 28 } ? (presetY + 108 + barH + 28);
    var right = fxX + 316, w = right + 28, h = leftH.max(masterY + 78).max(440);
    var fmt2 = { |v| ~uiFmt.(v, 2) };
    var fxModeItems = [
        "1 · 1 tap", "2 · 2 tap", "3 · 1+2 tap", "4 · 1+2+3 echo",
        "5 · 1 +rev", "6 · 2 +rev", "7 · 3 +rev", "8 · 1+2 +rev",
        "9 · 2+3 +rev", "10 · 1+3 +rev", "11 · all +rev", "12 · rev only"
    ];
    var scr = Window.availableBounds, win, page, mkGlyph;

    ~mixerWin !? { |x| try { x.close } };
    w = w.min(scr.width); h = h.min(scr.height);
    win = Window("NET · deck", Rect(scr.left + ((scr.width - w) / 2).max(0), scr.top + 40, w, h))
        .background_(pal.paper);
    ~mixerWin = win;
    ~mixerEz = (); ~mixerSoloBtn = (); ~mixerMuteBtn = (); ~mixerFx = ();

    ~uiRule.(win, Rect(0, 66, w, 1)).resize_(2);
    page = ~uiPage.(win.view, right - 28);
    ~uiTitle.(page, Rect(28, 20, 300, 36), "Deck");
    ~uiNav.(page, right, 26, [["matrix", { ~openMatrix }], ["machines", { ~openMachines }]]);
    ~uiRule.(page, Rect(fxX - 24, 67, 1, h - 67)).resize_(4);

    ~uiCap.(page, Rect(28, tableY - 26, 100, 14), "machine");
    ~uiCap.(page, Rect(172, tableY - 26, 100, 14), "vol");
    ~uiCap.(page, Rect(372, tableY - 26, 100, 14), "rev");
    ~uiCap.(page, Rect(572, tableY - 26, 100, 14), "dly");
    ~uiCap.(page, Rect(776, tableY - 26, 44, 14), "mute");
    ~uiCap.(page, Rect(832, tableY - 26, 44, 14), "solo");
    layers.do { |layer, i|
        var y = tableY + (i * rowH);
        var lv = ~cfg_mixer.levels[layer] ? ~mixerDefaultLevel;
        ~uiGlyph.(page, Rect(28, y + 1, ~uiGlyphSize.x, ~uiGlyphSize.y), layer);
        ~uiText.(page, Rect(52, y, 110, 20), layer.asString, ~uiType.label, pal.ink, true);
        ~mixerEz[layer] = (
            vol: ~uiRulerRow.(page, 172, y, 0, 140, "", ControlSpec(0, 1, \lin, 0, lv.vol), lv.vol,
                { |v| ~mixSet.(layer, \vol, v) }, fmt2),
            sendRev: ~uiRulerRow.(page, 372, y, 0, 140, "", ControlSpec(0, 1, \lin, 0, lv.sendRev), lv.sendRev,
                { |v| ~mixSet.(layer, \sendRev, v) }, fmt2),
            sendDly: ~uiRulerRow.(page, 572, y, 0, 140, "", ControlSpec(0, 1, \lin, 0, lv.sendDly), lv.sendDly,
                { |v| ~mixSet.(layer, \sendDly, v) }, fmt2)
        );
        ~mixerMuteBtn[layer] = ~uiBtn.(page, Rect(776, y - 2, 44, 24), "⊘",
            { ~mixMuteToggle.(layer) }, ~mixMuted[layer] == true);
        ~mixerSoloBtn[layer] = ~uiBtn.(page, Rect(832, y - 2, 44, 24), "◎",
            { ~mixSoloToggle.(layer) }, ~mixSoloCur == layer);
    };
    ~mixerMuteAllBtn = ~uiBtn.(page, Rect(776, footY, 44, 24), "⊘", { ~mixMuteAllToggle.value }, ~mixAllMuted.value);
    ~mixerSoloAllBtn = ~uiBtn.(page, Rect(832, footY, 44, 24), "◎", { ~mixUnsolo.value }, ~mixSoloCur.notNil);
    if(~fpLive.notNil) { ~mixerFpBuild.(page, 28, fpY) };
    ~uiCap.(page, Rect(presetX, presetY, 260, 14), "mixer preset");
    ~preset.bar(page, presetX, presetY + 20, \mixer);
    ~uiCap.(page, Rect(presetX, presetY + 88, 380, 14), "project · machines + mixer + matrix");
    ~preset.bar(page, presetX, presetY + 108, \project);

    mkGlyph = { |x, y, modeFn|
        var uv = UserView(page, Rect(x, y, 76, 24)).background_(pal.paper);
        uv.drawFunc_({ |u| ~uiDrawEcho.(u, modeFn.value) });
        uv
    };
    if(~cfg_effects.notNil) {
        var dlyGl, revGl;
        ~uiCap.(page, Rect(fxX, fxY, 380, 14), "echo");
        ~uiText.(page, Rect(fxX, fxY + 22, 40, 20), "echo");
        dlyGl = mkGlyph.(fxX + 42, fxY + 20, { ~cfg_effects.dly_mode });
        ~mixerFx[\dlyMode] = ~uiPopup.(page, Rect(fxX + 126, fxY + 20, 190, 24), fxModeItems,
            (~cfg_effects.dly_mode - 1).clip(0, 11), { |idx|
                Ndef(\space_echo_dly).set(\mode, idx + 1);
                ~cfg_effects.dly_mode = idx + 1;
                dlyGl.refresh;
            });
        ~uiText.(page, Rect(fxX, fxY + 54, 40, 20), "rev");
        revGl = mkGlyph.(fxX + 42, fxY + 52, { ~cfg_effects.rev_mode });
        ~mixerFx[\revMode] = ~uiPopup.(page, Rect(fxX + 126, fxY + 52, 190, 24), fxModeItems,
            (~cfg_effects.rev_mode - 1).clip(0, 11), { |idx|
                Ndef(\space_echo_rev).set(\mode, idx + 1);
                ~cfg_effects.rev_mode = idx + 1;
                revGl.refresh;
            });
        ~mixerFx[\bass] = ~uiRulerRow.(page, fxX, fxY + 86, 42, 190, "bass",
            ControlSpec(-1, 1, \lin, 0, ~cfg_effects.rev_bass), ~cfg_effects.rev_bass, { |v|
                [\space_echo_rev, \space_echo_dly].do { |n| Ndef(n).set(\bass, v) };
                ~cfg_effects.rev_bass = v; ~cfg_effects.dly_bass = v;
            }, fmt2);
        ~mixerFx[\treble] = ~uiRulerRow.(page, fxX, fxY + 114, 42, 190, "treble",
            ControlSpec(-1, 1, \lin, 0, ~cfg_effects.rev_treble), ~cfg_effects.rev_treble, { |v|
                [\space_echo_rev, \space_echo_dly].do { |n| Ndef(n).set(\treble, v) };
                ~cfg_effects.rev_treble = v; ~cfg_effects.dly_treble = v;
            }, fmt2);
        ~mixerFx[\dlyGlyph] = dlyGl; ~mixerFx[\revGlyph] = revGl;
    };
    ~tapeGui !? { |gui|
        ~uiCap.(page, Rect(fxX, tapeY, 380, 14), "tape");
        gui.(page, fxX, tapeY + 20);
    };
    ~uiCap.(page, Rect(fxX, masterY, 380, 14), "master");
    ~mixerEz[\master] = ~uiRulerRow.(page, fxX, masterY + 22, 42, 130, "vol",
        ControlSpec(0, 1, \lin, 0, ~cfg_mixer.master), ~cfg_mixer.master, { |v| ~masterSet.(v) }, fmt2);
    ~mixerRecBtn = ~uiBtn.(page, Rect(fxX + 246, masterY + 20, 70, 24), ["● rec", "■ rec"],
        { ~mixRecToggle.value }, ~mixRecOn);

    win.onClose_({
        if(~mixerWin === win) {
            ~mixerWin = nil; ~mixerEz = (); ~mixerSoloBtn = (); ~mixerMuteBtn = ();
            ~mixerRecBtn = nil; ~mixerMuteAllBtn = nil; ~mixerSoloAllBtn = nil; ~mixerFx = ();
            ~tapeWid = ();
            ~mixerFp = (); ~fpViews !? { |v| v.removeAt(\deck) };
        };
    });
    { if(win.isClosed.not) { win.front } }.defer(0.3);
};
~openMixer = { { ~mixerBuild.value }.defer };

~mixerGuiSync = { |layer, which, value|
    ~mixerEz[layer] !? { |row|
        if(layer == \master) { ~uiRulerSet.(row, value) } { row[which] !? { |r| ~uiRulerSet.(r, value) } };
    };
};
~mixerRefreshMute = {
    ~mixerMuteBtn.keysValuesDo { |l, b| ~uiBtnSet.(b, ~mixMuted[l] == true) };
    ~mixerMuteAllBtn !? { |b| ~uiBtnSet.(b, ~mixAllMuted.value) };
};
~mixerRefreshSolo = {
    ~mixerSoloBtn.keysValuesDo { |l, b| ~uiBtnSet.(b, ~mixSoloCur == l) };
    ~mixerSoloAllBtn !? { |b| ~uiBtnSet.(b, ~mixSoloCur.notNil) };
};
~mixerRecSync = { ~uiBtnSet.(~mixerRecBtn, ~mixRecOn) };

"mixer — ~openMixer".postln;
)
