// App/9_konstruktion.scd — UNGRUND · KONSTRUKTION (form §E.6): one grid
// generation act is read twice — macroform (4_sequencer timeline) and
// modulation topology. Pure sclang, no server.
// BRANCH experiment/patchbay: the reading-2 executor (8_modmatrix, 16 lines) is
// deleted; its replacement — the `schaltung` derivation in koppelfeld — arrives
// at stage S6. While ~cfg_modmtx is absent reading 2 yields an empty line list;
// reading 1 (timeline, levels, finish) works as before.
// Laws: docs/features/grid-modulation/reference.md; spec: dsp-spec.md there.
// API: ~konGenerate.(complexity, seed, tTier) · ~konDerive.(grid, tTier) ·
//      ~konSaveScore.

(
// ===== CONFIG — edit here ============================================
~cfg_kon = (
    tTier:        30,              // default score T_tier, s
    tTierRange:   [15, 60],        // T_tier field bounds in the mixer panel
    weakLevel:    0.5,             // weak coupling: x0.5 = -6 dB (decision 3)
    rateScale:    12,              // rate-law multiplier (user override: pulse, not drift)
    rateClip:     [0.05, 2.0],     // Hz, derivation step 3 (widened for rateScale)
    fmBase:       0.3, fmSpan: 0.9,        // fm = fmBase + fmSpan·strongShare
    depthGain:    0.22, depthFloor: 0.06,  // depth = clip(depthGain·cAB, floor, max)
    depthMax:     0.5,             // shared ceiling, theta included (user override §C.8)
    baseRange:    [0.15, 0.85],    // normalized range of destination base values
    scoreDir:     "docs/architecture/structure-grid"  // relative to the project root
);


// ===== LOGIC — derivation, act, score ================================
~konLayerOrder = [\alpha, \delta, \epsilon, \zeta, \theta];

// String keys, not Char (the glyphs are multibyte); Dictionary compares by value
~konLayerOf = Dictionary.newFrom([
    "█", \alpha, "▄", \delta, "▓", \epsilon, "░", \zeta, "▒", \theta
]);

~konLineFamily = [\P, \F, \S, \F, \P, \F, \S, \F, \S, \P, \S, \P, \P, \F, \P, \P];
~konFamilyLine = (
    P: ( alpha: 0, delta: 4, epsilon: 9, zeta: 11, theta: 14 ),
    S: ( alpha: 2, delta: 6, epsilon: 8, zeta: 10 ),
    F: ( alpha: 1, delta: 5, epsilon: 7, theta: 13 )
);

// pure function of the graph: only the published features of the 0_grid export
// — there is no third reading (reference, amendment II)
~konDerive = { |grid, tTier|
    var g = grid[\graph];
    var nodes = g[\nodes], edges = g[\edges];
    var tiers = g[\tiers], rowGap = g[\rowGap];
    var tauCell = tTier / rowGap;
    var layerIdx = ();
    var layerOfNode, census, loopPair, levels, timeline, lines;

    ~konLayerOrder.do { |l, k| layerIdx[l] = k };
    layerOfNode = { |n| ~konLayerOf[n[\ch]] };

    // census over the FULL graph, BY EDGE DIRECTION (amendment II)
    census = Array.fill(5, { Array.fill(5, 0) });
    edges.do { |e|
        var a = layerIdx[layerOfNode.(nodes[e[\src]])];
        var b = layerIdx[layerOfNode.(nodes[e[\dst]])];
        census[a][b] = census[a][b] + 1;
    };

    // a drawn loop A<->B: both directions non-zero AND at least one edge of the
    // pair is a back edge (amendment II)
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

    // reading 1 — macroform: a layer's level at a tier = max over its nodes
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

    // reading 2 — 16 lines: the reference's 7 steps (rate x rateScale is a user override)
    lines = (~cfg_modmtx !? { |c| c.lines } ? []).collect { |cfgLine, i|
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
        // step 1: the diagonal is excluded from source selection
        cands = (0..4).select { |a| (a != bIdx) and: { census[a][bIdx] > 0 } };
        ln = if(cands.isEmpty) {
            // step 7: empty census — an autonomous line (fm = 0, src has no effect)
            ( target: b, param: param, shape: cfgLine[\shape], rate: cfgLine[\rate],
              src: cfgLine[\src], fm: 0, depth: 0, loopAB: 0,
              srcLayer: nil, family: family, nEdges: 0,
              meanRoute: nil, strongShare: nil, cAB: nil, derived: false )
        } {
            // sort is not stable in SC — the tie-break is spelled out
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
            // cAB degrees over the FULL graph (back edges included): division defined
            cAB = ab.collect { |e| nodes[e[\dst]][\indeg] }.mean
                / ab.collect { |e| nodes[e[\src]][\outdeg] }.mean;
            isLoop = loopPair[aIdx][bIdx];
            // step 5b: a loop boosts both facing lines x1.5; clip AFTER the boost
            depth = (~cfg_kon.depthGain * cAB * if(isLoop) { 1.5 } { 1 })
                .clip(~cfg_kon.depthFloor, ~cfg_kon.depthMax);
            // step 6: a loop is periodic by construction => \sine
            shape = if(isLoop
                or: { (ab.count { |e| nodes[e[\dst]][\indeg] >= 2 } * 2) > ab.size })
                { \sine } { \noise };
            ( target: b, param: param, shape: shape, rate: rate, src: src,
              fm: fm, depth: depth, loopAB: if(isLoop) { 1 } { 0 },
              srcLayer: aLayer, family: family, nEdges: ab.size,
              meanRoute: meanRoute, strongShare: strongShare, cAB: cAB,
              derived: true )
        };
        // destination base value (override: an act is a new timbral identity even
        // at depth 0) — deterministic golden-ratio scramble
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
            srcI: e[\src], dstI: e[\dst],
            ret: e[\ret] == true, strong: e[\strong] == true,
            routeLen: e[\routeLen] )
      },
      timeline: timeline.asArray, lines: lines )
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
        kon[\text] = grid[\text];
        kon[\counts] = grid[\counts];
        // determinism is relative to ~cfg_grid — the score stores a CONFIG snapshot
        kon[\cfgGrid] = ~cfg_grid.copy;
        ~seqTimeline = kon[\timeline];
        // volumes belong to the performer (override 2026-07-18): the sequencer skips vols
        ~seqDriveVols = false;
        // base centres of the 16 destinations from the graph — BEFORE the matrix
        // rebuild, so modmtx_map_i captures the new centreN values
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
        if(~modBuild.notNil) {
            ~modBuild.(kon[\lines].collect { |ln|
                ( target: ln[\target], param: ln[\param], shape: ln[\shape],
                  rate: ln[\rate], src: ln[\src], fm: ln[\fm], depth: ln[\depth] )
            });
        } {
            "9_konstruktion — Чтение 2 пропущено: исполнителя топологии нет "
                "(деривация schaltung — этап S6 ветки patchbay). Чтение 1 (таймлайн) действует.".postln;
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
        (~modKeys ? []).do { |e, i|
            if(~modmatrixGuiSync.notNil) { ~modmatrixGuiSync.(i, e[\depth]) };
            if(~modmatrixGuiRelabel.notNil) { ~modmatrixGuiRelabel.(i, e[\label]) };
        };
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
        if(kon[\lines].isEmpty) {
            sb.add("_Чтение 2 не выполнено: исполнителя топологии нет "
                "(деривация schaltung — этап S6)._");
            sb.add("");
        };
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
