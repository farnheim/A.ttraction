// App/2_mixer.scd — UNGRUND · MIXER: per-layer vol + two fx sends (reverb
// §K.1 / delay §K.2), one aggregator per send bus, master (LeakDC +
// Limiter), solo, recorder, mixer window.
// Routes only layers listed in ~activeLayers (set by 1_app.scd).
// Signal flow: docs/architecture/app/README.md.


// ===== CONFIG — edit here ============================================
(
// Level table, key = layer name. vol = level into master; sendRev = tape
// reverb send (§K.1 table), sendDly = ping-pong delay send (§K.2 table).
// The two sends are independent by canon — see the aggregators below.
// Entries for unloaded layers are simply ignored.
~cfg_mixer = (
    master:  0.9,

    levels: (
        //            vol    sendRev (§K.1)  sendDly (§K.2)
        alpha:   ( vol: 0.85, sendRev: 0.55, sendDly: 0.20 ),
        beta:    ( vol: 0.00, sendRev: 0.00, sendDly: 0.00 ),   // stub — off
        gamma:   ( vol: 0.80, sendRev: 0.35, sendDly: 0.20 ),   // §K.1 flockung; the send is the drips' ONLY space
        delta:   ( vol: 0.80, sendRev: 0.45, sendDly: 0.00 ),   // §K.2: binde is not in the delay table
        epsilon: ( vol: 0.75, sendRev: 0.15, sendDly: 0.00 ),   // §K.1: self-diffuse — low send; §K.2: no delay
        zeta:    ( vol: 0.75, sendRev: 0.15, sendDly: 0.00 ),   // §K.2: kratzer is not in the delay table
        eta:     ( vol: 0.00, sendRev: 0.00, sendDly: 0.00 ),   // silence — no level
        theta:   ( vol: 0.80, sendRev: 0.18, sendDly: 0.00 )    // §K.1 schotter; §K.2 zero is a FORBIDDEN move, not a preference: the delay's 0.37/0.53 s taps put phantom events off the grid
    )
);

// fallback levels for a layer missing from the table (new synths/*.scd)
~mixerDefaultLevel = ( vol: 0.7, sendRev: 0.0, sendDly: 0.0 );

// master-sum recorder: file format and dir (relative to project root)
~cfg_recorder = ( header: "wav", sample: "int24", dir: "recordings" );


// ===== LOGIC — routers + master + GUI ================================
~mixerLayers = ~activeLayers ? [\alpha, \beta, \gamma, \delta, \epsilon, \zeta, \eta, \theta];

// ensure a level entry for every active layer
~mixerLayers.do { |layer|
    if(~cfg_mixer.levels[layer].isNil) {
        ~cfg_mixer.levels[layer] = ~mixerDefaultLevel.copy;
    };
};

// per-layer router: dry only -> ~busDry (fx sends are collected by the
// single aggregator below so the send bus has exactly ONE writer)
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
    if(agg.notNil) {
        Ndef(agg).set(("send_" ++ layer).asSymbol, value);
    } {
        Ndef(("mix_" ++ layer).asSymbol).set(\vol, value);
    };
    ~cfg_mixer.levels[layer][which] = value;
    if(~mixerGuiSync.notNil) { ~mixerGuiSync.(layer, which, value) };
};
~masterSet = { |value|
    Ndef(\master).set(\amp, value); ~cfg_mixer.master = value;
    if(~mixerGuiSync.notNil) { ~mixerGuiSync.(\master, \amp, value) };
};

// solo / unsolo: levels are read from ~cfg_mixer (never overwritten with
// zeros), so unsolo restores the original mix
~mixSolo = { |layer|
    ~mixerLayers.do { |l|
        var on = (l == layer);
        var lv = ~cfg_mixer.levels[l];
        Ndef(("mix_" ++ l).asSymbol).set(\vol, on.if({ lv.vol }, 0));
        ~mixerSendAgg.keysValuesDo { |which, agg|
            Ndef(agg).set(("send_" ++ l).asSymbol, on.if({ lv[which] }, 0));
        };
    };
    ~mixSoloCur = layer;
    if(~mixerRefreshSolo.notNil) { ~mixerRefreshSolo.value };
};
~mixUnsolo = {
    ~mixerLayers.do { |l|
        var lv = ~cfg_mixer.levels[l];
        Ndef(("mix_" ++ l).asSymbol).set(\vol, lv.vol);
        ~mixerSendAgg.keysValuesDo { |which, agg|
            Ndef(agg).set(("send_" ++ l).asSymbol, lv[which]);
        };
    };
    ~mixSoloCur = nil;
    if(~mixerRefreshSolo.notNil) { ~mixerRefreshSolo.value };
};
// pressing solo on the same layer again removes solo
~mixSoloToggle = { |layer|
    if(~mixSoloCur == layer) { ~mixUnsolo.value } { ~mixSolo.(layer) };
};

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
~mixerSoloBtn = ();    // layer -> Button (solo)
~mixSoloCur   = ~mixSoloCur;   // current solo layer (or nil), survives reopen

