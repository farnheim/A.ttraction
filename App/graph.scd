// App/graph.scd — NET graph: layer glyphs as walls on the Matrix field, clouds, depth; docs: docs/features/matrix-ru.md

(
// ===== CONFIG — edit here ============================================
~cfg_graph = (
    radius: 16,
    // [rows, cols] in grid cells: the Matrix draws a glyph of ~uiGlyphSize into it
    span:   [2, 2]
);

// ===== LOGIC =========================================================

// a vertex: (layer:, row:, col:) — the glyph's top left cell, not its centre
~graphLive = ~graphLive ? (on: false, verts: IdentityDictionary.new);

~graphActive = { ~graphLive[\on] == true };
~graphLayers = { ~fpClassOrder.select { |l| ~netLayers.value.includes(l) } };
~graphVerts = { ~graphLayers.value.collect { |l| ~graphLive[\verts][l] }.reject(_.isNil) };

~graphGrid = {
    var srcs = ~netAllPorts.(\src), dsts = ~netAllPorts.(\dst);
    var rows = IdentityDictionary.new, cols = IdentityDictionary.new;
    srcs.do { |p, i| rows[~netTag.(p)] = i };
    dsts.do { |p, i| cols[~netTag.(p)] = i };
    ( srcs: srcs, dsts: dsts, rows: rows, cols: cols, n: srcs.size, m: dsts.size, span: ~cfg_graph.span )
};
~graphAt = { |g, c|
    var r = g[\rows][~netTag.(c[\src])], k = g[\cols][~netTag.(c[\dst])];
    if(r.notNil and: { k.notNil }) { [r, k] }
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
~graphBlocked = { |g|
    var b = Array.fill(g[\n], { Array.fill(g[\m], false) }), lr = ~cfg_lines.lineRows;
    ~netCells.do { |c|
        ~graphAt.(g, c) !? { |rc|
            var sg = c[\depth].sign.asInteger;
            b[rc[0]][rc[1]] = true;
            (1 .. ~linesCover.(c[\depth] * lr)).do { |k|
                var r = rc[0] + (k * sg);
                if((r >= 0) and: { r < g[\n] }) { b[r][rc[1]] = true };
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

// doubled coordinates make cell and glyph centres whole: the circle test is exact (integers < 2^52)
~graphPeak = { |g, layer|
    var h = g[\span][0], w = g[\span][1], pr = g[\n] - h + 1, pc = g[\m] - w + 1;
    var q = 4 * ~cfg_graph.radius.squared, cnt = Array.fill(pr, { Array.fill(pc + 1, 0) }), any = false, best, bestN = 0;
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

~graphHome = { |g, layer|
    var band = (0 .. g[\n] - 1).select { |i| g[\srcs][i][0] == layer };
    ~graphLive[\verts][layer] !? { |v| [v[\row], v[\col]] } ?? {
        [
            if(band.isEmpty) { 0 } { ((band.first + band.last + 1 - g[\span][0]) / 2).floor.asInteger },
            ((g[\m] - g[\span][1]) / 2).floor.asInteger
        ]
    }
};

// deterministic: the cells alone decide; a glyph already placed is a wall for the next one
~graphPlace = {
    var g, b;
    if(~graphActive.value) {
        g = ~graphGrid.value;
        b = ~graphBlocked.(g);
        ~graphLayers.value.do { |l|
            var t = ~graphPeak.(g, l) ?? { ~graphHome.(g, l) }, at = ~graphNearest.(g, b, t);
            var v = ~graphLive[\verts][l] ?? { (layer: l) };
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

// ----- state ----------------------------------------------------------
~graphState = {
    var e = ();
    ~graphLive[\verts].keysValuesDo { |l, v| e[l] = [v[\row], v[\col]] };
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
            col: a[1].asInteger.clip(0, (g[\m] - g[\span][1]).max(0))
        );
    };
};

~graphSync = {
    var on = ~fpOn.value;
    if(on != ~graphActive.value) {
        ~graphLive[\on] = on;
        if(on) { ~graphPlace.value };
    };
    ~netChanged.value;
};
~fpViews[\graph] = ~graphSync;
~graphSync.value;


"graph — вершины слоёв на поле (~graphPlace, ~graphWalls).".postln;
)
