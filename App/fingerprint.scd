// App/fingerprint.scd — NET fingerprint: a braid structure folded into the law of chance; docs: docs/features/matrix-ru.md

(
// ===== CONFIG — edit here ============================================

// field 22 × 18 cells: square on the deck (cell 18 × 22 px), room for 20 glyphs in four lanes
~cfg_fp = (
    nodes:       [5, 20],
    strands:     [1, 4],
    swapProb:    [0.00, 0.50],
    cols:        22,
    rows:        18,
    runMin:      1,
    runMax:      4,
    rasterTries: 24,
    graphTries:  120,
    strongW:     1.0,
    weakW:       0.5,
    symTol:      0.02,
    symIters:    40,
    knobs:       (complexity: 0.9, links: 0.6, symmetry: 0.5)
);

// ===== LOGIC =========================================================

// a layer without a glyph takes no part
~fpClassOrder = [\alpha, \delta, \epsilon, \zeta, \theta];
~fpCharOf = (alpha: "█", delta: "▄", epsilon: "▓", zeta: "░", theta: "▒");
~fpLayerOf = Dictionary.new;
~fpClassOrder.do { |l| ~fpLayerOf[~fpCharOf[l]] = l };
// a node holds this until the layers are dealt: a symbol cannot move the layout
~fpNodeMark = "*";
~fpCrossOf = (
    single: (single: "┼", double: "╪"),
    double: (single: "╫", double: "╬")
);
~fpCrossChars = ~fpCrossOf.values.collect(_.values).flatten;
~fpLineChars = (
    weak:   (vert: "│", horiz: "─", upRight: "└", upLeft: "┘", downRight: "┌", downLeft: "┐"),
    strong: (vert: "║", horiz: "═", upRight: "╚", upLeft: "╝", downRight: "╔", downLeft: "╗")
);

~fpLive  = ~fpLive ? (on: false).putAll(~cfg_fp.knobs);
~fpViews = ~fpViews ? ();
~fpChanged = { ~fpViews.do { |f| f.value } };

~fpLerp = { |pair, t| pair[0] + ((pair[1] - pair[0]) * t) };
// (a..b) with a > b counts DOWN in SC and is non-empty — a degenerate segment would draw
~fpSpan = { |a, b| if(a > b) { [] } { (a .. b) } };

~fpActive = { |layers|
    (layers ?? { ~netLayers !? (_.value) } ?? { ~fpClassOrder }).select { |l| ~fpCharOf[l].notNil }
};

// a String is bytes: the box characters are three of them each
~fpCellsOf = { |row|
    var out = List.new, cur;
    row.do { |ch|
        var b = ch.ascii;
        if(b < 0) { b = b + 256 };
        if((b.bitAnd(0xC0) == 0x80) and: { cur.notNil }) { cur = cur ++ ch } {
            cur !? { out.add(cur) };
            cur = ch.asString;
        };
    };
    cur !? { out.add(cur) };
    out.asArray
};

~fpRender = { |fp|
    fp[\text].collect { |s|
        var i = s.size - 1;
        while { i >= 0 and: { s[i] == $  } } { i = i - 1 };
        if(i < 0) { "" } { s.copyRange(0, i) }
    }.join("\n")
};

// ----- the braid + coupling strength -----------------------------------

// each lane closes with one return (rule 11): the couplings form a permutation, one in and one out
~fpBraid = { |n, k, swapProb|
    var len = Array.fill(k, { |lane| (n div: k) + (lane < (n % k)).binaryValue });
    var grid = Array.fill(k, { List[] }), nodes = List[], edges = List[], swaps = 0;
    // one from another lane enters by the side facing its parent
    var addEdge = { |a, b|
        var e = (src: a, dst: b, strong: a.lane == b.lane,
            entry: case { a.lane == b.lane } { \up } { a.lane > b.lane } { \right } { \left });
        edges.add(e); b[\from] = e;
    };

    len.maxItem.do { |t|
        k.do { |lane|
            if(t < len[lane]) {
                var x = (tier: t, lane: lane, above: grid[lane].last);
                nodes.add(x); grid[lane].add(x);
            };
        };
    };

    (len.maxItem - 1).do { |t|
        var alive = (0 .. k - 1).select { |lane| len[lane] > (t + 1) }, to = (0 .. k - 1);
        var used = Array.fill(k, false);
        ~fpSpan.(0, alive.size - 2).scramble.do { |i|
            var a = alive[i], b = alive[i + 1];
            if(used[a].not and: { used[b].not } and: { swapProb.coin }) {
                to.swap(a, b); used[a] = true; used[b] = true; swaps = swaps + 1;
            };
        };
        alive.do { |lane| addEdge.(grid[lane][t], grid[to[lane]][t + 1]) };
    };

    (
        nodes: nodes.asArray, edges: edges.asArray, strands: k, swaps: swaps,
        rets: grid.collect { |g| (src: g.last, dst: g.first, strong: g.last[\from].strong) }
    )
};

// ----- placement ------------------------------------------------------

// run ≥ 2 under the parent (rule 3: no touching); ≥ 3 across lanes: each crossing coupling needs a turn row
~fpPlace = { |graph, cols|
    graph[\nodes].do { |n|
        var run = ~cfg_fp.runMin + ((~cfg_fp.runMax - ~cfg_fp.runMin + 1) * (1.0.rand ** 2.5)).floor;
        n.col = (cols * (n.lane + 1) / (graph[\strands] + 1)).floor.asInteger;
        n[\row] = if(n[\from].isNil) { 1 + (1.0.rand ** 2).round.asInteger } {
            var p = n[\from].src;
            p[\row].max(n[\above][\row]) + run.max(if(p.lane == n.lane) { 2 } { 3 })
        };
    };
};

// ----- rasterization --------------------------------------------------
~fpEdgeCells = { |e, j|
    var r1 = e.src[\row], r2 = e.dst[\row], x = e.src.col, c = e.dst.col, y = c + (x - c).sign;
    var g = if(e.strong) { ~fpLineChars.strong } { ~fpLineChars.weak };
    var out = List[];
    if(x == c) { ~fpSpan.(r1 + 1, r2 - 1).do { |r| out.add([r, x, g.vert]) } } {
        ~fpSpan.(r1 + 1, j - 1).do { |r| out.add([r, x, g.vert]) };
        out.add([j, x, if(y > x) { g.upRight } { g.upLeft }]);
        ~fpSpan.(x.min(y) + 1, x.max(y) - 1).do { |cc| out.add([j, cc, g.horiz]) };
        out.add([j, y, if(y > x) { g.downLeft } { g.downRight }]);
        ~fpSpan.(j + 1, r2 - 1).do { |r| out.add([r, y, g.vert]) };
        out.add([r2, y, if(y > c) { g.upLeft } { g.upRight }]);
    };
    out
};

// the two axes of a return differ in strength (rule 7): a mixed corner marks a change of reading direction
~fpReturnCells = { |e, x|
    var r1 = e[\src][\row], r2 = e[\dst][\row], c = e[\src].col, strong = e[\strong];
    var vert = if(strong) { "║" } { "│" }, horiz = if(strong) { "─" } { "═" };
    var out = List[];
    [r1, r2].do { |r| ~fpSpan.(c.min(x) + 1, c.max(x) - 1).do { |cc| out.add([r, cc, horiz]) } };
    out.add([r1, x, if(x > c) { if(strong) { "╜" } { "╛" } } { if(strong) { "╙" } { "╘" } }]);
    ~fpSpan.(r2 + 1, r1 - 1).do { |r| out.add([r, x, vert]) };
    out.add([r2, x, if(x > c) { if(strong) { "╖" } { "╕" } } { if(strong) { "╓" } { "╒" } }]);
    out
};

// a return leaves its last glyph by the side a swap did not come in by
~fpReturnCols = { |e, cols|
    var c = e[\src].col, taken = e[\src][\from][\entry];
    (1 .. cols - 2).reject { |x| (x == c) or: { taken == if(x > c) { \right } { \left } } }.scramble
};

// a failed routing is retried ON THE SAME graph (rasterTries): culling on collision would bias the draw
~fpAttempt = { |graph, cols, rows|
    var field, crossCount, place, pass, edgesByReach, n = 0, routed = false;
    var rets = graph[\rets], crossQuota = 3 * graph[\swaps];
    var isV = { |s| (s == ~fpLineChars.weak.vert) or: { s == ~fpLineChars.strong.vert } };
    var isH = { |s| (s == ~fpLineChars.weak.horiz) or: { s == ~fpLineChars.strong.horiz } };

    ~fpPlace.(graph, cols);
    edgesByReach = graph[\edges].sort { |a, b| (a.src.col - a.dst.col).abs > (b.src.col - b.dst.col).abs };

    // rule 8: a crossing is only a vertical through a horizontal; allowCross = false is the planar law
    place = { |list, allowCross|
        var need = List[], fine = true;
        var crossFor = { |vSym, hSym|
            ~fpCrossOf[if(vSym == "║") { \double } { \single }][if(hSym == "═") { \double } { \single }]
        };
        list.do { |t|
            var cur = field[t[0]][t[1]];
            if(fine) {
                case
                    { cur == " " } { }
                    { allowCross.not } { fine = false }
                    { isV.(t[2]) and: { isH.(cur) } } { need.add([t[0], t[1], crossFor.(t[2], cur)]) }
                    { isH.(t[2]) and: { isV.(cur) } } { need.add([t[0], t[1], crossFor.(cur, t[2])]) }
                    { true } { fine = false };
            };
        };
        if(fine and: { (crossCount + need.size) > crossQuota }) { fine = false };
        if(fine) {
            list.do { |t| if(field[t[0]][t[1]] == " ") { field[t[0]][t[1]] = t[2] } };
            need.do { |t| field[t[0]][t[1]] = t[2] };
            crossCount = crossCount + need.size;
        };
        fine
    };

    // planar is preferred: the crossing pass runs only when planar fails
    pass = {
        var fine = true;
        var route = { |options, cellsOf|
            var done = false;
            [false, true].do { |allow| options.do { |o| if(done.not) { done = place.(cellsOf.(o), allow) } } };
            done
        };
        field = Array.fill(rows, { Array.fill(cols, " ") });
        crossCount = 0;
        graph[\nodes].do { |g| field[g[\row]][g.col] = ~fpNodeMark };
        edgesByReach.do { |e|
            if(fine) { fine = route.(~fpSpan.(e.src[\row] + 1, e.dst[\row] - 1).scramble, { |j| ~fpEdgeCells.(e, j) }) };
        };
        rets.do { |e| if(fine) { fine = route.(~fpReturnCols.(e, cols), { |x| ~fpReturnCells.(e, x) }) } };
        fine
    };

    if(graph[\nodes].every { |g| g[\row] <= (rows - 2) }) {
        while { routed.not and: { n < ~cfg_fp.rasterTries } } { n = n + 1; routed = pass.value };
    };

    if(routed) {
        var idx = IdentityDictionary[];
        graph[\nodes].do { |g, i| idx[g] = i };
        (
            field: field,
            nodes: graph[\nodes].collect { |g| [g.tier, g.col, g[\row]] },
            edges: graph[\edges].collect { |e| [idx[e.src], idx[e.dst], e.strong.binaryValue, 0] }
                ++ rets.collect { |e| [idx[e[\src]], idx[e[\dst]], e[\strong].binaryValue, 1] },
            strands: graph[\strands],
            swaps: graph[\swaps]
        )
    }
};

// ----- layers onto nodes: chance picks who is present, symmetry who talks to whom
~fpPairW = { |nodeLayers, edges|
    var w = IdentityDictionary.new, cnt = IdentityDictionary.new;
    edges.do { |e|
        var a = nodeLayers[e[0]], b = nodeLayers[e[1]];
        if(w[a].isNil) { w[a] = IdentityDictionary.new; cnt[a] = IdentityDictionary.new };
        w[a][b] = (w[a][b] ? 0) + if(e[2] == 1) { ~cfg_fp.strongW } { ~cfg_fp.weakW };
        cnt[a][b] = (cnt[a][b] ? 0) + 1;
    };
    (W: w, n: cnt)
};

// 0 = every pair one-way, 1 = every pair balanced; no pair of two layers = 1
~fpSigma = { |nodeLayers, edges|
    var w = ~fpPairW.(nodeLayers, edges)[\W], num = 0, den = 0;
    w.keysValuesDo { |a, row|
        row.keysValuesDo { |b, x|
            if(a != b) {
                den = den + x;
                num = num + x.min((w[b] !? { |r| r[a] }) ? 0);
            };
        };
    };
    if(den > 0) { num / den } { 1.0 }
};

// swaps keep the histogram (only who sits where moves): each layer gets n div L glyphs or one more
~fpDeal = { |n, layers| layers.scramble.wrapExtend(n).scramble };

~fpAssign = { |n, edges, layers, target|
    var nl = ~fpDeal.(n, layers), sig = ~fpSigma.(nl, edges), tries = 0;
    var budget = ~cfg_fp.symIters * n;
    while { ((sig - target).abs >= ~cfg_fp.symTol) and: { tries < budget } } {
        var i = n.rand, j = n.rand, s2;
        tries = tries + 1;
        if(nl[i] != nl[j]) {
            nl.swap(i, j);
            s2 = ~fpSigma.(nl, edges);
            if((s2 - target).abs < (sig - target).abs) { sig = s2 } { nl.swap(i, j) };
        };
    };
    nl
};

// ----- the act: one seed, one borrowed stream -------------------------
~fpBuild = { |complexity, links, symmetry, seed, layers|
    var k0 = ~cfg_fp.knobs;
    var c = (complexity ? k0.complexity).clip(0, 1), l = (links ? k0.links).clip(0, 1);
    var sy = (symmetry ? k0.symmetry).clip(0, 1);
    var target = ~fpLerp.(~cfg_fp.nodes, c).round.asInteger.max(2);
    // a strand of one glyph would have to return into itself
    var k = ~fpLerp.(~cfg_fp.strands, c).round.asInteger.clip(1, target div: 2);
    var sp = ~fpLerp.(~cfg_fp.swapProb, l);
    var got, n = 0, wasRand, nl;
    layers = ~fpActive.(layers);
    seed = seed ?? { Date.seed };
    if(layers.isEmpty) { nil } {
        // the stream is BORROWED: a thread left reseeded would make later dice a function of the fp seed
        wasRand = thisThread.randData;
        thisThread.randSeed = seed;
        protect {
            while { got.isNil and: { n < ~cfg_fp.graphTries } } {
                n = n + 1;
                got = ~fpAttempt.(~fpBraid.(target, k, sp), ~cfg_fp.cols, ~cfg_fp.rows);
            };
            got !? { nl = ~fpAssign.(got[\nodes].size, got[\edges], layers, sy) };
        } { thisThread.randData = wasRand };
        got !? {
            got[\nodes].do { |p, i| got[\field][p[2]][p[1]] = ~fpCharOf[nl[i]] };
            (
                seed: seed, complexity: c, links: l, symmetry: sy,
                text: got[\field].collect { |row| row.join("") },
                nodes: got[\nodes].collect { |p, i| [p[0], p[1], nl[i], p[2]] },
                edges: got[\edges],
                counts: (
                    strands: got[\strands], nodes: nl.size,
                    returns: got[\edges].count { |e| e[3] == 1 }, swaps: got[\swaps],
                    crosses: got[\field].sum { |row| row.count { |x| ~fpCrossChars.any { |y| y == x } } },
                    sigma: ~fpSigma.(nl, got[\edges]).round(0.001)
                )
            )
        }
    }
};

// ----- the law --------------------------------------------------------

// W[A][B]: summed coupling strength from A's glyphs to B's, the diagonal included; M[A][B]: the mean
~fpWeights = { |fp, layers|
    var pw = ~fpPairW.(fp[\nodes].collect { |x| x[2].asSymbol }, fp[\edges]);
    var w = IdentityDictionary.new, cnt = IdentityDictionary.new, m = IdentityDictionary.new;
    layers = ~fpActive.(layers);
    layers.do { |a|
        w[a] = IdentityDictionary.new; cnt[a] = IdentityDictionary.new; m[a] = IdentityDictionary.new;
        layers.do { |b|
            w[a][b] = (pw[\W][a] !? { |r| r[b] }) ? 0;
            cnt[a][b] = (pw[\n][a] !? { |r| r[b] }) ? 0;
            m[a][b] = if(cnt[a][b] > 0) { w[a][b] / cnt[a][b] } { 0 };
        };
    };
    (W: w, M: m, n: cnt)
};

~fpOn = { (~fpLive[\on] == true) and: { ~fpCurrent.notNil } };
~fpLaw = { if(~fpOn.value) { ~fpWeights.(~fpCurrent) } };


// ----- live state -----------------------------------------------------
~fpGenerate = { |complexity, links, symmetry, seed|
    var fp;
    complexity = complexity ? ~fpLive[\complexity];
    links = links ? ~fpLive[\links];
    symmetry = symmetry ? ~fpLive[\symmetry];
    fp = ~fpBuild.(complexity, links, symmetry, seed);
    if(fp.isNil) { "fingerprint — укладка не найдена, прежний фингерпринт стоит".warn } {
        ~fpCurrent = fp;
        ~fpLive.putAll((complexity: fp[\complexity], links: fp[\links], symmetry: fp[\symmetry]));
        ~fpChanged.value;
        ("fingerprint · seed " ++ fp[\seed] ++ " · " ++ fp[\counts][\nodes] ++ " nodes · σ "
            ++ fp[\counts][\sigma]).postln;
    };
    fp
};

~fpSet = { |on = true|
    ~fpLive[\on] = on and: { ~fpCurrent.notNil };
    ~fpChanged.value;
    ~fpLive[\on]
};

~fpLoad = { |fp, on = false|
    if(fp.notNil and: { fp.isKindOf(Event).not or: { [\text, \nodes, \edges].any { |k| fp[k].isNil } } }) {
        "fingerprint — повреждённая структура в пресете, пропущена".warn;
    } {
        ~fpCurrent = fp;
        fp !? { ~fpLive.putAll((complexity: fp[\complexity], links: fp[\links], symmetry: fp[\symmetry])) };
        ~fpLive[\on] = (on == true) and: { fp.notNil };
        ~fpChanged.value;
    };
    ~fpCurrent
};


"fingerprint — закон dice (~fpGenerate, ~fpSet, ~fpLaw).".postln;
)
