// App/3_matrix.scd — the two pages of the field, drawn with the 0_ui kit.
// ~openMatrix: every source (row) against every destination (column); a cell
//   is a depth — filled = positive, hollow = negative. click = +0.3 (shift:
//   −0.3), drag up/down = depth, right-click or alt-click = off. Click a
//   row/column label = dice it, right-click = clear it.
// ~openMachines: the base value of every parameter of every machine.


// ===== CONFIG — edit here ============================================
(
~cfg_view = (
    cell:   9,
    labelW: 118,
    labelH: 104,
    headH:  176,
    rowH:   22,
    colW:   292
);


// ===== LOGIC =========================================================
~netCloseViews = {
    [~matWin, ~macWin].do { |w| w !? { |x| { try { x.close } }.defer } };
    ~matWin = nil; ~macWin = nil;
};

~netFmt = { |v|
    var a = v.abs;
    ~uiFmt.(v, case { a >= 100 } { 0 } { a >= 10 } { 1 } { a >= 0.1 } { 3 } { 4 })
};

~netPresetItems = { var items = ~listPresets.value; if(items.isEmpty) { ["—"] } { items } };


// ----- the matrix page ----------------------------------------------
~netBuildMatrix = {
    var cv = ~cfg_view, pal = ~uiPal, c = cv.cell, lw = cv.labelW, lh = cv.labelH, hh = cv.headH;
    var srcs = ~netAllSrc.value, dsts = ~netAllDst.value;
    var srcPos = (), dstPos = ();
    var cw = lw + (dsts.size * c) + 12, ch = lh + (srcs.size * c) + 12;
    var scr = Window.availableBounds;
    var ww = (cw + 16).max(1180).min(scr.width - 40), wh = (ch + hh + 16).min(scr.height - 40);
    var win, scroll, canvas, info, presetPop, nameField, driftBtn, hover, drag, x;
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

    ~uiCap.(win, Rect(28, 12, 700, 14), "net · matrix · " ++ srcs.size ++ " sources × "
        ++ dsts.size ++ " destinations · audio rate");
    ~uiTitle.(win, Rect(28, 26, 300, 36), "Matrix");
    info = ~uiText.(win, Rect(ww - 548, 32, 520, 16), status.value, 10.5, pal.ink2, false, \right);
    ~uiRule.(win, Rect(0, 66, ww, 1));

    x = 28;
    ~uiBtn.(win, Rect(x, 78, 64, 26), "dice", { ~netDice.value }); x = x + 72;
    ~uiBtn.(win, Rect(x, 78, 74, 26), "mutate", { ~netMutate.value }); x = x + 82;
    ~uiBtn.(win, Rect(x, 78, 68, 26), "shake", { ~netShake.value }); x = x + 76;
    ~uiBtn.(win, Rect(x, 78, 64, 26), "clear", { ~netClear.value }); x = x + 72;
    driftBtn = ~uiBtn.(win, Rect(x, 78, 68, 26), "drift", { |b|
        ~uiBtnSet.(b, ~netDrift.(b[\on].not));
    }, ~netDriftTask.notNil); x = x + 76;
    ~uiBtn.(win, Rect(x, 78, 104, 26), "dice bases", {
        ~netLayers.value.do { |l| ~netDiceBase.(l, 0.35) };
    }); x = x + 132;
    ~uiBtn.(win, Rect(x, 78, 64, 26), "desk", { ~openMixer !? { |f| f.value } }); x = x + 72;
    ~uiBtn.(win, Rect(x, 78, 92, 26), "machines", { ~openMachines.value });

    x = 28;
    [
        ["density", ControlSpec(0.001, 0.5, \exp), ~cfg_net.diceDensity, { |v| ~cfg_net.diceDensity = v }],
        ["depth",   ControlSpec(0.01, 1, \exp),    ~cfg_net.diceDepth,   { |v| ~cfg_net.diceDepth = v }],
        ["wander",  ControlSpec(0, 1),             ~cfg_net.wander,      { |v| ~netWander.(v, nil) }],
        ["wander Hz", ControlSpec(0.01, 400, \exp), ~cfg_net.wanderRate, { |v| ~netWander.(nil, v) }]
    ].do { |row|
        ~uiRulerRow.(win, x, 112, 70, 120, row[0], row[1], row[2], row[3], ~netFmt);
        x = x + 270;
    };

    ~uiCap.(win, Rect(28, 146, 60, 14), "preset");
    nameField = TextField(win, Rect(84, 142, 170, 24)).string_("").font_(~uiMono.(11))
        .background_(pal.paper).stringColor_(pal.ink);
    ~uiBtn.(win, Rect(262, 142, 64, 24), "save", {
        ~savePreset.(nameField.string);
        ~uiPopupItems.(presetPop, ~netPresetItems.value);
    });
    presetPop = ~uiPopup.(win, Rect(344, 142, 200, 24), ~netPresetItems.value, 0, { });
    ~uiBtn.(win, Rect(552, 142, 64, 24), "load", {
        var items = ~listPresets.value;
        if(presetPop[\index] < items.size) { ~loadPreset.(items[presetPop[\index]]) };
    });
    ~uiRule.(win, Rect(0, hh - 1, ww, 1));

    scroll = ScrollView(win, Rect(0, hh, ww, wh - hh)).hasBorder_(false).background_(pal.paper);
    canvas = UserView(scroll, Rect(0, 0, cw, ch)).background_(pal.paper);

    canvas.drawFunc_({ |u|
        var f = ~uiMono.(7), fb = ~uiMono.(7, true), gw = dsts.size * c, gh = srcs.size * c;
        var prevL;

        hover !? { |h|
            Pen.fillColor = pal.hi;
            Pen.fillRect(Rect(0, lh + (h[0] * c), lw + gw, c));
            Pen.fillRect(Rect(lw + (h[1] * c), 0, c, lh + gh));
        };

        Pen.strokeColor = pal.paper2; Pen.width = 1;
        (0, 4 .. dsts.size).do { |i| Pen.line((lw + (i * c) + 0.5)@lh, (lw + (i * c) + 0.5)@(lh + gh)) };
        (0, 4 .. srcs.size).do { |i| Pen.line(lw@(lh + (i * c) + 0.5), (lw + gw)@(lh + (i * c) + 0.5)) };
        Pen.stroke;
        Pen.strokeColor = pal.ink;
        Pen.strokeRect(Rect(lw + 0.5, lh + 0.5, gw, gh));

        prevL = nil;
        srcs.do { |p, i|
            var y = lh + (i * c), on = hover.notNil and: { hover[0] == i };
            if(p[0] != prevL) {
                Pen.strokeColor = pal.ink; Pen.width = 1;
                Pen.line(0@(y + 0.5), (lw + gw)@(y + 0.5)); Pen.stroke;
                ~uiPenText.((~uiPhi[p[0]] ? "") ++ " " ++ p[0], 2, y + 1, ~uiMono.(8, true), pal.ink);
                prevL = p[0];
            };
            ~uiPenText.(p[1].asString, lw - 4, y - 1, if(on) { fb } { f },
                if(on) { pal.ink } { pal.ink2 }, \right);
        };
        prevL = nil;
        dsts.do { |p, i|
            var xx = lw + (i * c), on = hover.notNil and: { hover[1] == i };
            if(p[0] != prevL) {
                Pen.strokeColor = pal.ink; Pen.width = 1;
                Pen.line((xx + 0.5)@0, (xx + 0.5)@(lh + gh)); Pen.stroke;
                prevL = p[0];
            };
            Pen.use {
                Pen.translate(xx, lh - 4);
                Pen.rotate(-0.5pi);
                Pen.stringAtPoint(p[1].asString, 0@0, if(on) { fb } { f }, if(on) { pal.ink } { pal.ink2 });
            };
        };

        ~netCells.do { |cell|
            var r = srcPos[tag.(cell[\src])], k = dstPos[tag.(cell[\dst])], d = cell[\depth];
            var rect, col;
            if(r.notNil and: { k.notNil }) {
                rect = Rect(lw + (k * c) + 1.5, lh + (r * c) + 1.5, c - 2, c - 2);
                col = pal.ink.copy.alpha_(0.3 + (d.abs.sqrt * 0.7));
                if(d > 0) {
                    Pen.fillColor = col; Pen.fillRect(rect);
                } {
                    Pen.strokeColor = col; Pen.width = 1.2; Pen.strokeRect(rect);
                };
            };
        };
    });

    canvas.mouseDownAction_({ |u, mx, my, mod, btn|
        var h = rowAt.(mx, my), off = (btn == 1) or: { mod.isAlt }, a, b, d0;
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
        var r = rowAt.(mx, my);
        var h = if(r[2] and: { r[3] } and: { mx >= lw } and: { my >= lh }) { r.keep(2) } { nil };
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
    var top = 180, cw = 28 + (layers.size * colW), ch = top + (maxN * rowH) + 20;
    var scr = Window.availableBounds;
    var ww = cw.min(scr.width - 40), wh = ch.min(scr.height - 40);
    var win, scroll, view, rulers = (), names = ();

    ~macWin !? { |w| try { w.close } };
    win = Window("NET · machines", Rect(60, 60, ww, wh)).background_(pal.paper);
    ~macWin = win;
    scroll = ScrollView(win, Rect(0, 0, ww, wh)).hasBorder_(false).background_(pal.paper);
    view = CompositeView(scroll, Rect(0, 0, cw, ch)).background_(pal.paper);

    ~uiTitle.(view, Rect(28, 26, 300, 36), "Machines");
    ~uiRule.(view, Rect(0, 66, cw, 1));

    layers.do { |l, li|
        var x0 = 28 + (li * colW), params = ~ungSpecOf.(l).params;
        rulers[l] = ();
        if(li > 0) { ~uiRule.(view, Rect(x0 - 14, 67, 1, ch - 67)) };
        ~uiText.(view, Rect(x0, 76, 30, 26), ~uiPhi[l] ? "", 18);
        ~uiText.(view, Rect(x0 + 30, 78, 200, 22), l.asString, 14, pal.ink, true);
        ~uiBtn.(view, Rect(x0, 110, 84, 24), "defaults", { ~netDefaults.(l) });
        ~uiBtn.(view, Rect(x0 + 90, 110, 84, 24), "dice", { ~netDiceBase.(l, 1.0) });
        ~uiBtn.(view, Rect(x0 + 180, 110, 84, 24), "nudge", { ~netDiceBase.(l, 0.2) });
        ~uiBtn.(view, Rect(x0, 140, 84, 24), "load…", {
            Dialog.openPanel({ |path| ~loadMachinePreset.(l, path) }, nil, false, ~machinePresetDir.(l));
        });
        ~uiBtn.(view, Rect(x0 + 90, 140, 84, 24), "save…", {
            Dialog.savePanel({ |path|
                ~saveMachinePreset.(l, path);
                names[l].string_(~machinePresetName[l]);
            }, nil, ~machinePresetDir.(l));
        });
        names[l] = ~uiText.(view, Rect(x0 + 180, 144, 84, 16), ~machinePresetName[l] ? "", 9.5, pal.ink2);
        params.do { |p, i|
            rulers[l][p.key] = ~uiRulerRow.(view, x0, top + (i * rowH), 88, 118,
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
                        { names[l].string_(~machinePresetName[l] ? "") }.defer;
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

"3_matrix — ~openMatrix / ~openMachines".postln;
)
