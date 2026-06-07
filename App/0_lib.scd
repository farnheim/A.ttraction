// =====================================================================
// App/0_lib.scd
// UNGRUND · LIB — общий инструментарий отстройки слоёв
//
// Здесь живёт ПОВТОРНО ИСПОЛЬЗУЕМЫЙ механизм работы со слоями:
//   1. реестр спецификаций параметров      ~ungSpecs[\layer]
//   2. живое хранилище текущих значений     ~ungVals[\layer]
//   3. установка параметра (Ndef + GUI)     ~setParam.(\layer, \key, v)
//   4. два независимых рандомайзера          ~rndFreq.(\layer) / ~rndParams.(\layer)
//   5. пресеты: сохранение и ЗАГРУЗКА        ~savePreset / ~loadPreset / ~listPresets
//   6. GUI-окно отстройки на слой            ~openTuner.(\layer)
//
// Каждый synths/<layer>.scd РЕГИСТРИРУЕТ свою спецификацию в ~ungSpecs.
// Спецификация (~spec_<layer>) — единый источник правды: из неё строятся
// и слайдеры, и рандомайзеры, и пресеты. Добавить слой = написать spec.
//
// Формат строки спецификации:
//   ( key: \amp, group: \tone, spec: ControlSpec(lo, hi, warp, step, default),
//     unit: " Hz", disp: \note )       // unit/disp — опционально
//   group: \freq — тоны/высоты (рандомайзер «частоты»);
//          \tone — тембр/среда (рандомайзер «параметры»).
//   disp: \note — слайдер показывает имя ноты (для тонов в MIDI-нотах).
//
// Пресеты: App/presets/<layer>/<name>.scd — каждый файл это event-литерал
//   ( amp: 0.22, density: 8.65, ... ), который ГРУЗИТСЯ обратно (.load).
//   В отличие от старого теста (только текстовый дамп) — здесь round-trip.
//
// Зависимости: грузить ПЕРВЫМ (до синтов) — synths/*.scd регистрируют
//   свои spec в ~ungSpecs, определённый здесь. См. 1_app.scd, шаг 0.
//   GUI/пресеты используются ИНТЕРАКТИВНО после полной загрузки App.
// =====================================================================

