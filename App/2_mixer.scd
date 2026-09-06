// App/2_mixer.scd — UNGRUND · MIXER: vol на слой + два fx-посыла (§K.1/§K.2),
// по агрегатору на шину, master (LeakDC + Limiter), solo/mute, рекордер, окно Desk.
// Маршрутизирует только ~activeLayers. Сигнал-флоу: docs/architecture/app/README.md.


// ===== CONFIG — edit here ============================================
(
// vol -> master; sendRev/sendDly -> таблицы §K.1/§K.2 (независимы по канону).
// `? ()`: живое сведение — СОСТОЯНИЕ, переживает hot-reload; таблица лишь
// сеет свежую сессию (авто-пресет затем перекрывает её)
~cfg_mixer = ~cfg_mixer ? (
    master:  0.9,

    levels: (
        //            vol    sendRev (§K.1)  sendDly (§K.2)
        alpha:   ( vol: 0.85, sendRev: 0.55, sendDly: 0.20 ),
        delta:   ( vol: 0.80, sendRev: 0.45, sendDly: 0.00 ),   // §K.2: binde is not in the delay table
        epsilon: ( vol: 0.75, sendRev: 0.15, sendDly: 0.00 ),   // §K.1: self-diffuse — low send; §K.2: no delay
        zeta:    ( vol: 0.75, sendRev: 0.15, sendDly: 0.00 ),   // §K.2: kratzer is not in the delay table
        theta:   ( vol: 0.80, sendRev: 0.16, sendDly: 0.00 )    // §K.2 ноль — ЗАПРЕТ, не вкус: эхо восполняло бы то, что истощает закон класса
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

// роутер слоя: только dry -> ~busDry (посылы собирает агрегатор ниже — у шины
// ровно ОДИН писатель); громкости у исполнителя (override 2026-07-18)
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

// агрегаторы посылов: ПО ОДНОМУ НА ШИНУ (таблицы §K.1/§K.2 независимы), каждый
// — единственный писатель своей шины (ReplaceOut: без накопления); имена
// параметров send_<layer> одинаковы — различает их Ndef
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
    // БЕЗ .play: тело уже пишет через ReplaceOut, монитор стал бы ВТОРЫМ писателем
};

// master: (dry + fx return), LeakDC, Limiter
Ndef(\master, { |amp = 0.9|
    var dry, fx, sig;
    // InFeedback, не In: читает шины независимо от порядка узлов
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
    // у muted/solo-скрытого слоя двигается только хранимый уровень — unmute
    // вернёт значение, которое сейчас показывает слайдер
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

// mute + solo сходятся в ОДНОЙ apply-функции; уровни читаются из ~cfg_mixer
// (нулями не перетираются) — снятие mute/solo возвращает исходный микс
~mixMuted = ~mixMuted ? ();   // layer -> true; переживает reopen/reload
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

// восстановить mute/solo на свежесобранных роутерах/агрегаторах
~mixApplyLevels.value;

// recorder пишет шину 0 с ХВОСТА root-группы (после Ndef(\master)) — в файл
// попадает ровно то, что слышно
~mixRecOn   = ~mixRecOn ? false;   // переживает reload
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


// ===== GUI — окно Desk (монохром; макет docs/architecture/app/ui/Main.dc.html) =====
// widget registries (idempotent on file reload)
~mixerEz      = ();    // layer -> ( \vol:, \sendRev:, \sendDly: ruler ); \master -> ruler
~mixerFx      = ();    // space-echo strip: ( dlyMode:, revMode: PopUpMenu; bass:, treble: ruler; dlyGlyph:, revGlyph: UserView )
~mixerSoloBtn = ();    // layer -> Button (solo)
~mixerMuteBtn = ();    // layer -> Button (mute)
~mixerModNote = nil;   // StaticText: why random is locked
~mixerModEz   = ();    // modmatrix line index -> ruler with [\label] StaticText + [\glyph] UserView (nil-safe; 8_modmatrix.scd)
~mixerModRnd  = nil;   // Button (random) — disabled while an act is active
~mixerGraph   = nil;   // UserView: mod graph (straight lines layer -> param)
~mixerTiers   = nil;   // UserView: tiers of ~seqTimeline
~mixerPresetPop  = nil;   // PopUpMenu (project presets; read by ~ungRefreshPresets)
~mixerPresetName = nil;   // TextField (preset name)
~mixSoloCur   = ~mixSoloCur;   // current solo layer (or nil), survives reopen

// structure-grid panel slots (0_grid.scd may be absent — panel is nil-safe)
~mixerGridTxt    = nil;   // TextView (поле)
~mixerGridStatus = nil;   // StaticText (число Ф / размер поля / отказ)
~mixerGridEz     = nil;   // ruler (сложность)
~gridComplexity  = ~gridComplexity ? 0.5;   // survives reopen / missing 0_grid

// Konstruktion slots (9_konstruktion.scd may be absent — nil-safe like 0_grid)
~mixerKonTtier   = nil;   // NumberBox (T_tier, партитурный — читается только актом)
~mixerKonBtns    = ();    // \start / \stop / \score Buttons
~gridLastText    = ~gridLastText;   // поле — партитура: переживает переоткрытие окна

// enable кнопок пьесы от ~konActive; гейтится только старт/стоп — «score»
// всегда активна и сама отчитывается статусом «нет акта»; random — наоборот
~mixerKonSync = {
    {
        var on = (~konActive == true);
        [\start, \stop].do { |k|
            ~uiBtnEnable.(~mixerKonBtns[k], on);
        };
        ~uiBtnEnable.(~mixerModRnd, on.not);
        ~mixerModNote !? { |t|
            t.string_(if(on) { "locked while an act is active" } { "" });
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
    ~mixerModEz      = ();
    ~mixerModRnd     = nil;
    ~mixerModNote    = nil;
    ~mixerGraph      = nil;
    ~mixerTiers      = nil;
    ~mixerFx         = ();
    ~mixerPresetPop  = nil;
    ~mixerPresetName = nil;
    ~modmatrixGuiSync = nil;
    ~modmatrixGuiRelabel = nil;
    ~mixerRecBtn     = nil;
    ~mixerGridTxt    = nil;
    ~mixerGridStatus = nil;
    ~mixerGridEz     = nil;
    ~mixerKonTtier   = nil;
    ~mixerKonBtns    = ();
};

// --- глифы --------------------------------------------------------------
// space echo: три головки ленты (маски режима из 6_effects) + пружина при ревере
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

~uiDrawLineGlyph = { |u, e|
    var w = u.bounds.width, y = u.bounds.height / 2;
    var ticks = ((e[\rate] ? 0) * 10).round.asInteger.clip(0, 12);
    var col = if(e[\enabled] ? true) { ~uiPal.ink } { ~uiPal.rule };
    Pen.use {
        Pen.strokeColor = col; Pen.width = ~uiLineWidth;
        Pen.lineDash = ~uiLineDash.(e[\depth] ? 0, e[\shape]);
        Pen.line(4@y, (w - 12)@y); Pen.stroke;
    };
    Pen.strokeColor = col; Pen.width = 1;
    ticks.do { |i| var x = 8 + (i * ((w - 28) / ticks.max(1))); Pen.line(x@(y - 8), x@(y - 4)) };
    Pen.stroke;
    Pen.moveTo((w - 12)@(y - 5)); Pen.lineTo((w - 2)@y); Pen.lineTo((w - 12)@(y + 5));
    Pen.lineTo((w - 12)@(y - 5));
    Pen.fillColor = if((e[\fm] ? 0) >= 0.6) { col } { ~uiPal.paper };
    Pen.fillStroke;
};

// координаты подобраны вручную под асимметрию рисунка; новый звуковой класс
// НЕ появится в графе, пока не получит место в обеих таблицах
~mixerGraphPos = ( theta: 270@62, delta: 462@66, alpha: 100@212, zeta: 462@214, epsilon: 270@302 );
~mixerGraphStacks = (
    theta:   ( kind: \row, x: 312, y: 104, step: 44 ),
    delta:   ( kind: \col, x: 392, y: 52,  side: \start ),
    alpha:   ( kind: \col, x: 68,  y: 190, side: \end ),
    zeta:    ( kind: \col, x: 392, y: 200, side: \start ),
    epsilon: ( kind: \row, x: 226, y: 262, step: 44 )
);
~mixerDrawGraph = { |u|
    var keys = ~modKeys ? [], per = (), font = ~uiMono.(9), gfont = ~uiMono.(28), nfont = ~uiMono.(10);
    var kon = ~konCurrent;
    // источник линии — слой ВЕДУЩЕЙ связи (~modKeys[src]), не её собственная цель
    var srcLayer = { |e| (keys[e[\src] ? -1] !? { |k| k[\target] }) ? e[\target] };
    var posOf = { |layer| if(~mixerLayers.includes(layer)) { ~mixerGraphPos[layer] } };
    var srcPos = { |e| posOf.(srcLayer.(e)) };
    var short = { |i| var s = (~modShort ? [])[i].asString; s.copyToEnd((s.indexOf($.) ? -1) + 1) };
    // связь рисуется, только если ОБА её конца — загруженные слои с местом на
    // поле: иначе линия сходилась бы в пустоту (у незагруженного слоя нет знака)
    keys.do { |e|
        if(posOf.(e[\target]).notNil and: { srcPos.(e).notNil }) {
            per[e[\target]] = (per[e[\target]] ? []).add(e);
        };
    };
    per.keysValuesDo { |t, arr|
        var st = ~mixerGraphStacks[t], dst = ~mixerGraphPos[t], sorted;
        if(st.notNil and: { dst.notNil }) {
            sorted = if(st[\kind] == \row) {
                arr.sort { |a, b| srcPos.(a).x <= srcPos.(b).x }
            } { arr };
            sorted.do { |e, k|
                var src = srcPos.(e), txt = short.(e[\index]), bw = txt.bounds(font).width;
                var lx, ly, tx, ty, dx, dy, d, sx, sy, ex, ey, loop, nx, ny;
                if(st[\kind] == \col) {
                    ly = st[\y] + (k * 17);
                    tx = st[\x]; ty = ly + 6;
                    lx = if(st[\side] == \start) { st[\x] + 4 } { st[\x] - 4 - bw };
                } {
                    tx = st[\x] + (k * st[\step]); ly = st[\y]; lx = tx - (bw / 2);
                    ty = if(src.y > ly) { ly + 13 } { ly - 2 };
                };
                dx = tx - src.x; dy = ty - src.y; d = dx.hypot(dy).max(1);
                sx = src.x + (dx / d * 20); sy = src.y + (dy / d * 20);
                ex = tx - (dx / d * 5);   ey = ty - (dy / d * 5);
                loop = kon.notNil and: { (kon[\lines][e[\index]] !? { |ln| ln[\loopAB] }) == 1 };
                Pen.use {
                    Pen.strokeColor = if(e[\enabled]) { ~uiPal.ink } { ~uiPal.rule };
                    Pen.width = ~uiLineWidth;
                    Pen.lineDash = ~uiLineDash.(e[\depth], e[\shape]);
                    if(loop) {
                        nx = dy.neg / d * 2.2; ny = dx / d * 2.2;
                        Pen.line((sx + nx)@(sy + ny), (ex + nx)@(ey + ny)); Pen.stroke;
                        Pen.line((sx - nx)@(sy - ny), (ex - nx)@(ey - ny)); Pen.stroke;
                    } {
                        Pen.line(sx@sy, ex@ey); Pen.stroke;
                    };
                };
                Pen.stringAtPoint(txt, lx@ly, font, ~uiPal.ink);
            };
        };
    };
    ~mixerGraphPos.keysValuesDo { |layer, pt|
        if(~mixerLayers.includes(layer)) {
            ~uiPenText.(~uiPhi[layer] ? "", pt.x, pt.y - 18, gfont, ~uiPal.ink, \middle);
            ~uiPenText.(layer.asString, pt.x, pt.y + 20, nfont, ~uiPal.ink, \middle);
        };
    };
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

~ungBuildMixer = {
    var layers = ~mixerLayers, w = 1440, h = 850, scr, winRect, win;
    var gx = 1010, rx = 1034, rw = 378, tableY = 444, rowH = 28, modY = 620;
    var hasFx = ~cfg_effects.notNil, hasMod = ~modKeys.notNil and: { ~modKeys.size > 0 };
    var hasGrid = ~gridGenerate.notNil;
    var fmt2 = { |v| ~uiFmt.(v, 2) }, fmt3 = { |v| ~uiFmt.(v, 3) };
    var fxModeItems = [
        "1 · 1 tap", "2 · 2 tap", "3 · 1+2 tap", "4 · 1+2+3 echo",
        "5 · 1 +rev", "6 · 2 +rev", "7 · 3 +rev", "8 · 1+2 +rev",
        "9 · 2+3 +rev", "10 · 1+3 +rev", "11 · all +rev", "12 · rev only"
    ];
    var graph, tiers, presetName, presetPop, gridTv, gridStatus, gridBtn, konRange, konTtierBox;
    var recBtn, mkGlyph;

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
    // состояние кнопки в ~mixRecOn: корректно после close/reopen во время записи
    recBtn = ~uiBtn.(win, Rect(1180, 28, 70, 26), ["● rec", "■ rec"],
        { ~mixRecToggle.value }, ~mixRecOn);
    ~mixerRecBtn = recBtn;
    ~uiBtn.(win, Rect(1258, 28, 74, 26), "unsolo", { ~mixUnsolo.value });
    ~uiBtn.(win, Rect(1340, 28, 72, 26), "close", { win.close });
    ~uiRule.(win, Rect(0, 66, w, 1));
    ~uiRule.(win, Rect(gx, 67, 1, h - 67));

    // --- mod graph ---
    ~uiCap.(win, Rect(28, 76, 400, 14), "layers · mod graph");
    graph = UserView(win, Rect(28, 92, 540, 340)).background_(~uiPal.paper);
    graph.drawFunc_({ |u| ~mixerDrawGraph.(u) });
    ~mixerGraph = graph;

    // --- space echo strip: mode per instance, tone shared; GUI едет ПОВЕРХ ~cfg_effects ---
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
        // каждая ручка пишет и ~cfg_effects: его читают ~savePreset и пересборка окна
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
        // тон ставит ОБА экземпляра; инициализация от rev-значений
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

    // --- mod matrix: 16 depths (panel index i == index in ~cfg_modmtx.lines) ---
    ~uiCap.(win, Rect(28, modY, 300, 14), "mod matrix");
    if(hasMod) {
        ~mixerModNote = ~uiText.(win, Rect(430, modY, 460, 14), "", 9.5, ~uiPal.ink2, false, \right);
        ~mixerModRnd = ~uiBtn.(win, Rect(900, modY - 4, 80, 24), "random",
            { if(~modRandomize.notNil) { ~modRandomize.value } });
        ~uiBtnEnable.(~mixerModRnd, ~konActive != true);
        ~modKeys.do { |e, i|
            var col = i div: 8, row = i mod: 8;
            var mx  = 28 + (col * 492), my = modY + 24 + (row * 22);
            var lbl, gl, r;
            ~uiText.(win, Rect(mx, my, 20, 20), i.asString.padLeft(2, "0"), 9.5, ~uiPal.ink2);
            lbl = ~uiText.(win, Rect(mx + 22, my, 118, 20), e[\label], 10.5);
            gl = UserView(win, Rect(mx + 144, my, 90, 20)).background_(~uiPal.paper);
            gl.drawFunc_({ |u| ~uiDrawLineGlyph.(u, ~modKeys[i] ? e) });
            r = ~uiRulerRow.(win, mx + 240, my, 0, 120, "", ControlSpec(0, 1, \lin, 0, e[\depth]),
                e[\depth], { |v| ~modDepthSet.(i, v) }, fmt3);
            r[\label] = lbl; r[\glyph] = gl;
            // связь на незагруженном слое (subset ~cfg_app.layers) — линейка видна, но мертва
            if(e[\enabled].not) { ~uiRulerEnable.(r, false) };
            ~mixerModEz[i] = r;
        };
    } {
        ~uiText.(win, Rect(28, modY + 24, 900, 18),
            "mod matrix off — set ~cfg_app.enableModMatrix = true and re-run 1_app.scd", 11, ~uiPal.ink2);
    };

    // --- structure grid (right column); nil-safe без 0_grid ---
    ~uiCap.(win, Rect(rx, 76, rw, 14), "structure grid 16×16");
    // растр создаётся ДО TextView: порядок создания = порядок наложения
    UserView(win, Rect(rx, 92, rw, 332)).background_(~uiPal.paper2)
        .drawFunc_({ |u| ~uiDrawDither.(u, Rect(74, 8, 230, 316)) });
    // TextView подогнан под 16×16 Menlo 17; QTextView не отключает перенос —
    // ширина ОБЯЗАНА вмещать 16 символов + скроллбар, иначе рисунок рассыпается
    gridTv = TextView(win, Rect(rx + 84, 100, 210, 316))
        .font_(Font("Menlo", 17)).editable_(false)
        .background_(~uiPal.paper).stringColor_(~uiPal.ink);
    // Qt красит плоский текст палитрой (baseText), не stringColor_ — после
    // каждого string_ цвет добивается по диапазону
    gridTv.palette_(gridTv.palette.baseText_(~uiPal.ink));
    // поле — партитура акта: переживает переоткрытие окна
    if(~gridLastText.notNil) {
        gridTv.string_(~gridLastText);
        gridTv.setStringColor(~uiPal.ink, 0, ~gridLastText.size);
    };
    ~mixerGridTxt = gridTv;

    // линейка только пишет значение — структуру строит кнопка
    ~mixerGridEz = ~uiRulerRow.(win, rx, 436, 84, 200, "complexity",
        ControlSpec(0, 1, \lin, 0, ~gridComplexity ? 0.5), ~gridComplexity ? 0.5,
        { |v| ~gridComplexity = v }, fmt2);

    // статус: длинный статус акта и путь партитуры, перенос сам
    gridStatus = ~uiText.(win, Rect(rx, 540, rw, 56), "", 9.5, ~uiPal.ink2);
    ~mixerGridStatus = gridStatus;

    gridBtn = ~uiBtn.(win, Rect(rx, 468, 90, 26), "generate", {
            // с Konstruktion кнопка = АКТ; без него — прежний чистый рисунок
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

    // Konstruktion: T_tier (читается только актом), start/stop, score;
    // всё nil-safe без 9_konstruktion.scd
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
    // низкий frameRate: playhead-подсветка блока без 60 fps на всё окно
    tiers.frameRate_(2).animate_(true);
    ~mixerTiers = tiers;

    // GUI sync hook <- ~mixSet/~masterSet
    ~mixerGuiSync = { |layer, which, v|
        var r = if(layer == \master) { ~mixerEz[\master] } { ~mixerEz[layer] !? { |row| row[which] } };
        r !? { ~uiRulerSet.(r, v) };
    };

    // depth-синк <- ~modDepthSet (линейка не зовёт action — без фидбек-петли)
    ~modmatrixGuiSync = { |i, v|
        ~mixerModEz[i] !? { |r|
            ~uiRulerSet.(r, v);
            { r[\glyph].refresh; ~mixerGraph !? { |uv| uv.refresh } }.defer;
        };
    };

    // relabel <- ~konGenerate: подписи src→dst меняются без пересборки окна
    ~modmatrixGuiRelabel = { |i, label|
        {
            ~mixerModEz[i] !? { |r| r[\label].string_(label); r[\glyph].refresh };
            ~mixerGraph !? { |uv| uv.refresh };
        }.defer;
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
