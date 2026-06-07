// =====================================================================
// App/2_mixer.scd
// UNGRUND · MIXER — уровни слоёв, посылы в эффекты, мастер + окно микшера
//
// Микшер — единственное место, где сводятся синт-слои. Для каждого слоя:
//   vol  — громкость сухого сигнала в мастер;
//   send — доля сигнала, уходящая в ~busFxSend (вход эффектов, §K).
//
// СИГНАЛ-ФЛОУ:
//   Ndef(\<class>)  --vol-->  ~busDry  -----\
//                  \--send-->  ~busFxSend     >--> Ndef(\master) --> out 0
//   Ndef(\tape_reverb)/(\ping_delay) --> ~busFxReturn --/
//
// Реализация: на каждый слой создаётся Ndef(\mix_<class>) — роутер,
//   читающий сухой слой и пишущий его × vol в ~busDry; один агрегатор
//   Ndef(\fxsend) суммирует все слои × send и пишет в ~busFxSend.
//
// ВАЖНО: маршрутизируются ТОЛЬКО реально загруженные слои — список берётся
//   из ~activeLayers (его ставит 1_app.scd по факту загрузки synths/*.scd).
//   Так выбор подмножества слоёв (~cfg_app.layers) не тянет пустые Ndef'ы.
//
// ОКНО МИКШЕРА: ~openMixer.value — фейдеры vol/send, solo и кнопка tuner
//   на каждый слой + мастер. GUI синхронизируется с ~mixSet через
//   ~mixerGuiSync (живая правка из MIDI/solo подтягивает фейдеры).
//
// Зависимости: синт-слои (Ndef(\monade) ...), эффекты (6_effects.scd),
//   шины ~busDry / ~busFxSend / ~busFxReturn (создаёт 1_app.scd),
//   ~activeLayers (1_app.scd). Итерировать сведение = править таблицу levels.
// =====================================================================


