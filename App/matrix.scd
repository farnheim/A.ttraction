// App/matrix.scd — the two pages of the field, drawn with the ui kit.
// ~openMatrix: every source (row) against every destination (column); a cell
//   is a depth — filled = positive, hollow = negative. click = +0.3 (shift:
//   −0.3), drag up/down = depth, right-click or alt-click = off. Click a
//   row/column label = dice it, right-click = clear it.
// ~openMachines: the base value of every parameter of every machine.


// ===== CONFIG — edit here ============================================
(
~cfg_view = (
    cell:   9,
    labelH: 30,
    headH:  132,
    rowH:   22,
    colW:   292,
    idSeed: 9401
);


// ===== LOGIC =========================================================
~netCloseViews = {
    [~matWin, ~macWin].do { |w| w !? { |x| { try { x.close } }.defer } };
    ~matWin = nil; ~macWin = nil;
};

~netIds = { |n|
    var gen = Routine { loop { 0x10000.rand.yield } }, seen = Set[], ids = Array(n);
    gen.randSeed = ~cfg_view.idSeed;
    while { ids.size < n } {
        var id = gen.next;
        if(seen.includes(id).not) { seen.add(id); ids.add(id.asHexString(4)) };
    };
    ids
};

~netFmt = { |v|
    var a = v.abs;
    ~uiFmt.(v, case { a >= 100 } { 0 } { a >= 10 } { 1 } { a >= 0.1 } { 3 } { 4 })
};



// ----- the matrix page ----------------------------------------------
~netBuildMatrix = {
    var cv = ~cfg_view, pal = ~uiPal, c = cv.cell, lh = cv.labelH, hh = cv.headH;
    var lw = ("0000".bounds(~uiMono.(7, true)).width + 4).ceil;
    var srcs = ~netAllSrc.value, dsts = ~netAllDst.value;
    var srcPos = (), dstPos = ();
    var ids = ~netIds.(srcs.size + dsts.size), srcId = ids.keep(srcs.size), dstId = ids.drop(srcs.size);
    var cw = lw + (dsts.size * c) + 12, ch = lh + (srcs.size * c) + 12;
    var presetW = (~cfg_presets.btnW * 3) + (~cfg_presets.gap * 2);
    var gw = dsts.size * c, gh = srcs.size * c, frameW = lw + gw + 1;
    var headW = (3 * 258) + 58 + 120 + 6 + 64 + 16 + presetW;
    var scr = Window.availableBounds;
    var ww = (frameW.max(headW) + 56).min(scr.width - 40), wh = (ch + hh + 16).min(scr.height - 40);
    var contentW = frameW.max(headW).min(ww - 56), right = 28 + contentW, ox = 28;
    var win, page, scroll, canvas, info, driftBtn, hover, drag, x;
    var tag = { |p| (p[0] ++ "." ++ p[1]).asSymbol };
    var infoFor = { |a, b|
        var d = ~netDepth.(a[0], a[1], b[0], b[1]);
        tag.(a) ++ "  →  " ++ tag.(b) ++ "   " ++ if(d == 0) { "·" } { ~uiFmt.(d, 3) }
    };
    var status = { ~netCells.size.asString ++ " cells" };
    var rowAt = { |mx, my|
        var col = ((mx - lw) / c).floor.asInteger, row = ((my - lh) / c).floor.asInteger;
        [row, col, (row >= 0) and: { row < srcs.size }, (col >= 0) and: { col < dsts.size }]
    };

    srcs.do { |p, i| srcPos[tag.(p)] = i };
    dsts.do { |p, i| dstPos[tag.(p)] = i };

    ~matWin !? { |w| try { w.close } };
    win = Window("NET · matrix", Rect(30, 30, ww, wh)).background_(pal.paper);
    win.acceptsMouseOver = true;
    ~matWin = win;

    ~uiRule.(win, Rect(0, 52, ww, 1)).resize_(2);
    ~uiRule.(win, Rect(0, hh - 1, ww, 1)).resize_(2);
    scroll = ScrollView(win, Rect(0, hh, ww, wh - hh)).hasBorder_(false).background_(pal.paper).resize_(5);
    canvas = UserView(scroll, Rect(0, 0, ox + cw + 28, ch)).background_(pal.paper);
    // the page covers the header only: over the grid it would swallow the mouse
    page = ~uiPage.(win.view, contentW, hh - 1, { |left|
        ox = left;
        canvas.resizeTo(ox + cw + 28, ch);
        canvas.refresh;
    });

    ~uiTitle.(page, Rect(28, 12, 300, 36), "Matrix");
    x = ~uiNav.(page, right, 18, [["deck", { ~openMixer }], ["machines", { ~openMachines }]]);
    info = ~uiText.(page, Rect(x - 536, 22, 520, 16), status.value, nil, pal.grey, false, \right);

    x = 28;
    ~uiBtn.(page, Rect(x, 64, 64, 24), "dice", { ~netDice.value }); x = x + 70;
    ~uiBtn.(page, Rect(x, 64, 74, 24), "mutate", { ~netMutate.value }); x = x + 80;
    ~uiBtn.(page, Rect(x, 64, 68, 24), "shake", { ~netShake.value }); x = x + 74;
    ~uiBtn.(page, Rect(x, 64, 64, 24), "clear", { ~netClear.value }); x = x + 70;
    driftBtn = ~uiBtn.(page, Rect(x, 64, 68, 24), "drift", { |b|
        ~uiBtnSet.(b, ~netDrift.(b[\on].not));
    }, ~netDriftTask.notNil); x = x + 74;
    ~uiBtn.(page, Rect(x, 64, 104, 24), "dice bases", {
        ~netLayers.value.do { |l| ~netDiceBase.(l, 0.35) };
    });

    x = 28;
    [
        ["density", ControlSpec(0.001, 0.5, \exp), ~cfg_net.diceDensity, { |v| ~cfg_net.diceDensity = v }],
        ["depth",   ControlSpec(0.01, 1, \exp),    ~cfg_net.diceDepth,   { |v| ~cfg_net.diceDepth = v }],
        ["wander",  ControlSpec(0, 1),             ~cfg_net.wander,      { |v| ~netWander.(v, nil) }],
        ["wander Hz", ControlSpec(0.01, 400, \exp), ~cfg_net.wanderRate, { |v| ~netWander.(nil, v) }]
    ].do { |row|
        ~uiRulerRow.(page, x, 96, 58, 120, row[0], row[1], row[2], row[3], ~netFmt);
        x = x + 258;
    };

    ~preset.bar(page, right - presetW, 64, \matrix);

    canvas.drawFunc_({ |u|
        var f = ~uiMono.(7), fb = ~uiMono.(7, true);

        Pen.translate(ox, 0);
        hover !? { |h|
            var cy = lh + (h[0] * c) + (c / 2).floor + 0.5, cx = lw + (h[1] * c) + (c / 2).floor + 0.5;
            Pen.strokeColor = pal.grey; Pen.width = 1;
            Pen.line(0 @ cy, (lw + gw) @ cy);
            Pen.line(cx @ 0, cx @ (lh + gh));
            Pen.stroke;
        };

        Pen.fillColor = pal.grey;
        (0, 4 .. dsts.size).do { |i|
            (0, 4 .. srcs.size).do { |j| Pen.addRect(Rect(lw + (i * c), lh + (j * c), 1, 1)) };
        };
        Pen.fill;
        Pen.strokeColor = pal.ink;
        Pen.strokeRect(Rect(lw + 0.5, lh + 0.5, gw, gh));

        srcs.do { |p, i|
            var y = lh + (i * c), on = hover.notNil and: { hover[0] == i };
            ~uiPenText.(srcId[i], 0, y - 1, if(on) { fb } { f }, if(on) { pal.ink } { pal.grey });
        };
        dsts.do { |p, i|
            var xx = lw + (i * c), on = hover.notNil and: { hover[1] == i };
            Pen.use {
                Pen.translate(xx, lh - 4);
                Pen.rotate(-0.5pi);
                Pen.stringAtPoint(dstId[i], 0@0, if(on) { fb } { f }, if(on) { pal.ink } { pal.grey });
            };
        };

        ~netCells.do { |cell|
            var r = srcPos[tag.(cell[\src])], k = dstPos[tag.(cell[\dst])], d = cell[\depth];
            var side, rect;
            if(r.notNil and: { k.notNil }) {
                side = ((c - 2) * (0.35 + (d.abs.sqrt * 0.65))).round.max(2);
                rect = Rect(lw + (k * c) + ((c - side) / 2), lh + (r * c) + ((c - side) / 2), side, side);
                if(d > 0) {
                    Pen.fillColor = pal.ink; Pen.fillRect(rect);
                } {
                    Pen.strokeColor = pal.ink; Pen.width = 1; Pen.strokeRect(rect.insetBy(0.5, 0.5));
                };
            };
        };
    });

    canvas.mouseDownAction_({ |u, mx, my, mod, btn|
        var h, off = (btn == 1) or: { mod.isAlt }, a, b, d0;
        mx = mx - ox;
        h = rowAt.(mx, my);
        case
        { h[2] and: { h[3] } and: { mx >= lw } and: { my >= lh } } {
            a = srcs[h[0]]; b = dsts[h[1]];
            if(off) { ~netSet.(a[0], a[1], b[0], b[1], 0) } {
                d0 = ~netDepth.(a[0], a[1], b[0], b[1]);
                if(d0 == 0) {
                    d0 = if(mod.isShift) { -0.3 } { 0.3 };
                    ~netSet.(a[0], a[1], b[0], b[1], d0);
                };
                drag = ( a: a, b: b, y0: my, d0: d0 );
            };
        }
        { h[2] and: { mx < lw } and: { my >= lh } } {
            a = srcs[h[0]];
            if(off) { ~netClearRow.(a[0], a[1]) } { ~netDiceRow.(a[0], a[1]) };
        }
        { h[3] and: { my < lh } and: { mx >= lw } } {
            b = dsts[h[1]];
            if(off) { ~netClearCol.(b[0], b[1]) } { ~netDiceCol.(b[0], b[1]) };
        };
    });
    canvas.mouseMoveAction_({ |u, mx, my|
        drag !? { |dr|
            ~netSet.(dr[\a][0], dr[\a][1], dr[\b][0], dr[\b][1],
                (dr[\d0] + ((dr[\y0] - my) / 120)).clip(-1, 1));
            info.string_(infoFor.(dr[\a], dr[\b]));
        };
    });
    canvas.mouseUpAction_({ drag = nil });
    canvas.mouseOverAction_({ |u, mx, my|
        var r, h;
        mx = mx - ox;
        r = rowAt.(mx, my);
        h = if(r[2] and: { r[3] } and: { mx >= lw } and: { my >= lh }) { r.keep(2) } { nil };
        if(h != hover) {
            hover = h;
            info.string_(if(h.isNil) { status.value } { infoFor.(srcs[h[0]], dsts[h[1]]) });
            u.refresh;
        };
    });

    ~netViews[\matrix] = {
        {
            if(win.isClosed.not) {
                canvas.refresh;
                ~uiBtnSet.(driftBtn, ~netDriftTask.notNil);
                if(hover.isNil and: { drag.isNil }) { info.string_(status.value) };
            };
        }.defer
    };
    win.onClose_({
        if(~matWin === win) { ~matWin = nil; ~netViews.removeAt(\matrix) };
    });
    { if(win.isClosed.not) { win.front } }.defer(0.3);
};
~openMatrix = { { ~netBuildMatrix.value }.defer };


// ----- the machines page --------------------------------------------
~netBuildMachines = {
    var cv = ~cfg_view, pal = ~uiPal, layers = ~netLayers.value, rowH = cv.rowH, colW = cv.colW;
    var maxN = layers.collect { |l| ~ungSpecOf.(l).params.size }.maxItem ? 1;
    var top = 210, contentW = ((layers.size - 1) * colW) + 264, right = 28 + contentW;
    var cw = contentW + 56, ch = top + (maxN * rowH) + 20;
    var scr = Window.availableBounds;
    var ww = cw.min(scr.width - 40), wh = ch.min(scr.height - 40);
    var win, scroll, view, page, rulers = ();

    ~macWin !? { |w| try { w.close } };
    win = Window("NET · machines", Rect(60, 60, ww, wh)).background_(pal.paper);
    ~macWin = win;
    scroll = ScrollView(win, Rect(0, 0, ww, wh)).hasBorder_(false).background_(pal.paper).resize_(5);
    view = CompositeView(scroll, Rect(0, 0, cw, ch)).background_(pal.paper);
    // the canvas never shrinks below its content (the scroll bars stay) but grows
    // with a larger window, so the rules on it reach the window edge
    // Qt still sends a resize while the window is tearing down, when the scroll
    // view has no inner bounds left
    scroll.onResize_({ |sv|
        var ib = sv.innerBounds;
        if(ib.notNil and: { view.isClosed.not }) { view.resizeTo(ib.width.max(cw), ib.height.max(ch)) };
    });

    ~uiRule.(view, Rect(0, 66, cw, 1)).resize_(2);
    page = ~uiPage.(view, contentW);
    ~uiTitle.(page, Rect(28, 26, 300, 36), "Machines");
    ~uiNav.(page, right, 32, [["deck", { ~openMixer }], ["matrix", { ~openMatrix }]]);

    layers.do { |l, li|
        var x0 = 28 + (li * colW), params = ~ungSpecOf.(l).params;
        rulers[l] = ();
        if(li > 0) { ~uiRule.(page, Rect(x0 - 14, 67, 1, ch - 67)).resize_(4) };
        ~uiGlyph.(page, Rect(x0, 80, ~uiGlyphSize.x, ~uiGlyphSize.y), l);
        ~uiText.(page, Rect(x0 + 24, 79, 200, 20), l.asString, ~uiType.label, pal.ink, true);
        ~uiBtn.(page, Rect(x0, 110, 84, 24), "defaults", { ~netDefaults.(l) });
        ~uiBtn.(page, Rect(x0 + 90, 110, 84, 24), "dice", { ~netDiceBase.(l, 1.0) });
        ~uiBtn.(page, Rect(x0 + 180, 110, 84, 24), "nudge", { ~netDiceBase.(l, 0.2) });
        ~preset.bar(page, x0, 140, l);
        params.do { |p, i|
            rulers[l][p.key] = ~uiRulerRow.(page, x0, top + (i * rowH), 88, 118,
                p.key.asString, p.spec, ~netGet.(l, p.key),
                { |v| ~setParam.(l, p.key, v) }, ~netFmt);
        };
    };

    ~netHooks[\machines] = { |layer, key, v|
        if(win.isClosed.not) {
            (if(layer.isNil) { layers } { [layer] }).do { |l|
                rulers[l] !? { |rs|
                    if(key.isNil or: { layer.isNil }) {
                        rs.keysValuesDo { |k, r| ~uiRulerSet.(r, ~netGet.(l, k)) };
                    } {
                        rs[key] !? { |r| ~uiRulerSet.(r, v) };
                    };
                };
            };
        };
    };
    win.onClose_({
        if(~macWin === win) { ~macWin = nil; ~netHooks.removeAt(\machines) };
    });
    { if(win.isClosed.not) { win.front } }.defer(0.3);
};
~openMachines = { { ~netBuildMachines.value }.defer };

"matrix — ~openMatrix / ~openMachines".postln;
)