(
// ----- реестры (идемпотентно: повторная загрузка не сбрасывает) ------
~ungSpecs        = ~ungSpecs        ? ();   // \layer -> spec event
~ungVals         = ~ungVals         ? ();   // \layer -> ( key: value )
~ungTuner        = ~ungTuner        ? ();   // \layer -> Window
~ungTunerEz      = ~ungTunerEz      ? ();   // \layer -> ( key -> EZSlider )
~ungTunerNoteTxt = ~ungTunerNoteTxt ? ();   // \layer -> ( key -> StaticText )
~ungTunerSync    = ~ungTunerSync    ? ();   // \layer -> { |key, v| ... }
~ungTunerPop     = ~ungTunerPop     ? ();   // \layer -> PopUpMenu (пресеты)
~ungTunerName    = ~ungTunerName    ? ();   // \layer -> TextField (имя пресета)
~ungTunerOffset  = 0;                        // смещение позиции окон

// корень пресетов: App/presets (рядом с этим файлом)
~ungPresetRoot = ((~appDir ? (thisProcess.nowExecutingPath !? (_.dirname))) ? "")
    +/+ "presets";


// ----- спец/значения ------------------------------------------------
~ungSpecOf = { |layer| ~ungSpecs[layer.asSymbol] };

~ungDefault = { |layer, key|
    var p = ~ungSpecOf.(layer).params.detect { |e| e.key == key.asSymbol };
    p !? { p.spec.default };
};


// ----- установка параметра: Ndef + хранилище + синхронизация GUI -----
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

// применить дефолты из spec ко всему слою (вызывается из synths/<layer>.scd)
~ungApplyDefaults = { |layer|
    layer = layer.asSymbol;
    ~ungSpecOf.(layer).params.do { |p| ~setParam.(layer, p.key, p.spec.default) };
};


// ----- рандомайзеры: по группам spec --------------------------------
~rndGroup = { |layer, group|
    layer = layer.asSymbol;
    ~ungSpecOf.(layer).params.do { |p|
        // p[\group] (НЕ p.group): .group — это метод Object, перекрывает ключ
        if(p[\group] == group) { ~setParam.(layer, p.key, p.spec.map(1.0.rand)) };
    };
};
~rndFreq   = { |layer| ~rndGroup.(layer, \freq) };   // «частоты»
~rndParams = { |layer| ~rndGroup.(layer, \tone) };   // «параметры тембра»


// ----- пресеты: каталог, save, load, list ---------------------------
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
        e = path.load;                       // event-литерал из файла
        if(e.isKindOf(Event)) {
            e.keysValuesDo { |k, v| ~setParam.(layer, k, v) };
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


// ----- ноты: MIDI -> имя / имя+центы (для disp \note) ---------------
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

// параметр под LFO-маппингом? (тогда .set игнорируется — пометить в GUI)
~isMapped = { |layer, key|
    ~cfg_lfo.notNil and: {
        ~cfg_lfo.lines.any { |l|
            (l.target == layer.asSymbol) and: { l.param == key.asSymbol }
        };
    };
};


// ----- GUI: обновление списка пресетов в открытом окне --------------
~ungRefreshPresets = { |layer|
    layer = layer.asSymbol;
    if(~ungTunerPop[layer].notNil) {
        var items = ~listPresets.(layer);
        { ~ungTunerPop[layer].items_(if(items.isEmpty) { ["—"] } { items }) }.defer;
    };
};


// ----- GUI: построение окна отстройки слоя --------------------------
~ungBuildTuner = { |layer|
    var spec, freqs, tones, rows, y0, rowH, slBottom, by, py, w, h, off, mkSlider;
    layer = layer.asSymbol;
    spec  = ~ungSpecOf.(layer);

    freqs = spec.params.select { |p| p[\group] == \freq };   // p[\group], не p.group
    tones = spec.params.select { |p| p[\group] == \tone };
    rows  = max(freqs.size, tones.size);

    y0 = 92; rowH = 26;
    slBottom = y0 + (rows * rowH);
    by = slBottom + 16;             // строка рандомайзеров
    py = by + 46;                   // строка пресетов
    w  = 964; h = py + 24 + 16;

    if(~ungTuner[layer].notNil) { ~ungTuner[layer].close };
    ~ungTunerEz[layer]      = ();
    ~ungTunerNoteTxt[layer] = ();

    off = (~ungTunerOffset * 26);
    ~ungTunerOffset = ~ungTunerOffset + 1;
    ~ungTuner[layer] = Window(
        "UNGRUND · tuner — " ++ layer ++ " (живой Ndef в App)",
        Rect(70 + off, 70 + off, w, h)
    ).background_(Color.gray(0.12));

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

    // конструктор одного слайдера (freq: с именем ноты; tone: обычный)
    mkSlider = { |p, x, y, sw, isFreq|
        var v0, lbl, mapped, ez;
        v0     = (~ungVals[layer] !? { ~ungVals[layer][p.key] }) ? p.spec.default;
        mapped = ~isMapped.(layer, p.key);
        lbl    = p.key.asString ++ (p[\unit] ? "");
        if(mapped) { lbl = lbl ++ " ⟳LFO" };
        ez = EZSlider(~ungTuner[layer], Rect(x, y, sw, 24), lbl, p.spec, { |e|
            ~setParam.(layer, p.key, e.value);
        }, v0);
        ez.labelView.stringColor_(if(mapped) { Color(0.6, 0.6, 0.45) } { Color.white });
        ez.round_(0.001);
        ~ungTunerEz[layer][p.key] = ez;
        if(isFreq and: { p[\disp] == \note }) {
            var t = StaticText(~ungTuner[layer], Rect(x + sw + 8, y, 120, 24))
                .stringColor_(Color.gray(0.88)).font_(Font("Menlo", 11, true))
                .string_(~ungNoteLabel.(v0));
            ~ungTunerNoteTxt[layer][p.key] = t;
        };
    };

    freqs.do { |p, i| mkSlider.(p, 18,  y0 + (i * rowH), 300, true) };
    tones.do { |p, i| mkSlider.(p, 470, y0 + (i * rowH), 470, false) };

    // функция синхронизации GUI <- ~setParam (рандом/пресеты)
    ~ungTunerSync[layer] = { |key, v|
        {
            var ez = ~ungTunerEz[layer] !? { ~ungTunerEz[layer][key] };
            var t  = ~ungTunerNoteTxt[layer] !? { ~ungTunerNoteTxt[layer][key] };
            if(ez.notNil) { ez.value_(v) };
            if(t.notNil)  { t.string_(~ungNoteLabel.(v)) };
        }.defer;
    };

    // ----- рандомайзеры -----
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

    // ----- пресеты: имя | save | список | load | refresh -----
    StaticText(~ungTuner[layer], Rect(18, py + 2, 58, 22))
        .string_("preset:").stringColor_(Color.gray(0.75)).font_(Font("Menlo", 11));
    ~ungTunerName[layer] = TextField(~ungTuner[layer], Rect(80, py, 168, 24))
        .string_("").font_(Font("Menlo", 11));
    Button(~ungTuner[layer], Rect(254, py, 90, 24))
        .states_([["save", Color.white, Color(0.20, 0.40, 0.24)]])
        .font_(Font("Menlo", 11, true))
        .action_({ ~savePreset.(layer, ~ungTunerName[layer].string) });
    ~ungTunerPop[layer] = PopUpMenu(~ungTuner[layer], Rect(352, py, 200, 24))
        .font_(Font("Menlo", 11));
    Button(~ungTuner[layer], Rect(560, py, 90, 24))
        .states_([["load", Color.white, Color(0.20, 0.34, 0.44)]])
        .font_(Font("Menlo", 11, true))
        .action_({
            var items = ~listPresets.(layer);
            var idx = ~ungTunerPop[layer].value;
            if(items.notEmpty and: { idx < items.size }) {
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
        .action_({ ~ungTuner[layer].close });

    ~ungRefreshPresets.(layer);

    ~ungTuner[layer].onClose_({
        ~ungTuner[layer]        = nil;
        ~ungTunerEz[layer]      = nil;
        ~ungTunerNoteTxt[layer] = nil;
        ~ungTunerSync[layer]    = nil;
        ~ungTunerPop[layer]     = nil;
        ~ungTunerName[layer]    = nil;
    });
    ~ungTuner[layer].front;
};

// открыть окно отстройки слоя (с defer на AppClock для GUI)
~openTuner = { |layer|
    layer = layer.asSymbol;
    if(~ungSpecOf.(layer).isNil) {
        ("openTuner: нет spec для " ++ layer ++ " — загружен ли слой?").warn;
    } {
        { ~ungBuildTuner.(layer) }.defer;
    };
};

// закрыть все окна отстройки (вызывается из ~appCleanup)
~ungCloseTuners = {
    ~ungTuner.values.do { |win| if(win.notNil) { { win.close }.defer } };
};

"0_lib — инструментарий отстройки готов (~openTuner.(\\layer)).".postln;
)
