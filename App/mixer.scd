// App/mixer.scd — the output stage and the Deck window (~openMixer); docs: docs/architecture/app/code-notes.md

// ===== CONFIG — edit here ============================================
(
// `? ()`: the live mix is state and survives a hot reload; the table only seeds a fresh session
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

~mixerDefaultLevel = ( vol: 0.7, sendRev: 0.0, sendDly: 0.0 );

~cfg_recorder = ( header: "wav", sample: "int24", dir: "recordings" );

// one glyph card (5:6) per cell, so a line meets the glyph edge to edge
~cfg_fpView = ( cell: 18 @ 22, line: 2, gap: 3 );

// ===== LOGIC — routers + master + GUI ================================
~mixerLayers = ~netLayers.value;

~mixerLayers.do { |layer|
    if(~cfg_mixer.levels[layer].isNil) {
        ~cfg_mixer.levels[layer] = ~mixerDefaultLevel.copy;
    };
};

// dry -> ~busDry only: the sends are collected by the aggregators, ONE writer per bus
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

// one aggregator per send bus, its sole writer (ReplaceOut); sends tap the router: post-fader
~mixerSendMix = {
    Mix(~mixerLayers.collect { |layer|
        var amt = NamedControl.kr(("send_" ++ layer).asSymbol, 0);
        Ndef(("mix_" ++ layer).asSymbol).ar(2) * amt.lag(0.1);
    })
};

Ndef(\fxsendRev, { ReplaceOut.ar(~busFxSendRev.index, ~mixerSendMix.value) });
Ndef(\fxsendDly, { ReplaceOut.ar(~busFxSendDly.index, ~mixerSendMix.value) });

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

// everything before the Limiter is ONE function: render_master's probe calls it too
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

// which: \vol | \sendRev | \sendDly
~mixSet = { |layer, which = \vol, value|
    var agg = ~mixerSendAgg[which];
    if(~cfg_mixer.levels[layer].isNil) { ~cfg_mixer.levels[layer] = ~mixerDefaultLevel.copy };
    ~cfg_mixer.levels[layer][which] = value;
    // a muted / solo-hidden layer only stores its vol: unmute restores what the slider shows
    if(agg.notNil) {
        Ndef(agg).set(("send_" ++ layer).asSymbol, value);
    } {
        if(~mixLayerAudible.(layer)) { Ndef(("mix_" ++ layer).asSymbol).set(\vol, value) };
    };
    ~mixerGuiSync.(layer, which, value);
};
~masterSet = { |value|
    Ndef(\master).set(\amp, value); ~cfg_mixer.master = value;
    ~mixerGuiSync.(\master, \amp, value);
};

// levels are never overwritten with zeros: clearing mute/solo restores the mix
~mixMuted = ~mixMuted ? ();
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
    ~mixerRefreshSolo.value;
};
~mixUnsolo = {
    ~mixSoloCur = nil; ~mixApplyLevels.value;
    ~mixerRefreshSolo.value;
};
~mixSoloToggle = { |layer|
    if(~mixSoloCur == layer) { ~mixUnsolo.value } { ~mixSolo.(layer) };
};

~mixMuteToggle = { |layer|
    ~mixMuted[layer] = (~mixMuted[layer] != true);
    ~mixApplyLevels.value;
    ~mixerRefreshMute.value;
};
~mixAllMuted = { ~mixerLayers.every { |l| ~mixMuted[l] == true } };
~mixMuteAllToggle = {
    var mute = ~mixAllMuted.value.not;
    ~mixerLayers.do { |l| ~mixMuted[l] = mute };
    ~mixApplyLevels.value;
    ~mixerRefreshMute.value;
};

~mixApplyLevels.value;

// recorded from the tail of the root group, after Ndef(\master): exactly what is heard
~mixRecOn = ~mixRecOn ? false;

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


// ===== GUI — the Deck (ui kit) ======================================
~mixerEz = ~mixerEz ? (); ~mixerSoloBtn = ~mixerSoloBtn ? (); ~mixerMuteBtn = ~mixerMuteBtn ? ();
~mixerFx = ~mixerFx ? (); ~mixerFp = ~mixerFp ? ();