// update all solo-button visuals from ~mixSoloCur
~mixerRefreshSolo = {
    { ~mixerSoloBtn.keysValuesDo { |layer, btn|
        if(btn.notNil) { btn.value_(if(~mixSoloCur == layer.asSymbol) { 1 } { 0 }) };
    } }.defer;
};

~ungBuildMixer = {
    var layers, rowH, y0, w, h, by, mkRow, masterEz, recBtn;
    var win;   // local capture: closures must not depend on the global slot
    layers = ~mixerLayers;
    rowH = 30; y0 = 74;
    by = y0 + (layers.size * rowH) + 14;
    w  = 954; h = by + 40 + 40;

    // close previous window best-effort (reference may be a destroyed Qt
    // object; .close without try would abort the rebuild — same as tuner)
    if(~mixerWin.notNil) { try { ~mixerWin.close } };
    // reset all slots so nothing touches old widgets during the rebuild gap
    ~mixerWin     = nil;
    ~mixerGuiSync = nil;
    ~mixerEz      = ();
    ~mixerSoloBtn = ();
    ~mixerRecBtn  = nil;

    win = Window(
        "UNGRUND · mixer — живое сведение слоёв (App)",
        Rect(60, 60, w, h)
    ).background_(Color.gray(0.12));
    ~mixerWin = win;

    StaticText(~mixerWin, Rect(18, 10, w - 36, 22))
        .string_("сведение слоёв — vol в мастер · rev/dly посылы в эффекты · solo · tuner (живой Ndef)")
        .stringColor_(Color.gray(0.92)).font_(Font("Menlo", 13, true));

    StaticText(~mixerWin, Rect(112, 50, 210, 16)).string_("vol -> master")
        .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 9));
    StaticText(~mixerWin, Rect(332, 50, 210, 16)).string_("rev -> tape reverb (§K.1)")
        .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 9));
    StaticText(~mixerWin, Rect(552, 50, 210, 16)).string_("dly -> ping-pong (§K.2)")
        .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 9));

    // one row per layer
    mkRow = { |layer, i|
        var y = y0 + (i * rowH);
        var lv = ~cfg_mixer.levels[layer] ? ~mixerDefaultLevel;
        var hasSpec = ~ungSpecOf.notNil and: { ~ungSpecOf.(layer).notNil };
        var ezV, ezR, ezD, soloBtn, tunBtn;

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

        soloBtn = Button(~mixerWin, Rect(772, y, 56, 24))
            .states_([
                ["solo", Color.gray(0.9),  Color.gray(0.26)],
                ["SOLO", Color.white,      Color(0.55, 0.42, 0.16)]
            ])
            .font_(Font("Menlo", 11, true))
            .action_({ ~mixSoloToggle.(layer) });
        soloBtn.value_(if(~mixSoloCur == layer) { 1 } { 0 });

        tunBtn = Button(~mixerWin, Rect(836, y, 100, 24))
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
    Button(~mixerWin, Rect(836, by, 100, 24))
        .states_([["закрыть", Color.gray(0.9), Color(0.4, 0.18, 0.18)]])
        .font_(Font("Menlo", 11))
        .action_({ win.close });

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

    // clear registries only if this is still the CURRENT window (or it was
    // already taken down by ~appCleanup, which nils ~mixerWin before the
    // deferred close) — otherwise the deferred onClose of an OLD window
    // would wipe slots registered by the NEW one (same trap as the tuner)
    win.onClose_({
        if(~mixerWin.isNil or: { ~mixerWin === win }) {
            ~mixerGuiSync = nil;
            ~mixerEz      = ();
            ~mixerSoloBtn = ();
            ~mixerRecBtn  = nil;
            ~mixerWin     = nil;
        };
    });
    win.front;
};

// open the mixer window (deferred to AppClock)
~openMixer = { { ~ungBuildMixer.value }.defer };

"2_mixer — маршрутизация + сеттеры + окно микшера (~openMixer).".postln;
)
