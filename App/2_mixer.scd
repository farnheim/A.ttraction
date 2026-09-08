// App/2_mixer.scd — UNGRUND · MIXER: per-layer vol + two fx sends (§K.1/§K.2),
// one aggregator per bus, master (LeakDC + Limiter), solo/mute, recorder, Desk.
// Routes ~activeLayers only. Signal flow: docs/architecture/app/README.md.


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
~mixerLayers = ~activeLayers ? [\alpha, \delta, \epsilon, \zeta, \theta];

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
~mixerRecSync = {
    ~uiBtnSet.(~mixerRecBtn, ~mixRecOn);
};


// ===== GUI — Desk window (monochrome; layout docs/architecture/app/ui/Main.dc.html) =====
// widget registries (idempotent on file reload)
~mixerEz      = ();    // layer -> ( \vol:, \sendRev:, \sendDly: ruler ); \master -> ruler
~mixerFx      = ();    // space-echo strip: ( dlyMode:, revMode: PopUpMenu; bass:, treble: ruler; dlyGlyph:, revGlyph: UserView )
~mixerSoloBtn = ();    // layer -> Button (solo)
~mixerMuteBtn = ();    // layer -> Button (mute)
~mixerPatchLocked = "locked while an act is active";
~mixerPatchNote = nil; // StaticText: the last patch, or why the patcher refused
~mixerPatchSeed = nil; // NumberBox: seed of ~kfRandomize (0 = a fresh one per click)
~mixerPatchBtn  = nil; // Button (patch) — disabled while an act is active
~mixerPatchSeedVal = ~mixerPatchSeedVal ? 0;   // survives a window reopen
~mixerGraph   = nil;   // UserView: koppelfeld graph (cables per layer pair)
~mixerTiers   = nil;   // UserView: tiers of ~seqTimeline
~mixerKfStrip = nil;   // UserView: scheme state (mode · Λmax · cables · verdict · armed)
~mixerKfBtns  = ();    // \arm / \disarm / \window Buttons
~mixerGainPop = nil;   // PopUpMenu (page of 16 cable gains)
~mixerGainRows = [];   // one row per strip: ( txt: ruler: cable: spec: )
~kfGainPage   = ~kfGainPage ? 0;   // survives a window reopen
// mixer export, called by ~kfInstall (§8.4/D103): nil while there is no window,
// so a scheme applied with the desk closed touches no dead widget
~kfGuiRelabel = ~kfGuiRelabel;
~mixerPresetPop  = nil;   // PopUpMenu (project presets; read by ~ungRefreshPresets)
~mixerPresetName = nil;   // TextField (preset name)
~mixSoloCur   = ~mixSoloCur;   // current solo layer (or nil), survives reopen

// structure-grid panel slots (0_grid.scd may be absent — panel is nil-safe)
~mixerGridTxt    = nil;   // TextView (the field)
~mixerGridStatus = nil;   // StaticText (glyph count / field size / refusal)
~mixerGridEz     = nil;   // ruler (complexity)
~gridComplexity  = ~gridComplexity ? 0.5;   // survives reopen / missing 0_grid

// Konstruktion slots (9_konstruktion.scd may be absent — nil-safe like 0_grid)
~mixerKonTtier   = nil;   // NumberBox (score T_tier — read by the act only)
~mixerKonBtns    = ();    // \start / \stop / \score Buttons
~gridLastText    = ~gridLastText;   // the field is score: survives a window reopen

// piece buttons enable off ~konActive; only start/stop are gated — "score" is
// always live and reports "no act" itself; patch is the other way round
~mixerKonSync = {
    {
        var on = (~konActive == true);
        [\start, \stop].do { |k|
            ~uiBtnEnable.(~mixerKonBtns[k], on);
        };
        ~uiBtnEnable.(~mixerPatchBtn, on.not and: { ~kfRandomize.notNil });
        // the note carries the last patch report — only the lock message is the
        // sync's to write, and only the sync's to take back
        ~mixerPatchNote !? { |t|
            case
            { on } { t.string_(~mixerPatchLocked) }
            { t.string == ~mixerPatchLocked } { t.string_("") }
            { };
        };
        ~mixerGraph !? { |uv| uv.refresh };
        ~mixerTiers !? { |uv| uv.refresh };
    }.defer;
};

// update all solo-button visuals from ~mixSoloCur
~mixerRefreshSolo = {
    ~mixerSoloBtn.keysValuesDo { |layer, btn|
        ~uiBtnSet.(btn, ~mixSoloCur == layer.asSymbol);
    };
};

// update all mute-button visuals from ~mixMuted
~mixerRefreshMute = {
    ~mixerMuteBtn.keysValuesDo { |layer, btn|
        ~uiBtnSet.(btn, ~mixMuted[layer.asSymbol] == true);
    };
};

// full slot reset shared by the pre-build teardown and onClose: nothing may
// touch widgets of a dead window (~loadPreset defers updates through ~mixerFx)
~mixerResetSlots = {
    ~mixerWin        = nil;
    ~mixerGuiSync    = nil;
    ~mixerEz         = ();
    ~mixerSoloBtn    = ();
    ~mixerMuteBtn    = ();
    ~mixerPatchNote  = nil;
    ~mixerPatchSeed  = nil;
    ~mixerPatchBtn   = nil;
    ~mixerGraph      = nil;
    ~mixerTiers      = nil;
    ~mixerKfStrip    = nil;
    ~mixerKfBtns     = ();
    ~mixerGainPop    = nil;
    ~mixerGainRows   = [];
    ~kfGuiRelabel    = nil;
    ~mixerFx         = ();
    ~mixerPresetPop  = nil;
    ~mixerPresetName = nil;
    ~mixerRecBtn     = nil;
    ~mixerGridTxt    = nil;
    ~mixerGridStatus = nil;
    ~mixerGridEz     = nil;
    ~mixerKonTtier   = nil;
    ~mixerKonBtns    = ();
};