// ===== CONFIG — edit here ============================================
(
// Таблица уровней, ключ = имя слоя. vol = громкость в мастер,
// send = посыл в эффекты (§K.1/K.2 рекомендуемые уровни как старт).
// Может содержать ВСЕ 8 слоёв — лишние (не загруженные) просто игнорируются.
~cfg_mixer = (
    master:  0.9,                                    // мастер-уровень

    levels: (
        //            vol    send  (send из §K.1 tape reverb)
        monade:   ( vol: 0.85, send: 0.55 ),
        riss:     ( vol: 0.90, send: 0.30 ),
        flockung: ( vol: 0.80, send: 0.35 ),
        binde:    ( vol: 0.80, send: 0.45 ),
        schliere: ( vol: 0.85, send: 0.15 ),
        kratzer:  ( vol: 0.75, send: 0.15 ),
        zaesur:   ( vol: 0.00, send: 0.00 ),          // тишина — без уровня
        firnis:   ( vol: 0.70, send: 0.60 )
    )
);

// уровни по умолчанию для слоя, которого нет в таблице (новый synths/*.scd)
~mixerDefaultLevel = ( vol: 0.7, send: 0.0 );


// ===== LOGIC — routers + master + GUI ================================
// порядок слоёв = реально загруженные слои (1_app.scd), иначе все 8.
~mixerLayers = ~activeLayers ? [\monade, \riss, \flockung, \binde, \schliere, \kratzer, \zaesur, \firnis];

// гарантировать запись уровней для каждого активного слоя (fallback)
~mixerLayers.do { |layer|
    if(~cfg_mixer.levels[layer].isNil) {
        ~cfg_mixer.levels[layer] = ~mixerDefaultLevel.copy;
    };
};

// --- роутер на каждый слой: только сухой -> ~busDry -----------------
// (посылы в эффекты собирает один агрегатор ~busFxSend ниже — чтобы
//  send-шина имела РОВНО одного писателя через ReplaceOut и никогда не
//  накапливалась между блоками. Так порядок узлов не критичен.)
~mixerLayers.do { |layer|
    var routerKey = ("mix_" ++ layer).asSymbol;
    var lv = ~cfg_mixer.levels[layer];
    Ndef(routerKey, { |vol = 0|
        var src = Ndef(layer.asSymbol).ar(2);        // читаем сухой слой
        src * vol.lag(0.1)                            // сухой -> ~busDry
    });
    Ndef(routerKey).set(\vol, lv.vol);
    Ndef(routerKey).fadeTime = 1;
    Ndef(routerKey).play(out: ~busDry.index, numChannels: 2);
};

// --- агрегатор посылов: сумма всех слоёв × send -> ~busFxSend --------
// Единственный писатель send-шины. ReplaceOut => без накопления.
// send-доли хранятся как именованные controls \send_<layer>.
// Тело читает ~mixerLayers (тот же отфильтрованный список) при сборке Ndef.
Ndef(\fxsend, {
    var sends = ~mixerLayers.collect { |layer|
        var amt = NamedControl.kr(("send_" ++ layer).asSymbol, 0);
        Ndef(layer.asSymbol).ar(2) * amt.lag(0.1);
    };
    ReplaceOut.ar(~busFxSend.index, Mix(sends));
});
~mixerLayers.do { |layer|
    Ndef(\fxsend).set(("send_" ++ layer).asSymbol, ~cfg_mixer.levels[layer].send);
};
Ndef(\fxsend).fadeTime = 1;
Ndef(\fxsend).play(out: ~busFxSend.index, numChannels: 2);

// --- мастер: сумма (сухой + возврат эффектов), LeakDC, Limiter ------
Ndef(\master, { |amp = 0.9|
    var dry, fx, sig;
    // InFeedback (НЕ In): читает шины НЕЗАВИСИМО от порядка узлов — роутеры
    // mix_* и эффекты могут стоять в графе позже мастера. In.ar здесь давал
    // тишину (мастер читал ~busDry до того, как роутеры туда писали).
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
Ndef(\master).play(out: 0, numChannels: 2);          // в аппаратный выход

// --- хук синхронизации GUI <- ~mixSet (ставится окном микшера) -------
//   { |layer, which, v| ... } — обновляет соответствующий фейдер.
//   nil, пока окно не открыто (живёт без GUI).
~mixerGuiSync = ~mixerGuiSync;   // notNil только когда окно построено

// --- удобный сеттер для живой правки / MIDI / sequencer -------------
// ~mixSet.(\monade, \vol, 0.5)  — громкость слоя в мастер
// ~mixSet.(\firnis, \send, 0.8) — посыл слоя в эффекты (агрегатор \fxsend)
~mixSet = { |layer, which = \vol, value|
    if(~cfg_mixer.levels[layer].isNil) { ~cfg_mixer.levels[layer] = ~mixerDefaultLevel.copy };
    if(which == \send) {
        Ndef(\fxsend).set(("send_" ++ layer).asSymbol, value);
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

// --- solo / unsolo для отстройки одного слоя в полном тракте ---------
// ~mixSolo.(\monade)  — звучит только monade (через реверб + мастер);
//                       остальные слои глушатся (vol=0, send=0).
// ~mixUnsolo.value    — восстановить уровни/посылы всех слоёв из CONFIG.
// Уровни читаются из ~cfg_mixer (не перетираются нулями), поэтому возврат
// возвращает исходное сведение.
~mixSolo = { |layer|
    ~mixerLayers.do { |l|
        var on = (l == layer);
        var lv = ~cfg_mixer.levels[l];
        Ndef(("mix_" ++ l).asSymbol).set(\vol, on.if({ lv.vol }, 0));
        Ndef(\fxsend).set(("send_" ++ l).asSymbol, on.if({ lv.send }, 0));
    };
    ~mixSoloCur = layer;
    if(~mixerRefreshSolo.notNil) { ~mixerRefreshSolo.value };
};
~mixUnsolo = {
    ~mixerLayers.do { |l|
        var lv = ~cfg_mixer.levels[l];
        Ndef(("mix_" ++ l).asSymbol).set(\vol, lv.vol);
        Ndef(\fxsend).set(("send_" ++ l).asSymbol, lv.send);
    };
    ~mixSoloCur = nil;
    if(~mixerRefreshSolo.notNil) { ~mixerRefreshSolo.value };
};
// тумблер solo: повторное нажатие на тот же слой снимает solo
~mixSoloToggle = { |layer|
    if(~mixSoloCur == layer) { ~mixUnsolo.value } { ~mixSolo.(layer) };
};


// ===== GUI — окно микшера ============================================
// реестры виджетов (идемпотентно при перезагрузке файла)
~mixerEz      = ();    // layer -> ( \vol: EZSlider, \send: EZSlider ); \master -> EZSlider
~mixerSoloBtn = ();    // layer -> Button (solo)
~mixSoloCur   = ~mixSoloCur;   // текущий соло-слой (или nil), переживает реоткрытие

// обновить визуал всех solo-кнопок по ~mixSoloCur
~mixerRefreshSolo = {
    { ~mixerSoloBtn.keysValuesDo { |layer, btn|
        if(btn.notNil) { btn.value_(if(~mixSoloCur == layer.asSymbol) { 1 } { 0 }) };
    } }.defer;
};

~ungBuildMixer = {
    var layers, rowH, y0, w, h, by, mkRow, masterEz;
    layers = ~mixerLayers;
    rowH = 30; y0 = 74;
    by = y0 + (layers.size * rowH) + 14;   // строка мастера/кнопок
    w  = 812; h = by + 40 + 40;

    if(~mixerWin.notNil) { ~mixerWin.close };
    ~mixerEz      = ();
    ~mixerSoloBtn = ();

    ~mixerWin = Window(
        "UNGRUND · mixer — живое сведение слоёв (App)",
        Rect(60, 60, w, h)
    ).background_(Color.gray(0.12));

    StaticText(~mixerWin, Rect(18, 10, w - 36, 22))
        .string_("сведение слоёв — vol в мастер · send в эффекты · solo · tuner (живой Ndef)")
        .stringColor_(Color.gray(0.92)).font_(Font("Menlo", 13, true));

    // заголовки колонок
    StaticText(~mixerWin, Rect(112, 50, 250, 16)).string_("vol -> master")
        .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 9));
    StaticText(~mixerWin, Rect(372, 50, 250, 16)).string_("send -> fx")
        .stringColor_(Color.gray(0.6)).font_(Font("Menlo", 9));

    // одна строка на слой
    mkRow = { |layer, i|
        var y = y0 + (i * rowH);
        var lv = ~cfg_mixer.levels[layer] ? ~mixerDefaultLevel;
        var hasSpec = ~ungSpecOf.notNil and: { ~ungSpecOf.(layer).notNil };
        var ezV, ezS, soloBtn, tunBtn;

        StaticText(~mixerWin, Rect(16, y, 92, 24))
            .string_(layer.asString)
            .stringColor_(Color.gray(0.9)).font_(Font("Menlo", 12, true));

        ezV = EZSlider(~mixerWin, Rect(112, y, 250, 24), "vol",
            ControlSpec(0, 1, \lin, 0, lv.vol),
            { |ez| ~mixSet.(layer, \vol, ez.value) }, lv.vol);
        ezV.round_(0.001);

        ezS = EZSlider(~mixerWin, Rect(372, y, 250, 24), "send",
            ControlSpec(0, 1, \lin, 0, lv.send),
            { |ez| ~mixSet.(layer, \send, ez.value) }, lv.send);
        ezS.round_(0.001);

        soloBtn = Button(~mixerWin, Rect(632, y, 56, 24))
            .states_([
                ["solo", Color.gray(0.9),  Color.gray(0.26)],
                ["SOLO", Color.white,      Color(0.55, 0.42, 0.16)]
            ])
            .font_(Font("Menlo", 11, true))
            .action_({ ~mixSoloToggle.(layer) });
        soloBtn.value_(if(~mixSoloCur == layer) { 1 } { 0 });

        tunBtn = Button(~mixerWin, Rect(694, y, 100, 24))
            .states_([["tuner", Color.white, Color(0.18, 0.34, 0.44)]])
            .font_(Font("Menlo", 11, true))
            .action_({ ~openTuner.(layer) });
        if(hasSpec.not) {
            // нет spec (заглушка) — tuner недоступен, отметим серым
            tunBtn.states_([["tuner —", Color.gray(0.4), Color.gray(0.18)]])
                .enabled_(false);
        };

        ~mixerEz[layer]      = ( vol: ezV, send: ezS );
        ~mixerSoloBtn[layer] = soloBtn;
    };
    layers.do { |layer, i| mkRow.(layer, i) };

    // --- строка мастера + кнопки ---
    StaticText(~mixerWin, Rect(16, by, 92, 24))
        .string_("master").stringColor_(Color.white).font_(Font("Menlo", 12, true));
    masterEz = EZSlider(~mixerWin, Rect(112, by, 250, 24), "amp",
        ControlSpec(0, 1, \lin, 0, ~cfg_mixer.master),
        { |ez| ~masterSet.(ez.value) }, ~cfg_mixer.master);
    masterEz.round_(0.001);
    ~mixerEz[\master] = masterEz;

    Button(~mixerWin, Rect(372, by, 130, 24))
        .states_([["all / unsolo", Color.gray(0.95), Color.gray(0.28)]])
        .font_(Font("Menlo", 11, true))
        .action_({ ~mixUnsolo.value });
    Button(~mixerWin, Rect(694, by, 100, 24))
        .states_([["закрыть", Color.gray(0.9), Color(0.4, 0.18, 0.18)]])
        .font_(Font("Menlo", 11))
        .action_({ ~mixerWin.close });

    // --- хук синхронизации GUI <- ~mixSet/~masterSet ---
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

    ~mixerWin.onClose_({
        ~mixerGuiSync = nil;
        ~mixerEz      = ();
        ~mixerSoloBtn = ();
        ~mixerWin     = nil;
    });
    ~mixerWin.front;
};

// открыть окно микшера (с defer на AppClock для GUI)
~openMixer = { { ~ungBuildMixer.value }.defer };

"2_mixer — маршрутизация + сеттеры + окно микшера (~openMixer).".postln;
)