// centred whatever field it was drawn on: a preset keeps its own text
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
    var cx = x + (cols * cw) + 28, wid = ();
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
            { |v| ~fpLive[k] = v }, ~uiFmt);
    };
    wid[\generate] = ~uiBtn.(page, Rect(cx, y + 116, 84, 24), "generate", { ~fpGenerate.(nil, nil, nil, Date.seed) });
    wid[\dice] = ~uiBtn.(page, Rect(cx + 90, y + 116, 84, 24), "→ dice", { ~fpSet.((~fpLive[\on] == true).not) },
        ~fpLive[\on] == true);
    ~uiBtnEnable.(wid[\dice], ~fpCurrent.notNil);
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

// presets beside the fingerprint, tape + master on the right: both end on the canvas's lower edge
~mixerLayout = { |layers|
    var rowH = 28, tableY = 110, footY = tableY + (layers.size * rowH) + 6, fpY = footY + 44;
    var fpBottom = fpY + 20 + (~cfg_fp.rows * ~cfg_fpView.cell.y);
    var barH = (~cfg_presets.btnH * 2) + ~cfg_presets.gap;
    var fxX = 1010, fxY = 84, echoEnd = fxY + if(~cfg_effects.notNil) { 158 } { 0 };
    var tapeH = ~tapeGui !? { (~tapeGuiHeight ? 0) + 42 } ? 0;
    var masterY = (fpBottom - 44).max(echoEnd + tapeH), right = fxX + 316;
    (
        rowH: rowH, tableY: tableY, footY: footY, fpY: fpY,
        presetX: 28 + (~cfg_fp.cols * ~cfg_fpView.cell.x) + 28, presetY: fpBottom - (108 + barH),
        fxX: fxX, fxY: fxY, tapeY: masterY - tapeH, masterY: masterY,
        right: right, w: right + 28, h: (fpBottom + 28).max(masterY + 78).max(440),
        cols: [[\vol, 172, "vol"], [\sendRev, 372, "rev"], [\sendDly, 572, "dly"]], muteX: 776, soloX: 832
    )
};

~mixerBuildTable = { |page, lay, layers|
    var y0 = lay.tableY - 26;
    ~uiCap.(page, Rect(28, y0, 100, 14), "machine");
    lay.cols.do { |c| ~uiCap.(page, Rect(c[1], y0, 100, 14), c[2]) };
    ~uiCap.(page, Rect(lay.muteX, y0, 44, 14), "mute");
    ~uiCap.(page, Rect(lay.soloX, y0, 44, 14), "solo");
    layers.do { |layer, i|
        var y = lay.tableY + (i * lay.rowH), lv = ~cfg_mixer.levels[layer] ? ~mixerDefaultLevel;
        ~uiGlyph.(page, Rect(28, y + 1, ~uiGlyphSize.x, ~uiGlyphSize.y), layer);
        ~uiText.(page, Rect(52, y, 110, 20), layer.asString, ~uiType.label, ~uiPal.ink, true);
        ~mixerEz[layer] = ();
        lay.cols.do { |c|
            ~mixerEz[layer][c[0]] = ~uiRulerRow.(page, c[1], y, 0, 140, "", ControlSpec(0, 1, \lin, 0, lv[c[0]]),
                lv[c[0]], { |v| ~mixSet.(layer, c[0], v) }, ~uiFmt);
        };
        ~mixerMuteBtn[layer] = ~uiBtn.(page, Rect(lay.muteX, y - 2, 44, 24), "⊘",
            { ~mixMuteToggle.(layer) }, ~mixMuted[layer] == true);
        ~mixerSoloBtn[layer] = ~uiBtn.(page, Rect(lay.soloX, y - 2, 44, 24), "◎",
            { ~mixSoloToggle.(layer) }, ~mixSoloCur == layer);
    };
    ~mixerMuteAllBtn = ~uiBtn.(page, Rect(lay.muteX, lay.footY, 44, 24), "⊘",
        { ~mixMuteAllToggle.value }, ~mixAllMuted.value);
    ~mixerSoloAllBtn = ~uiBtn.(page, Rect(lay.soloX, lay.footY, 44, 24), "◎",
        { ~mixUnsolo.value }, ~mixSoloCur.notNil);
};