// --- glyphs -------------------------------------------------------------
// space echo: three tape heads (mode masks from 6_effects) + a spring on reverb
~uiDrawEcho = { |u, mode|
    var h1 = [1, 0, 1, 1, 1, 0, 0, 1, 0, 1, 1, 0], h2 = [0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0];
    var h3 = [0, 0, 0, 1, 0, 0, 1, 0, 1, 1, 1, 0], rv = [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1];
    var m = ((mode ? 1) - 1).clip(0, 11), y = u.bounds.height / 2;
    Pen.strokeColor = ~uiPal.ink; Pen.width = 1;
    Pen.line(2@y, 52@y); Pen.stroke;
    [h1, h2, h3].do { |hm, i|
        var r = Rect(6 + (i * 16), y - 7, 9, 14);
        Pen.width = 1.2;
        Pen.fillColor = if(hm[m] == 1) { ~uiPal.ink } { ~uiPal.paper };
        Pen.fillRect(r); Pen.strokeRect(r);
    };
    if(rv[m] == 1) {
        Pen.width = 1.3; Pen.moveTo(55@y);
        [58@(y - 6), 61@(y + 6), 64@(y - 6), 67@(y + 6), 70@(y - 6), 73@y].do { |p| Pen.lineTo(p) };
        Pen.stroke;
    };
};

// coordinates hand-fitted to the asymmetry of the drawing; a new sound class
// will NOT appear in the graph until it has a place here
~mixerGraphPos = ( theta: 270@62, delta: 462@66, alpha: 100@212, zeta: 462@214, epsilon: 270@302 );
~mixerDrawGraph = { |u|
    var cables = (~kfCables ? []).select { |c| c[\enabled] != false };
    var font = ~uiMono.(9), gfont = ~uiMono.(28), nfont = ~uiMono.(10);
    // a pair is drawn only if BOTH layers are loaded and have a place on the
    // field: an unloaded layer has no glyph and the line would end in nothing
    var posOf = { |l| if(~mixerLayers.includes(l.asSymbol)) { ~mixerGraphPos[l.asSymbol] } };
    var pairKey = { |a, b| (a.asString ++ ">" ++ b.asString).asSymbol };
    var per = (), selfCnt = (), inLoop = ();
    // §8.4: the stroke reads Σgain of the pair, the caption its cable count —
    // two different facts, so one may not be derived from the other
    var sumG = (), selfSum = (), curveCnt = (), selfCurve = ();
    var bump = { |reg, k, cv| if(reg[k].isNil) { reg[k] = () }; reg[k][cv] = (reg[k][cv] ? 0) + 1 };
    // fixed order, not keysValuesDo: an Event iterates by hash, and a tie would
    // pick a different curve from frame to frame
    var domCurve = { |e|
        var best = nil, bn = 0;
        [\clip, \fold, \step].do { |cv| if(((e ? ())[cv] ? 0) > bn) { bn = e[cv]; best = cv } };
        best
    };
    // the cycle is read off the SCHEME (the verdict of ~kfApply, else the loops
    // the derivation wrote into it) — the modmatrix line that used to carry it
    // is gone with the module
    var loops = (~kfVerdict !? { |v| v[\loops] })
        ?? { (~kfSchaltung !? { |x| x[\loops] }) ? [] };
    var mode = (~kfVerdict !? { |v| v[\mode] }) ?? { ~kfSchaltung !? { |x| x[\mode] } };
    loops.do { |lp|
        var ls = (lp[\nodes] ? []).collect { |n| n.asString.split($.)[0].asSymbol };
        ls.do { |a| ls.do { |b| inLoop[pairKey.(a, b)] = true } };
    };
    cables.do { |c|
        var a = c[\src][0].asSymbol, b = c[\dst][0].asSymbol;
        var g = c[\gain] ? 0, cv = c[\curve] ? \clip;
        if(posOf.(a).notNil and: { posOf.(b).notNil }) {
            if(a == b) {
                selfCnt[a] = (selfCnt[a] ? 0) + 1;
                selfSum[a] = (selfSum[a] ? 0) + g;
                bump.(selfCurve, a, cv);
            } {
                var k = pairKey.(a, b);
                per[k] = (per[k] ? 0) + 1;
                sumG[k] = (sumG[k] ? 0) + g;
                bump.(curveCnt, k, cv);
            };
        };
    };
    per.keysValuesDo { |k, n|
        var ab = k.asString.split($>);
        var src = posOf.(ab[0]), dst = posOf.(ab[1]);
        var dx = dst.x - src.x, dy = dst.y - src.y, d = dx.hypot(dy).max(1);
        var ux = dx / d, uy = dy / d, px = uy.neg, py = ux;
        var sx = src.x + (ux * 22) + (px * 3), sy = src.y + (uy * 22) + (py * 3);
        var ex = dst.x - (ux * 26) + (px * 3), ey = dst.y - (uy * 26) + (py * 3);
        Pen.use {
            Pen.strokeColor = ~uiPal.ink; Pen.width = ~uiLineWidth;
            Pen.lineDash = ~uiLineDash.((sumG[k] ? 0) / 4, domCurve.(curveCnt[k]));
            if(inLoop[k] == true) {
                [1.7, -1.7].do { |o|
                    Pen.line((sx + (px * o))@(sy + (py * o)), (ex + (px * o))@(ey + (py * o)));
                    Pen.stroke;
                };
            } {
                Pen.line(sx@sy, ex@ey); Pen.stroke;
            };
        };
        Pen.use {
            Pen.fillColor = ~uiPal.ink;
            Pen.moveTo(ex@ey);
            Pen.lineTo((ex - (ux * 8) + (px * 3))@(ey - (uy * 8) + (py * 3)));
            Pen.lineTo((ex - (ux * 8) - (px * 3))@(ey - (uy * 8) - (py * 3)));
            Pen.fill;
        };
        ~uiPenText.(n.asString, ((sx + ex) / 2) + (px * 9), ((sy + ey) / 2) + (py * 9) - 6,
            font, ~uiPal.ink2, \middle);
    };
    // an intra-layer pair has no line to draw: it is a ring on its own glyph
    selfCnt.keysValuesDo { |l, n|
        var pt = posOf.(l);
        pt !? {
            Pen.use {
                Pen.strokeColor = ~uiPal.ink; Pen.width = ~uiLineWidth;
                Pen.lineDash = ~uiLineDash.((selfSum[l] ? 0) / 4, domCurve.(selfCurve[l]));
                Pen.addArc((pt.x - 27)@(pt.y - 25), 9, 0, 2pi); Pen.stroke;
            };
            ~uiPenText.(n.asString, pt.x - 27, pt.y - 44, font, ~uiPal.ink2, \middle);
        };
    };
    ~mixerGraphPos.keysValuesDo { |layer, pt|
        if(~mixerLayers.includes(layer)) {
            ~uiPenText.(~uiPhi[layer] ? "", pt.x, pt.y - 18, gfont, ~uiPal.ink, \middle);
            ~uiPenText.(layer.asString, pt.x, pt.y + 20, nfont, ~uiPal.ink, \middle);
        };
    };
    ~uiPenText.(
        if(~kfNodes.isNil or: { ~kfApply.isNil }) { "koppelfeld off" } {
            if(cables.isEmpty) { "no scheme" } {
                "cables " ++ cables.size ++ " · " ++ (mode ? "—")
                    ++ " · loops " ++ loops.size
            };
        }, 2, 2, font, ~uiPal.ink2);
};

