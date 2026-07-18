// App/2_mixer.scd — UNGRUND · MIXER: per-layer vol + two fx sends (Space Echo
// reverb-forward §K.1 / Space Echo multi-tap echo §K.2), one aggregator per
// send bus, master (LeakDC + Limiter), solo, mute, recorder, mixer window.
// Routes only layers listed in ~activeLayers (set by 1_app.scd).
// Signal flow: docs/architecture/app/README.md.


// ===== CONFIG — edit here ============================================
(
// Level table, key = layer name. vol = level into master; sendRev = Space Echo
// reverb-forward send (§K.1 table), sendDly = Space Echo multi-tap echo send
// (§K.2 table).
// The two sends are independent by canon — see the aggregators below.
// Entries for unloaded layers are simply ignored.
~cfg_mixer = (
    master:  0.9,

    levels: (
        //            vol    sendRev (§K.1)  sendDly (§K.2)
        alpha:   ( vol: 0.85, sendRev: 0.55, sendDly: 0.20 ),
        delta:   ( vol: 0.80, sendRev: 0.45, sendDly: 0.00 ),   // §K.2: binde is not in the delay table
        epsilon: ( vol: 0.75, sendRev: 0.15, sendDly: 0.00 ),   // §K.1: self-diffuse — low send; §K.2: no delay
        zeta:    ( vol: 0.75, sendRev: 0.15, sendDly: 0.00 ),   // §K.2: kratzer is not in the delay table
        theta:   ( vol: 0.80, sendRev: 0.16, sendDly: 0.00 )    // §K.1 splitter; §K.2 zero is a FORBIDDEN move, not a preference: a feedback echo replenishes at constant density exactly what the class's law is exhausting
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

// per-layer router: dry only -> ~busDry (fx sends are collected by the
// single aggregator below so the send bus has exactly ONE writer).
// Konstruktion (user override 2026-07-18) volumes are the performer's — the
// act touches neither \vol nor any fade here, so the plain 0.1 lag stands
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

// send aggregators: ONE PER EFFECT BUS, so the §K.1 and §K.2 send tables stay
// independent — a layer may go to the reverb and NOT to the delay, which a
// single shared send bus cannot express (both effects would read one sum).
// Each aggregator is the SOLE writer of its bus; ReplaceOut => no
// accumulation across blocks.
// both aggregators expose the SAME param names (send_<layer>) — the Ndef they
// live on is what distinguishes the §K.1 send from the §K.2 send
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
    // NO .play: the proxy body already writes via ReplaceOut; a monitor would
    // add a SECOND writer mixing the empty proxy bus on top of ReplaceOut
};

// master: (dry + fx return), LeakDC, Limiter
Ndef(\master, { |amp = 0.9|
    var dry, fx, sig;
    // InFeedback (NOT In): reads buses regardless of node order — routers
    // and effects may sit later in the graph than the master
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
    // a muted / solo-hidden layer keeps its zero at the router; only its stored
    // level moves, so unmuting restores the value the slider now shows
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

// mute + solo compose through ONE apply function: a layer is audible unless it
// is muted, or a solo is active and it is not the soloed one. Levels are read
// from ~cfg_mixer (never overwritten with zeros), so clearing mute/solo
// restores the original mix. ~mixMuted survives a mixer-file reload, and
// ~mixApplyLevels is re-run at load (below) so the rebuilt routers honour it.
~mixMuted = ~mixMuted ? ();   // layer -> true when muted; survives reopen/reload
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
// pressing solo on the same layer again removes solo
~mixSoloToggle = { |layer|
    if(~mixSoloCur == layer) { ~mixUnsolo.value } { ~mixSolo.(layer) };
};

// mute is per-layer and independent — many layers may be muted at once, and a
// mute stands whether or not a solo is active
~mixMuteToggle = { |layer|
    ~mixMuted[layer] = (~mixMuted[layer] != true);
    ~mixApplyLevels.value;
    if(~mixerRefreshMute.notNil) { ~mixerRefreshMute.value };
};

// restore persisted mute/solo onto the freshly (re)built routers/aggregators
~mixApplyLevels.value;

// recorder: records hardware bus 0 — the Recorder node sits at the TAIL of
// the root group, i.e. AFTER Ndef(\master), so the file gets exactly what
// is heard (dry + fx, LeakDC, Limiter, master amp)
~mixRecOn   = ~mixRecOn ? false;   // survives file reload
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
    { if(~mixerRecBtn.notNil) {
        ~mixerRecBtn.value_(if(~mixRecOn) { 1 } { 0 });
    } }.defer;
};


// ===== GUI — mixer window ============================================
// widget registries (idempotent on file reload)
~mixerEz      = ();    // layer -> ( \vol:, \sendRev:, \sendDly: EZSlider ); \master -> EZSlider
~mixerFx      = ();    // space-echo strip: ( dlyMode:, revMode: PopUpMenu; bass:, treble: EZSlider )
~mixerSoloBtn = ();    // layer -> Button (solo)
~mixerMuteBtn = ();    // layer -> Button (mute)
~mixerModEz   = ();    // modmatrix line index -> depth EZSlider (nil-safe; 8_modmatrix.scd)
~mixSoloCur   = ~mixSoloCur;   // current solo layer (or nil), survives reopen

// structure-grid panel slots (0_grid.scd may be absent — panel is nil-safe)
~mixerGridTxt    = nil;   // TextView (поле)
~mixerGridStatus = nil;   // StaticText (число Ф / размер поля / отказ)
~mixerGridEz     = nil;   // EZSlider (сложность)
~gridComplexity  = ~gridComplexity ? 0.5;   // survives reopen / missing 0_grid

// Konstruktion slots (9_konstruktion.scd may be absent — nil-safe like 0_grid)
~mixerKonTtier   = nil;   // NumberBox (T_tier, партитурный — читается только актом)
~mixerKonBtns    = ();    // \start / \stop / \score Buttons
~gridLastText    = ~gridLastText;   // поле — партитура: переживает переоткрытие окна

// enable-состояние кнопок пьесы от ~konActive (зовут постройка окна и акт).
// Гейтится только старт/стоп: «партитура» всегда активна и сама отчитывается
// статусом «нет акта» — молчащая выключенная кнопка читалась как поломка
~mixerKonSync = {
    {
        var on = (~konActive == true);
        [\start, \stop].do { |k|
            if(~mixerKonBtns[k].notNil) { ~mixerKonBtns[k].enabled_(on) };
        };
    }.defer;
};

// update all solo-button visuals from ~mixSoloCur
~mixerRefreshSolo = {
    { ~mixerSoloBtn.keysValuesDo { |layer, btn|
        if(btn.notNil) { btn.value_(if(~mixSoloCur == layer.asSymbol) { 1 } { 0 }) };
    } }.defer;
};

// update all mute-button visuals from ~mixMuted
~mixerRefreshMute = {
    { ~mixerMuteBtn.keysValuesDo { |layer, btn|
        if(btn.notNil) { btn.value_(if(~mixMuted[layer.asSymbol] == true) { 1 } { 0 }) };
    } }.defer;
};

~ungBuildMixer = {
    var layers, rowH, y0, w, h, by, mkRow, masterEz, recBtn;
    var gx, gw, gh, hasGrid, gridTv, gridEz, gridStatus, gridBtn;
    var konRange, konTtierBox, konStartBtn, konStopBtn, konScoreBtn;
    var hasMod;
    var fxY, hasFx, fxModeItems;
    var win;   // local capture: closures must not depend on the global slot
    layers = ~mixerLayers;
    rowH = 30; y0 = 74;
    by = y0 + (layers.size * rowH) + 14;
    // space-echo control strip sits where the master row was; master + all
    // panels below shift down by one row. Present only if effects are loaded
    // (~cfg_effects created by 6_effects.scd; nil when enableEffects=false)
    hasFx = ~cfg_effects.notNil;
    fxY   = by;
    if(hasFx) { by = by + 34 };
    // поле фиксировано 16×16 (user override 2026-07-18): TextView подогнан
    // ровно под 16 строк Menlo 17 (~10.3 px/символ, ~20 px/строка) + рамка.
    // QTextView не умеет отключать перенос — ширина ОБЯЗАНА вмещать 16
    // символов + скроллбар, иначе Qt переносит хвост и псевдографика рассыпается
    gx = 1002; gw = 210;
    w  = gx + gw + 16;
    h  = (by + 40 + 40).max(620);
    gh = 332;
    hasGrid = ~gridGenerate.notNil;
    hasMod  = ~modKeys.notNil and: { ~modKeys.size > 0 };

    // close previous window best-effort (reference may be a destroyed Qt
    // object; .close without try would abort the rebuild — same as tuner)
    if(~mixerWin.notNil) { try { ~mixerWin.close } };
    // reset all slots so nothing touches old widgets during the rebuild gap
    ~mixerWin        = nil;
    ~mixerGuiSync    = nil;
    ~mixerEz         = ();
    ~mixerSoloBtn    = ();
    ~mixerMuteBtn    = ();
    ~mixerModEz      = ();
    ~mixerFx         = ();
    ~modmatrixGuiSync = nil;
    ~modmatrixGuiRelabel = nil;
    ~mixerRecBtn     = nil;
    ~mixerGridTxt    = nil;
    ~mixerGridStatus = nil;
    ~mixerGridEz     = nil;
    ~mixerKonTtier   = nil;
    ~mixerKonBtns    = ();

    win = Window(
        "UNGRUND · mixer — живое сведение слоёв (App)",
        Rect(60, 60, w, h)
    ).background_(Color.gray(0.12));
    ~mixerWin = win;

    StaticText(~mixerWin, Rect(18, 10, w - 36, 22))
        .string_("сведение слоёв — vol в мастер · rev/dly посылы в эффекты · mute/solo · tuner (живой Ndef)")
        .stringColor_(Color.gray(0.92)).font_(Font("Menlo", 13, true));

    StaticText(~mixerWin, Rect(112, 50, 210, 16)).string_("vol -> master")
        .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 9));
    StaticText(~mixerWin, Rect(332, 50, 210, 16)).string_("rev -> space echo · reverb (§K.1)")
        .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 9));
    StaticText(~mixerWin, Rect(552, 50, 210, 16)).string_("dly -> space echo · echo (§K.2)")
        .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 9));

    // one row per layer
    mkRow = { |layer, i|
        var y = y0 + (i * rowH);
        var lv = ~cfg_mixer.levels[layer] ? ~mixerDefaultLevel;
        var hasSpec = ~ungSpecOf.notNil and: { ~ungSpecOf.(layer).notNil };
        var ezV, ezR, ezD, muteBtn, soloBtn, tunBtn;

        StaticText(~mixerWin, Rect(16, y, 92, 24))
            .string_(layer.asString)
            .stringColor_(Color.gray(0.9)).font_(Font("Menlo", 12, true));

        ezV = EZSlider(~mixerWin, Rect(112, y, 210, 24), "vol",
            ControlSpec(0, 1, \lin, 0, lv.vol),
            { |ez| ~mixSet.(layer, \vol, ez.value) }, lv.vol);
        ezV.round_(0.001);

        ezR = EZSlider(~mixerWin, Rect(332, y, 210, 24), "rev",
            ControlSpec(0, 1, \lin, 0, lv.sendRev),
            { |ez| ~mixSet.(layer, \sendRev, ez.value) }, lv.sendRev);
        ezR.round_(0.001);

        ezD = EZSlider(~mixerWin, Rect(552, y, 210, 24), "dly",
            ControlSpec(0, 1, \lin, 0, lv.sendDly),
            { |ez| ~mixSet.(layer, \sendDly, ez.value) }, lv.sendDly);
        ezD.round_(0.001);

        muteBtn = Button(~mixerWin, Rect(772, y, 52, 24))
            .states_([
                ["mute", Color.gray(0.9),  Color.gray(0.26)],
                ["MUTE", Color.white,      Color(0.5, 0.12, 0.12)]
            ])
            .font_(Font("Menlo", 11, true))
            .action_({ ~mixMuteToggle.(layer) });
        muteBtn.value_(if(~mixMuted[layer] == true) { 1 } { 0 });

        soloBtn = Button(~mixerWin, Rect(828, y, 52, 24))
            .states_([
                ["solo", Color.gray(0.9),  Color.gray(0.26)],
                ["SOLO", Color.white,      Color(0.55, 0.42, 0.16)]
            ])
            .font_(Font("Menlo", 11, true))
            .action_({ ~mixSoloToggle.(layer) });
        soloBtn.value_(if(~mixSoloCur == layer) { 1 } { 0 });

        tunBtn = Button(~mixerWin, Rect(884, y, 100, 24))
            .states_([["tuner", Color.white, Color(0.18, 0.34, 0.44)]])
            .font_(Font("Menlo", 11, true))
            .action_({ ~openTuner.(layer) });
        if(hasSpec.not) {
            // no spec (stub) — tuner unavailable
            tunBtn.states_([["tuner —", Color.gray(0.4), Color.gray(0.18)]])
                .enabled_(false);
        };

        ~mixerEz[layer]      = ( vol: ezV, sendRev: ezR, sendDly: ezD );
        ~mixerSoloBtn[layer] = soloBtn;
        ~mixerMuteBtn[layer] = muteBtn;
    };
    layers.do { |layer, i| mkRow.(layer, i) };

    // --- master row + buttons ---
    StaticText(~mixerWin, Rect(16, by, 92, 24))
        .string_("master").stringColor_(Color.white).font_(Font("Menlo", 12, true));
    masterEz = EZSlider(~mixerWin, Rect(112, by, 210, 24), "amp",
        ControlSpec(0, 1, \lin, 0, ~cfg_mixer.master),
        { |ez| ~masterSet.(ez.value) }, ~cfg_mixer.master);
    masterEz.round_(0.001);
    ~mixerEz[\master] = masterEz;

    Button(~mixerWin, Rect(332, by, 130, 24))
        .states_([["all / unsolo", Color.gray(0.95), Color.gray(0.28)]])
        .font_(Font("Menlo", 11, true))
        .action_({ ~mixUnsolo.value });

    // record button state lives in ~mixRecOn, so it stays correct after
    // close/reopen while recording
    recBtn = Button(~mixerWin, Rect(472, by, 110, 24))
        .states_([
            ["● rec",  Color.gray(0.9), Color.gray(0.26)],
            ["■ REC",  Color.white,     Color(0.62, 0.14, 0.14)]
        ])
        .font_(Font("Menlo", 11, true))
        .action_({ ~mixRecToggle.value });
    recBtn.value_(if(~mixRecOn) { 1 } { 0 });
    ~mixerRecBtn = recBtn;
    Button(~mixerWin, Rect(884, by, 100, 24))
        .states_([["закрыть", Color.gray(0.9), Color(0.4, 0.18, 0.18)]])
        .font_(Font("Menlo", 11))
        .action_({ win.close });

    // --- space echo control strip (mode selectors + tone) ---
    // mode = head-mask × reverb table (12 positions). Rows 1–4 = ECHO/delay
    // modes (reverb OFF); 5–12 include the spring reverb. Both instances get a
    // selector so the delay modes are reachable, per the §K.2 unit. Tone (bass +
    // treble) is a global fx tone wired to both instances' RE-201 shelves.
    // All six params live in ~cfg_effects (rev_/dly_mode, rev_/dly_bass,
    // rev_/dly_treble) and drive the Ndefs at load — the GUI rides on top.
    if(hasFx) {
        var dlyPop, revPop, bassEz, trebEz;
        fxModeItems = [
            "1 ·1 tap", "2 ·2 tap", "3 ·1+2 tap", "4 ·1+2+3 echo",
            "5 ·1 +rev", "6 ·2 +rev", "7 ·3 +rev", "8 ·1+2 +rev",
            "9 ·2+3 +rev", "10 ·1+3 +rev", "11 all +rev", "12 rev only"
        ];
        StaticText(~mixerWin, Rect(16, fxY, 92, 24))
            .string_("space echo").stringColor_(Color(0.55, 0.7, 0.85))
            .font_(Font("Menlo", 12, true));

        StaticText(~mixerWin, Rect(112, fxY, 40, 24)).string_("echo")
            .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 10));
        dlyPop = PopUpMenu(~mixerWin, Rect(154, fxY, 168, 24))
            .items_(fxModeItems).font_(Font("Menlo", 11))
            .value_((~cfg_effects.dly_mode - 1).clip(0, 11))
            .action_({ |m| Ndef(\space_echo_dly).set(\mode, m.value + 1) });

        StaticText(~mixerWin, Rect(332, fxY, 34, 24)).string_("rev")
            .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 10));
        revPop = PopUpMenu(~mixerWin, Rect(368, fxY, 174, 24))
            .items_(fxModeItems).font_(Font("Menlo", 11))
            .value_((~cfg_effects.rev_mode - 1).clip(0, 11))
            .action_({ |m| Ndef(\space_echo_rev).set(\mode, m.value + 1) });

        // tone knobs set BOTH instances (global fx tone); init from rev values
        bassEz = EZSlider(~mixerWin, Rect(552, fxY, 210, 24), "bass",
            ControlSpec(-1, 1, \lin, 0, ~cfg_effects.rev_bass),
            { |ez|
                Ndef(\space_echo_rev).set(\bass, ez.value);
                Ndef(\space_echo_dly).set(\bass, ez.value);
            }, ~cfg_effects.rev_bass);
        bassEz.round_(0.01);

        trebEz = EZSlider(~mixerWin, Rect(772, fxY, 210, 24), "treble",
            ControlSpec(-1, 1, \lin, 0, ~cfg_effects.rev_treble),
            { |ez|
                Ndef(\space_echo_rev).set(\treble, ez.value);
                Ndef(\space_echo_dly).set(\treble, ez.value);
            }, ~cfg_effects.rev_treble);
        trebEz.round_(0.01);

        ~mixerFx = ( dlyMode: dlyPop, revMode: revPop, bass: bassEz, treble: trebEz );
    };

    // --- модуляционная матрица (панель слева, под master) ---
    // nil-безопасна: без App/8_modmatrix.scd (enableModMatrix=false) панель
    // выключена — тем же приёмом, что hasGrid у сетки. Индекс i строки == индекс
    // в ~cfg_modmtx.lines, так что ~modDepthSet.(i, ...) адресует ту же связь.
    // Заголовок ВНУТРИ ветки: безусловный заголовок над заглушкой читается как
    // «пустое место» и путает (отсюда баг-репорт 2026-07-17).
    if(hasMod) {
        StaticText(~mixerWin, Rect(16, by + 40, 660, 16))
            .string_("модуляционная матрица — 16 уровней влияния (частота одной связи ведёт другую)")
            .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 9));
        Button(~mixerWin, Rect(684, by + 37, 140, 20))
            .states_([["рандом связей", Color.white, Color(0.28, 0.2, 0.44)]])
            .font_(Font("Menlo", 10, true))
            .action_({ if(~modRandomize.notNil) { ~modRandomize.value } });
        ~modKeys.do { |e, i|
            var col = i div: 8;
            var row = i mod: 8;
            var mx  = 16 + (col * 492);
            var my  = by + 60 + (row * 24);
            var ez;
            ez = EZSlider(~mixerWin, Rect(mx, my, 470, 22), e[\label],
                ControlSpec(0, 1, \lin, 0, e[\depth]),
                { |sl| ~modDepthSet.(i, sl.value) }, e[\depth]);
            ez.round_(0.001);
            ez.labelView.stringColor_(Color.white);
            // связь на незагруженном слое (subset ~cfg_app.layers) — слайдер виден, но мёртв
            if(e[\enabled].not) { ez.enabled_(false) };
            ~mixerModEz[i] = ez;
        };
    } {
        StaticText(~mixerWin, Rect(16, by + 40, 900, 18))
            .string_("модуляционная матрица ВЫКЛ — включи ~cfg_app.enableModMatrix = true и перезапусти весь блок 1_app.scd")
            .stringColor_(Color(0.85, 0.55, 0.2)).font_(Font("Menlo", 11, true));
    };

    // --- структурная сетка (панель справа) ---
    // панель nil-безопасна: без App/0_grid.scd кнопка выключена — тем же
    // приёмом, что hasSpec у кнопки tuner
    StaticText(~mixerWin, Rect(gx, 50, gw, 16))
        .string_("структурная сетка 16×16 (канон)")
        .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 9));

    gridTv = TextView(~mixerWin, Rect(gx, y0, gw, gh))
        .font_(Font("Menlo", 17))
        .editable_(false)
        .background_(Color.gray(0.08))
        .stringColor_(Color.white);
    // Qt: плоский текст красится палитрой (baseText), stringColor_ его не берёт —
    // см. note в TextView.schelp; после каждого string_ цвет добивается по диапазону
    gridTv.palette_(gridTv.palette.baseText_(Color.white));
    // поле — партитура текущего акта: обязано пережить переоткрытие окна
    if(~gridLastText.notNil) {
        gridTv.string_(~gridLastText);
        gridTv.setStringColor(Color.white, 0, ~gridLastText.size);
    };
    ~mixerGridTxt = gridTv;

    gridEz = EZSlider(~mixerWin, Rect(gx, y0 + gh + 8, gw, 24), "сложность",
        ControlSpec(0, 1, \lin, 0, ~gridComplexity ? 0.5),
        // слайдер только пишет ~gridComplexity: перерисовывать поле на каждый
        // пиксель движения незачем, структуру строит кнопка
        { |ez| ~gridComplexity = ez.value }, ~gridComplexity ? 0.5);
    gridEz.round_(0.01);
    ~mixerGridEz = gridEz;

    // до 5 строк статуса Menlo 9: сюда пишутся и длинный статус акта,
    // и путь записанной партитуры — StaticText переносит сам
    gridStatus = StaticText(~mixerWin, Rect(gx, y0 + gh + 98, gw, 56))
        .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 9));
    ~mixerGridStatus = gridStatus;

    gridBtn = Button(~mixerWin, Rect(gx, y0 + gh + 38, 118, 24))
        .states_([["сгенерировать", Color.white, Color(0.18, 0.34, 0.44)]])
        .font_(Font("Menlo", 11, true))
        .action_({
            // с модулем Konstruktion кнопка = АКТ (поле + таймлайн + 16 линий,
            // GUI обновляет сам акт); без него — прежний чистый рисунок
            if(~konGenerate.notNil) {
                ~konGenerate.(~gridComplexity ? 0.5, nil, ~konTtier);
            } {
                var g = ~gridGenerate.(~gridComplexity ? 0.5);
                if(g.isNil) {
                    gridStatus.string_(
                        "отказ: не разложилось за " ++ ~cfg_grid.graphTries ++ " графов"
                    );
                } {
                    ~gridLastText = g[\text];
                    gridTv.string_(g[\text]);
                    gridTv.setStringColor(Color.white, 0, g[\text].size);
                    gridStatus.string_(
                        "Ф: " ++ g[\nodes] ++ " · поле: " ++ g[\cols] ++ "×" ++ g[\rows]
                    );
                };
            };
        });

    // Konstruktion: T_tier — параметр партитуры (читается только актом),
    // старт/стоп пьесы и партитура; всё nil-safe без 9_konstruktion.scd
    konRange = (~cfg_kon !? { ~cfg_kon[\tTierRange] }) ? [15, 60];
    StaticText(~mixerWin, Rect(gx + 122, y0 + gh + 38, 12, 24)).string_("T")
        .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 10));
    konTtierBox = NumberBox(~mixerWin, Rect(gx + 136, y0 + gh + 38, 44, 24))
        .clipLo_(konRange[0]).clipHi_(konRange[1])
        .step_(1).scroll_step_(1)
        .font_(Font("Menlo", 11))
        .value_(~konTtier ? ((~cfg_kon !? { ~cfg_kon[\tTier] }) ? 30))
        .action_({ |nb| ~konTtier = nb.value });
    ~mixerKonTtier = konTtierBox;

    konStartBtn = Button(~mixerWin, Rect(gx, y0 + gh + 68, 64, 24))
        .states_([["старт", Color.white, Color(0.2, 0.4, 0.24)]])
        .font_(Font("Menlo", 11, true))
        .action_({ if((~konActive == true) and: { ~seqStart.notNil }) { ~seqStart.value } });
    konStopBtn = Button(~mixerWin, Rect(gx + 68, y0 + gh + 68, 64, 24))
        .states_([["стоп", Color.white, Color(0.42, 0.2, 0.2)]])
        .font_(Font("Menlo", 11, true))
        .action_({ if((~konActive == true) and: { ~seqStop.notNil }) { ~seqStop.value } });
    konScoreBtn = Button(~mixerWin, Rect(gx + 136, y0 + gh + 68, 74, 24))
        .states_([["партитура", Color.white, Color(0.3, 0.3, 0.42)]])
        .font_(Font("Menlo", 11, true))
        .action_({
            if(~konSaveScore.notNil) { ~konSaveScore.value } {
                gridStatus.string_("модуль Konstruktion не загружен (enableKonstruktion)");
            };
        });
    ~mixerKonBtns = ( start: konStartBtn, stop: konStopBtn, score: konScoreBtn );
    ~mixerKonSync.value;

    if(hasGrid) {
        gridStatus.string_("сложность -> кнопка; поле выделяется и копируется");
    } {
        gridBtn.states_([["сетка —", Color.gray(0.4), Color.gray(0.18)]])
            .enabled_(false);
        gridEz.enabled_(false);
        gridStatus.string_("модуль сетки не загружен (App/0_grid.scd)");
    };

    // GUI sync hook <- ~mixSet/~masterSet
    ~mixerGuiSync = { |layer, which, v|
        {
            if(layer == \master) {
                if(~mixerEz[\master].notNil) { ~mixerEz[\master].value_(v) };
            } {
                var row = ~mixerEz[layer];
                if(row.notNil and: { row[which].notNil }) { row[which].value_(v) };
            };
        }.defer;
    };

    // modmatrix depth sync <- ~modDepthSet (value_ never fires the action, so
    // no fader<->setter feedback loop — same reason as ~mixerGuiSync)
    ~modmatrixGuiSync = { |i, v|
        { if(~mixerModEz[i].notNil) { ~mixerModEz[i].value_(v) } }.defer;
    };

    // relabel hook <- ~konGenerate: после ~modBuild подписи src→dst меняются
    // на месте, без пересборки окна
    ~modmatrixGuiRelabel = { |i, label|
        { if(~mixerModEz[i].notNil) { ~mixerModEz[i].labelView.string_(label) } }.defer;
    };

    // clear registries only if this is still the CURRENT window (or it was
    // already taken down by ~appCleanup, which nils ~mixerWin before the
    // deferred close) — otherwise the deferred onClose of an OLD window
    // would wipe slots registered by the NEW one (same trap as the tuner)
    win.onClose_({
        if(~mixerWin.isNil or: { ~mixerWin === win }) {
            ~mixerGuiSync    = nil;
            ~mixerEz         = ();
            ~mixerSoloBtn    = ();
            ~mixerMuteBtn    = ();
            ~mixerModEz      = ();
            ~modmatrixGuiSync = nil;
            ~modmatrixGuiRelabel = nil;
            ~mixerRecBtn     = nil;
            ~mixerGridTxt    = nil;
            ~mixerGridStatus = nil;
            ~mixerGridEz     = nil;
            ~mixerKonTtier   = nil;
            ~mixerKonBtns    = ();
            ~mixerWin        = nil;
        };
    });
    win.front;
};

// open the mixer window (deferred to AppClock)
~openMixer = { { ~ungBuildMixer.value }.defer };

"2_mixer — маршрутизация + сеттеры + окно микшера (~openMixer).".postln;
)
