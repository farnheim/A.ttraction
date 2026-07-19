// App/8_modmatrix.scd — UNGRUND · MOD MATRIX: 16 kr-модуляторов, ЧАСТОТУ
// каждого ведёт выход другого (одно 16-цикловое кольцо через все пять слоёв);
// depth — фейдеры в окне микшера, ~modRandomize — рандом rate/fm/depth (guard
// ~konActive), ~modBuild.(lines) — пересборка из деривации 9_konstruktion.
// Грузится ДО микшера. Референс + полная таблица: docs/features/parameters-ru.md.


// ===== CONFIG — edit here ============================================
(
// Строка: ( target, param, shape: \noise|\sine, rate: baseHz, src: 0..15,
//   fm: октавы связи, depth: 0..1 ); диапазон и центр — из ControlSpec цели.
// src — одно кольцо alpha→delta→epsilon→zeta→theta→…: каждый слой и ведёт, и
// ведом. Потолки depth theta СНЯТЫ (поправка II 2026-07-18, защита — клипы
// слоя); rates ×12 (override 2026-07-18: пульс, не дрейф — синхронно с
// rateScale деривации Konstruktion).
~cfg_modmtx = (
    lines: [
        ( target: \alpha,   param: \density,     shape: \noise, rate: 0.60, src: 3,  fm: 0.8, depth: 0.25 ),
        ( target: \alpha,   param: \oil,         shape: \noise, rate: 0.40, src: 13, fm: 0.7, depth: 0.30 ),
        ( target: \alpha,   param: \bright,      shape: \noise, rate: 0.84, src: 14, fm: 0.9, depth: 0.20 ),
        ( target: \alpha,   param: \metalAmt,    shape: \noise, rate: 0.54, src: 15, fm: 0.8, depth: 0.20 ),
        ( target: \delta,   param: \breathDepth, shape: \noise, rate: 0.34, src: 0,  fm: 0.7, depth: 0.25 ),
        ( target: \delta,   param: \metal,       shape: \noise, rate: 0.73, src: 1,  fm: 0.9, depth: 0.22 ),
        ( target: \delta,   param: \vowelSel,    shape: \sine,  rate: 0.44, src: 2,  fm: 0.8, depth: 0.25 ),
        ( target: \epsilon, param: \mWidth,      shape: \noise, rate: 0.28, src: 4,  fm: 0.6, depth: 0.18 ),
        ( target: \epsilon, param: \flowCeil,    shape: \noise, rate: 0.62, src: 5,  fm: 0.9, depth: 0.22 ),
        ( target: \epsilon, param: \flowLevel,   shape: \noise, rate: 0.37, src: 6,  fm: 0.7, depth: 0.20 ),
        ( target: \zeta,    param: \bedHumpFreq, shape: \noise, rate: 0.79, src: 7,  fm: 1.0, depth: 0.22 ),
        ( target: \zeta,    param: \fineRate,    shape: \noise, rate: 0.52, src: 8,  fm: 0.8, depth: 0.25 ),
        ( target: \zeta,    param: \popRate,     shape: \noise, rate: 0.31, src: 9,  fm: 0.7, depth: 0.22 ),
        ( target: \theta,   param: \edgeWidth,   shape: \noise, rate: 0.58, src: 10, fm: 0.8, depth: 0.15 ),
        ( target: \theta,   param: \ioi0,        shape: \noise, rate: 0.25, src: 11, fm: 0.6, depth: 0.10 ),
        ( target: \theta,   param: \decel,       shape: \noise, rate: 0.42, src: 12, fm: 0.6, depth: 0.10 )
    ]
);


// ===== LOGIC — coupled modulator network =============================
// Два kr-прокси на строку: modmtx_osc_i (биполярный осциллятор, частота FM'ится
// от osc_<src>) и modmtx_map_i (осц в spec-диапазон цели вокруг центра, по
// depth). Кольцо разрешается через общую kr-шину (JITLib) — один блок латентности,
// не ошибка. Идемпотентный reload по ~modActive: unmap ДО clear (прецедент 3_lfo).
~modShort = [
    "a.dens", "a.oil",  "a.brgt", "a.metl",
    "d.brth", "d.metl", "d.vwl",
    "e.mwid", "e.ceil", "e.flow",
    "z.hump", "z.fine", "z.pop",
    "t.edge", "t.ioi",  "t.decl"
];

~modOscKey = { |i| ("modmtx_osc_" ++ i).asSymbol };
~modMapKey = { |i| ("modmtx_map_" ++ i).asSymbol };

// полная (пере)сборка 16 линий из любого списка (CONFIG или деривация);
// teardown СНАЧАЛА, по собственному реестру, unmap до clear
~modBuild = { |lines|
    (~modActive ? []).do { |e|
        Ndef(e[\target]).unmap(e[\param]);
        Ndef(e[\mapKey]).clear;
        Ndef(e[\oscKey]).clear;
    };

    ~modKeys   = [];   // per-line descriptor read by the mixer panel (index, label, depth, enabled)
    ~modActive = [];   // osc/map keys + target/param of the current run (teardown above)

    lines.do { |line, i|
        var layer  = line[\target].asSymbol;
        var param  = line[\param].asSymbol;
        var shape  = line[\shape];
        var srcOscKey = ~modOscKey.(line[\src]);
        var oscKey = ~modOscKey.(i);
        var mapKey = ~modMapKey.(i);
        var pspec, cspec, center, centerN;

        pspec = ~ungSpecOf.(layer) !? { |s| s.params.detect { |p| p[\key] == param } };

        if(pspec.isNil) {
            // слой не загружен (subset ~cfg_app.layers) ИЛИ параметр выпал из
            // spec (переписанный слой) — строка в панели disabled
            ("8_modmatrix — строка " ++ i ++ ": "
                ++ if(~ungSpecOf.(layer).isNil,
                    { "слой " ++ layer ++ " не загружен" },
                    { "параметра " ++ layer ++ "." ++ param ++ " нет в spec" })
                ++ ", связь пропущена").warn;
            ~modKeys = ~modKeys.add((
                index: i, label: ~modShort[line[\src]] ++ "→" ++ ~modShort[i],
                target: layer, param: param, depth: line[\depth], enabled: false
            ));
        } {
            cspec   = pspec[\spec];
            center  = (~ungVals[layer] !? { ~ungVals[layer][param] }) ? cspec.default;
            centerN = cspec.unmap(center);

            Ndef(oscKey, { |rate = 0.05, fm = 0.8|
                var srcSig = Ndef(srcOscKey).kr(1);
                var freq = (rate * (2 ** (fm * srcSig))).clip(0.001, 30);
                var osc = switch(shape,
                    \sine,  { SinOsc.kr(freq) },
                    \noise, { LFNoise2.kr(freq) },
                    { LFNoise2.kr(freq) }
                );
                osc.clip(-1, 1)
            });
            Ndef(oscKey).set(\rate, line[\rate], \fm, line[\fm]);

            // прямой перенос (override 2026-07-18): униполярный осц МИКСИРУЕТСЯ
            // с центром по depth — при depth 1 параметр ходит ВЕСЬ spec-диапазон;
            // нормализованное spec-пространство выравнивает \exp-параметры
            Ndef(mapKey, { |depth = 0|
                var oscSig = Ndef(oscKey).kr(1);
                var oscN = (oscSig + 1) * 0.5;
                cspec.map(((centerN * (1 - depth)) + (oscN * depth)).clip(0, 1))
            });
            Ndef(mapKey).set(\depth, line[\depth]);

            Ndef(layer).map(param, Ndef(mapKey));

            ~modKeys = ~modKeys.add((
                index: i, label: ~modShort[line[\src]] ++ "→" ++ ~modShort[i],
                target: layer, param: param, depth: line[\depth], enabled: true
            ));
            ~modActive = ~modActive.add((
                oscKey: oscKey, mapKey: mapKey, target: layer, param: param
            ));
        };
    };
};

// на load матрица — CONFIG; reload при активном акте вернёт CONFIG-топологию
// (повторный ~konGenerate восстанавливает пьесу)
~modBuild.(~cfg_modmtx.lines);

// живой depth-сеттер (фейдер/MIDI): ~modDepthSet.(i, 0.4)
~modDepthSet = { |i, v|
    var line = ~cfg_modmtx.lines[i];
    var entry = ~modKeys[i];
    if(entry.notNil and: { entry[\enabled] }) {
        Ndef(~modMapKey.(i)).set(\depth, v);
        line[\depth] = v;
        entry[\depth] = v;
        if(~modmatrixGuiSync.notNil) { ~modmatrixGuiSync.(i, v) };
    };
};

// рандом rate/fm/depth (живые NamedControls, без пересборки); src/shape —
// топология — не трогаются, кольцо остаётся одним циклом.
// ~modRandomize.() = все связи; ~modRandomize.(5) = одна.
~modRandomize = { |i|
    var doLine = { |idx|
        var line  = ~cfg_modmtx.lines[idx];
        var entry = ~modKeys[idx];
        var newRate, newFm, newDepth;
        if(entry.notNil and: { entry[\enabled] }) {
            // диапазон ×12 синхронно с CONFIG-ставками; depth 0..0.5 всем
            newRate  = 0.12.exprand(1.44);
            newFm    = 0.3.rrand(1.2);
            newDepth = 0.0.rrand(0.5);
            Ndef(~modOscKey.(idx)).set(\rate, newRate, \fm, newFm);
            Ndef(~modMapKey.(idx)).set(\depth, newDepth);
            line[\rate] = newRate; line[\fm] = newFm; line[\depth] = newDepth;
            entry[\depth] = newDepth;
            if(~modmatrixGuiSync.notNil) { ~modmatrixGuiSync.(idx, newDepth) };
        };
    };
    // guard: рандом разрушил бы выведенные периоды пьесы (решение 1 спеки)
    if(~konActive == true) {
        "8_modmatrix — рандом отключён: активна пьеса Konstruktion (новая пьеса — кнопка «сгенерировать»)".postln;
        nil
    } {
        if(i.isNil) { ~cfg_modmtx.lines.size.do { |idx| doLine.(idx) } } { doLine.(i) };
        ("8_modmatrix — рандом модуляции: "
            ++ if(i.isNil, { "все связи" }, { "связь " ++ i })).postln;
    };
};

// GUI-хуки, ставит окно микшера (nil без GUI)
~modmatrixGuiSync = ~modmatrixGuiSync;
~modmatrixGuiRelabel = ~modmatrixGuiRelabel;

("8_modmatrix — модуляционная матрица: активных связей "
    ++ ~modActive.size ++ "/" ++ ~cfg_modmtx.lines.size
    ++ " (глубины -> микшер)").postln;
)
