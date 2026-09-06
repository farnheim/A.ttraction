// App/7_viz.scd — UNGRUND · VIZ: one window — timeline of the running act
// (tiers + playhead) and live LFO values (control-bus polling ~10 Hz on
// AppClock). All dependencies are soft/nil-safe; opens even without LFO/sequencer.
// Loaded last by 1_app.scd when enableVizGui. Макет: docs/architecture/app/ui/Timeline.dc.html.


// ===== CONFIG — edit here ============================================
(
~cfg_viz = (
    pollRate: 10,      // LFO poll rate, Hz
    w:        1100,    // window width
    seqH:     220,     // sequencer section height
    lfoRowH:  40       // LFO row height (label line + ruler line)
);


// ===== LOGIC — window + polling ======================================
~vizPollRoutine = ~vizPollRoutine;   // stopped in onClose

// read the current LFO proxy value (async -> callback)
~vizReadLfo = { |lfoKey, action|
    var proxy = Ndef(lfoKey);
    if(proxy.notNil and: { proxy.bus.notNil }) {
        proxy.bus.get({ |v| action.(v) });
    } {
        action.(nil);
    };
};

~vizDrawShape = { |u, shape|
    var w = u.bounds.width, h = u.bounds.height, m = h / 2;
    Pen.strokeColor = ~uiPal.ink; Pen.width = 1.3;
    switch(shape,
        \tri,    { Pen.moveTo(2@(h - 3)); [11@3, 20@(h - 3), 29@3, 37@(h - 3)].do { |p| Pen.lineTo(p) } },
        \noise0, { Pen.moveTo(2@(m + 3)); [9@(m + 3), 9@3, 16@3, 16@(h - 3), 23@(h - 3), 23@(m - 2), 30@(m - 2), 30@(m + 2), 37@(m + 2)].do { |p| Pen.lineTo(p) } },
        \noise,  { Pen.moveTo(2@(m + 1)); Pen.curveTo(13@(m + 1), 6@3, 9@(h - 2)); Pen.curveTo(23@(m + 2), 17@3, 20@(h - 2)); Pen.curveTo(37@(m - 2), 28@(h - 2), 33@3) },
        { Pen.moveTo(2@m); Pen.curveTo(18@m, 7@(m - 12), 13@(m - 12)); Pen.curveTo(34@m, 23@(m + 12), 29@(m + 12)) }
    );
    Pen.stroke;
};

~vizDrawTimeline = { |u|
    var w = u.bounds.width, h = u.bounds.height;
    var tl = ~seqTimeline ? ~cfg_seq.timeline;
    var tMax = (tl.collect { |b| b.t }.maxItem ? 1).max(1);
    var layers = ~mixerLayers ? (~activeLayers ? []), left = 90, top = 22, right = 60;
    var rowH = ((h - top - 30) / layers.size.max(1)).min(30), levels = (), f = ~uiMono.(9.5);
    var xOf = { |t| left + (t / tMax * (w - left - right)) };
    tl.do { |b, i|
        var x = xOf.(b.t), nextT = (i < (tl.size - 1)).if({ tl[i + 1].t }, { tMax });
        var segW = (xOf.(nextT) - x).max(2), cur = (~seqCurrentBlock == i);
        (b[\vols]   ? []).do { |pair| levels[pair[0]] = pair[1] };
        (b[\active] ? []).do { |layer| levels[layer] = 1.0 };
        (b[\gone]   ? []).do { |layer| levels[layer] = nil };
        if(b[\finish] == true) {
            ~uiPenText.("╝", x + 4, top + ((rowH * layers.size) / 2) - 8, ~uiMono.(14), ~uiPal.ink);
            ~uiPenText.("finish", x + 4, top + ((rowH * layers.size) / 2) + 8, f, ~uiPal.ink2);
        } {
            if(cur) {
                Pen.fillColor = ~uiPal.hi;
                Pen.fillRect(Rect(x, top - 6, segW, (rowH * layers.size) + 12));
            };
            Pen.strokeColor = ~uiPal.rule; Pen.width = 0.8;
            Pen.line(x@(top - 6), x@(top + (rowH * layers.size))); Pen.stroke;
            ~uiPenText.(b.t.asString ++ "s", x + 4, 2, f, ~uiPal.ink2);
            layers.do { |layer, k|
                var y = top + (k * rowH), lv = levels[layer];
                Pen.strokeColor = ~uiPal.rule; Pen.width = 0.6;
                Pen.line(x@(y + rowH), (x + segW)@(y + rowH)); Pen.stroke;
                if(lv.notNil) {
                    Pen.fillColor = ~uiPal.ink;
                    if(lv >= 0.75) {
                        Pen.fillRect(Rect(x + 3, y + 5, segW - 6, rowH - 10));
                    } {
                        Pen.fillRect(Rect(x + 3, y + (rowH / 2), segW - 6, (rowH / 2) - 5));
                    };
                };
            };
        };
    };
    layers.do { |layer, k|
        ~uiPenText.((~uiPhi[layer] ? "") ++ " " ++ layer, left - 10, top + (k * rowH) + (rowH / 2) - 7, ~uiMono.(11), ~uiPal.ink, \right);
    };
    // playhead (wall-clock × tempo => units of the t axis)
    if(~seqStartTime.notNil) {
        var elapsed = (Main.elapsedTime - ~seqStartTime) * (~cfg_seq.tempo ? 1);
        var px = xOf.(elapsed.clip(0, tMax));
        Pen.strokeColor = ~uiPal.ink; Pen.width = 1.4;
        Pen.line((px - 1.5)@(top - 10), (px - 1.5)@(top + (rowH * layers.size) + 8)); Pen.stroke;
        Pen.line((px + 1.5)@(top - 10), (px + 1.5)@(top + (rowH * layers.size) + 8)); Pen.stroke;
        ~uiPenText.("▶ " ++ (elapsed / 60).floor.asInteger ++ ":"
            ++ (elapsed - ((elapsed / 60).floor * 60)).floor.asInteger.asString.padLeft(2, "0")
            ++ (~seqCurrentBlock !? { |b| " · block " ++ b } ? ""),
            px, top + (rowH * layers.size) + 12, f, ~uiPal.ink, \middle);
    };
};

~ungBuildViz = {
    var w, seqH, lfoRowH, lines, h, y, seqView, lfoBars, lfoLabels;
    w       = ~cfg_viz.w;
    seqH    = ~cfg_viz.seqH;
    lfoRowH = ~cfg_viz.lfoRowH;
    lines   = (~cfg_lfo.notNil).if({ ~cfg_lfo.lines }, { [] });
    h       = 70 + seqH + 46 + (max(lines.size, 1) * lfoRowH) + 40;

    if(~vizWin.notNil) { ~vizWin.close };
    lfoBars   = ();
    lfoLabels = ();

    ~vizWin = Window("UNGRUND · timeline", Rect(900, 60, w, h)).background_(~uiPal.paper);

    ~uiCap.(~vizWin, Rect(28, 12, 600, 14), "ungrund · 4_sequencer + 7_viz · tiers and live LFO");
    ~uiTitle.(~vizWin, Rect(28, 26, 300, 36), "Timeline");
    ~uiBtn.(~vizWin, Rect(w - 100, 28, 72, 26), "close", { ~vizWin.close });
    ~uiRule.(~vizWin, Rect(0, 66, w, 1));

    // --- section 1: timeline ---------------------------------------------
    if(~cfg_seq.isNil) {
        ~uiText.(~vizWin, Rect(28, 80, w - 56, 22), "sequencer not loaded (enableSequencer = false)", 11, ~uiPal.ink2);
    } {
        ~uiCap.(~vizWin, Rect(28, 78, 600, 14),
            "blocks · " ++ if(~seqTimeline.notNil, "~seqTimeline (act)", "~cfg_seq.timeline (demo)"));
        seqView = UserView(~vizWin, Rect(28, 96, w - 56, seqH)).background_(~uiPal.paper);
        // ~seqTimeline читается В drawFunc (view анимирован): акт виден сразу
        seqView.drawFunc_({ |uv| ~vizDrawTimeline.(uv) });
        seqView.frameRate_(10).animate_(true);
    };

    // --- section 2: LFO -------------------------------------------------
    y = 96 + seqH + 16;
    ~uiRule.(~vizWin, Rect(28, y, w - 56, 1));
    ~uiCap.(~vizWin, Rect(28, y + 10, 300, 14), "lfo · 3_lfo · live values");
    y = y + 30;

    if(~cfg_lfo.isNil) {
        ~uiText.(~vizWin, Rect(28, y, w - 56, 22), "LFO not loaded (enableLfo = false)", 11, ~uiPal.ink2);
    } {
        lines.do { |line, i|
            var ry = y + (i * lfoRowH), lo = line.min, hi = line.max, gl;
            ~uiText.(~vizWin, Rect(28, ry, 260, 18), line.target.asString ++ "." ++ line.param.asString, 10.5);
            gl = UserView(~vizWin, Rect(292, ry, 40, 18)).background_(~uiPal.paper);
            gl.drawFunc_({ |u| ~vizDrawShape.(u, line.shape) });
            ~uiText.(~vizWin, Rect(344, ry, 90, 18), line.rate.asString ++ " Hz", 10.5, ~uiPal.ink2);
            ~uiText.(~vizWin, Rect(440, ry, 200, 18), "[" ++ lo ++ " … " ++ hi ++ "]", 10.5, ~uiPal.ink2);
            lfoBars[i] = ~uiRuler.(~vizWin, Rect(28, ry + 18, 300, 20), ControlSpec(lo, hi), lo, nil);
            ~uiRulerEnable.(lfoBars[i], false);
            lfoLabels[i] = ~uiText.(~vizWin, Rect(336, ry + 18, 80, 20), "—", 10.5);
        };
    };

    // --- LFO value polling on AppClock ----------------------------------
    if(~vizPollRoutine.notNil) { ~vizPollRoutine.stop };
    if(~cfg_lfo.notNil and: { ~lfoKeys.notNil }) {
        ~vizPollRoutine = Routine({
            var dt = 1 / (~cfg_viz.pollRate.max(1));
            loop {
                ~lfoKeys.do { |lfoKey, i|
                    var line = lines[i];
                    if(line.notNil and: { lfoBars[i].notNil }) {
                        ~vizReadLfo.(lfoKey, { |v|
                            if(v.notNil) {
                                ~uiRulerSet.(lfoBars[i], v);
                                { if(lfoLabels[i].notNil) { lfoLabels[i].string_(v.round(0.001).asString) } }.defer;
                            };
                        });
                    };
                };
                dt.wait;
            };
        }).play(AppClock);
    };

    ~vizWin.onClose_({
        if(~vizPollRoutine.notNil) { ~vizPollRoutine.stop; ~vizPollRoutine = nil };
        ~vizWin = nil;
    });
    ~vizWin.front;
};

~openViz  = { { ~ungBuildViz.value }.defer };
~vizClose = {
    if(~vizPollRoutine.notNil) { ~vizPollRoutine.stop; ~vizPollRoutine = nil };
    if(~vizWin.notNil) { { ~vizWin.close }.defer };
};

"7_viz — окно Timeline готово (~openViz / ~vizClose).".postln;
)