~mixerBuildFx = { |page, x, y|
    var mode = { |inst, row|
        var key = (inst ++ "_mode").asSymbol, gy = y + 20 + (row * 32), glyph;
        ~uiText.(page, Rect(x, gy + 2, 40, 20), if(inst == \dly) { "echo" } { "rev" });
        glyph = UserView(page, Rect(x + 42, gy, 76, 24)).background_(~uiPal.paper)
            .drawFunc_({ |u| ~uiDrawEcho.(u, ~cfg_effects[key]) });
        ~mixerFx[(inst ++ "Glyph").asSymbol] = glyph;
        ~mixerFx[(inst ++ "Mode").asSymbol] = ~uiPopup.(page, Rect(x + 126, gy, 190, 24), ~echoModes.names,
            ~echoModeIndex.(~cfg_effects[key]), { |idx| ~fxSet.(key, idx + 1); glyph.refresh });
    };
    var tone = { |key, row|
        ~mixerFx[key] = ~uiRulerRow.(page, x, y + 86 + (row * 28), 42, 190, key.asString,
            ControlSpec(-1, 1, \lin, 0, ~cfg_effects[key]), ~cfg_effects[key], { |v| ~fxSet.(key, v) }, ~uiFmt);
    };
    ~uiCap.(page, Rect(x, y, 380, 14), "echo");
    mode.(\dly, 0);
    mode.(\rev, 1);
    tone.(\bass, 0);
    tone.(\treble, 1);
};

~mixerBuildMaster = { |page, x, y|
    ~uiCap.(page, Rect(x, y, 380, 14), "master");
    ~mixerEz[\master] = ~uiRulerRow.(page, x, y + 22, 42, 130, "vol",
        ControlSpec(0, 1, \lin, 0, ~cfg_mixer.master), ~cfg_mixer.master, { |v| ~masterSet.(v) }, ~uiFmt);
    ~mixerRecBtn = ~uiBtn.(page, Rect(x + 246, y + 20, 70, 24), ["● rec", "■ rec"],
        { ~mixRecToggle.value }, ~mixRecOn);
};

~mixerBuild = {
    var layers = ~mixerLayers, lay = ~mixerLayout.(layers), scr = Window.availableBounds, win, page;
    var w = lay.w.min(scr.width), h = lay.h.min(scr.height);

    ~mixerWin !? { |x| try { x.close } };
    win = Window("NET · deck", Rect(scr.left + ((scr.width - w) / 2).max(0), scr.top + 40, w, h))
        .background_(~uiPal.paper);
    ~mixerWin = win;
    ~mixerEz = (); ~mixerSoloBtn = (); ~mixerMuteBtn = (); ~mixerFx = ();

    ~uiRule.(win, Rect(0, 66, w, 1)).resize_(2);
    page = ~uiPage.(win.view, lay.right - 28);
    ~uiTitle.(page, Rect(28, 20, 300, 36), "Deck");
    ~uiNav.(page, lay.right, 26, [["matrix", { ~openMatrix }], ["machines", { ~openMachines }]]);
    ~uiRule.(page, Rect(lay.fxX - 24, 67, 1, h - 67)).resize_(4);

    ~mixerBuildTable.(page, lay, layers);
    ~mixerFpBuild.(page, 28, lay.fpY);
    ~uiCap.(page, Rect(lay.presetX, lay.presetY, 260, 14), "mixer preset");
    ~preset.bar(page, lay.presetX, lay.presetY + 20, \mixer);
    ~uiCap.(page, Rect(lay.presetX, lay.presetY + 88, 380, 14), "project · machines + mixer + matrix");
    ~preset.bar(page, lay.presetX, lay.presetY + 108, \project);
    if(~cfg_effects.notNil) { ~mixerBuildFx.(page, lay.fxX, lay.fxY) };
    ~tapeGui !? { |gui|
        ~uiCap.(page, Rect(lay.fxX, lay.tapeY, 380, 14), "tape");
        gui.(page, lay.fxX, lay.tapeY + 20);
    };
    ~mixerBuildMaster.(page, lay.fxX, lay.masterY);

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
~mixerFxSync = {
    [\dly, \rev].do { |inst|
        ~mixerFx[(inst ++ "Mode").asSymbol] !? { |p| ~uiPopupSet.(p, ~echoModeIndex.(~cfg_effects[(inst ++ "_mode").asSymbol])) };
        ~mixerFx[(inst ++ "Glyph").asSymbol] !? { |g| { g.refresh }.defer };
    };
    [\bass, \treble].do { |k| ~mixerFx[k] !? { |r| ~uiRulerSet.(r, ~cfg_effects[k]) } };
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