~mixerDrawTiers = { |u|
    var w = u.bounds.width, h = u.bounds.height;
    var tl = ~seqTimeline ? (~cfg_seq !? { ~cfg_seq.timeline }) ? [];
    var blocks = tl.reject { |b| b[\finish] == true }, n = blocks.size.max(1), layers = ~mixerLayers;
    var left = 64, top = 16, colW = (w - left) / n, rowH = ((h - top) / layers.size.max(1)).min(20);
    var levels = (), f = ~uiMono.(9);
    blocks.do { |b, i|
        var x = left + (i * colW);
        (b[\vols]   ? []).do { |pair| levels[pair[0]] = pair[1] };
        (b[\active] ? []).do { |layer| levels[layer] = 1.0 };
        (b[\gone]   ? []).do { |layer| levels[layer] = nil };
        if(~seqCurrentBlock == i) {
            Pen.fillColor = ~uiPal.hi;
            Pen.fillRect(Rect(x, top - 2, colW, (rowH * layers.size) + 4));
        };
        ~uiPenText.(b[\t].asString, x + (colW / 2), 0, f, ~uiPal.ink2, \middle);
        layers.do { |layer, k|
            var y = top + (k * rowH), lv = levels[layer];
            Pen.strokeColor = ~uiPal.rule; Pen.width = 1;
            Pen.strokeRect(Rect(x + 1.5, y + 1.5, colW - 3, rowH - 3));
            if(lv.notNil) {
                Pen.fillColor = ~uiPal.ink;
                if(lv >= 0.75) {
                    Pen.fillRect(Rect(x + 2, y + 2, colW - 4, rowH - 4));
                } {
                    Pen.fillRect(Rect(x + 2, y + (rowH / 2), colW - 4, (rowH / 2) - 2));
                };
            };
        };
    };
    layers.do { |layer, k|
        ~uiPenText.((~uiPhi[layer] ? "") ++ " " ++ layer.asString.keep(3), 0, top + (k * rowH) + 3, f, ~uiPal.ink);
    };
};

