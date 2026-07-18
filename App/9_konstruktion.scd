// App/9_konstruktion.scd — UNGRUND · KONSTRUKTION: форма §E.6 — один акт
// генерации сетки (0_grid) читается дважды: как макроформа (таймлайн для
// 4_sequencer) и как топология модуляции (16 линий для 8_modmatrix).
// Законы вывода: docs/features/grid-modulation/reference.md; спека:
// plans/active/grid-konstruktion-spec.md. Грузится шагом 7b в 1_app.scd
// (требует enableSequencer + enableModMatrix). Чистый sclang: не бутит
// сервер, не пишет в шины, аудио-графов не создаёт; cleanup — в ~appCleanup.
// API: ~konGenerate.(complexity, seed, tTier) — акт (три артефакта разом);
//      ~konDerive.(grid, tTier) — чистая деривация; ~konSaveScore — партитура.

(
// ===== CONFIG — edit here ============================================
~cfg_kon = (
    tTier:        30,              // умолчание партитурного T_tier, с
    tTierRange:   [15, 60],        // границы поля T_tier в панели микшера
    weakLevel:    0.5,             // слабая связь: ×0.5 = −6 dB (решение 3)
    rateScale:    12,              // множитель закона rate (user override: пульс, не дрейф)
    rateClip:     [0.05, 2.0],     // Гц, шаг 3 деривации (расширен под rateScale)
    fmBase:       0.3, fmSpan: 0.9,        // fm = fmBase + fmSpan·strongShare
    depthGain:    0.22, depthFloor: 0.06,  // depth = clip(depthGain·cAB, floor, max)
    depthMax:     0.5,             // общий потолок, theta включительно (user override §C.8)
    baseRange:    [0.15, 0.85],    // нормализованный диапазон базовых значений целей
    scoreDir:     "docs/architecture/structure-grid"  // относительно корня проекта
);


// ===== LOGIC — деривация, акт, партитура =============================
~konLayerOrder = [\alpha, \delta, \epsilon, \zeta, \theta];

// ключи — String, не Char: символы Ф многобайтные (UTF-8), $-литерал их не
// возьмёт; Dictionary (не IdentityDictionary/Event) сравнивает String по значению
~konLayerOf = Dictionary.newFrom([
    "█", \alpha, "▄", \delta, "▓", \epsilon, "░", \zeta, "▒", \theta
]);

~konLineFamily = [\P, \F, \S, \F, \P, \F, \S, \F, \S, \P, \S, \P, \P, \F, \P, \P];
~konFamilyLine = (
    P: ( alpha: 0, delta: 4, epsilon: 9, zeta: 11, theta: 14 ),
    S: ( alpha: 2, delta: 6, epsilon: 8, zeta: 10 ),
    F: ( alpha: 1, delta: 5, epsilon: 7, theta: 13 )
);

// чистая функция графа: только опубликованные признаки экспорта 0_grid
// (символ, ранг, степени, strongIn, strong, routeLen) — третьего прочтения нет
~konDerive = { |grid, tTier|
    var g = grid[\graph];
    var nodes = g[\nodes], edges = g[\edges];
    var tiers = g[\tiers], rowGap = g[\rowGap];
    var tauCell = tTier / rowGap;
    var layerIdx = ();
    var layerOfNode, census, loopPair, levels, timeline, lines;

    ~konLayerOrder.do { |l, k| layerIdx[l] = k };
    layerOfNode = { |n| ~konLayerOf[n[\ch]] };

    // census по ПОЛНОМУ графу и ПО НАПРАВЛЕНИЮ ребра (поправка II): возврат
    // B-нижний → A-верхний даёт вклад в K[B][A] — влияние течёт по стрелке
    census = Array.fill(5, { Array.fill(5, 0) });
    edges.do { |e|
        var a = layerIdx[layerOfNode.(nodes[e[\src]])];
        var b = layerIdx[layerOfNode.(nodes[e[\dst]])];
        census[a][b] = census[a][b] + 1;
    };

    // нарисованная петля A⇄B: оба направления ненулевые И хотя бы одно
    // ребро пары — возвратное (поправка II референции)
    loopPair = Array.fill(5, { Array.fill(5, false) });
    (0..4).do { |a|
        (0..4).do { |b|
            if((a < b)
                and: { census[a][b] > 0 } and: { census[b][a] > 0 }
                and: { edges.any { |e|
                    var ea = layerIdx[layerOfNode.(nodes[e[\src]])];
                    var eb = layerIdx[layerOfNode.(nodes[e[\dst]])];
                    (e[\ret] == true) and: {
                        ((ea == a) and: { eb == b }) or: { (ea == b) and: { eb == a } }
                    };
                } }
            ) {
                loopPair[a][b] = true;
                loopPair[b][a] = true;
            };
        };
    };

    // чтение 1 — макроформа: уровень слоя на ранге = max по его узлам
    levels = Array.fill(tiers, { () });
    nodes.do { |n|
        var l = layerOfNode.(n);
        var lv = if(n[\strongIn]) { 1.0 } { ~cfg_kon.weakLevel };
        levels[n[\tier]][l] = (levels[n[\tier]][l] ? 0).max(lv);
    };
    timeline = List[];
    tiers.do { |r|
        var vols = List[], gone = List[];
        ~konLayerOrder.do { |l|
            var cur = levels[r][l];
            var prev = if(r > 0) { levels[r - 1][l] };
            if(cur.notNil and: { prev != cur }) { vols.add([l, cur]) };
            if(cur.isNil and: { prev.notNil }) { gone.add(l) };
        };
        timeline.add(( t: r * tTier, vols: vols.asArray, gone: gone.asArray ));
    };
    timeline.add((
        t: tiers * tTier,
        gone: ~konLayerOrder.select { |l| levels[tiers - 1][l].notNil },
        finish: true
    ));

    // чтение 2 — 16 линий: 7 шагов референции (rate ×rateScale — user override)
    lines = ~cfg_modmtx.lines.collect { |cfgLine, i|
        var b = cfgLine[\target].asSymbol;
        var param = cfgLine[\param].asSymbol;
        var family = ~konLineFamily[i];
        var bIdx = layerIdx[b];
        var j = 0;
        var cands, sorted, aIdx, aLayer, src, ab, ln, isLoop;
        var meanRoute, rate, strongShare, fm, cAB, depth, shape;
        var colSum, baseLo, baseHi;
        ~cfg_modmtx.lines.do { |lx, k|
            if((k < i) and: { lx[\target].asSymbol == b }) { j = j + 1 };
        };
        // шаг 1: диагональ исключена из ВЫБОРА источников (census целиком — партитуре)
        cands = (0..4).select { |a| (a != bIdx) and: { census[a][bIdx] > 0 } };
        ln = if(cands.isEmpty) {
            // шаг 7: пустой census — автономная линия (rate/src/shape из CONFIG,
            // при fm = 0 вход src не влияет)
            ( target: b, param: param, shape: cfgLine[\shape], rate: cfgLine[\rate],
              src: cfgLine[\src], fm: 0, depth: 0, loopAB: 0,
              srcLayer: nil, family: family, nEdges: 0,
              meanRoute: nil, strongShare: nil, cAB: nil, derived: false )
        } {
            // sort в SC не стабилен — tie-break порядка слоёв задан сравнением явно
            sorted = cands.sort { |x, y|
                (census[x][bIdx] > census[y][bIdx]) or: {
                    (census[x][bIdx] == census[y][bIdx]) and: { x < y }
                }
            };
            aIdx = sorted[j mod: sorted.size];
            aLayer = ~konLayerOrder[aIdx];
            src = ~konFamilyLine[family][aLayer] ? ~konFamilyLine[\P][aLayer];
            ab = edges.select { |e|
                (layerOfNode.(nodes[e[\src]]) == aLayer)
                    and: { layerOfNode.(nodes[e[\dst]]) == b }
            };
            meanRoute = ab.collect { |e| e[\routeLen] }.mean;
            rate = (~cfg_kon.rateScale / (meanRoute * tauCell))
                .clip(~cfg_kon.rateClip[0], ~cfg_kon.rateClip[1]);
            strongShare = ab.count { |e| e[\strong] } / ab.size;
            fm = ~cfg_kon.fmBase + (~cfg_kon.fmSpan * strongShare);
            // степени в cAB — по ПОЛНОМУ графу (indeg/outdeg экспорта включают
            // возвраты): у листа с возвратом outdeg = 1, деление определено
            cAB = ab.collect { |e| nodes[e[\dst]][\indeg] }.mean
                / ab.collect { |e| nodes[e[\src]][\outdeg] }.mean;
            isLoop = loopPair[aIdx][bIdx];
            // шаг 5б (поправка II): нарисованная петля бустит обе встречные
            // линии пары ×1.5; клип depthMax — ПОСЛЕ буста
            depth = (~cfg_kon.depthGain * cAB * if(isLoop) { 1.5 } { 1 })
                .clip(~cfg_kon.depthFloor, ~cfg_kon.depthMax);
            // шаг 6 расширен: петля периодична по построению => \sine
            shape = if(isLoop
                or: { (ab.count { |e| nodes[e[\dst]][\indeg] >= 2 } * 2) > ab.size })
                { \sine } { \noise };
            ( target: b, param: param, shape: shape, rate: rate, src: src,
              fm: fm, depth: depth, loopAB: if(isLoop) { 1 } { 0 },
              srcLayer: aLayer, family: family, nEdges: ab.size,
              meanRoute: meanRoute, strongShare: strongShare, cAB: cAB,
              derived: true )
        };
        // базовое значение цели (user override: акт = новая тембральная
        // идентичность даже при depth 0): детерминированный скрэмбл seed +
        // признаков графа/census золотым сечением, зажатый в baseRange
        colSum = (0..4).sum { |a| census[a][bIdx] };
        baseLo = ~cfg_kon.baseRange[0];
        baseHi = ~cfg_kon.baseRange[1];
        ln[\baseN] = baseLo + ((baseHi - baseLo) * (
            ((grid[\seed] ? 0) * 0.6180339887)
            + ((i + 1) * 2.6180339887)
            + (colSum * 0.7548776662)
            + (census[bIdx].sum * 0.5698402910)
            + (tiers * 0.3624480570)
            + ((ln[\meanRoute] ? 0) * 0.2205488529)
        ).frac);
        ln
    };

    ( seed: grid[\seed], complexity: grid[\complexity], tTier: tTier,
      tiers: tiers, rowGap: rowGap, tauCell: tauCell,
      census: census, loops: loopPair,
      edgeTab: edges.collect { |e|
          ( src: layerOfNode.(nodes[e[\src]]), dst: layerOfNode.(nodes[e[\dst]]),
            ret: e[\ret] == true, strong: e[\strong] == true,
            routeLen: e[\routeLen] )
      },
      timeline: timeline.asArray, lines: lines )
};

// акт генерации: один акт — одна пьеса — три артефакта разом.
// Пьесу НЕ запускает: старт — отдельный акт перформера (~seqStart / кнопка).
~konGenerate = { |complexity, seed, tTier|
    var grid, kon, dur, status;
    if(Tdef(\ung_sequencer).isPlaying and: { ~seqStop.notNil }) { ~seqStop.value };
    grid = ~gridGenerate.(complexity ? 0.5, seed);
    if(grid.isNil) {
        // отказ: акт прерван БЕЗ частичных артефактов — старая пьеса действует
        status = "отказ: не разложилось за " ++ ~cfg_grid.graphTries
            ++ " графов — акт прерван";
        ("9_konstruktion — " ++ status).postln;
        { ~mixerGridStatus !? { |st| st.string_(status) } }.defer;
        nil
    } {
        kon = ~konDerive.(grid, tTier ? ~cfg_kon.tTier);
        kon[\text] = grid[\text];
        kon[\counts] = grid[\counts];
        // детерминизм относителен ~cfg_grid — партитура пишет снапшот CONFIG
        kon[\cfgGrid] = ~cfg_grid.copy;
        ~seqTimeline = kon[\timeline];
        // громкости — исполнителю (user override 2026-07-18): таймлайн живёт
        // для viz и finish-блока, vols секвенсор не применяет, роутеры и их
        // \fade акт не трогает
        ~seqDriveVols = false;
        // новая тембральная идентичность акта: базовые центры всех 16 целей
        // из графа, ДО пересборки матрицы — modmtx_map_i захватывает centerN
        // уже новых значений (~setParam: Ndef + ~ungVals + tuner-синк)
        if(~setParam.notNil) {
            kon[\lines].do { |ln|
                var pspec = ~ungSpecOf.(ln[\target]) !? { |s|
                    s.params.detect { |p| p[\key] == ln[\param] }
                };
                pspec !? {
                    ~setParam.(ln[\target], ln[\param], pspec[\spec].map(ln[\baseN]));
                };
            };
            if(~ungSyncAll.notNil) { ~konLayerOrder.do { |l| ~ungSyncAll.(l) } };
        };
        ~modBuild.(kon[\lines].collect { |ln|
            ( target: ln[\target], param: ln[\param], shape: ln[\shape],
              rate: ln[\rate], src: ln[\src], fm: ln[\fm], depth: ln[\depth] )
        });
        ~konCurrent = kon;
        ~konActive = true;
        ~gridLastText = grid[\text];
        dur = kon[\tiers] * kon[\tTier];
        status = "Ф: " ++ grid[\nodes] ++ " · поле: " ++ grid[\cols] ++ "×"
            ++ grid[\rows] ++ " · seed: " ++ grid[\seed]
            ++ " · пьеса: " ++ kon[\tiers] ++ "×" ++ kon[\tTier] ++ " = "
            ++ (dur / 60).floor.asInteger ++ ":"
            ++ (dur - ((dur / 60).floor * 60)).round.asInteger.asString.padLeft(2, "0");
        {
            ~mixerGridTxt !? { |tv|
                tv.string_(grid[\text]);
                tv.setStringColor(Color.white, 0, grid[\text].size);
            };
            ~mixerGridStatus !? { |st| st.string_(status) };
        }.defer;
        (~modKeys ? []).do { |e, i|
            if(~modmatrixGuiSync.notNil) { ~modmatrixGuiSync.(i, e[\depth]) };
            if(~modmatrixGuiRelabel.notNil) { ~modmatrixGuiRelabel.(i, e[\label]) };
        };
        if(~mixerKonSync.notNil) { ~mixerKonSync.value };
        ("9_konstruktion — акт: " ++ status).postln;
        kon
    };
};

// партитура (решение 6): пара construction-NNNN.txt + construction-NNNN.score.md
~konSaveScore = {
    var kon = ~konCurrent;
    var dir, existing, nnnn, base, txtPath, mdPath, sb, fmt;
    var writeErr, statusStr;
    if(kon.isNil) {
        statusStr = "партитуры нет: сначала акт (кнопка «сгенерировать»)";
        ("9_konstruktion — " ++ statusStr).postln;
        { ~mixerGridStatus !? { |st| st.string_(statusStr) } }.defer;
        nil
    } {
        dir = ~appDir.dirname +/+ ~cfg_kon.scoreDir;
        if(File.exists(dir).not) { File.mkdir(dir) };
        existing = (dir +/+ "construction-*.txt").pathMatch;
        nnnn = (existing.collect { |p|
            PathName(p).fileNameWithoutExtension.copyRange(13, 16).asInteger
        }.maxItem ? 0) + 1;
        base = "construction-" ++ nnnn.asString.padLeft(4, "0");
        txtPath = dir +/+ base ++ ".txt";
        mdPath  = dir +/+ base ++ ".score.md";
        fmt = { |v, nd = 4| if(v.isNil) { "—" } { v.round(10 ** nd.neg).asString } };

        sb = List[];
        sb.add("# " ++ base ++ " — партитура Konstruktion");
        sb.add("");
        sb.add("- дата: " ++ Date.getDate.stamp);
        sb.add("- seed: " ++ kon[\seed] ++ " · complexity: " ++ kon[\complexity]);
        sb.add("- T_tier: " ++ kon[\tTier] ++ " с · tiers: " ++ kon[\tiers]
            ++ " · rowGap: " ++ kon[\rowGap]
            ++ " · τ_cell: " ++ fmt.(kon[\tauCell], 3) ++ " с");
        sb.add("- длительность: " ++ (kon[\tiers] * kon[\tTier]) ++ " с");
        sb.add("- поле: `" ++ base ++ ".txt`");
        kon[\counts] !? { |ct|
            sb.add("- счётчики поля (правило 9): ветвящихся узлов " ++ ct[\branching]
                ++ " · переходных углов " ++ ct[\transitions]
                ++ " · крестов " ++ ct[\crosses]);
        };
        sb.add("");
        sb.add("## Снапшот ~cfg_grid (детерминизм относителен CONFIG генератора)");
        sb.add("");
        sb.add("```");
        kon[\cfgGrid].sortedKeysValuesDo { |k, v| sb.add(k ++ ": " ++ v) };
        sb.add("```");
        sb.add("");
        sb.add("## Таймлайн");
        sb.add("");
        sb.add("| t, с | событие | слой | уровень |");
        sb.add("|------|---------|------|---------|");
        kon[\timeline].do { |blk|
            (blk[\vols] ? []).do { |pair|
                sb.add("| " ++ blk[\t] ++ " | vol | " ++ pair[0]
                    ++ " | ×" ++ pair[1] ++ " |");
            };
            (blk[\gone] ? []).do { |l|
                sb.add("| " ++ blk[\t] ++ " | gone | " ++ l ++ " | — |");
            };
            if(blk[\finish] == true) {
                sb.add("| " ++ blk[\t] ++ " | finish | — | — |");
            };
        };
        sb.add("");
        sb.add("## Рёбра графа (род: прямое/возврат — правило 7)");
        sb.add("");
        sb.add("| # | src | dst | род | сила | routeLen |");
        sb.add("|" ++ "---|".dup(6).join);
        (kon[\edgeTab] ? []).do { |e, k|
            sb.add("| " ++ k ++ " | " ++ e[\src] ++ " | " ++ e[\dst]
                ++ " | " ++ if(e[\ret]) { "возврат" } { "прямое" }
                ++ " | " ++ if(e[\strong]) { "сильное" } { "слабое" }
                ++ " | " ++ e[\routeLen] ++ " |");
        };
        sb.add("");
        sb.add("## Census 5×5 (K[src][dst], по направлению рёбер; диагональ читает только макроформа)");
        sb.add("");
        sb.add("| src\\\\dst | " ++ ~konLayerOrder.join(" | ") ++ " |");
        sb.add("|" ++ "---|".dup(6).join);
        ~konLayerOrder.do { |a, ai|
            sb.add("| " ++ a ++ " | " ++ kon[\census][ai].join(" | ") ++ " |");
        };
        kon[\loops] !? { |lp|
            var pairs = List[];
            (0..4).do { |a| (0..4).do { |b|
                if((a < b) and: { lp[a][b] == true }) {
                    pairs.add(~konLayerOrder[a] ++ "⇄" ++ ~konLayerOrder[b]);
                };
            } };
            sb.add("");
            sb.add("нарисованные петли (поправка II): "
                ++ if(pairs.isEmpty) { "нет" } { pairs.join(" · ") });
        };
        sb.add("");
        sb.add("## 16 линий модуляции");
        sb.add("");
        sb.add("| i | цель | Ф | srcLayer | src | shape | rate, Гц | fm, окт "
            ++ "| depth | петля | baseN | meanRoute | strongShare | cAB | derived |");
        sb.add("|" ++ "---|".dup(15).join);
        kon[\lines].do { |ln, i|
            sb.add("| " ++ i ++ " | " ++ ln[\target] ++ "." ++ ln[\param]
                ++ " | " ++ ln[\family]
                ++ " | " ++ (ln[\srcLayer] ? "—") ++ " | " ++ ln[\src]
                ++ " | " ++ ln[\shape] ++ " | " ++ fmt.(ln[\rate])
                ++ " | " ++ fmt.(ln[\fm], 3) ++ " | " ++ fmt.(ln[\depth], 3)
                ++ " | " ++ (ln[\loopAB] ? 0)
                ++ " | " ++ fmt.(ln[\baseN], 3)
                ++ " | " ++ fmt.(ln[\meanRoute], 2)
                ++ " | " ++ fmt.(ln[\strongShare], 3) ++ " | " ++ fmt.(ln[\cAB], 3)
                ++ " | " ++ ln[\derived] ++ " |");
        };
        // отчёт всегда доходит до панели: успех показывает путь партитуры,
        // отказ записи — внятную ошибку (кнопка не имеет права молчать)
        writeErr = nil;
        try {
            File.use(txtPath, "w", { |f| f.write(kon[\text] ++ "\n") });
            File.use(mdPath, "w", { |f| f.write(sb.join("\n") ++ "\n") });
        } { |err| writeErr = err };
        if(writeErr.notNil) {
            statusStr = "ошибка записи партитуры: " ++ writeErr.errorString;
            ("9_konstruktion — " ++ statusStr).postln;
            { ~mixerGridStatus !? { |st| st.string_(statusStr) } }.defer;
            nil
        } {
            statusStr = "партитура: " ++ ~cfg_kon.scoreDir ++ "/" ++ base ++ ".score.md";
            ("9_konstruktion — записано: " ++ txtPath).postln;
            ("9_konstruktion — записано: " ++ mdPath).postln;
            { ~mixerGridStatus !? { |st| st.string_(statusStr) } }.defer;
            [txtPath, mdPath]
        };
    };
};

// идемпотентная перезагрузка: файл не пересоздаёт и не убивает текущий акт
~konActive  = ~konActive ? false;
~konCurrent = ~konCurrent;
~konTtier   = ~konTtier ? ~cfg_kon.tTier;

"9_konstruktion — форма Konstruktion (~konGenerate / ~konSaveScore).".postln;
)
