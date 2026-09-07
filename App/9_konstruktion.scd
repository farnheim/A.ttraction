// App/9_konstruktion.scd — UNGRUND · KONSTRUKTION (form §E.6): one grid
// generation act is read twice — macroform (4_sequencer timeline) and
// modulation topology. Pure sclang, no server.
// BRANCH experiment/patchbay: reading 2 is no longer 16 fixed matrix lines but
// the `schaltung` of reference §6 — the SAME eight steps the patcher walks,
// entered through ~kfDeriveScheme so the law has one implementation. Without
// 8_koppelfeld reading 2 is skipped with its reason; reading 1 (timeline,
// levels, finish) stands on the drawing alone and works as before.
// Laws: docs/features/grid-modulation/reference.md; spec: dsp-spec.md there.
// API: ~konGenerate.(complexity, seed, tTier) · ~konDerive.(grid, tTier) ·
//      ~konSaveScore.

(
// ===== CONFIG — edit here ============================================
~cfg_kon = (
    tTier:        30,              // default score T_tier, s
    tTierRange:   [15, 60],        // T_tier field bounds in the mixer panel
    weakLevel:    0.5,             // weak coupling: x0.5 = -6 dB (decision 3)
    scoreDir:     "docs/architecture/structure-grid"  // relative to the project root
);


// ===== LOGIC — derivation, act, score ================================
// the index basis of both readings lives with the alphabet in 0_grid — the
// census columns and this list must be the SAME numbering (§17 D82)
~konLayerOrder = ~gridClassOrder;

// pure function of the graph: only the published features of the 0_grid export
// — there is no third reading (reference, amendment II). Both laws it reads live
// in 8_koppelfeld: the census / drawn loops (~kfGraphFacts) and the eight steps
// of the derivation (~kfDeriveScheme). The act substitutes its own drawing and
// its own T_tier for the patcher's seed, and nothing else.
~konDerive = { |grid, tTier|
    var nodes = grid[\graph][\nodes];
    var tiers = grid[\graph][\tiers];
    var tT = tTier ? ~cfg_kon.tTier;
    // tau_cell is the score's own quantity (T_tier per drawn row), not part of the
    // census law: reading 1 keeps it with module 8 off
    var tauCell = tT / max(1, grid[\graph][\rowGap]);
    var census, loopPair, edgeTab, schaltung;
    var levels, timeline;

    // reading 1 — macroform: a layer's level at a tier = max over its nodes.
    // It stands on the drawing alone (glyph, tier, strongIn) and therefore
    // survives with module 8 off; only reading 2 needs the census law living there
    levels = Array.fill(tiers, { () });
    nodes.do { |n|
        var l = ~gridLayerOf[n[\ch]];
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
        timeline.add(( t: r * tT, vols: vols.asArray, gone: gone.asArray ));
    };
    timeline.add((
        t: tiers * tT,
        gone: ~konLayerOrder.select { |l| levels[tiers - 1][l].notNil },
        finish: true
    ));

    // the derivation runs HERE and not above: reading 1 is already finished, so
    // a refusal or an exception inside module 8 costs reading 2 and not the act
    schaltung = if(~kfGraphFacts.isNil or: { ~kfDeriveScheme.isNil }) {
        // one law, one place: without the module there is no second copy of the
        // census or of the eight steps to fall back on, and an empty one would
        // be a lie about the drawing. Reading 2 is skipped WITH ITS REASON
        ("9_konstruktion — Чтение 2 пропущено: 8_koppelfeld выключен, закон "
            "деривации (census, петли, восемь шагов §6) живёт там. "
            "Чтение 1 (таймлайн) действует.").postln;
        nil
    } {
        // the act's own T_tier, not ~cfg_kf.patchTtier: tau_cell is the time
        // base of THIS piece, and the band law of step 4 reads it
        var facts = ~kfGraphFacts.(grid, tT);
        census = facts[\census];
        loopPair = facts[\loopPair];
        edgeTab = facts[\edgeTab];
        // reference §6: reading 2 IS the derivation of the patcher, given the
        // drawing of the piece. Depth is the length of a path in the drawing,
        // polarity is the kind of an edge, and the axis of complexity is the
        // axis of the mode — none of it is assigned from above
        ~kfDeriveScheme.(facts, "акт Konstruktion (Чтение 2)");
    };


    ( seed: grid[\seed], complexity: grid[\complexity], tTier: tT,
      tiers: tiers, rowGap: grid[\graph][\rowGap],
      tauCell: tauCell,
      census: census, loops: loopPair, edgeTab: edgeTab,
      timeline: timeline.asArray, schaltung: schaltung )
};

// the act: one piece, three artefacts at once; it does NOT start the piece
// (starting is the performer's act: ~seqStart / the button)
~konGenerate = { |complexity, seed, tTier|
    var grid, kon, dur, status;
    if(Tdef(\ung_sequencer).isPlaying and: { ~seqStop.notNil }) { ~seqStop.value };
    grid = ~gridGenerate.(complexity ? 0.5, seed);
    if(grid.isNil) {
        // refusal: the act aborts with NO partial artefacts — the old piece stands
        status = "refused: no layout after " ++ ~cfg_grid.graphTries
            ++ " graphs — act aborted";
        ("9_konstruktion — " ++ status).postln;
        { ~mixerGridStatus !? { |st| st.string_(status) } }.defer;
        nil
    } {
        kon = ~konDerive.(grid, tTier ? ~cfg_kon.tTier);
    };
    if(kon.notNil) {
        kon[\text] = grid[\text];
        kon[\counts] = grid[\counts];
        // determinism is relative to ~cfg_grid — the score stores a CONFIG snapshot
        kon[\cfgGrid] = ~cfg_grid.copy;
        ~seqTimeline = kon[\timeline];
        // volumes belong to the performer (override 2026-07-18): the sequencer skips vols
        ~seqDriveVols = false;
        // reference §6: the act owns topology, polarities, bands, curves, windows
        // and the resting values — and it owns them THROUGH the scheme. The rests
        // of its targets ride inside `schaltung`, and ~kfInstall writes each one
        // with ~setParam (accepted value, so ~ungVals / tuner / preset carry what
        // sounds); nodes the act does not address keep the preset. What is left
        // to the hand are the gains and the layer volumes
        kon[\schaltung] !? { |sch|
            if(~kfApply.isNil) {
                ("9_konstruktion — схема выведена, но применить нечем: ~kfApply "
                    "не загружен (8_koppelfeld выключен)").warn;
            } {
                // arming, not a cut: forty cables at once is a step on forty
                // parameters, and arrival is composed (reference §8)
                ~kfApply.(sch, (~cfg_kf !? { |c| c[\armTime] }) ? 4);
            };
        };
        ~konCurrent = kon;
        ~konActive = true;
        ~gridLastText = grid[\text];
        dur = kon[\tiers] * kon[\tTier];
        status = "Φ " ++ grid[\nodes] ++ " · field " ++ grid[\cols] ++ "×"
            ++ grid[\rows] ++ " · seed " ++ grid[\seed]
            ++ " · piece " ++ kon[\tiers] ++ " × " ++ kon[\tTier] ++ " s = "
            ++ (dur / 60).floor.asInteger ++ ":"
            ++ (dur - ((dur / 60).floor * 60)).round.asInteger.asString.padLeft(2, "0");
        {
            ~mixerGridTxt !? { |tv|
                tv.string_(grid[\text]);
                tv.setStringColor((~uiPal !? { ~uiPal.ink }) ? Color.black, 0, grid[\text].size);
            };
            ~mixerGridStatus !? { |st| st.string_(status) };
        }.defer;
        if(~mixerKonSync.notNil) { ~mixerKonSync.value };
        ("9_konstruktion — акт: " ++ status).postln;
        kon
    };
};

// score (decision 6): the pair construction-NNNN.txt + construction-NNNN.score.md
~konSaveScore = {
    var kon = ~konCurrent;
    var dir, existing, nnnn, base, txtPath, mdPath, sb, fmt;
    var writeErr, statusStr;
    if(kon.isNil) {
        statusStr = "no score yet: generate an act first";
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
        sb.add("## Рёбра графа (род: прямое/возврат — правило 7; узлы индексами:"
            ++ " закон предка поверяем по самой таблице)");
        sb.add("");
        sb.add("| # | src | dst | род | сила | routeLen |");
        sb.add("|" ++ "---|".dup(6).join);
        (kon[\edgeTab] ? []).do { |e, k|
            sb.add("| " ++ k
                ++ " | " ++ e[\src] ++ "(" ++ (e[\srcI] ? "—") ++ ")"
                ++ " | " ++ e[\dst] ++ "(" ++ (e[\dstI] ? "—") ++ ")"
                ++ " | " ++ if(e[\ret]) { "возврат" } { "прямое" }
                ++ " | " ++ if(e[\strong]) { "сильное" } { "слабое" }
                ++ " | " ++ e[\routeLen] ++ " |");
        };
        sb.add("");
        sb.add("## Census 5×5 (K[src][dst], по направлению рёбер; диагональ читает только макроформа)");
        sb.add("");
        if(kon[\census].isNil) {
            sb.add("_Чтение 2 не выполнено (8_koppelfeld выключен): census не выведен._");
        } {
            sb.add("| src\\\\dst | " ++ ~konLayerOrder.join(" | ") ++ " |");
            sb.add("|" ++ "---|".dup(6).join);
            ~konLayerOrder.do { |a, ai|
                sb.add("| " ++ a ++ " | " ++ kon[\census][ai].join(" | ") ++ " |");
            };
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
        sb.add("## Схема (Чтение 2 — восемь шагов §6 референса)");
        sb.add("");
        if(kon[\schaltung].isNil) {
            sb.add("_Чтение 2 не выполнено: 8_koppelfeld выключен, закон деривации "
                "живёт там._");
        } {
            var sch = kon[\schaltung], rep = sch[\report] ? ();
            var cables = (sch[\cables] ? []).select { |cb| cb[\enabled] != false };
            sb.add("- кабелей: " ++ cables.size ++ " · целей: " ++ (rep[\targets] ? "—")
                ++ " · межслойных: " ++ fmt.((rep[\interlayer] ? 0) * 100, 1) ++ " %"
                ++ " · глубины: " ++ ((rep[\depths] ? []).asString));
            sb.add("- режим: " ++ (sch[\mode] ? "—") ++ " · Λmax: " ++ fmt.(rep[\lamMax], 3)
                ++ " · петель: " ++ (rep[\loops] ? 0)
                ++ " · проходов ремонта: " ++ (rep[\repairs] ? 0));
            (rep[\notes] ? []).do { |n| sb.add("- NOTE " ++ n) };
            sb.add("");
            sb.add("| # | источник | цель | пол. | gain | f_c, Гц | полоса | кривая | окно |");
            sb.add("|" ++ "---|".dup(9).join);
            cables.do { |cb, i|
                sb.add("| " ++ i
                    ++ " | " ++ cb[\src][0] ++ "." ++ cb[\src][1]
                    ++ " | " ++ cb[\dst][0] ++ "." ++ cb[\dst][1]
                    ++ " | " ++ if(cb[\pol] < 0) { "−1" } { "+1" }
                    ++ " | " ++ fmt.(cb[\gain], 3)
                    ++ " | " ++ fmt.(cb[\fc], 4)
                    ++ " | " ++ cb[\band]
                    ++ " | " ++ cb[\curve]
                    ++ " | " ++ fmt.((cb[\win] ? [])[0], 3) ++ "…"
                    ++ fmt.((cb[\win] ? [])[1], 3) ++ " |");
            };
            sb.add("");
            sb.add("### Циклы (Λ = Π gain; период T ≈ 2·Στ)");
            sb.add("");
            if((sch[\loops] ? []).isEmpty) {
                sb.add("_петель нет: рисунок не дал возвратов — схема в `ruhe`_");
            } {
                sb.add("| узлы | звеньев | Λ | инверсий | Στ, с | T, с |");
                sb.add("|" ++ "---|".dup(6).join);
                sch[\loops].do { |lp|
                    sb.add("| " ++ (lp[\nodes] ? []).join(" → ")
                        ++ " | " ++ (lp[\len] ? "—")
                        ++ " | " ++ fmt.(lp[\lam], 3)
                        ++ " | " ++ (lp[\inv] ? "—")
                        ++ " | " ++ fmt.(lp[\tau], 3)
                        ++ " | " ++ fmt.(lp[\period], 3) ++ " |");
                };
            };
        };
        // the button may never stay silent: success = a path, a write failure = an error
        writeErr = nil;
        try {
            File.use(txtPath, "w", { |f| f.write(kon[\text] ++ "\n") });
            File.use(mdPath, "w", { |f| f.write(sb.join("\n") ++ "\n") });
        } { |err| writeErr = err };
        if(writeErr.notNil) {
            statusStr = "score write error: " ++ writeErr.errorString;
            ("9_konstruktion — " ++ statusStr).postln;
            { ~mixerGridStatus !? { |st| st.string_(statusStr) } }.defer;
            nil
        } {
            statusStr = "score: " ++ ~cfg_kon.scoreDir ++ "/" ++ base ++ ".score.md";
            ("9_konstruktion — записано: " ++ txtPath).postln;
            ("9_konstruktion — записано: " ++ mdPath).postln;
            { ~mixerGridStatus !? { |st| st.string_(statusStr) } }.defer;
            [txtPath, mdPath]
        };
    };
};

// idempotent reload: the current act is neither rebuilt nor killed
~konActive  = ~konActive ? false;
~konCurrent = ~konCurrent;
~konTtier   = ~konTtier ? ~cfg_kon.tTier;

"9_konstruktion — форма Konstruktion (~konGenerate / ~konSaveScore).".postln;
)