// --- koppelfeld: scheme state + per-cable gains (§8.4) -------------------
// the strip redraws itself once a second for the same reason the graph does —
// the scheme changes from four places (patch button, act, IDE, preset) — and it
// is the ONE caller of ~kfVerdictRefresh (D99): a gain moved by hand makes the
// verdict of the last ~kfApply a statement about a graph that no longer stands
~mixerDrawKfStrip = { |u|
    var f = ~uiMono.(10), str;
    if(~kfReport.isNil or: { ~kfNodes.isNil }) {
        str = "koppelfeld off (enableKoppelfeld)";
    } {
        var v = if(~kfVerdictRefresh.notNil) { ~kfVerdictRefresh.value } { ~kfVerdict };
        var rep = ~kfReport.value;
        // a NOTE is half the verdict: V10 files an unpatched layer as a note, so
        // "ok" alone would show a scheme that never touches epsilon as complete
        var notes = (v !? { |x| (x[\notes] ? []).size }) ? 0;
        // the parens are load-bearing: `++` after the last block of a bare `case`
        // would append to that BLOCK, not to the string the case returns
        var verdict = (case
            { v.isNil }    { "no verdict" }
            { v[\valid] }   { "V1–V13 ok" }
            { "V1–V13 · " ++ v[\errors].size ++ " error" ++ if(v[\errors].size == 1) { "" } { "s" } })
            ++ if(notes > 0) { " · " ++ notes ++ " note" ++ if(notes == 1) { "" } { "s" } } { "" };
        str = (rep[\mode] ? "—").asString
            ++ " · Λmax " ++ ~uiFmt.(rep[\lamMax] ? 0, 2)
            ++ " · cables " ++ rep[\cables] ++ "/" ++ ((~cfg_kf !? { |x| x[\cableMax] }) ? 64)
            ++ if((rep[\disabled] ? 0) > 0) { " (off " ++ rep[\disabled] ++ ")" } { "" }
            ++ " · interlayer " ++ ~uiFmt.((rep[\interlayer] ? 0) * 100, 1) ++ " %"
            ++ " · " ++ verdict
            ++ " · " ++ if(rep[\armed] == true) { "armed" } { "disarmed" };
    };
    ~uiPenText.(str, 0, 3, f, ~uiPal.ink);
};

// a strip is one ENABLED cable; the page shows 16 of them
~mixerGainCables = { (~kfCables ? []).select { |c| c[\enabled] != false } };
~mixerGainPages  = { ((~mixerGainCables.value.size / 16).ceil.asInteger).clip(1, 4) };
~mixerGainLabel  = { |lk|
    (~uiPhi[lk[0].asSymbol] ? "") ++ " " ++ lk[1].asString.keep(12)
};

// rebind labels, specs and values of the 16 strips: called by ~kfInstall on every
// scheme change and by the page popup. Silent on a dead window, and every widget
// touch is deferred — ~kfInstall runs inside the fork of ~kfApply
~mixerGainRelabel = {
    {
        if(~mixerWin.notNil and: { ~mixerGainRows.notEmpty }) {
            var cables = ~mixerGainCables.value;
            var pages = ~mixerGainPages.value;
            var gmaxAbs = (~cfg_kf !? { |x| x[\gainAbsMax] }) ? 4;
            var items = if(cables.isEmpty) { ["no cables"] } {
                pages.collect { |i|
                    "gains " ++ ((i * 16) + 1) ++ "–" ++ ((i + 1) * 16).min(cables.size)
                };
            };
            ~kfGainPage = (~kfGainPage ? 0).clip(0, pages - 1);
            ~uiPopupItems.(~mixerGainPop, items);
            ~uiPopupSet.(~mixerGainPop, ~kfGainPage);
            ~mixerGainRows.do { |row, i|
                // the row holds the cable EVENT, never its index in ~kfCables:
                // ~kfGainSet finds the slot by object identity and ~kfInstall
                // replaces the whole table
                var c = cables[(~kfGainPage * 16) + i];
                row[\cable] = c;
                if(c.isNil) {
                    row[\spec] = ControlSpec(0, gmaxAbs, \lin);
                    row[\ruler][\spec] = row[\spec];
                    row[\txt].string_("—");
                    ~uiRulerSet.(row[\ruler], 0);
                    ~uiRulerEnable.(row[\ruler], false);
                } {
                    var gmax = if(~kfGainMax.notNil) {
                        min(gmaxAbs, ~kfGainMax.(c[\dst][0], c[\dst][1]))
                    } { gmaxAbs };
                    row[\spec] = ControlSpec(0, gmax.max(0.0001), \lin);
                    row[\ruler][\spec] = row[\spec];
                    row[\txt].string_(~mixerGainLabel.(c[\src]) ++ " → " ++ ~mixerGainLabel.(c[\dst]));
                    ~uiRulerSet.(row[\ruler], (c[\gain] ? 0).clip(0, row[\spec].maxval));
                    ~uiRulerEnable.(row[\ruler], ~kfGainSet.notNil);
                };
            };
        };
    }.defer;
};

