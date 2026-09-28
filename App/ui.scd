// App/ui.scd — UI kit: monochrome paper/ink, hand-drawn buttons, rulers and
// popups (Qt widgets draw in the OS style and ignore the palette). Loads before
// the windows; pure language side.

(
~uiPal = (
    paper:  Color.new255(237, 240, 235),
    ink:    Color.new255(38, 35, 36),
    grey:   Color.new255(161, 161, 159)
);
// type after splav.cc: text 14 · label 14 semibold · title 20 semibold, all × 10/14
~uiType  = ( text: 10, label: 10, title: 14 );
~uiMono  = { |size, bold = false| Font("IBM Plex Mono", size ? ~uiType.text, bold) };
// a machine's glyph: a 30 × 36 pixel card cut into vertical bands, each solid
// or a 1-px checker (lit where x + y is even) — drawn in device-sized pixels at
// any scale, because a scaled checker smears into grey
~uiGlyphs = (
    alpha:   [[0, 30, \solid]],
    delta:   [[0, 24, \solid], [24, 30, \dither]],
    epsilon: [[0, 18, \solid], [18, 24, \dither], [24, 30, \solid]],
    zeta:    [[0, 18, \solid], [18, 30, \dither]],
    theta:   [[0, 24, \dither], [24, 30, \solid]]
);
~uiGlyphSize = 15 @ 18;
~uiGlyphPen = { |x0, y0, h, layer, color|
    var w = (h * 5 / 6).round.asInteger;
    Pen.fillColor = color ? ~uiPal.ink;
    (~uiGlyphs[layer] ? []).do { |band|
        var xa = (band[0] * w / 30).round.asInteger, xb = (band[1] * w / 30).round.asInteger;
        if(band[2] == \solid) { Pen.addRect(Rect(x0 + xa, y0, xb - xa, h)) } {
            h.do { |y| (xa .. xb - 1).do { |x| if((x + y).even) { Pen.addRect(Rect(x0 + x, y0 + y, 1, 1)) } } };
        };
    };
    Pen.fill;
};
~uiGlyph = { |parent, rect, layer|
    UserView(parent, rect).background_(~uiPal.paper).drawFunc_({ |u|
        ~uiGlyphPen.(0, 0, u.bounds.height.min(u.bounds.width * 6 / 5).asInteger, layer)
    })
};

// a box-drawing character as four arms [up, down, left, right], each 0, single
// or double — drawn, not typeset: IBM Plex Mono is not sure to carry them
~uiBoxArms = Dictionary.newFrom([
    "│", [1, 1, 0, 0], "─", [0, 0, 1, 1], "┌", [0, 1, 0, 1], "┐", [0, 1, 1, 0], "└", [1, 0, 0, 1], "┘", [1, 0, 1, 0],
    "║", [2, 2, 0, 0], "═", [0, 0, 2, 2], "╔", [0, 2, 0, 2], "╗", [0, 2, 2, 0], "╚", [2, 0, 0, 2], "╝", [2, 0, 2, 0],
    "╒", [0, 1, 0, 2], "╓", [0, 2, 0, 1], "╕", [0, 1, 2, 0], "╖", [0, 2, 1, 0],
    "╘", [1, 0, 0, 2], "╙", [2, 0, 0, 1], "╛", [1, 0, 2, 0], "╜", [2, 0, 1, 0],
    "┼", [1, 1, 1, 1], "╬", [2, 2, 2, 2], "╪", [1, 1, 2, 2], "╫", [2, 2, 1, 1]
]);
// filled bands, not strokes: a stroke of width 2 straddles the pixel grid.
// In a corner each line of a double arm stops on the edge of the matching
// line of the other arm (outer on outer, inner on inner), so ╔ closes instead
// of crossing itself; straight arms and crosses run through the centre
~uiBoxPen = { |x0, y0, w, h, sym, color, sw = 2, gap = 3|
    var arms = ~uiBoxArms[sym], cx = w div: 2, cy = h div: 2, corner;
    var bands = { |v, c|
        var a = c - ((if(v == 2) { (2 * sw) + gap } { sw }) div: 2);
        if(v == 2) { [[a, a + sw], [a + sw + gap, a + (2 * sw) + gap]] } { [[a, a + sw]] }
    };
    arms !? {
        corner = (arms.count { |v| v > 0 } == 2) and: { (arms[0] + arms[1]) > 0 } and: { (arms[2] + arms[3]) > 0 };
        Pen.fillColor = color ? ~uiPal.ink;
        arms.do { |v, i|
            var vert = i < 2, sa = if(i.even) { -1 } { 1 }, size = if(vert) { h } { w };
            var along = if(vert) { cy } { cx }, across, p, sp, perp;
            if(v > 0) {
                across = bands.(v, if(vert) { cx } { cy });
                if(corner) {
                    p = if(vert) { if(arms[2] > 0) { 2 } { 3 } } { if(arms[0] > 0) { 0 } { 1 } };
                    sp = if(p.even) { -1 } { 1 };
                    perp = bands.(arms[p], along);
                };
                across.do { |ab, k|
                    var inner, line, start, lo, hi;
                    start = if(corner) {
                        inner = (across.size == 2) and: { (k == 1) == (sp > 0) };
                        line = if((sa > 0) == inner) { perp.last } { perp.first };
                        if(sa > 0) { line[0] } { line[1] }
                    } { along };
                    lo = if(sa > 0) { start } { 0 };
                    hi = if(sa > 0) { size } { start };
                    if(vert) { Pen.addRect(Rect(x0 + ab[0], y0 + lo, sw, hi - lo)) }
                        { Pen.addRect(Rect(x0 + lo, y0 + ab[0], hi - lo, sw)) };
                };
            };
        };
        Pen.fill;
    };
};

~uiText = { |parent, rect, string, size, color, bold = false, align = \left|
    StaticText(parent, rect).string_(string).font_(~uiMono.(size, bold))
        .stringColor_(color ? ~uiPal.ink).align_(align);
};
~uiCap   = { |parent, rect, string| ~uiText.(parent, rect, string.toUpper, ~uiType.label, ~uiPal.grey) };
// the mark: an S under a bar, 175 × 272 units (Fill 1.svg)
~uiLogo = [
    [\m, 88.87, 236.15], [\c, 111.14, 236.15, 133.79, 231.54, 133.79, 213.49],
    [\c, 133.79, 196.21, 94.24, 191.99, 64.29, 184.31], [\c, 38.56, 177.78, 5.92, 166.65, 5.92, 134.01],
    [\c, 5.92, 91.39, 41.64, 73.72, 86.56, 73.72], [\c, 124.19, 73.72, 167.97, 89.08, 169.12, 133.62],
    [\l, 125.34, 133.62], [\c, 122.66, 113.66, 106.91, 109.05, 85.03, 109.05],
    [\c, 68.13, 109.05, 48.16, 113.28, 48.16, 127.1], [\c, 48.16, 142.84, 70.82, 143.99, 93.47, 148.98],
    [\c, 128.03, 156.66, 174.88, 165.88, 174.88, 210.04], [\c, 174.88, 258.42, 130.72, 271.48, 88.87, 271.48],
    [\c, 48.16, 271.48, -3.29, 253.81, 0.17, 205.81], [\l, 45.48, 205.81],
    [\c, 45.48, 220.79, 54.69, 236.15, 88.87, 236.15],
    [\m, 8.61, 36.1], [\l, 165.28, 36.1], [\l, 165.28, 0], [\l, 8.61, 0]
];
// the mark stands on the title's baseline, as tall as a machine's glyph.
// Qt centres the line box (ascent 1.025 + descent 0.275 em) in the rect, so the
// baseline sits 0.375 em below its middle (IBM Plex Mono metrics)
~uiTitle = { |parent, rect, string|
    var size = ~uiType.title, markH = ~uiGlyphSize.y, k = markH / 272, w = (175 * k).ceil;
    var base = (rect.height / 2) + (size * 0.375), gap = (size * 0.6).round;
    UserView(parent, Rect(rect.left, rect.top, w + 1, rect.height)).background_(~uiPal.paper).drawFunc_({
        Pen.translate(0, base - markH);
        Pen.scale(k, k);
        ~uiLogo.do { |op|
            switch(op[0],
                \m, { Pen.moveTo(op[1] @ op[2]) },
                \l, { Pen.lineTo(op[1] @ op[2]) },
                \c, { Pen.curveTo(op[5] @ op[6], op[1] @ op[2], op[3] @ op[4]) }
            );
        };
        Pen.fillColor = ~uiPal.ink;
        Pen.fill;
    });
    // Font knows only regular and bold; a style sheet reaches the SemiBold face
    StaticText(parent, Rect(rect.left + w + gap, rect.top, rect.width - w - gap, rect.height))
        .string_(string).stringColor_(~uiPal.ink)
        .setProperty(\styleSheet, "font-family: 'IBM Plex Mono'; font-size: %px; font-weight: 600;".format(size));
};
~uiNav = { |parent, right, y, items|
    var w = 90, gap = 8, x0 = right - (items.size * w) - ((items.size - 1) * gap);
    items.do { |it, i|
        ~uiBtn.(parent, Rect(x0 + (i * (w + gap)), y, w, 24), it[0], { it[1].value !? { |f| f.value } })
            .at(\view).resize_(3);
    };
    x0
};
// a page's content is one column of contentW centred in its host, with a
// margin on both sides; the header's left and right items sit on the column's
// edges (margin, margin + contentW). The host re-centres it when it resizes;
// height nil = the host's height, followed on resize. Qt still sends a resize
// while the window is tearing down, with no bounds left
~uiPage = { |host, contentW, height, onMove, margin = 28|
    var pw = contentW + (margin * 2), page = CompositeView(host, Rect(0, 0, pw, height ? 1));
    var center = {
        var b = host.bounds, x;
        if(b.notNil and: { page.isClosed.not }) {
            x = ((b.width - pw) / 2).max(0).round;
            page.bounds = Rect(x, 0, pw, height ? b.height);
            onMove.value(x + margin);
        };
    };
    host.onResize_(center);
    center.value;
    page
};
~uiRule  = { |parent, rect| UserView(parent, rect).background_(~uiPal.ink) };
// fixed number of decimals (round(0.01).asString drops trailing zeros)
~uiFmt = { |v, d = 2|
    var m = (10 ** d).asInteger, n = (v * m).round.asInteger;
    if(n < 0, "−", "") ++ (n.abs div: m).asString ++ "." ++ (n.abs mod: m).asString.padLeft(d, "0");
};
// a button is a layout frame; Qt Button draws in the OS style (rounded
// gradient) and ignores the palette, so it is drawn by hand. label is a string
// or [off, on]; on = inverted (pressed state OR a permanently inverted primary)
~uiBtn = { |parent, rect, label, action, on = false|
    var labels = if(label.isKindOf(String)) { [label, label] } { label };
    var b = ( on: on, enabled: true, pressed: false, act: action, labels: labels );
    var uv = UserView(parent, rect).background_(~uiPal.paper);
    b[\view] = uv;
    uv.drawFunc_({ |u|
        var w = u.bounds.width, h = u.bounds.height;
        var font = ~uiMono.value, str = b[\labels][if(b[\on]) { 1 } { 0 }];
        var inv  = b[\enabled] and: { b[\on] or: { b[\pressed] } };
        var line = if(b[\enabled]) { ~uiPal.ink } { ~uiPal.grey };
        Pen.fillColor = if(inv) { ~uiPal.ink } { ~uiPal.paper };
        Pen.fillRect(Rect(0, 0, w, h));
        Pen.strokeColor = line; Pen.width = 1;
        Pen.strokeRect(Rect(0.5, 0.5, w - 1, h - 1));
        ~uiPenText.(str, w / 2, (h - str.bounds(font).height) / 2, font,
            if(inv) { ~uiPal.paper } { line }, \middle);
    });
    uv.mouseDownAction_({ if(b[\enabled]) { b[\pressed] = true; uv.refresh } });
    uv.mouseUpAction_({ |u, x, y|
        var hit = (x >= 0) and: { y >= 0 } and: { x <= u.bounds.width } and: { y <= u.bounds.height };
        b[\pressed] = false;
        uv.refresh;
        // only the sync hooks move `on` (~mixerRefreshMute and friends) — the
        // button never toggles it itself, or model and view drift apart
        if(b[\enabled] and: hit) { b[\act].value(b) };
    });
    b;
};
~uiBtnSet    = { |b, on| b !? { b[\on] = on; { b[\view].refresh }.defer } };
~uiBtnEnable = { |b, flag| b !? { b[\enabled] = flag; { b[\view].refresh }.defer } };

// a popup is a layout frame plus its own drop layer; PopUpMenu draws in the OS
// style. The layer lives IN THE SAME window (creation order = stacking order),
// so no second window needs focus; a transparent backdrop catches outside clicks
~uiPopup = { |parent, rect, items, index = 0, action|
    var p = ( items: items, index: index, act: action, enabled: true, hover: -1 );
    var uv = UserView(parent, rect).background_(~uiPal.paper);
    p[\view] = uv;
    p[\parent] = parent;
    uv.drawFunc_({ |u|
        var w = u.bounds.width, h = u.bounds.height, font = ~uiMono.value;
        var str = ((p[\items] ? [])[p[\index]] ? "—").asString;
        var col = if(p[\enabled]) { ~uiPal.ink } { ~uiPal.grey };
        var cy = h / 2;
        Pen.strokeColor = col; Pen.width = 1;
        Pen.strokeRect(Rect(0.5, 0.5, w - 1, h - 1));
        ~uiPenText.(str, 9, cy - (str.bounds(font).height / 2), font, col);
        Pen.fillColor = col;
        Pen.moveTo((w - 17)@(cy - 2.5)); Pen.lineTo((w - 9)@(cy - 2.5));
        Pen.lineTo((w - 13)@(cy + 3)); Pen.fill;
    });
    uv.mouseDownAction_({ if(p[\enabled]) { ~uiPopupOpen.(p) } });
    p;
};
~uiPopupOpen = { |p|
    var rect = p[\view].bounds, items = p[\items] ? [], n = items.size.max(1);
    var rowH = 22, listH = (n * rowH) + 2, font = ~uiMono.value;
    var host = if(p[\parent].isKindOf(Window)) { p[\parent].view } { p[\parent] };
    var top = rect.top + rect.height, scrim, list;
    if(p[\close].notNil) { p[\close].value };
    if(items.isEmpty) { nil } {
        if(top + listH > host.bounds.height) { top = (rect.top - listH).max(0) };
        // the backdrop is slightly opaque: a fully transparent widget gets no click
        scrim = UserView(p[\parent], Rect(0, 0, host.bounds.width, host.bounds.height))
            .background_(Color(0, 0, 0, 0.01));
        list = UserView(p[\parent], Rect(rect.left, top, rect.width, listH))
            .background_(~uiPal.paper);
        p[\close] = { scrim.remove; list.remove; p[\close] = nil; p[\hover] = -1 };
        scrim.mouseDownAction_({ p[\close].value });
        list.drawFunc_({ |u|
            var w = u.bounds.width;
            Pen.strokeColor = ~uiPal.ink; Pen.width = 1;
            Pen.strokeRect(Rect(0.5, 0.5, w - 1, u.bounds.height - 1));
            items.do { |it, i|
                var y = 1 + (i * rowH), sel = (i == p[\index]), hov = (i == p[\hover]);
                if(sel or: hov) {
                    Pen.fillColor = if(sel) { ~uiPal.ink } { ~uiPal.grey };
                    Pen.fillRect(Rect(1, y, w - 2, rowH));
                };
                ~uiPenText.(it.asString, 9, y + ((rowH - it.asString.bounds(font).height) / 2),
                    font, if(sel or: hov) { ~uiPal.paper } { ~uiPal.ink });
            };
        });
        list.mouseMoveAction_({ |u, x, y|
            var h = ((y - 1) / rowH).floor.clip(0, n - 1);
            if(h != p[\hover]) { p[\hover] = h; u.refresh };
        });
        list.mouseUpAction_({ |u, x, y|
            var idx = ((y - 1) / rowH).floor;
            if((idx >= 0) and: { idx < n } and: { x >= 0 } and: { x <= u.bounds.width }) {
                p[\index] = idx;
                p[\close].value;
                p[\view].refresh;
                p[\act].value(idx, p);
            } { p[\close].value };
        });
    };
};
~uiPopupSet    = { |p, idx| p !? { p[\index] = idx; { p[\view].refresh }.defer } };
~uiPopupItems  = { |p, items| p !? { p[\items] = items; p[\index] = p[\index].clip(0, items.size - 1); { p[\view].refresh }.defer } };
~uiPopupEnable = { |p, flag| p !? { p[\enabled] = flag; { p[\view].refresh }.defer } };

// Pen.stringAtPoint places a string by its own ink box rounded to pixels: at
// small sizes a monospaced column wobbles by the first letter. stringInRect
// places it by the font's metrics, the same for every string
~uiPenText = { |str, x, y, font, color, anchor = \left|
    var bw = str.bounds(font).width;
    var ax = switch(anchor, \right, { x - bw }, \middle, { x - (bw / 2) }, { x });
    Pen.stringInRect(str, Rect(ax, y, 4000, 4000), font, color, \topLeft);
};

~uiRuler = { |parent, rect, spec, v0, action|
    var uv = UserView(parent, rect).background_(~uiPal.paper);
    var r = (
        view: uv, spec: spec, norm: spec.unmap(v0 ? spec.default).clip(0, 1),
        act: action, enabled: true, fmt: { |v| ~uiFmt.(v, 3) }
    );
    // r[\spec], never the captured argument: ~uiRulerSet already reads the slot,
    // so a ruler whose spec was swapped (koppelfeld gain strips, whose ceiling is
    // the class of the CURRENT destination) would otherwise act through the spec
    // it was born with while drawing the new one
    var apply = { |px|
        if(r[\enabled]) {
            r[\norm] = ((px - 4) / (uv.bounds.width - 8)).clip(0, 1);
            uv.refresh;
            r[\valTxt] !? { |t| t.string_(r[\fmt].(r[\spec].map(r[\norm]))) };
            r[\act].value(r[\spec].map(r[\norm]));
        };
    };
    uv.drawFunc_({ |u|
        var w = u.bounds.width, y = (u.bounds.height * 0.5).round, x = 4 + (r[\norm] * (w - 8));
        var col = if(r[\enabled]) { ~uiPal.ink } { ~uiPal.grey };
        Pen.width = 1; Pen.strokeColor = col;
        Pen.line(4@y, (w - 4)@y); Pen.stroke;
        Pen.strokeColor = ~uiPal.grey;
        11.do { |i|
            var tx = 4 + (i * (w - 8) / 10);
            Pen.line(tx@(y - if(i % 5 == 0, 6, 3)), tx@y);
        };
        Pen.stroke;
        Pen.strokeColor = col; Pen.width = 2;
        Pen.line(4@y, x@y); Pen.stroke;
        Pen.fillColor = col;
        Pen.moveTo((x - 4.5)@(y + 7)); Pen.lineTo(x@(y + 1)); Pen.lineTo((x + 4.5)@(y + 7));
        Pen.fill;
    });
    uv.mouseDownAction_({ |u, x| apply.(x) });
    uv.mouseMoveAction_({ |u, x| apply.(x) });
    r;
};
~uiRulerRow = { |parent, x, y, labelW, rulerW, label, spec, v0, action, fmt|
    var r, txt;
    fmt = fmt ? { |v| ~uiFmt.(v, 3) };
    if(labelW > 0) { ~uiText.(parent, Rect(x, y, labelW, 20), label, nil, ~uiPal.grey) };
    r = ~uiRuler.(parent, Rect(x + labelW, y, rulerW, 20), spec, v0, action);
    txt = ~uiText.(parent, Rect(x + labelW + rulerW + 6, y, 64, 20), fmt.(v0 ? spec.default));
    r[\valTxt] = txt; r[\fmt] = fmt;
    r;
};
~uiRulerSet = { |r, v|
    r[\norm] = r[\spec].unmap(v).clip(0, 1);
    { r[\view].refresh; r[\valTxt] !? { |t| t.string_(r[\fmt].(v)) } }.defer;
};
~uiRulerEnable = { |r, on| r[\enabled] = on; { r[\view].refresh }.defer };

// space echo: three tape heads (mode masks from effects) + a spring on reverb
~uiDrawEcho = { |u, mode|
    var h1 = [1, 0, 1, 1, 1, 0, 0, 1, 0, 1, 1, 0], h2 = [0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0];
    var h3 = [0, 0, 0, 1, 0, 0, 1, 0, 1, 1, 1, 0], rv = [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1];
    var m = ((mode ? 1) - 1).clip(0, 11), y = u.bounds.height / 2;
    Pen.strokeColor = ~uiPal.ink; Pen.width = 1;
    Pen.line(2@y, 52@y); Pen.stroke;
    [h1, h2, h3].do { |hm, i|
        var r = Rect(6 + (i * 16), y - 7, 9, 14);
        Pen.width = 1.2;
        Pen.fillColor = if(hm[m] == 1) { ~uiPal.ink } { ~uiPal.paper };
        Pen.fillRect(r); Pen.strokeRect(r);
    };
    if(rv[m] == 1) {
        Pen.width = 1.3; Pen.moveTo(55@y);
        [58@(y - 6), 61@(y + 6), 64@(y - 6), 67@(y + 6), 70@(y - 6), 73@y].do { |p| Pen.lineTo(p) };
        Pen.stroke;
    };
};

"ui — ui kit".postln;
)
