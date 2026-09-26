// App/mixer.scd — MIXER: per-machine vol + two fx sends, one aggregator per
// bus, master (LeakDC + Limiter), solo/mute, recorder, mixer window (~openMixer).
// The output stage only: nothing here touches the field.


// ===== CONFIG — edit here ============================================
(
// vol -> master; sendRev/sendDly -> §K.1/§K.2 tables (independent by canon).
// `? ()`: the live mix is STATE and survives a hot reload; the table only seeds
// a fresh session (the auto-preset then overrides it)
~cfg_mixer = ~cfg_mixer ? (
    master:  0.9,

    levels: (
        //            vol    sendRev (§K.1)  sendDly (§K.2)
        alpha:   ( vol: 0.85, sendRev: 0.55, sendDly: 0.20 ),
        delta:   ( vol: 0.80, sendRev: 0.45, sendDly: 0.00 ),   // §K.2: binde is not in the delay table
        epsilon: ( vol: 0.75, sendRev: 0.15, sendDly: 0.00 ),   // §K.1: self-diffuse — low send; §K.2: no delay
        zeta:    ( vol: 0.75, sendRev: 0.15, sendDly: 0.00 ),   // §K.2: kratzer is not in the delay table
        theta:   ( vol: 0.80, sendRev: 0.16, sendDly: 0.00 )    // §K.2 zero is a BAN, not taste: echo would refill what the class law exhausts
    )
);

// fallback levels for a layer missing from the table (new synths/*.scd)
~mixerDefaultLevel = ( vol: 0.7, sendRev: 0.0, sendDly: 0.0 );

// master-sum recorder: file format and dir (relative to project root)
~cfg_recorder = ( header: "wav", sample: "int24", dir: "recordings" );


// ===== LOGIC — routers + master + GUI ================================
~mixerLayers = ~activeLayers ? ~ungSpecs.keys.asArray.sort;

// ensure a level entry for every active layer
~mixerLayers.do { |layer|
    if(~cfg_mixer.levels[layer].isNil) {
        ~cfg_mixer.levels[layer] = ~mixerDefaultLevel.copy;
    };
};

// layer router: dry -> ~busDry only (the aggregator below collects the sends —
// exactly ONE writer per bus); volumes belong to the performer (2026-07-18)
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
// names coincide — the Ndef tells them apart
~mixerSendMix = {
    Mix(~mixerLayers.collect { |layer|
        var amt = NamedControl.kr(("send_" ++ layer).asSymbol, 0);
        Ndef(layer.asSymbol).ar(2) * amt.lag(0.1);
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

// master: (dry + fx return), LeakDC, Limiter
Ndef(\master, { |amp = 0.9|
    var dry, fx, sig;
    // InFeedback, not In: reads the buses whatever the node order
    dry = InFeedback.ar(~busDry.index, 2);
    fx  = InFeedback.ar(~busFxReturn.index, 2);
    sig = dry + fx;
    sig = LeakDC.ar(sig);
    sig = Limiter.ar(sig, 0.95, 0.01);               // §K.4: limiter 0.95
    sig = sig * amp.lag(0.05);
    sig
});
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
    // for a muted / solo-hidden layer only the stored level moves — unmute
    // restores the value the slider shows right now
    if(~mixLayerAudible.(layer)) {
        if(agg.notNil) {
            Ndef(agg).set(("send_" ++ layer).asSymbol, value);
        } {
            Ndef(("mix_" ++ layer).asSymbol).set(\vol, value);
        };
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
            Ndef(agg).set(("send_" ++ l).asSymbol, on.if({ lv[which] }, 0));
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


// ===== GUI — Desk window (ui kit) ===================================
~mixerEz = ~mixerEz ? (); ~mixerSoloBtn = ~mixerSoloBtn ? (); ~mixerMuteBtn = ~mixerMuteBtn ? ();
~mixerFx = ~mixerFx ? ();

~mixerBuild = {
    var pal = ~uiPal, layers = ~mixerLayers, rowH = 28, tableY = 110;
    var fxX = 1010, w = 1440, h = (tableY + (layers.size * rowH) + 40).max(440);
    var fmt2 = { |v| ~uiFmt.(v, 2) };
    var fxModeItems = [
        "1 · 1 tap", "2 · 2 tap", "3 · 1+2 tap", "4 · 1+2+3 echo",
        "5 · 1 +rev", "6 · 2 +rev", "7 · 3 +rev", "8 · 1+2 +rev",
        "9 · 2+3 +rev", "10 · 1+3 +rev", "11 · all +rev", "12 · rev only"
    ];
    var scr = Window.availableBounds, win, mkGlyph;

    ~mixerWin !? { |x| try { x.close } };
    w = w.min(scr.width); h = h.min(scr.height);
    win = Window("NET · desk", Rect(scr.left + ((scr.width - w) / 2).max(0), scr.top + 40, w, h))
        .background_(pal.paper);
    ~mixerWin = win;
    ~mixerEz = (); ~mixerSoloBtn = (); ~mixerMuteBtn = (); ~mixerFx = ();

    ~uiCap.(win, Rect(28, 12, 600, 14), "net · mixing desk");
    ~uiTitle.(win, Rect(28, 26, 300, 36), "Desk");
    ~uiCap.(win, Rect(896, 32, 56, 14), "master");
    ~mixerEz[\master] = ~uiRulerRow.(win, 954, 30, 0, 150, "",
        ControlSpec(0, 1, \lin, 0, ~cfg_mixer.master), ~cfg_mixer.master, { |v| ~masterSet.(v) }, fmt2);
    ~mixerRecBtn = ~uiBtn.(win, Rect(1180, 28, 70, 26), ["● rec", "■ rec"],
        { ~mixRecToggle.value }, ~mixRecOn);
    ~uiBtn.(win, Rect(1258, 28, 74, 26), "unsolo", { ~mixUnsolo.value });
    ~uiBtn.(win, Rect(1340, 28, 72, 26), "close", { win.close });
    ~uiRule.(win, Rect(0, 66, w, 1));
    ~uiRule.(win, Rect(fxX - 24, 67, 1, h - 67));

    ~uiCap.(win, Rect(28, tableY - 26, 100, 14), "machine");
    ~uiCap.(win, Rect(172, tableY - 26, 100, 14), "vol");
    ~uiCap.(win, Rect(372, tableY - 26, 100, 14), "rev");
    ~uiCap.(win, Rect(572, tableY - 26, 100, 14), "dly");
    ~uiCap.(win, Rect(776, tableY - 26, 44, 14), "mute");
    ~uiCap.(win, Rect(832, tableY - 26, 44, 14), "solo");
    ~uiCap.(win, Rect(888, tableY - 26, 60, 14), "field");
    layers.do { |layer, i|
        var y = tableY + (i * rowH);
        var lv = ~cfg_mixer.levels[layer] ? ~mixerDefaultLevel;
        ~uiText.(win, Rect(28, y, 22, 20), ~uiPhi[layer] ? "", 14);
        ~uiText.(win, Rect(52, y, 110, 20), layer.asString, 12, pal.ink, true);
        ~mixerEz[layer] = (
            vol: ~uiRulerRow.(win, 172, y, 0, 140, "", ControlSpec(0, 1, \lin, 0, lv.vol), lv.vol,
                { |v| ~mixSet.(layer, \vol, v) }, fmt2),
            sendRev: ~uiRulerRow.(win, 372, y, 0, 140, "", ControlSpec(0, 1, \lin, 0, lv.sendRev), lv.sendRev,
                { |v| ~mixSet.(layer, \sendRev, v) }, fmt2),
            sendDly: ~uiRulerRow.(win, 572, y, 0, 140, "", ControlSpec(0, 1, \lin, 0, lv.sendDly), lv.sendDly,
                { |v| ~mixSet.(layer, \sendDly, v) }, fmt2)
        );
        ~mixerMuteBtn[layer] = ~uiBtn.(win, Rect(776, y - 2, 44, 24), "⊘",
            { ~mixMuteToggle.(layer) }, ~mixMuted[layer] == true);
        ~mixerSoloBtn[layer] = ~uiBtn.(win, Rect(832, y - 2, 44, 24), "◎",
            { ~mixSoloToggle.(layer) }, ~mixSoloCur == layer);
        ~uiBtn.(win, Rect(888, y - 2, 44, 24), "M", { ~openMachines !? { |f| f.value } });
    };
    ~uiBtn.(win, Rect(28, tableY + (layers.size * rowH) + 6, 90, 24), "matrix",
        { ~openMatrix !? { |f| f.value } });

    mkGlyph = { |x, y, modeFn|
        var uv = UserView(win, Rect(x, y, 76, 24)).background_(pal.paper);
        uv.drawFunc_({ |u| ~uiDrawEcho.(u, modeFn.value) });
        uv
    };
    if(~cfg_effects.notNil) {
        var dlyGl, revGl;
        ~uiCap.(win, Rect(fxX, 84, 380, 14), "space echo");
        ~uiText.(win, Rect(fxX, 106, 40, 20), "echo", 10.5);
        dlyGl = mkGlyph.(fxX + 42, 104, { ~cfg_effects.dly_mode });
        ~mixerFx[\dlyMode] = ~uiPopup.(win, Rect(fxX + 126, 104, 190, 24), fxModeItems,
            (~cfg_effects.dly_mode - 1).clip(0, 11), { |idx|
                Ndef(\space_echo_dly).set(\mode, idx + 1);
                ~cfg_effects.dly_mode = idx + 1;
                dlyGl.refresh;
            });
        ~uiText.(win, Rect(fxX, 138, 40, 20), "rev", 10.5);
        revGl = mkGlyph.(fxX + 42, 136, { ~cfg_effects.rev_mode });
        ~mixerFx[\revMode] = ~uiPopup.(win, Rect(fxX + 126, 136, 190, 24), fxModeItems,
            (~cfg_effects.rev_mode - 1).clip(0, 11), { |idx|
                Ndef(\space_echo_rev).set(\mode, idx + 1);
                ~cfg_effects.rev_mode = idx + 1;
                revGl.refresh;
            });
        ~mixerFx[\bass] = ~uiRulerRow.(win, fxX, 170, 42, 190, "bass",
            ControlSpec(-1, 1, \lin, 0, ~cfg_effects.rev_bass), ~cfg_effects.rev_bass, { |v|
                [\space_echo_rev, \space_echo_dly].do { |n| Ndef(n).set(\bass, v) };
                ~cfg_effects.rev_bass = v; ~cfg_effects.dly_bass = v;
            }, fmt2);
        ~mixerFx[\treble] = ~uiRulerRow.(win, fxX, 198, 42, 190, "treble",
            ControlSpec(-1, 1, \lin, 0, ~cfg_effects.rev_treble), ~cfg_effects.rev_treble, { |v|
                [\space_echo_rev, \space_echo_dly].do { |n| Ndef(n).set(\treble, v) };
                ~cfg_effects.rev_treble = v; ~cfg_effects.dly_treble = v;
            }, fmt2);
        ~mixerFx[\dlyGlyph] = dlyGl; ~mixerFx[\revGlyph] = revGl;
    };
    ~uiRule.(win, Rect(fxX, 234, 400, 1));

    ~uiCap.(win, Rect(fxX, 246, 380, 14), "desk preset");
    ~preset.bar(win, fxX, 266, \mixer);
    ~uiCap.(win, Rect(fxX, 334, 380, 14), "project · machines + desk + matrix");
    ~preset.bar(win, fxX, 354, \project);

    win.onClose_({
        if(~mixerWin === win) {
            ~mixerWin = nil; ~mixerEz = (); ~mixerSoloBtn = (); ~mixerMuteBtn = ();
            ~mixerRecBtn = nil; ~mixerFx = ();
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
~mixerRefreshMute = { ~mixerMuteBtn.keysValuesDo { |l, b| ~uiBtnSet.(b, ~mixMuted[l] == true) } };
~mixerRefreshSolo = { ~mixerSoloBtn.keysValuesDo { |l, b| ~uiBtnSet.(b, ~mixSoloCur == l) } };
~mixerRecSync = { ~uiBtnSet.(~mixerRecBtn, ~mixRecOn) };

"mixer — ~openMixer".postln;
)
