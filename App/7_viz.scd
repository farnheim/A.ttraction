// App/7_viz.scd — UNGRUND · VIZ: one window — sequencer timeline (blocks +
// playhead) and live LFO values (control-bus polling ~10 Hz on AppClock).
// All dependencies are soft/nil-safe; opens even without LFO/sequencer.
// Loaded last by 1_app.scd when enableVizGui.


// ===== CONFIG — edit here ============================================
(
~cfg_viz = (
    pollRate: 10,      // LFO poll rate, Hz
    w:        720,     // window width
    seqH:     150,     // sequencer section height
    lfoRowH:  26       // LFO row height
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

~ungBuildViz = {
    var w, seqH, lfoRowH, lines, total, h, y, seqView, lfoBars, lfoLabels;
    w       = ~cfg_viz.w;
    seqH    = ~cfg_viz.seqH;
    lfoRowH = ~cfg_viz.lfoRowH;
    lines   = (~cfg_lfo.notNil).if({ ~cfg_lfo.lines }, { [] });
    total   = (seqH + 70) + (max(lines.size, 1) * lfoRowH) + 40;
    h       = total;

    if(~vizWin.notNil) { ~vizWin.close };
    lfoBars   = ();
    lfoLabels = ();

    ~vizWin = Window(
        "UNGRUND · viz — секвенсор + LFO (App)",
        Rect(900, 60, w, h)
    ).background_(Color.gray(0.10));

    StaticText(~vizWin, Rect(18, 10, w - 36, 22))
        .string_("визуализация — таймлайн секвенсора (вверху) · значения LFO (внизу)")
        .stringColor_(Color.gray(0.9)).font_(Font("Menlo", 12, true));

    // --- section 1: sequencer timeline ---------------------------------
    StaticText(~vizWin, Rect(18, 38, 300, 16))
        .string_("СЕКВЕНСОР").stringColor_(Color.gray(0.6)).font_(Font("Menlo", 10, true));

    if(~cfg_seq.isNil) {
        StaticText(~vizWin, Rect(18, 60, w - 36, 22))
            .string_("секвенсор не загружен (enableSequencer=false)")
            .stringColor_(Color(0.6, 0.4, 0.4)).font_(Font("Menlo", 11));
    } {
        var x0    = 18, vw = w - 36, vy = 60, vh = seqH;
        seqView = UserView(~vizWin, Rect(x0, vy, vw, vh));
        seqView.background_(Color.gray(0.06));
        seqView.drawFunc_({ |uv|
            var bw = uv.bounds.width, bh = uv.bounds.height;
            // ~seqTimeline читается В drawFunc (view анимирован): акт виден сразу
            var tl    = ~seqTimeline ? ~cfg_seq.timeline;
            var tMax  = (tl.collect { |b| b.t }.maxItem ? 1).max(1);
            tl.do { |b, i|
                var bx     = (b.t / tMax) * bw;
                var nextT  = (i < (tl.size - 1)).if({ tl[i + 1].t }, { tMax });
                var segW   = ((nextT - b.t) / tMax * bw).max(2);
                var active = (b.active ? []).collect(_.asString)
                    ++ (b[\vols] ? []).collect { |p| p[0].asString ++ "×" ++ p[1] };
                var gone   = b.gone ? [];
                var cur    = (~seqCurrentBlock == i);
                Pen.fillColor = cur.if(
                    { Color(0.30, 0.42, 0.20) },
                    { Color.gray(0.16) });
                Pen.fillRect(Rect(bx, 14, segW - 2, bh - 28));
                Pen.stringAtPoint(b.t.asString ++ "s",
                    (bx + 4) @ 2, Font("Menlo", 9), Color.gray(0.7));
                Pen.stringAtPoint(active.join(" "),
                    (bx + 4) @ 18, Font("Menlo", 9), Color(0.7, 0.85, 0.6));
                if(gone.notEmpty) {
                    Pen.stringAtPoint("-" ++ gone.collect(_.asString).join(" "),
                        (bx + 4) @ (bh - 26), Font("Menlo", 9), Color(0.8, 0.5, 0.5));
                };
            };
            // playhead (wall-clock × tempo => units of the t axis)
            if(~seqStartTime.notNil) {
                var elapsed = (Main.elapsedTime - ~seqStartTime)
                    * (~cfg_seq.tempo ? 1);
                var px = (elapsed / tMax).clip(0, 1) * bw;
                Pen.strokeColor = Color(0.9, 0.9, 0.4);
                Pen.width = 2;
                Pen.line(px @ 0, px @ bh); Pen.stroke;
            };
        });
        seqView.animate_(true);
    };

    // --- section 2: LFO -------------------------------------------------
    y = 60 + seqH + 16;
    StaticText(~vizWin, Rect(18, y, 300, 16))
        .string_("LFO — живые значения").stringColor_(Color.gray(0.6))
        .font_(Font("Menlo", 10, true));
    y = y + 22;

    if(~cfg_lfo.isNil) {
        StaticText(~vizWin, Rect(18, y, w - 36, 22))
            .string_("LFO не загружен (enableLfo=false)")
            .stringColor_(Color(0.6, 0.4, 0.4)).font_(Font("Menlo", 11));
    } {
        lines.do { |line, i|
            var ry = y + (i * lfoRowH);
            var lo = line.min, hi = line.max;
            var lbl = line.target.asString ++ "." ++ line.param.asString
                ++ "  " ++ line.shape.asString
                ++ "  " ++ line.rate ++ "Hz  [" ++ lo ++ ".." ++ hi ++ "]";
            StaticText(~vizWin, Rect(18, ry, 360, 22))
                .string_(lbl).stringColor_(Color.gray(0.82)).font_(Font("Menlo", 10));
            // display-only value bar
            lfoBars[i]   = Slider(~vizWin, Rect(384, ry + 4, w - 384 - 70, 14))
                .value_(0).enabled_(false)
                .background_(Color.gray(0.06));
            lfoLabels[i] = StaticText(~vizWin, Rect(w - 78, ry, 60, 22))
                .string_("—").stringColor_(Color.gray(0.7)).font_(Font("Menlo", 10));
        };
    };

    Button(~vizWin, Rect(w - 90, h - 32, 72, 24))
        .states_([["закрыть", Color.gray(0.9), Color(0.4, 0.18, 0.18)]])
        .font_(Font("Menlo", 11))
        .action_({ ~vizWin.close });

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
                                var lo = line.min, hi = line.max;
                                var norm = v.linlin(lo, hi, 0, 1).clip(0, 1);
                                { if(lfoBars[i].notNil) {
                                    lfoBars[i].value_(norm);
                                    lfoLabels[i].string_(v.round(0.001).asString);
                                } }.defer;
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

"7_viz — окно визуализации готово (~openViz / ~vizClose).".postln;
)
