// App/graph.scd — NET · the graph of the layers on the Matrix field: one vertex
// per active layer, its glyph standing in the grid. A glyph is a wall of the
// geometry (lines.scd): no cell in its rectangle, a line stops at its edge. Its
// cloud is every cell within `radius` of its centre. Three hands per vertex:
// shift the cloud one step along the destinations (x) or the sources (y), and
// its depth, from the cells' own x to the free room of the geometry. After a
// throw a glyph comes to the densest cloud of its layer's cells.
// The graph lives while the fingerprint is the law of chance (fingerprint.scd,
// → dice); without it there are no walls and no clouds: the plain field.
// Pure language: every cell passes through ~netWrite (cells.scd).
// API: ~graphShift.(layer, dx, dy) · ~graphDepth.(layer, k) · ~graphPlace ·
//      ~graphRefresh · ~graphLoad.(state)
// Reference: docs/features/matrix-ru.md, «Граф».

(
// ===== CONFIG — edit here ============================================
~cfg_graph = (
    radius: 16
);


// ===== LOGIC =========================================================
// a vertex: (layer:, row:, col:, depth:) — row/col the glyph's top left cell
~graphLive = ~graphLive ? (on: false, verts: IdentityDictionary.new);

~graphActive = { ~graphLive[\on] == true };
~graphLayers = { ~fpClassOrder.select { |l| ~netLayers.value.includes(l) } };
~graphVerts = { ~graphLayers.value.collect { |l| ~graphLive[\verts][l] }.reject(_.isNil) };

// the glyph's rectangle in cells of the grid, [rows, cols]: the drawn glyph
// must fit in it
~graphSpan = {
    [(~uiGlyphSize.y / ~cfg_view.cell).ceil.asInteger, (~uiGlyphSize.x / ~cfg_view.cell).ceil.asInteger]
};

~graphGrid = {
    var srcs = ~netAllPorts.(\src), dsts = ~netAllPorts.(\dst);
    var rows = IdentityDictionary.new, cols = IdentityDictionary.new;
    srcs.do { |p, i| rows[~netTag.(p)] = i };
    dsts.do { |p, i| cols[~netTag.(p)] = i };
    ( srcs: srcs, dsts: dsts, rows: rows, cols: cols, n: srcs.size, m: dsts.size, span: ~graphSpan.value )
};
~graphAt = { |g, c|
    var r = g[\rows][~netTag.(c[\src])], k = g[\cols][~netTag.(c[\dst])];
    if(r.notNil and: { k.notNil }) { [r, k] }
};

// in doubled coordinates, so the centre of a cell and of a glyph are whole
// numbers and the circle is exact
~graphD2 = { |g, v, r, c|
    var dy = (2 * r) + 1 - (2 * v[\row]) - g[\span][0], dx = (2 * c) + 1 - (2 * v[\col]) - g[\span][1];
    (dy * dy) + (dx * dx)
};
~graphR2 = { 4 * ~cfg_graph.radius.squared };

~graphCloud = { |layer, g|
    var v = ~graphLive[\verts][layer];
    g = g ?? { ~graphGrid.value };
    if(~graphActive.value.not or: { v.isNil }) { [] } {
        ~netCells.values.select { |c|
            ~graphAt.(g, c) !? { |rc| ~graphD2.(g, v, rc[0], rc[1]) <= ~graphR2.value } ? false
        }
    }
};

// a cell in two circles listens to the nearest vertex, a tie to the first
// in ~fpClassOrder
~graphOwner = { |g, verts, rc|
    var best, bestD = ~graphR2.value;
    verts.do { |v|
        var d = ~graphD2.(g, v, rc[0], rc[1]);
        if((d < bestD) or: { best.isNil and: { d == bestD } }) { best = v; bestD = d };
    };
    best
};

~graphOverlap = { |g, a, b|
    (a[0] < (b[0] + g[\span][0])) and: { b[0] < (a[0] + g[\span][0]) }
        and: { a[1] < (b[1] + g[\span][1]) } and: { b[1] < (a[1] + g[\span][1]) }
};

~graphWallsOf = { |g, verts|
    var walls = IdentityDictionary.new;
    verts.do { |v|
        (v[\col] .. v[\col] + g[\span][1] - 1).do { |c|
            g[\dsts][c] !? { |p|
                var k = ~netTag.(p);
                walls[k] = (walls[k] ? []).add([v[\row], v[\row] + g[\span][0] - 1]);
            };
        };
    };
    walls
};
~graphWalls = {
    if(~graphActive.value) { ~graphWallsOf.(~graphGrid.value, ~graphVerts.value) } { IdentityDictionary.new }
};


// ----- where a glyph stands -------------------------------------------
// every cell and every row under a line of the stored depths
~graphBlocked = { |g|
    var b = Array.fill(g[\n], { Array.fill(g[\m], false) }), lr = ~cfg_lines.lineRows;
    ~netCells.do { |c|
        ~graphAt.(g, c) !? { |rc|
            var len = c[\depth].abs * lr, sg = c[\depth].sign.asInteger, k = 1;
            b[rc[0]][rc[1]] = true;
            while { (k - 1) < (len - 1e-9) } {
                var r = rc[0] + (k * sg);
                if((r >= 0) and: { r < g[\n] }) { b[r][rc[1]] = true };
                k = k + 1;
            };
        };
    };
    b
};

~graphFree = { |g, b, r, c|
    var h = g[\span][0], w = g[\span][1];
    (r >= 0) and: { c >= 0 } and: { (r + h) <= g[\n] } and: { (c + w) <= g[\m] } and: {
        (r .. r + h - 1).every { |y| (c .. c + w - 1).every { |x| b[y][x].not } }
    }
};

// the top left corner whose circle holds the most cells of `layer` (a tie:
// the smaller row, then column); nil when the layer has no cell. Each cell
// adds one to the run of corners around it, row by row
~graphPeak = { |g, layer|
    var h = g[\span][0], w = g[\span][1], pr = g[\n] - h + 1, pc = g[\m] - w + 1;
    var q = ~graphR2.value, cnt = Array.fill(pr, { Array.fill(pc + 1, 0) }), any = false, best, bestN = 0;
    ~netCells.do { |c|
        if(c[\src][0] == layer) {
            ~graphAt.(g, c) !? { |rc|
                var lo = (((2 * rc[0]) + 1 - h - q.sqrt) / 2).ceil.asInteger.max(0);
                var hi = (((2 * rc[0]) + 1 - h + q.sqrt) / 2).floor.asInteger.min(pr - 1);
                any = true;
                if(lo <= hi) { (lo .. hi).do { |p|
                    var dy = (2 * rc[0]) + 1 - (2 * p) - h, s2 = q - (dy * dy), s, a, z;
                    if(s2 >= 0) {
                        s = s2.sqrt.floor.asInteger;
                        while { ((s + 1) * (s + 1)) <= s2 } { s = s + 1 };
                        while { (s * s) > s2 } { s = s - 1 };
                        a = (((2 * rc[1]) + 1 - w - s) / 2).ceil.asInteger.max(0);
                        z = (((2 * rc[1]) + 1 - w + s) / 2).floor.asInteger.min(pc - 1);
                        if(a <= z) { cnt[p][a] = cnt[p][a] + 1; cnt[p][z + 1] = cnt[p][z + 1] - 1 };
                    };
                } };
            };
        };
    };
    if(any) {
        cnt.do { |row, p|
            var run = 0;
            pc.do { |x|
                run = run + row[x];
                if(run > bestN) { bestN = run; best = [p, x] };
            };
        };
        best
    }
};

// the free corner nearest to t (a tie: the smaller row, then column), ring by
// ring until no ring can hold a nearer one
~graphNearest = { |g, b, t|
    var best, bestD = inf, k = 0, kmax = g[\n].max(g[\m]);
    var ring = { |k|
        var out = List.new;
        if(k == 0) { out.add(t) } {
            (t[1] - k .. t[1] + k).do { |c| out.add([t[0] - k, c]); out.add([t[0] + k, c]) };
            (t[0] - k + 1 .. t[0] + k - 1).do { |r| out.add([r, t[1] - k]); out.add([r, t[1] + k]) };
        };
        out
    };
    while { (k <= kmax) and: { (k * k) <= bestD } } {
        ring.(k).do { |p|
            var d = (p[0] - t[0]).squared + (p[1] - t[1]).squared;
            var nearer = (d < bestD) or: { (d == bestD) and: { (p[0] < best[0]) or: { (p[0] == best[0]) and: { p[1] < best[1] } } } };
            if(nearer and: { ~graphFree.(g, b, p[0], p[1]) }) { best = p; bestD = d };
        };
        k = k + 1;
    };
    best
};

// a layer without cells keeps its place; the first time it stands in the
// middle of its band of rows and of the field
~graphHome = { |g, layer|
    var band = (0 .. g[\n] - 1).select { |i| g[\srcs][i][0] == layer };
    ~graphLive[\verts][layer] !? { |v| [v[\row], v[\col]] } ?? {
        [
            if(band.isEmpty) { 0 } { ((band.first + band.last + 1 - g[\span][0]) / 2).floor.asInteger },
            ((g[\m] - g[\span][1]) / 2).floor.asInteger
        ]
    }
};

// deterministic: the cells alone decide. A glyph already placed is a wall
// for the next one
~graphPlace = {
    var g, b;
    if(~graphActive.value) {
        g = ~graphGrid.value;
        b = ~graphBlocked.(g);
        ~graphLayers.value.do { |l|
            var t = ~graphPeak.(g, l) ?? { ~graphHome.(g, l) }, at = ~graphNearest.(g, b, t);
            var v = ~graphLive[\verts][l] ?? { (layer: l, depth: 0) };
            at = at ?? { v[\row] !? { [v[\row], v[\col]] } };
            at !? {
                v[\row] = at[0]; v[\col] = at[1];
                ~graphLive[\verts][l] = v;
                (at[0] .. at[0] + g[\span][0] - 1).do { |y|
                    (at[1] .. at[1] + g[\span][1] - 1).do { |x| if((y < g[\n]) and: { x < g[\m] }) { b[y][x] = true } };
                };
            };
        };
    };
};


// ----- the effective depth ----------------------------------------------
// the cells of a cloud reach for the room the geometry leaves them, dealt at
// once per column as ~linesDeal deals a throw: facing lines share the gap,
// every other cell stands at its x. Both layouts are valid and the field's
// bounds are linear in the lengths, so every point between them is too
~graphRefresh = {
    var g, verts, walls, cols, deep = IdentitySet.new, lr = ~cfg_lines.lineRows;
    var put = { |c, eff| if((eff - (c[\eff] ? c[\depth])).abs > 1e-9) { ~netWrite.(c[\src], c[\dst], c[\depth], eff) } };
    if(~graphActive.value.not) {
        ~netCells.values.do { |c| put.(c, c[\depth]) };
    } {
        g = ~graphGrid.value;
        verts = ~graphVerts.value;
        walls = ~graphWallsOf.(g, verts);
        cols = IdentityDictionary.new;
        ~netCells.values.do { |c|
            var rc = ~graphAt.(g, c), own;
            if(rc.isNil) { put.(c, c[\depth]) } {
                own = ~graphOwner.(g, verts, rc);
                cols[rc[1]] = (cols[rc[1]] ? List.new).add(
                    (row: rc[0], len: c[\depth] * lr, fixed: own.isNil, cell: c, k: own !? { own[\depth] }));
                if(own.notNil) { deep.add(rc[1]) };
            };
        };
        cols.keysValuesDo { |ci, list|
            if(deep.includes(ci).not) { list.do { |e| put.(e[\cell], e[\cell][\depth]) } } {
                ~linesDeal.(~linesWall.(list.asArray, walls[~netTag.(g[\dsts][ci])]), g[\n],
                    { |up, down, e| if(e[\len] > 0) { down } { up.neg } }).do { |e|
                    var c = e[\cell], x, mx;
                    if(e[\fixed].not) {
                        x = c[\depth];
                        mx = x.sign * (e[\len] / lr).abs.max(x.abs);
                        put.(c, x + (e[\k] * (mx - x)));
                    } { c !? { put.(c, c[\depth]) } };
                };
            };
        };
    };
};

~graphDepth = { |layer, k|
    ~graphLive[\verts][layer.asSymbol] !? { |v|
        v[\depth] = k.clip(0, 1);
        ~netChanged.value;
        v[\depth]
    }
};


// ----- the shift ------------------------------------------------------
// one step of the cloud and its glyph, whole or not at all; nil when done,
// otherwise why not. The law of the fingerprint is not asked
~graphShiftWhy = { |layer, dx, dy|
    var v = ~graphLive[\verts][layer.asSymbol], g, to, others, cloud, moves, keys, taken, cols, check, lr, why;
    dx = dx.sign.asInteger; dy = dy.sign.asInteger;
    case
    { ~graphActive.value.not or: { v.isNil } } { \off }
    { (dx == 0) and: { dy == 0 } } { nil }
    {
        g = ~graphGrid.value;
        lr = ~cfg_lines.lineRows;
        to = [v[\row] + dy, v[\col] + dx];
        others = ~graphVerts.value.reject { |x| x === v };
        cloud = ~graphCloud.(v[\layer], g);
        keys = IdentitySet.newFrom(cloud.collect { |c| ~netCellKey.(c[\src], c[\dst]) });
        moves = cloud.collect { |c| var rc = ~graphAt.(g, c); [c, rc[0] + dy, rc[1] + dx] };
        taken = { |r, k|
            ~netCells[~netCellKey.(g[\srcs][r], g[\dsts][k])] !? { |c|
                keys.includes(~netCellKey.(c[\src], c[\dst])).not } ? false
        };
        cols = { |walls, only|
            var out = IdentityDictionary.new;
            only.do { |k| out[k] = List.new };
            ~netCells.values.do { |c|
                if(keys.includes(~netCellKey.(c[\src], c[\dst])).not) {
                    ~graphAt.(g, c) !? { |rc| out[rc[1]] !? { |l| l.add((row: rc[0], len: c[\depth] * lr)) } };
                };
            };
            moves.do { |m| out[m[2]] !? { |l| l.add((row: m[1], len: m[0][\depth] * lr)) } };
            out.keys.asArray.select { |k|
                ~linesValid.(~linesWall.(out[k].asArray, walls[~netTag.(g[\dsts][k])]), g[\n]).not
            }
        };
        check = {
            var glyphCols = (to[1] .. to[1] + g[\span][1] - 1);
            var bad = cols.(~graphWallsOf.(g, others ++ [(row: to[0], col: to[1])]),
                IdentitySet.newFrom(moves.collect(_[2]) ++ glyphCols));
            case
            { bad.isEmpty } { nil }
            { bad.every { |k| glyphCols.includes(k) }
                and: { cols.(~graphWallsOf.(g, others), IdentitySet.newFrom(bad)).isEmpty } } { \wall }
            { \geometry }
        };
        case
        { (to[0] < 0) or: { to[1] < 0 } or: { (to[0] + g[\span][0]) > g[\n] } or: { (to[1] + g[\span][1]) > g[\m] } }
            { \frame }
        { others.any { |x| ~graphOverlap.(g, to, [x[\row], x[\col]]) } } { \glyph }
        { moves.any { |m| (m[1] < 0) or: { m[2] < 0 } or: { m[1] >= g[\n] } or: { m[2] >= g[\m] } } } { \frame }
        { moves.any { |m| ~netTag.(g[\srcs][m[1]]) == ~netTag.(g[\dsts][m[2]]) } } { \self }
        { moves.any { |m| (others.collect { |x| [x[\row], x[\col]] } ++ [to]).any { |p|
            (m[1] >= p[0]) and: { m[1] < (p[0] + g[\span][0]) } and: { m[2] >= p[1] } and: { m[2] < (p[1] + g[\span][1]) }
        } } } { \glyph }
        { moves.any { |m| taken.(m[1], m[2]) } } { \taken }
        { (why = check.value).notNil } { why }
        {
            cloud.do { |c| ~netWrite.(c[\src], c[\dst], 0) };
            moves.do { |m| ~netWrite.(g[\srcs][m[1]], g[\dsts][m[2]], m[0][\depth]) };
            v[\row] = to[0]; v[\col] = to[1];
            ~netChanged.value;
            nil
        }
    }
};
~graphShift = { |layer, dx, dy| ~graphShiftWhy.(layer, dx, dy).isNil };


// ----- state ----------------------------------------------------------
~graphState = {
    var e = ();
    ~graphLive[\verts].keysValuesDo { |l, v| e[l] = [v[\row], v[\col], v[\depth]] };
    e
};
// a preset carries its places: the glyphs stand where it put them, no throw
~graphLoad = { |state|
    var g = ~graphGrid.value;
    state.keysValuesDo { |l, a|
        l = l.asSymbol;
        ~graphLive[\verts][l] = (
            layer: l,
            row: a[0].asInteger.clip(0, (g[\n] - g[\span][0]).max(0)),
            col: a[1].asInteger.clip(0, (g[\m] - g[\span][1]).max(0)),
            depth: (a[2] ? 0).clip(0, 1)
        );
    };
};

// the graph follows the fingerprint: on with its law, placed as it comes on
~graphSync = {
    var on = (~fpLive[\on] == true) and: { ~fpCurrent.notNil };
    if(on != ~graphActive.value) {
        ~graphLive[\on] = on;
        if(on) { ~graphPlace.value };
    };
    ~netChanged.value;
};
~fpViews[\graph] = ~graphSync;
~graphSync.value;


"graph — вершины слоёв на поле (~graphShift, ~graphDepth, ~graphPlace).".postln;
)