~ungBuildMixer = {
    var layers = ~mixerLayers, w = 1440, h = 850, scr, winRect, win;
    var gx = 1010, rx = 1034, rw = 378, tableY = 444, rowH = 28, modY = 610;
    var hasFx = ~cfg_effects.notNil, hasPatch = ~kfRandomize.notNil and: { ~kfApply.notNil };
    var hasGrid = ~gridGenerate.notNil;
    var fmt2 = { |v| ~uiFmt.(v, 2) }, fmt3 = { |v| ~uiFmt.(v, 3) };
    var fxModeItems = [
        "1 · 1 tap", "2 · 2 tap", "3 · 1+2 tap", "4 · 1+2+3 echo",
        "5 · 1 +rev", "6 · 2 +rev", "7 · 3 +rev", "8 · 1+2 +rev",
        "9 · 2+3 +rev", "10 · 1+3 +rev", "11 · all +rev", "12 · rev only"
    ];
    var graph, tiers, presetName, presetPop, gridTv, gridStatus, gridBtn, konRange, konTtierBox;
    var recBtn, mkGlyph, patchSeed, patchNote, kfStrip, armT;

    // close previous window best-effort (destroyed Qt object — contract §6)
    if(~mixerWin.notNil) { try { ~mixerWin.close } };
    ~mixerResetSlots.value;

    scr = Window.availableBounds;
    w = w.min(scr.width); h = h.min(scr.height);
    winRect = Rect(scr.left + ((scr.width - w) / 2).max(0), scr.top, w, h);
    win = Window("UNGRUND · desk", winRect).background_(~uiPal.paper);
    ~mixerWin = win;

    // --- header: title, master, rec, unsolo, close ---
    ~uiCap.(win, Rect(28, 12, 600, 14),
        "ungrund · mixing desk" ++ ((~konCurrent !? { |k| " · act seed " ++ k[\seed] }) ? ""));
    ~uiTitle.(win, Rect(28, 26, 300, 36), "Desk");
    ~uiCap.(win, Rect(896, 32, 56, 14), "master");
    ~mixerEz[\master] = ~uiRulerRow.(win, 954, 30, 0, 150, "",
        ControlSpec(0, 1, \lin, 0, ~cfg_mixer.master), ~cfg_mixer.master, { |v| ~masterSet.(v) }, fmt2);
    // button state lives in ~mixRecOn: correct after a close/reopen while recording
    recBtn = ~uiBtn.(win, Rect(1180, 28, 70, 26), ["● rec", "■ rec"],
        { ~mixRecToggle.value }, ~mixRecOn);
    ~mixerRecBtn = recBtn;
    ~uiBtn.(win, Rect(1258, 28, 74, 26), "unsolo", { ~mixUnsolo.value });
    ~uiBtn.(win, Rect(1340, 28, 72, 26), "close", { win.close });
    ~uiRule.(win, Rect(0, 66, w, 1));
    ~uiRule.(win, Rect(gx, 67, 1, h - 67));

    // --- koppelfeld graph ---
    ~uiCap.(win, Rect(28, 76, 400, 14), "layers · koppelfeld");
    graph = UserView(win, Rect(28, 92, 540, 340)).background_(~uiPal.paper);
    graph.drawFunc_({ |u| ~mixerDrawGraph.(u) });
    // the scheme changes from four places (the patch button, an act, the IDE, a
    // preset) — a slow self-redraw is cheaper than a hook in each of them
    graph.frameRate_(1).animate_(true);
    ~mixerGraph = graph;

    // --- space echo strip: mode per instance, tone shared; GUI rides ON TOP of ~cfg_effects ---
    mkGlyph = { |x, y, modeFn|
        var uv = UserView(win, Rect(x, y, 76, 24)).background_(~uiPal.paper);
        uv.drawFunc_({ |u| ~uiDrawEcho.(u, modeFn.value) });
        uv;
    };
    if(hasFx) {
        var dlyPop, revPop, bassEz, trebEz, dlyGl, revGl;
        ~uiCap.(win, Rect(600, 96, 380, 14), "space echo");
        ~uiText.(win, Rect(600, 118, 40, 20), "echo", 10.5);
        dlyGl = mkGlyph.(642, 116, { ~cfg_effects.dly_mode });
        // every knob also writes ~cfg_effects: ~savePreset and a window rebuild read it
        dlyPop = ~uiPopup.(win, Rect(726, 116, 190, 24), fxModeItems,
            (~cfg_effects.dly_mode - 1).clip(0, 11), { |idx|
                Ndef(\space_echo_dly).set(\mode, idx + 1);
                ~cfg_effects.dly_mode = idx + 1;
                dlyGl.refresh;
            });
        ~uiText.(win, Rect(600, 150, 40, 20), "rev", 10.5);
        revGl = mkGlyph.(642, 148, { ~cfg_effects.rev_mode });
        revPop = ~uiPopup.(win, Rect(726, 148, 190, 24), fxModeItems,
            (~cfg_effects.rev_mode - 1).clip(0, 11), { |idx|
                Ndef(\space_echo_rev).set(\mode, idx + 1);
                ~cfg_effects.rev_mode = idx + 1;
                revGl.refresh;
            });
        // tone sets BOTH instances; initialized from the rev values
        bassEz = ~uiRulerRow.(win, 600, 182, 42, 190, "bass",
            ControlSpec(-1, 1, \lin, 0, ~cfg_effects.rev_bass), ~cfg_effects.rev_bass, { |v|
                Ndef(\space_echo_rev).set(\bass, v);
                Ndef(\space_echo_dly).set(\bass, v);
                ~cfg_effects.rev_bass = v;
                ~cfg_effects.dly_bass = v;
            }, fmt2);
        trebEz = ~uiRulerRow.(win, 600, 210, 42, 190, "treble",
            ControlSpec(-1, 1, \lin, 0, ~cfg_effects.rev_treble), ~cfg_effects.rev_treble, { |v|
                Ndef(\space_echo_rev).set(\treble, v);
                Ndef(\space_echo_dly).set(\treble, v);
                ~cfg_effects.rev_treble = v;
                ~cfg_effects.dly_treble = v;
            }, fmt2);
        ~mixerFx = ( dlyMode: dlyPop, revMode: revPop, bass: bassEz, treble: trebEz,
            dlyGlyph: dlyGl, revGlyph: revGl );
    };
    ~uiRule.(win, Rect(600, 246, 380, 1));

    // --- project presets: name | save | list | load | refresh ---
    ~uiCap.(win, Rect(600, 258, 380, 14), "preset");
    // separate assignment (see comment at win): chaining via [k]= returns the Event
    presetName = TextField(win, Rect(600, 278, 190, 24)).string_("").font_(~uiMono.(11))
        .background_(~uiPal.paper).stringColor_(~uiPal.ink);
    ~mixerPresetName = presetName;
    ~uiBtn.(win, Rect(798, 278, 70, 24), "save",
        { if(presetName.notNil) { ~savePreset.(presetName.string) } });
    presetPop = ~uiPopup.(win, Rect(600, 310, 190, 24), ["—"], 0, { });
    ~mixerPresetPop = presetPop;
    ~uiBtn.(win, Rect(798, 310, 60, 24), "load", {
        var items = ~listPresets.value;
        var idx = presetPop !? { presetPop[\index] };
        if(idx.notNil and: { items.notEmpty } and: { idx < items.size }) {
            ~loadPreset.(items[idx]);
        };
    });
    ~uiBtn.(win, Rect(866, 310, 80, 24), "refresh", { ~ungRefreshPresets.value });
    ~ungRefreshPresets.value;

    // --- mixer table: one row per layer ---
    ~uiCap.(win, Rect(28, tableY - 18, 100, 14), "layer");
    ~uiCap.(win, Rect(172, tableY - 18, 100, 14), "vol");
    ~uiCap.(win, Rect(372, tableY - 18, 100, 14), "rev · §K.1");
    ~uiCap.(win, Rect(572, tableY - 18, 100, 14), "dly · §K.2");
    ~uiCap.(win, Rect(776, tableY - 18, 44, 14), "mute");
    ~uiCap.(win, Rect(832, tableY - 18, 44, 14), "solo");
    ~uiCap.(win, Rect(888, tableY - 18, 44, 14), "T");
    layers.do { |layer, i|
        var y = tableY + (i * rowH);
        var lv = ~cfg_mixer.levels[layer] ? ~mixerDefaultLevel;
        var hasSpec = ~ungSpecOf.notNil and: { ~ungSpecOf.(layer).notNil };
        var ezV, ezR, ezD, muteBtn, soloBtn, tunBtn;
        ~uiText.(win, Rect(28, y, 22, 20), ~uiPhi[layer] ? "", 14);
        ~uiText.(win, Rect(52, y, 110, 20), layer.asString, 12, ~uiPal.ink, true);
        ezV = ~uiRulerRow.(win, 172, y, 0, 140, "", ControlSpec(0, 1, \lin, 0, lv.vol), lv.vol,
            { |v| ~mixSet.(layer, \vol, v) }, fmt2);
        ezR = ~uiRulerRow.(win, 372, y, 0, 140, "", ControlSpec(0, 1, \lin, 0, lv.sendRev), lv.sendRev,
            { |v| ~mixSet.(layer, \sendRev, v) }, fmt2);
        ezD = ~uiRulerRow.(win, 572, y, 0, 140, "", ControlSpec(0, 1, \lin, 0, lv.sendDly), lv.sendDly,
            { |v| ~mixSet.(layer, \sendDly, v) }, fmt2);
        muteBtn = ~uiBtn.(win, Rect(776, y - 2, 44, 24), "⊘", { ~mixMuteToggle.(layer) },
            ~mixMuted[layer] == true);
        soloBtn = ~uiBtn.(win, Rect(832, y - 2, 44, 24), "◎", { ~mixSoloToggle.(layer) },
            ~mixSoloCur == layer);
        tunBtn  = ~uiBtn.(win, Rect(888, y - 2, 44, 24), "T", { ~openTuner.(layer) });
        // no spec (stub) — tuner unavailable
        if(hasSpec.not) { ~uiBtnEnable.(tunBtn, false) };
        ~mixerEz[layer]      = ( vol: ezV, sendRev: ezR, sendDly: ezD );
        ~mixerSoloBtn[layer] = soloBtn;
        ~mixerMuteBtn[layer] = muteBtn;
    };
    ~uiRule.(win, Rect(0, modY - 12, gx, 1));

    // --- koppelfeld: the patcher of §7 in one click ---
    ~uiCap.(win, Rect(28, modY, 300, 14), "koppelfeld · patch");
    ~uiText.(win, Rect(28, modY + 24, 40, 20), "seed", 10.5, ~uiPal.ink2);
    // 0 = a fresh seed per click; the seed that DREW is written back here, so a
    // patch heard once can be asked for again (A-3)
    patchSeed = NumberBox(win, Rect(70, modY + 22, 120, 24))
        .clipLo_(0).clipHi_(2147483647).step_(1).scroll_step_(1)
        .font_(~uiMono.(11)).align_(\center)
        .background_(~uiPal.paper).normalColor_(~uiPal.ink)
        .value_(~mixerPatchSeedVal ? 0)
        .action_({ |nb| ~mixerPatchSeedVal = nb.value.asInteger });
    ~mixerPatchSeed = patchSeed;
    ~uiText.(win, Rect(206, modY + 24, 200, 20),
        "c ← complexity · arm " ++ (((~cfg_kf !? { |x| x[\armTime] }) ? 4).asString) ++ " s",
        10.5, ~uiPal.ink2);
    patchNote = ~uiText.(win, Rect(400, modY + 24, 490, 20), "", 9.5, ~uiPal.ink2, false, \right);
    ~mixerPatchNote = patchNote;
    ~mixerPatchBtn = ~uiBtn.(win, Rect(900, modY + 22, 80, 24), "patch", {
        var c = (~gridComplexity ? 0.5).clip(0, 1);
        var sd = patchSeed.value.asInteger;
        case
        { ~kfRandomize.isNil or: { ~kfApply.isNil } } {
            patchNote.string_("koppelfeld off (enableKoppelfeld)");
        }
        { ~konActive == true } { patchNote.string_(~mixerPatchLocked) }
        {
            var sch = ~kfRandomize.(if(sd > 0) { sd } { nil }, c);
            if(sch.isNil) {
                // the patcher refuses whole and says why in the post window; the
                // live scheme is untouched, and the panel may not pretend otherwise
                patchNote.string_("patcher refused — see the post window");
            } {
                var rep = sch[\report] ? ();
                ~kfApply.(sch, (~cfg_kf !? { |x| x[\armTime] }) ? 4);
                patchSeed.value_(rep[\seed] ? sd);
                ~mixerPatchSeedVal = patchSeed.value.asInteger;
                patchNote.string_("seed " ++ (rep[\seed] ? "—") ++ " · c " ++ c
                    ++ " · cables " ++ (rep[\cables] ? 0)
                    ++ " · targets " ++ (rep[\targets] ? 0)
                    ++ " · " ++ (sch[\mode] ? "—"));
            };
        };
    });
    if(hasPatch.not) {
        ~uiBtnEnable.(~mixerPatchBtn, false);
        patchNote.string_("koppelfeld off (enableKoppelfeld)");
    };

    // --- koppelfeld: scheme state + arm/disarm + the window of S7 ---
    kfStrip = UserView(win, Rect(28, modY + 48, 610, 20)).background_(~uiPal.paper);
    kfStrip.drawFunc_({ |u| ~mixerDrawKfStrip.(u) });
    // same reason as the graph above: the scheme changes from four places, and
    // the verdict ages under the hand (D99) — a slow self-redraw, not four hooks
    kfStrip.frameRate_(1).animate_(true);
    ~mixerKfStrip = kfStrip;

    armT = { (~cfg_kf !? { |x| x[\armTime] }) ? 4 };
    ~mixerKfBtns = (
        arm: ~uiBtn.(win, Rect(652, modY + 46, 64, 24), "arm",
            { ~kfArm !? { |f| f.(armT.value) } }),
        disarm: ~uiBtn.(win, Rect(722, modY + 46, 74, 24), "disarm",
            { ~kfDisarm !? { |f| f.(armT.value) } }),
        // S7 defines ~openKoppelfeld (precedent ~openMixer/~openTuner/~openViz);
        // until then the button says so instead of doing nothing on a click
        window: ~uiBtn.(win, Rect(804, modY + 46, 176, 24),
            if(~openKoppelfeld.notNil) { "koppelfeld" } { "koppelfeld — not loaded" },
            { ~openKoppelfeld !? (_.value) })
    );
    if(hasPatch.not) {
        [\arm, \disarm].do { |k| ~uiBtnEnable.(~mixerKfBtns[k], false) };
    };
    if(~openKoppelfeld.isNil) { ~uiBtnEnable.(~mixerKfBtns[\window], false) };

    // --- koppelfeld: 16 cable gains per page (§8.4) ---
    ~uiCap.(win, Rect(28, modY + 76, 260, 14), "koppelfeld · cable gains");
    ~mixerGainPop = ~uiPopup.(win, Rect(292, modY + 72, 130, 22), ["—"], 0,
        { |idx| ~kfGainPage = idx; ~kfGuiRelabel !? (_.value) });
    ~mixerGainRows = 16.collect { |i|
        var col = i div: 8, gy = modY + 96 + ((i % 8) * 16);
        var x = 28 + (col * 476);
        var row = ( cable: nil, spec: ControlSpec(0, 4, \lin) );
        row[\txt] = ~uiText.(win, Rect(x, gy, 196, 16), "—", 9.5, ~uiPal.ink2);
        row[\ruler] = ~uiRuler.(win, Rect(x + 200, gy, 176, 14), row[\spec], 0, { |v|
            row[\cable] !? { |c| ~kfGainSet !? { |f| f.(c, v) } };
        });
        row[\ruler][\valTxt] = ~uiText.(win, Rect(x + 382, gy, 56, 16), fmt2.(0), 9.5);
        row[\ruler][\fmt] = fmt2;
        row;
    };
    // mixer export, not module 8's: it dies with the window it draws into
    ~kfGuiRelabel = ~mixerGainRelabel;
    ~kfGuiRelabel.value;

    // --- structure grid (right column); nil-safe without 0_grid ---
    ~uiCap.(win, Rect(rx, 76, rw, 14), "structure grid 16×16");
    // the raster is created BEFORE the TextView: creation order = stacking order
    UserView(win, Rect(rx, 92, rw, 332)).background_(~uiPal.paper2)
        .drawFunc_({ |u| ~uiDrawDither.(u, Rect(74, 8, 230, 316)) });
    // the TextView is fitted to 16x16 Menlo 17; QTextView cannot disable wrapping
    // — the width MUST hold 16 chars plus the scrollbar or the drawing falls apart
    gridTv = TextView(win, Rect(rx + 84, 100, 210, 316))
        .font_(Font("Menlo", 17)).editable_(false)
        .background_(~uiPal.paper).stringColor_(~uiPal.ink);
    // Qt colours flat text through the palette (baseText), not stringColor_ — the
    // colour is reapplied over the range after every string_
    gridTv.palette_(gridTv.palette.baseText_(~uiPal.ink));
    // the field is the act's score: survives a window reopen
    if(~gridLastText.notNil) {
        gridTv.string_(~gridLastText);
        gridTv.setStringColor(~uiPal.ink, 0, ~gridLastText.size);
    };
    ~mixerGridTxt = gridTv;

    // the ruler only stores the value — the button builds the structure
    ~mixerGridEz = ~uiRulerRow.(win, rx, 436, 84, 200, "complexity",
        ControlSpec(0, 1, \lin, 0, ~gridComplexity ? 0.5), ~gridComplexity ? 0.5,
        { |v| ~gridComplexity = v }, fmt2);

    // status: long act status and score path, wraps on its own
    gridStatus = ~uiText.(win, Rect(rx, 540, rw, 56), "", 9.5, ~uiPal.ink2);
    ~mixerGridStatus = gridStatus;

    gridBtn = ~uiBtn.(win, Rect(rx, 468, 90, 26), "generate", {
            // with Konstruktion the button is the ACT; without it, the plain drawing
            if(~konGenerate.notNil) {
                ~konGenerate.(~gridComplexity ? 0.5, nil, ~konTtier);
            } {
                var g = ~gridGenerate.(~gridComplexity ? 0.5);
                if(g.isNil) {
                    gridStatus.string_("no layout after " ++ ~cfg_grid.graphTries ++ " graphs");
                } {
                    ~gridLastText = g[\text];
                    gridTv.string_(g[\text]);
                    gridTv.setStringColor(~uiPal.ink, 0, g[\text].size);
                    gridStatus.string_("Φ " ++ g[\nodes] ++ " · field " ++ g[\cols] ++ "×" ++ g[\rows]);
                };
            };
        }, true);

    // Konstruktion: T_tier (read by the act only), start/stop, score;
    // all nil-safe without 9_konstruktion.scd
    konRange = (~cfg_kon !? { ~cfg_kon[\tTierRange] }) ? [15, 60];
    ~uiText.(win, Rect(rx + 100, 471, 12, 20), "T", 10.5, ~uiPal.ink2);
    konTtierBox = NumberBox(win, Rect(rx + 114, 468, 48, 26))
        .clipLo_(konRange[0]).clipHi_(konRange[1])
        .step_(1).scroll_step_(1)
        .font_(~uiMono.(11)).align_(\center)
        .background_(~uiPal.paper).normalColor_(~uiPal.ink)
        .value_(~konTtier ? ((~cfg_kon !? { ~cfg_kon[\tTier] }) ? 30))
        .action_({ |nb| ~konTtier = nb.value });
    ~uiText.(win, Rect(rx + 168, 471, 12, 20), "s", 10.5, ~uiPal.ink2);
    ~mixerKonTtier = konTtierBox;

    ~mixerKonBtns = (
        start: ~uiBtn.(win, Rect(rx, 504, 60, 26), "start",
            { if((~konActive == true) and: { ~seqStart.notNil }) { ~seqStart.value } }),
        stop:  ~uiBtn.(win, Rect(rx + 66, 504, 60, 26), "stop",
            { if((~konActive == true) and: { ~seqStop.notNil }) { ~seqStop.value } }),
        score: ~uiBtn.(win, Rect(rx + 132, 504, 70, 26), "score", {
            if(~konSaveScore.notNil) { ~konSaveScore.value } {
                gridStatus.string_("Konstruktion not loaded (enableKonstruktion)");
            };
        })
    );

    if(hasGrid) {
        gridStatus.string_("complexity → generate; the field can be selected and copied");
    } {
        ~uiBtnEnable.(gridBtn, false);
        ~uiRulerEnable.(~mixerGridEz, false);
        gridStatus.string_("grid module not loaded (App/0_grid.scd)");
    };

    // --- tiers of the current timeline (act or CONFIG demo) ---
    ~uiRule.(win, Rect(rx, 604, rw, 1));
    ~uiCap.(win, Rect(rx, 614, rw, 14), "tiers");
    tiers = UserView(win, Rect(rx, 632, rw, 130)).background_(~uiPal.paper);
    tiers.drawFunc_({ |u| ~mixerDrawTiers.(u) });
    // low frameRate: block playhead highlight without 60 fps over the whole window
    tiers.frameRate_(2).animate_(true);
    ~mixerTiers = tiers;

    // GUI sync hook <- ~mixSet/~masterSet
    ~mixerGuiSync = { |layer, which, v|
        var r = if(layer == \master) { ~mixerEz[\master] } { ~mixerEz[layer] !? { |row| row[which] } };
        r !? { ~uiRulerSet.(r, v) };
    };

    ~mixerKonSync.value;

    // guard: only the CURRENT window (or one already taken down by ~appCleanup)
    // may clear the slots — the deferred onClose of an OLD window must not wipe
    // registries of the NEW one (contract §6)
    win.onClose_({
        if(~mixerWin.isNil or: { ~mixerWin === win }) { ~mixerResetSlots.value };
    });
    win.front;
};

// open the mixer window (deferred to AppClock)
~openMixer = { { ~ungBuildMixer.value }.defer };

"2_mixer — маршрутизация + сеттеры + окно Desk (~openMixer).".postln;
)
