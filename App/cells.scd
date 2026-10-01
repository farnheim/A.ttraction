// App/cells.scd — NET matrix cells: the store, its one write door ~netWrite, hand and chance; docs: docs/features/matrix-ru.md

// ===== CONFIG — edit here ============================================
(
~cfg_net = (
    diceDensity: 0.03,
    diceDepth:   0.5,
    minDepth:    0.0005,
    // start values only: the live ones (~netLive) survive a re-run of this file, as cells and nodes do
    wander:      0.0,
    wanderRate:  0.3,
    drift:       0,
    driftPeriod: 3.0,
    cellLag:     0.08,
    // the per-cell rate factor is fixed by the cell's key, so a preset plays back as it was saved
    rateSpread:  [0.25, 4.0],
    lineDensity: 4,
    mutateShare: 0.1,
    mutateTries: 20
);

// ===== LOGIC =========================================================
~netCells = ~netCells ? Dictionary.new;
~netViews = ~netViews ? ();
~netLive  = ~netLive ? (wander: ~cfg_net.wander, wanderRate: ~cfg_net.wanderRate, drift: ~cfg_net.drift);

// depth only thins inside [0, x] (a line is the cell's ceiling); LFNoise2 overshoots ±1, hence the clip
SynthDef(\net_cell, { |src = 0, dst = 0, depth = 0, wander = 0, wrate = 0.3, drift = 0, dper = 3,
    rmul = 1, lagT = 0.08|
    var h = wander.lag(0.1) * 0.5;
    var g = depth.lag(lagT) * (1 - (drift.lag(1) * (1 - LFNoise2.kr(rmul / dper.max(0.01)).clip(-1, 1)) * 0.5));
    Out.ar(dst, InFeedback.ar(src)
        * LFNoise2.ar((wrate * rmul).clip(0.001, 400)).clip(-1, 1).madd(h * g, (1 - h) * g));
}).add;


// ----- the store and its nodes ----------------------------------------
~netCellKey = { |src, dst| (~netTag.(src) ++ ">" ++ ~netTag.(dst)).asSymbol };
~netPort = { |l, k| [l.asSymbol, k.asSymbol] };

~netEnsureGroup = {
    if(~netGroup.isNil or: { ~netGroup.isPlaying.not }) {
        ~netGroup = Group.tail(s);
        NodeWatcher.register(~netGroup, true);
    };
    ~netGroup
};

~netHands = { [
    wander: ~netLive.wander, wrate: ~netLive.wanderRate,
    drift: ~netLive.drift, dper: ~cfg_net.driftPeriod, lagT: ~cfg_net.cellLag
] };

~netSpawn = { |c|
    var si = ~netPortIndex.(c[\src][0], c[\src][1], \src);
    var di = ~netPortIndex.(c[\dst][0], c[\dst][1], \dst);
    c[\node] !? { |nd| nd.free; c[\node] = nil };
    if(si.notNil and: { di.notNil } and: { s.serverRunning }) {
        c[\node] = Synth(\net_cell, [src: si, dst: di, depth: c[\depth], rmul: c[\rmul]] ++ ~netHands.value,
            ~netEnsureGroup.value);
    };
};

~netRateOf = { |key|
    var lo = ~cfg_net.rateSpread[0], hi = ~cfg_net.rateSpread[1];
    lo * ((hi / lo) ** ((key.asString.hash.abs % 10007) / 10006))
};

~netWrite = { |src, dst, depth|
    var key = ~netCellKey.(src, dst), c = ~netCells[key];
    depth = depth.clip(-1, 1);
    case
    { depth.abs < ~cfg_net.minDepth } {
        ~netCells.removeAt(key) !? { |x| x[\node] !? { |nd| nd.free } };
    }
    { c.isNil } {
        c = ( src: src, dst: dst, depth: depth, rmul: ~netRateOf.(key) );
        ~netCells[key] = c;
        ~netSpawn.(c);
    }
    {
        c[\depth] = depth;
        if(c[\node].notNil) { c[\node].set(\depth, depth) } { ~netSpawn.(c) };
    };
};
~netApply = { |triples| triples.do { |t| ~netWrite.(t[0], t[1], t[2]) } };
~netTriples = { |skip|
    ~netCells.values.asArray
        .reject { |c| skip.notNil and: { skip.includes(c) } }
        .collect { |c| [c[\src], c[\dst], c[\depth]] }
};
~netChanged = { ~netViews.do { |f| f.value } };
~netThrown = { ~graphPlace !? (_.value) };

~netClear = { |notify = true|
    ~netCells.values.do { |c| ~netWrite.(c[\src], c[\dst], 0) };
    if(notify) { ~netChanged.value };
};

// after any layer (re)load: a bus may have moved, and a cell holds indices
~netRewire = {
    if(s.serverRunning) {
        ~netGroup !? { |g| if(g.isPlaying) { g.free } };
        ~netGroup = nil;
        ~netCells.do { |c| c[\node] = nil; ~netSpawn.(c) };
    };
};


// ----- cells <-> columns of lines.scd ---------------------------------
~netFrame = {
    var rows = IdentityDictionary.new, cols = IdentitySet.new;
    ~netAllPorts.(\src).do { |p, i| rows[~netTag.(p)] = i };
    ~netAllPorts.(\dst).do { |p| cols.add(~netTag.(p)) };
    ( rows: rows, cols: cols, n: rows.size, walls: (~graphWalls !? (_.value)) ?? { IdentityDictionary.new } )
};

~netColumns = { |frame, triples, fixed|
    var lr = ~cfg_lines.lineRows, order = List.new, groups = IdentityDictionary.new;
    triples.do { |t|
        var r = frame[\rows][~netTag.(t[0])], k = ~netTag.(t[1]);
        if(r.notNil and: { frame[\cols].includes(k) }) {
            if(groups[k].isNil) { groups[k] = List.new; order.add(k) };
            groups[k].add((row: r, len: t[2] * lr, fixed: fixed, src: t[0], dst: t[1]));
        };
    };
    groups.do { |g| g.sort { |x, y| x[\row] < y[\row] } };
    [order, groups]
};

// the shortest line that may exist, in rows
~netLeast = { ~cfg_net.minDepth * ~cfg_lines.lineRows };

~netPlan = { |cands, lenFn, skip|
    var f = ~netFrame.value, fixed = ~netColumns.(f, ~netTriples.(skip), true)[1];
    var fresh = ~netColumns.(f, cands.reject { |ab| ab[0] == ab[1] }.collect { |ab| ab ++ [0] }, false);
    var least = ~netLeast.value, plan = List.new;
    fresh[0].do { |k|
        var col = ~linesWall.((fixed[k] ? []).asArray, f[\walls][k]);
        fresh[1][k].do { |e| col = ~linesAccept.(col, e, f[\n], least) };
        ~linesDeal.(col, f[\n], lenFn).do { |e|
            if(e[\fixed].not) { plan.add([e[\src], e[\dst], e[\len] / ~cfg_lines.lineRows]) };
        };
    };
    plan
};

~netDealRandom = { |depth, law|
    var cap = (depth ? ~cfg_net.diceDepth).abs.min(1) * ~cfg_lines.lineRows;
    var least = ~netLeast.value, capOf = ~netCapOf.(law);
    { |up, down, e|
        var sg = case { (up > least) and: { down > least } } { [-1, 1].choose }
            { down > least } { 1 } { up > least } { -1 } { 0 };
        sg * (cap * (capOf !? { |f| f.(e) } ? 1)).min(if(sg > 0) { down } { up }) * (1.0 - 1.0.rand).squared
    }
};

~netRange = { |sl, sk, dl, dk|
    var f = ~netFrame.value, src = ~netPort.(sl, sk), dst = ~netPort.(dl, dk);
    var r = f[\rows][~netTag.(src)], col;
    if(r.isNil or: { f[\cols].includes(~netTag.(dst)).not }) { nil } {
        col = ~netColumns.(f, ~netTriples.value.select { |t| (t[1] == dst) and: { t[0] != src } }, true)[1];
        ~linesRange.(~linesWall.((col[~netTag.(dst)] ? []).asArray, f[\walls][~netTag.(dst)]), r, f[\n])
            / ~cfg_lines.lineRows
    }
};


// ----- the hand ---------------------------------------------------------

// `range` is the cell's range when the caller holds it already (a drag)
~netPut = { |sl, sk, dl, dk, depth, range|
    var src = ~netPort.(sl, sk), dst = ~netPort.(dl, dk);
    (range ?? { ~netRange.(sl, sk, dl, dk) }) !? { |rg| depth = depth.clip(rg[0], rg[1]) };
    ~netWrite.(src, dst, depth);
};
~netSet = { |sl, sk, dl, dk, depth, range| ~netPut.(sl, sk, dl, dk, depth, range); ~netChanged.value };
~netDepth = { |sl, sk, dl, dk|
    ~netCells[~netCellKey.(~netPort.(sl, sk), ~netPort.(dl, dk))] !? { |c| c[\depth] } ? 0
};

// straight to the store, not through the hand: ~netPut would clip each cell against the ones read before
~netLoad = { |triples|
    ~netClear.(false);
    ~netApply.(triples.collect { |t| [~netPort.(*t[0]), ~netPort.(*t[1]), t[2]] });
};


// ----- chance ---------------------------------------------------------

// with no law every path is the plain one, draw for draw: a pre-fingerprint seed throws the same matrix
~netLaw = { ~fpLaw !? (_.value) };

~netBlocks = { |srcs, dsts, law|
    var group = { |ports|
        var d = IdentityDictionary.new, order = List.new;
        ports.do { |p| if(d[p[0]].isNil) { d[p[0]] = List.new; order.add(p[0]) }; d[p[0]].add(p) };
        order.collect { |l| [l, d[l]] }
    };
    var out = List.new, gd = group.(dsts);
    group.(srcs).do { |ga| gd.do { |gb|
        var w = (law[\W][ga[0]] !? { |r| r[gb[0]] }) ? 0;
        if(w > 0) { out.add([ga[1], gb[1], w]) };
    } };
    out
};

// under a law the expected count stays density · |srcs| · |dsts|, shared by weight, not by port count
~netCandidates = { |srcs, dsts, density, law|
    var cands = List.new, blocks, sum, n;
    if(law.isNil) {
        srcs.do { |a| dsts.do { |b| if(density.coin) { cands.add([a, b]) } } };
    } {
        blocks = ~netBlocks.(srcs, dsts, law);
        sum = blocks.sum { |x| x[2] };
        n = density * srcs.size * dsts.size;
        blocks.do { |x|
            var p = (n * x[2] / sum / (x[0].size * x[1].size)).min(1);
            x[0].do { |a| x[1].do { |b| if(p.coin) { cands.add([a, b]) } } };
        };
    };
    cands
};

~netPickPair = { |srcs, dsts, blocks|
    var x;
    case
    { blocks.isNil } { [srcs.choose, dsts.choose] }
    { blocks.isEmpty } { nil }
    { x = blocks[blocks.collect(_[2]).normalizeSum.windex]; [x[0].choose, x[1].choose] }
};

// a pair the law says nothing of keeps the whole depth: only shake meets one (a hand or preset cell)
~netCapOf = { |law|
    law !? { |w| { |e|
        var a = e[\src][0], b = e[\dst][0];
        if(((w[\n][a] !? { |r| r[b] }) ? 0) > 0) { w[\M][a][b] } { 1 }
    } }
};

~netThrow = { |srcs, dsts, density, depth|
    var law = ~netLaw.value;
    ~netApply.(~netPlan.(~netCandidates.(srcs, dsts, density, law), ~netDealRandom.(depth, law)));
    ~netThrown.value;
    ~netChanged.value;
    law
};

~netDice = { |density, depth, clear = true|
    var law;
    if(clear) { ~netClear.(false) };
    law = ~netThrow.(~netAllPorts.(\src), ~netAllPorts.(\dst), density ? ~cfg_net.diceDensity, depth);
    ("net · dice · " ++ ~netCells.size ++ " cells" ++ if(law.notNil) { " · fingerprint" } { "" }).postln;
};

~netClearLine = { |side, port, notify = true|
    var tag = ~netTag.(port);
    ~netCells.values.select { |c| ~netTag.(c[side]) == tag }.do { |c| ~netWrite.(c[\src], c[\dst], 0) };
    if(notify) { ~netChanged.value };
};
~netDiceLine = { |side, port, density, depth|
    var others = ~netAllPorts.(if(side == \src) { \dst } { \src });
    density = (density ? ~cfg_net.diceDensity) * ~cfg_net.lineDensity;
    ~netClearLine.(side, port, false);
    if(side == \src) { ~netThrow.([port], others, density, depth) } { ~netThrow.(others, [port], density, depth) };
};

// a cell onto itself is never placed again (~netPlan): it stands fixed, or its column's lines run through it
~netShake = { |depth|
    var cells = ~netCells.values.asArray.reject { |c| c[\src] == c[\dst] };
    ~netApply.(~netPlan.(cells.collect { |c| [c[\src], c[\dst]] },
        ~netDealRandom.(depth, ~netLaw.value), IdentitySet.newFrom(cells)));
    ~netChanged.value;
};
~netMutate = { |n, depth|
    var cells = ~netCells.values.asArray, srcs = ~netAllPorts.(\src), dsts = ~netAllPorts.(\dst);
    var law = ~netLaw.value, blocks = law !? { |w| ~netBlocks.(srcs, dsts, w) }, made = 0, tries = 0, plan;
    n = n ? (cells.size * ~cfg_net.mutateShare).ceil.asInteger.max(1);
    // a law that lets no pair talk could only remove: the matrix would shrink unseen
    if(blocks.isNil or: { blocks.notEmpty }) {
        cells.scramble.keep(n.min(cells.size)).do { |c| ~netWrite.(c[\src], c[\dst], 0) };
        while { (made < n) and: { tries < ~cfg_net.mutateTries } } {
            plan = ~netPlan.(Array.fill(n - made, { ~netPickPair.(srcs, dsts, blocks) }).reject(_.isNil),
                ~netDealRandom.(depth, law))
                .select { |t| t[2].abs >= ~cfg_net.minDepth };
            ~netApply.(plan);
            made = made + plan.size;
            tries = tries + 1;
        };
        ~netThrown.value;
        ~netChanged.value;
    };
};


// ----- the two hands on the whole field -------------------------------
~netHandsSet = { ~netGroup !? { |g| if(g.isPlaying) { g.set(*~netHands.value) } } };

~netWander = { |amt, rate|
    amt  !? { ~netLive.wander = amt.clip(0, 1) };
    rate !? { ~netLive.wanderRate = rate.clip(0.001, 400) };
    ~netHandsSet.value;
};

~netDrift = { |on = true|
    ~netLive.drift = if(on) { 1 } { 0 };
    ~netHandsSet.value;
    ~netChanged.value;
    on
};

~netHandsSet.value;


"cells — поле готово (~netDice, ~netSet, ~netWander, ~netDrift).".postln;
)
