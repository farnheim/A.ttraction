// App/0_grid.scd — UNGRUND · GRID: grid generator per the canon in
// docs/architecture/structure-grid/README.md (rules 1–9). Pure logic.
// API: ~gridGenerate.(complexity, seed) -> ( text:, field:, nodes:, rows:,
//      cols:, seed:, complexity:, counts:, graph: ) or nil on refusal;
//      ~gridRender.(grid) -> the field as a string.
// Alphabet: structure-grid/char.md; load-bearing implementation WHYs:
// docs/features/grid-modulation/reference.md, Implementation notes.

(
// ===== CONFIG — edit here ============================================
// the complexity slider 0..1 interpolates between each pair [a, b]; field fixed
// 16×16 (override 2026-07-18).
~cfg_grid = (
    nodes:      [7, 20],        // glyph count at complexity 0 -> 1
    // the lower bounds are ZERO (rule 9): c = 0 must give one bare trunk
    branchProb: [0.00, 0.90],   // glyph branching probability (rule 4)
    mergeProb:  [0.00, 0.95],   // probability two branches converge into one glyph
    maxOut:     3,              // max outgoing couplings per node
    maxFront:   [1, 5],         // a front wider than 5 will not route — silent culling would bias the draw
    cols:       16,             // field width  (canonical minimum, fixed)
    rows:       16,             // field height (canonical minimum, fixed)
    // the tier step is derived from the graph (rowGap = (rows-2) div (tiers-1),
    // clamped) — a fixed step rejected trunk graphs (Implementation notes)
    rowGapMin:  2,              // rule 3: at least one coupling between tiers
    rowGapMax:  8,              // step ceiling (couplings are not stretched further)
    colGap:     3,              // node step across columns (>= 3: side exits)
    relax:      4,              // layout smoothing passes (shorter couplings)
    rasterTries: 24,            // attempts to route ONE graph; 16x16 needs headroom
    graphTries: 120             // attempts to grow a new graph before refusing
);


// ===== LOGIC — graph, layout, rasterization ==========================
// the canon alphabet (rev. 2026-07-18): transition corners mark a back edge
// (rule 7), crosses mark intersections (rule 8); branch/merge only at a glyph
~gridFillChars = ["░", "▒", "▓", "█", "▄"];
// the glyph IS the layer identity of a node: both readings of the act are
// spelled in it (levels in reading 1, census in reading 2), and the two
// readers live in modules that switch on and off independently — a copy of
// this table in either of them would drift the moment a class leaves §C
~gridLayerOf = Dictionary.newFrom([
    "█", \alpha, "▄", \delta, "▓", \epsilon, "░", \zeta, "▒", \theta
]);
// the ORDER of the five classes is an INDEX BASIS, not a list: the census 5×5
// of 8_koppelfeld and the line derivation of 9_konstruktion number the layers
// with it, and a private copy in either of them would silently transpose the
// table the day a class leaves §C. Both modules load after 0_grid
~gridClassOrder = [\alpha, \delta, \epsilon, \zeta, \theta];
// the GUI's layer glyph is the same alphabet read backwards — derived, never
// typed a second time (0_lib loads before 0_grid, so it lives here)
~uiPhi = ();
~gridLayerOf.keysValuesDo { |ch, l| ~uiPhi[l] = ch };
~gridLineChars = (
    weak: (
        vert: "│", horiz: "─",
        upRight: "└", upLeft: "┘", downRight: "┌", downLeft: "┐"
    ),
    strong: (
        vert: "║", horiz: "═",
        upRight: "╚", upLeft: "╝", downRight: "╔", downLeft: "╗"
    )
);

~gridLerp = { |pair, t| pair[0] + ((pair[1] - pair[0]) * t) };

// (a..b) with a > b counts DOWN in SC and is non-empty — a degenerate segment would draw
~gridSpan = { |a, b| if(a > b) { [] } { (a .. b) } };

~gridMedian = { |vals|
    var s = vals.asArray.sort;
    var m = s.size div: 2;
    if(s.size.odd) { s[m] } { (s[m - 1] + s[m]) / 2 };
};

~gridRender = { |grid|
    grid[\field].collect { |row|
        var s = row.join("");
        var i = s.size - 1;
        while { i >= 0 and: { s[i] == $  } } { i = i - 1 };
        if(i < 0) { "" } { s.copyRange(0, i) };
    }.join("\n");
};

// ----- graph by tiers (stage 1) + coupling strength (stage 2) --------
~gridGrow = { |target, branchProb, mergeProb, maxFront|
    var nodes = List[];
    var edges = List[];
    var mkNode, addEdge, frontier, tier, root;

    mkNode = { |t|
        var n = (tier: t, ins: List[], outs: List[], col: 0, ch: ~gridFillChars.choose);
        nodes.add(n); n;
    };
    addEdge = { |a, b|
        var e = (src: a, dst: b, strong: true, exitSide: \down, entrySide: \up);
        edges.add(e); a.outs.add(e); b.ins.add(e); e;
    };

    root = mkNode.(0);
    frontier = [root];
    tier = 0;

    while { nodes.size < target and: { frontier.size > 0 } } {
        var slots = List[];
        var kids = List[];
        var i = 0;
        var budget = target - nodes.size;
        var room = maxFront;
        var ods = Array.fill(frontier.size, 0);
        // od is drawn at random, slots go in front order: no leftward bias
        (0 .. frontier.size - 1).scramble.do { |ix|
            var n = frontier[ix];
            // total glyph degree <= 4: a cell has exactly four neighbours (rule 4)
            var cap = ~cfg_grid.maxOut.min(4 - n.ins.size).min(budget).min(room);
            // od = 0 on exhaustion is a leaf (rule 5); the root does not branch
            // (rules 2, 6); rrand(2, cap) at cap = 1 would return 2 — branch only
            // when cap >= 2
            var od = if(cap < 1) { 0 } {
                if(n !== root and: { cap >= 2 } and: { branchProb.coin }) {
                    rrand(2, cap)
                } { 1 };
            };
            ods[ix] = od;
            budget = budget - od;
            room = room - od;
        };
        frontier.do { |n, ix| ods[ix].do { slots.add(n) } };
        while { i < slots.size } {
            var kid = mkNode.(tier + 1);
            addEdge.(slots[i], kid);
            if(
                (i + 1 < slots.size)
                and: { slots[i + 1] !== slots[i] }
                and: { mergeProb.coin }
            ) {
                addEdge.(slots[i + 1], kid);
                i = i + 2;
            } {
                i = i + 1;
            };
            kids.add(kid);
        };
        frontier = kids.asArray;
        tier = tier + 1;
    };

    // rule 6: merging takes priority over branching; nodes come in tier order, so
    // the strength of the incoming coupling is already known
    nodes.do { |n|
        var strong = case
            { n.ins.size >= 2 } { true }
            { n.outs.size >= 2 } { false }
            { n.ins.size == 0 } { true }
            { true } { n.ins[0].strong };
        n.outs.do { |e| e.strong = strong };
    };

    ( nodes: nodes.asArray, edges: edges.asArray, tiers: tier + 1 )
};

// ----- layout (stage 3) ----------------------------------------------
// a row is placed at the MEAN desired column (not the field centre) and is NOT
// re-sorted: birth order is the planar embedding of the graph
// (Implementation notes)
~gridPlaceTier = { |arr, desired, cols|
    var lo, hi, shift;
    arr.do { |n, i|
        var c = desired[i];
        if(i > 0) { c = c.max(arr[i - 1].col + ~cfg_grid.colGap) };
        n.col = c;
    };
    shift = (desired.mean - arr.collect { |n| n.col }.mean).round.asInteger;
    arr.do { |n| n.col = n.col + shift };
    lo = arr.first.col;
    if(lo < 1) { arr.do { |n| n.col = n.col + (1 - lo) } };
    hi = arr.last.col;
    if(hi > (cols - 2)) { arr.do { |n| n.col = n.col - (hi - (cols - 2)) } };
    arr;
};

~gridLayout = { |graph, cols|
    var byTier = Array.fill(graph[\tiers], { List[] });
    var top = graph[\tiers] - 1;
    var downSweep, upSweep;
    graph[\nodes].do { |n| byTier[n.tier].add(n) };
    byTier = byTier.collect(_.asArray);
    byTier[0][0].col = (cols / 2).floor.asInteger;

    downSweep = {
        ~gridSpan.(1, top).do { |t|
            byTier[t] = ~gridPlaceTier.(
                byTier[t],
                byTier[t].collect { |n|
                    ~gridMedian.(n.ins.collect { |e| e.src.col }).round.asInteger
                },
                cols
            );
        };
    };
    upSweep = {
        ~gridSpan.(0, top - 1).reverse.do { |t|
            byTier[t] = ~gridPlaceTier.(
                byTier[t],
                byTier[t].collect { |n|
                    if(n.outs.isEmpty) { n.col } {
                        ~gridMedian.(n.outs.collect { |e| e.dst.col }).round.asInteger
                    };
                },
                cols
            );
        };
    };

    downSweep.value;
    ~cfg_grid.relax.do { upSweep.value; downSweep.value };
    byTier;
};

// ----- glyph sides: each coupling takes exactly one neighbour; an incoming one
// never takes \down, an outgoing one never takes \up (direction of growth)
~gridSides = { |graph|
    var ok = true;
    var pick = { |cands, used|
        var side = cands.detect { |s| used[s].isNil };
        if(side.isNil) { ok = false } { used[side] = true };
        side ? \down;
    };
    var order = { |dc, alt|
        var sides = if(dc < 0) { [\left, \right] } { if(dc > 0) { [\right, \left] } { [\left, \right] } };
        sides ++ [alt];
    };
    graph[\nodes].do { |n|
        var used = ();
        var insA  = n.ins.asArray.sort  { |a, b| (a.src.col - n.col).abs < (b.src.col - n.col).abs };
        var outsA = n.outs.asArray.sort { |a, b| (a.dst.col - n.col).abs < (b.dst.col - n.col).abs };
        insA.do { |e, i|
            var dc = e.src.col - n.col;
            var cands = if(i == 0) { [\up] ++ order.(dc, \up) } { order.(dc, \up) };
            e.entrySide = pick.(cands, used);
        };
        outsA.do { |e, i|
            var dc = e.dst.col - n.col;
            var cands = if(i == 0) { [\down] ++ order.(dc, \down) } { order.(dc, \down) };
            e.exitSide = pick.(cands, used);
        };
    };
    ok;
};

// ----- rasterization (stage 4) + checks (stage 5) --------------------
// a failed routing is retried ON THE SAME graph (rasterTries) — culling on
// collision would bias the draw; back edges are best-effort under the ancestor
// law, intersections come on a second lane pass within the rule-9 quota
// (amendment 2026-07-18)
~gridAttempt = { |graph, cols, rows, cx = 0.5|
    var field;
    var ok = true;
    var rowGap, rowOf, cells, place, edgesByReach, routed, pass;
    var nN = graph[\nodes].size;
    var retQuota   = (cx * nN / 4).floor.asInteger;
    var crossQuota = (cx * nN / 3).floor.asInteger;
    var crossCount = 0;
    var rets, ancestorsOf, freeH, retCells, retLanes;
    var isV = { |s| (s == "│") or: { s == "║" } };
    var isH = { |s| (s == "─") or: { s == "═" } };

    // tier step fitted to the graph: a trunk compresses, a shallow one stretches
    // and gets lanes — culling by height would not knock out trunks
    rowGap = if(graph[\tiers] > 1) {
        ((rows - 2) div: (graph[\tiers] - 1)).clip(~cfg_grid.rowGapMin, ~cfg_grid.rowGapMax)
    } { ~cfg_grid.rowGapMax };

    rowOf = { |n| 1 + (n.tier * rowGap) };

    // unreachable under the canonical CONFIG — insures a manual nodes/rows edit
    if(1 + ((graph[\tiers] - 1) * rowGap) > (rows - 1)) { ok = false };

    if(ok) { ~gridLayout.(graph, cols) };
    if(ok) {
        graph[\nodes].do { |n|
            if(n.col < 1 or: { n.col > (cols - 2) }) { ok = false };
        };
    };

    // rule 3: Chebyshev distance between any two glyphs >= 2
    if(ok) {
        graph[\nodes].do { |a, i|
            graph[\nodes].do { |b, j|
                if(i < j) {
                    var d = (rowOf.(a) - rowOf.(b)).abs.max((a.col - b.col).abs);
                    if(d < 2) { ok = false };
                };
            };
        };
    };

    if(ok) { ok = ~gridSides.(graph) };

    // --- back edges (rule 7): chosen AFTER layout and sides; ancestors are
    // ordered lists, not an IdentitySet (seed determinism)
    rets = List[];
    if(ok) {
        graph[\nodes].do { |n|
            n[\sidesUsed] = n.ins.collect { |e| e.entrySide }
                ++ n.outs.collect { |e| e.exitSide };
            n[\retNeed] = 0;
        };
        ancestorsOf = IdentityDictionary[];
        graph[\nodes].do { |n|
            var lst = List[];
            n.ins.do { |e|
                if(lst.detect { |a| a === e.src }.isNil) { lst.add(e.src) };
                ancestorsOf[e.src].do { |a|
                    if(lst.detect { |x| x === a }.isNil) { lst.add(a) };
                };
            };
            ancestorsOf[n] = lst;
        };
        freeH = { |n|
            ([\left, \right].reject { |s| n[\sidesUsed].includes(s) }).size;
        };
        if(retQuota > 0) {
            var cands = List[];
            graph[\nodes].do { |n|
                ancestorsOf[n].do { |a| cands.add([n, a]) };
            };
            cands.asArray.scramble.do { |pair|
                var s = pair[0], d = pair[1];
                if((rets.size < retQuota)
                    and: { s[\retOut] != true } and: { d[\retIn] != true }
                    and: { freeH.(s) > s[\retNeed] } and: { freeH.(d) > d[\retNeed] }
                ) {
                    rets.add((
                        src: s, dst: d,
                        // a back edge inherits the INCOMING strength of src (rule 6)
                        strong: (s.ins.size >= 2)
                            or: { s.ins.size == 0 }
                            or: { s.ins[0].strong }
                    ));
                    s[\retOut] = true; d[\retIn] = true;
                    s[\retNeed] = s[\retNeed] + 1;
                    d[\retNeed] = d[\retNeed] + 1;
                };
            };
        };
    };

    // the two back-edge axes differ in strength (rule 7); a mixed corner marks a
    // change of reading direction
    retCells = { |e, x|
        var src = e[\src], dst = e[\dst];
        var r1 = rowOf.(src), c1 = src.col;
        var r2 = rowOf.(dst), c2 = dst.col;
        var strong = e[\strong];
        var vert  = if(strong) { "║" } { "│" };
        var horiz = if(strong) { "─" } { "═" };
        var bot = if(x > c1) { if(strong) { "╜" } { "╛" } } { if(strong) { "╙" } { "╘" } };
        var top = if(x > c2) { if(strong) { "╖" } { "╕" } } { if(strong) { "╓" } { "╒" } };
        var out = List[];
        ~gridSpan.(c1.min(x) + 1, c1.max(x) - 1).do { |c| out.add([r1, c, horiz]) };
        out.add([r1, x, bot]);
        ~gridSpan.(r2 + 1, r1 - 1).do { |r| out.add([r, x, vert]) };
        out.add([r2, x, top]);
        ~gridSpan.(c2.min(x) + 1, c2.max(x) - 1).do { |c| out.add([r2, c, horiz]) };
        out;
    };

    // column x sets the sides of both ends; x == col is excluded (Implementation notes)
    retLanes = { |e|
        var src = e[\src], dst = e[\dst];
        var out = List[];
        (1 .. cols - 2).do { |x|
            var sSide, dSide;
            if((x != src.col) and: { x != dst.col }) {
                sSide = if(x > src.col) { \right } { \left };
                dSide = if(x > dst.col) { \right } { \left };
                if(
                    src[\sidesUsed].includes(sSide).not
                    and: { src[\retSides].includes(sSide).not }
                    and: { dst[\sidesUsed].includes(dSide).not }
                    and: { dst[\retSides].includes(dSide).not }
                ) {
                    out.add(( x: x, srcSide: sSide, dstSide: dSide ));
                };
            };
        };
        out.asArray.scramble;
    };

    cells = { |e, j|
        var n1 = e.src, n2 = e.dst;
        var r1 = rowOf.(n1), r2 = rowOf.(n2);
        var g = if(e.strong) { ~gridLineChars.strong } { ~gridLineChars.weak };
        var out = List[];
        var x, y;
        case
            { e.exitSide == \left }  { x = n1.col - 1; out.add([r1, x, g.downRight]) }
            { e.exitSide == \right } { x = n1.col + 1; out.add([r1, x, g.downLeft]) }
            { true }                 { x = n1.col };
        case
            { e.entrySide == \left }  { y = n2.col - 1; out.add([r2, y, g.upRight]) }
            { e.entrySide == \right } { y = n2.col + 1; out.add([r2, y, g.upLeft]) }
            { true }                  { y = n2.col };
        if(x == y) {
            ~gridSpan.(r1 + 1, r2 - 1).do { |r| out.add([r, x, g.vert]) };
        } {
            ~gridSpan.(r1 + 1, j - 1).do { |r| out.add([r, x, g.vert]) };
            out.add([j, x, if(y > x) { g.upRight } { g.upLeft }]);
            ~gridSpan.(x.min(y) + 1, x.max(y) - 1).do { |c| out.add([j, c, g.horiz]) };
            out.add([j, y, if(y > x) { g.downLeft } { g.downRight }]);
            ~gridSpan.(j + 1, r2 - 1).do { |r| out.add([r, y, g.vert]) };
        };
        out;
    };

    // rule 8: an intersection is strictly a vertical through a horizontal within
    // quota, the cross follows the axis strengths; allowCross=false is the planar
    // law (and the whole of c=0)
    place = { |list, allowCross = false|
        var need = List[];
        var fine = true;
        var crossFor = { |vSym, hSym|
            if(vSym == "║") { if(hSym == "═") { "╬" } { "╫" } }
            { if(hSym == "═") { "╪" } { "┼" } };
        };
        list.do { |t|
            var cur;
            if(fine) {
                if((t[0] < 0) or: { t[0] >= rows } or: { t[1] < 0 } or: { t[1] >= cols }) {
                    fine = false;
                } {
                    cur = field[t[0]][t[1]];
                    case
                        { cur == " " } { }
                        { allowCross.not } { fine = false }
                        { isV.(t[2]) and: { isH.(cur) } } { need.add([t[0], t[1], crossFor.(t[2], cur)]) }
                        { isH.(t[2]) and: { isV.(cur) } } { need.add([t[0], t[1], crossFor.(cur, t[2])]) }
                        { true } { fine = false };
                };
            };
        };
        if(fine and: { (crossCount + need.size) > crossQuota }) { fine = false };
        if(fine) {
            list.do { |t| if(field[t[0]][t[1]] == " ") { field[t[0]][t[1]] = t[2] } };
            need.do { |t| field[t[0]][t[1]] = t[2] };
            crossCount = crossCount + need.size;
        };
        fine;
    };

    edgesByReach = graph[\edges].sort { |a, b|
        (a.src.col - a.dst.col).abs > (b.src.col - b.dst.col).abs
    };

    pass = {
        var fine = true;
        field = Array.fill(rows, { Array.fill(cols, " ") });
        crossCount = 0;
        // routeLen is valid only from a SUCCESSFUL pass — the reset is mandatory
        graph[\edges].do { |e| e[\routeLen] = nil };
        rets.do { |e| e[\routeLen] = nil; e[\placed] = false };
        graph[\nodes].do { |n| n[\retSides] = List[] };
        graph[\nodes].do { |n| if(place.([[rowOf.(n), n.col, n.ch]]).not) { fine = false } };
        edgesByReach.do { |e|
            if(fine) {
                var lanes = ~gridSpan.(rowOf.(e.src) + 1, rowOf.(e.dst) - 1).scramble;
                var done = false;
                // planar is preferred: the second pass runs only when planar fails
                [false, true].do { |allow|
                    lanes.do { |j|
                        var list;
                        if(done.not) {
                            list = cells.(e, j);
                            done = place.(list, allow);
                            if(done) { e[\routeLen] = list.size };
                        };
                    };
                };
                if(done.not) { fine = false };
            };
        };
        // back edges are best-effort AFTER the skeleton: one that will not fit is dropped
        if(fine) {
            rets.do { |e|
                var lanes = retLanes.(e);
                var done = false;
                [false, true].do { |allow|
                    lanes.do { |lane|
                        var list;
                        if(done.not) {
                            list = retCells.(e, lane[\x]);
                            done = place.(list, allow);
                            if(done) {
                                e[\routeLen] = list.size;
                                e[\placed] = true;
                                e[\src][\retSides].add(lane[\srcSide]);
                                e[\dst][\retSides].add(lane[\dstSide]);
                            };
                        };
                    };
                };
            };
        };
        fine;
    };

    if(ok) {
        var n = 0;
        routed = false;
        while { routed.not and: { n < ~cfg_grid.rasterTries } } {
            n = n + 1;
            routed = pass.value;
        };
        ok = routed;
    };

    if(ok) {
        var idx = IdentityDictionary[];
        var placedRets = rets.select { |e| e[\placed] == true };
        var retInOf = IdentityDictionary[], retOutOf = IdentityDictionary[];
        var transitions = 0, crosses = 0;
        var retCorner = ["╒", "╓", "╘", "╙", "╕", "╖", "╛", "╜"];
        var crossSyms = ["┼", "╬", "╫", "╪"];
        graph[\nodes].do { |n, i| idx[n] = i };
        placedRets.do { |e|
            retOutOf[e[\src]] = (retOutOf[e[\src]] ? 0) + 1;
            retInOf[e[\dst]]  = (retInOf[e[\dst]] ? 0) + 1;
        };
        // counters read the FINISHED FIELD (rule 9); String membership via == (§6)
        field.do { |row| row.do { |s|
            if(retCorner.any { |x| x == s }) { transitions = transitions + 1 };
            if(crossSyms.any { |x| x == s }) { crosses = crosses + 1 };
        } };
        (
            field: field, nodes: graph[\nodes].size, rows: rows, cols: cols,
            counts: (
                branching: graph[\nodes].count { |n| n.outs.size >= 2 },
                transitions: transitions,
                crosses: crosses
            ),
            graph: (
                tiers: graph[\tiers], rowGap: rowGap,
                nodes: graph[\nodes].collect { |n, i|
                    (
                        i: i, tier: n.tier, ch: n.ch,
                        // two kinds of degree: the skeleton (indegS/outdegS) for
                        // reading 1, the full graph for reading 2
                        indegS: n.ins.size, outdegS: n.outs.size,
                        indeg: n.ins.size + (retInOf[n] ? 0),
                        outdeg: n.outs.size + (retOutOf[n] ? 0),
                        // incoming strength ALONG THE SKELETON (rule 6)
                        strongIn: (n.ins.size == 0)
                            or: { n.ins.size >= 2 }
                            or: { n.ins[0].strong }
                    )
                },
                edges: graph[\edges].collect { |e|
                    ( src: idx[e.src], dst: idx[e.dst],
                      strong: e.strong, ret: false, routeLen: e[\routeLen] )
                } ++ placedRets.collect { |e|
                    ( src: idx[e[\src]], dst: idx[e[\dst]],
                      strong: e[\strong], ret: true, routeLen: e[\routeLen] )
                }
            )
        )
    };
};

~gridGenerate = { |complexity = 0.5, seed|
    var t = complexity.clip(0, 1);
    var target = ~gridLerp.(~cfg_grid[\nodes], t).round.asInteger.max(2);
    var bp   = ~gridLerp.(~cfg_grid[\branchProb], t);
    var mp   = ~gridLerp.(~cfg_grid[\mergeProb], t);
    var cols = ~cfg_grid[\cols];
    var rows = ~cfg_grid[\rows];
    var mf = ~gridLerp.(~cfg_grid[\maxFront], t).round.asInteger.max(1);
    var got = nil, n = 0, wasRand;
    // seed BEFORE the retry loop: one deterministic stream => (seed, complexity)
    // reproduces the drawing bit for bit (Konstruktion dsp-spec)
    seed = seed ?? { Date.seed };
    // …and the language stream is BORROWED, not taken: ~kfRandomize calls the
    // generator up to `patchSeedTries` times per patch, and a thread left
    // reseeded would make every later ~rndGroup / preset scramble a function of
    // the last grid seed
    wasRand = thisThread.randData;
    thisThread.randSeed = seed;
    protect {
        while { got.isNil and: { n < ~cfg_grid.graphTries } } {
            n = n + 1;
            got = ~gridAttempt.(~gridGrow.(target, bp, mp, mf), cols, rows, t);
        };
    } { thisThread.randData = wasRand };
    got !? { got[\text] = ~gridRender.(got); got[\seed] = seed; got[\complexity] = t; got };
};

"0_grid — генератор структурных сеток (~gridGenerate / ~gridRender).".postln;
)
