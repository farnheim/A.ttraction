// App/ui.scd — UI kit: monochrome paper/ink, hand-drawn buttons, rulers and
// popups (Qt widgets draw in the OS style and ignore the palette). Loads before
// the windows; pure language side.

(
~uiPal = (
    paper:  Color.new255(241, 236, 226),
    paper2: Color.new255(231, 224, 209),
    ink:    Color.new255(27, 25, 21),
    ink2:   Color.new255(91, 86, 77),
    rule:   Color.new255(185, 176, 159),
    hi:     Color.new255(221, 215, 201)
);
~uiMono  = { |size = 11, bold = false| Font("Menlo", size, bold) };
~uiSerif = { |size = 26| Font("Georgia", size) };
// a machine's glyph: one block character per layer, read by every window
~uiPhi = ( alpha: "█", delta: "▄", epsilon: "▓", zeta: "░", theta: "▒" );

~uiText = { |parent, rect, string, size = 11, color, bold = false, align = \left|
    StaticText(parent, rect).string_(string).font_(~uiMono.(size, bold))
        .stringColor_(color ? ~uiPal.ink).align_(align);
};
~uiCap   = { |parent, rect, string| ~uiText.(parent, rect, string.toUpper, 9, ~uiPal.ink2) };
~uiTitle = { |parent, rect, string|
    StaticText(parent, rect).string_(string).font_(~uiSerif.(26)).stringColor_(~uiPal.ink);
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
        var font = ~uiMono.(11), str = b[\labels][if(b[\on]) { 1 } { 0 }];
        var inv  = b[\enabled] and: { b[\on] or: { b[\pressed] } };
        var line = if(b[\enabled]) { ~uiPal.ink } { ~uiPal.rule };
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
        var w = u.bounds.width, h = u.bounds.height, font = ~uiMono.(11);
        var str = ((p[\items] ? [])[p[\index]] ? "—").asString;
        var col = if(p[\enabled]) { ~uiPal.ink } { ~uiPal.rule };
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
    var rowH = 22, listH = (n * rowH) + 2, font = ~uiMono.(11);
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
                    Pen.fillColor = if(sel) { ~uiPal.ink } { ~uiPal.hi };
                    Pen.fillRect(Rect(1, y, w - 2, rowH));
                };
                ~uiPenText.(it.asString, 9, y + ((rowH - it.asString.bounds(font).height) / 2),
                    font, if(sel) { ~uiPal.paper } { ~uiPal.ink });
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

~uiPenText = { |str, x, y, font, color, anchor = \left|
    var bw = str.bounds(font).width;
    var ax = switch(anchor, \right, { x - bw }, \middle, { x - (bw / 2) }, { x });
    Pen.stringAtPoint(str, ax@y, font, color);
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
        var col = if(r[\enabled]) { ~uiPal.ink } { ~uiPal.rule };
        Pen.width = 1; Pen.strokeColor = col;
        Pen.line(4@y, (w - 4)@y); Pen.stroke;
        Pen.strokeColor = ~uiPal.rule;
        11.do { |i|
            var tx = 4 + (i * (w - 8) / 10);
            Pen.line(tx@(y - if(i % 5 == 0, 6, 3)), tx@y);
        };
        Pen.stroke;
        Pen.strokeColor = col; Pen.width = 2.5;
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
    if(labelW > 0) { ~uiText.(parent, Rect(x, y, labelW, 20), label, 10.5, ~uiPal.ink2) };
    r = ~uiRuler.(parent, Rect(x + labelW, y, rulerW, 20), spec, v0, action);
    txt = ~uiText.(parent, Rect(x + labelW + rulerW + 6, y, 64, 20), fmt.(v0 ? spec.default), 10.5);
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
