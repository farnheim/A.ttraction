// App/8b_kfwindow.scd — UNGRUND · KOPPELFELD, the Nord window (spec §9).
// Five columns of the 111 nodes (one row per parameter: class, name, value
// scale, f_max), the cables drawn OVER them on the same UserView, an inspector
// for the selected cable and the selected node, and the §9.2 proxy meter that
// feeds the live markers.
// Stage S7. The window OWNS nothing of the field: every edit goes through the
// module-8 writers (~kfGainSet, ~kfPoke, ~kfRelease, ~kfArm/~kfDisarm,
// ~kfRandomize/~kfApply) — a second writer is exactly footgun 7/D99.
// Loads AFTER 8_koppelfeld (needs ~kfNodes/~kfClass/~kfBand) and BEFORE the
// mixer (§10.1): the desk's koppelfeld button binds ~openKoppelfeld at build.
// Spec: plans/active/patchbay-koppelfeld.md (§9, §10.4, A-14).


// ===== CONFIG — edit here ============================================
(
~cfg_kfwin = (
    // 1440, not the §9.1 1668: Window.availableBounds on the score machine is
    // 1440 wide and a Qt window is CLAMPED to it while its widgets are not —
    // an inspector laid out at x 1362 would simply not exist on screen (D111)
    winW:      1440,
    winH:      760,
    colW:      220,    // preferred column width; ~kfWinGeom narrows it to fit
    colPad:    4,      // left inset of a row inside its column …
    gutter:    12,     // … and the lane on its right the cables run in
    rowH:      18,     // §9.1
    headH:     88,     // header block: caption, title, state strip, buttons
    barX:      90,     // value scale, from the row's left inset …
    barW:      76,     // … and its width
    fieldY:    88,
    fieldH:    500,
    margin:    14,     // window margin; the inspector is anchored off the RIGHT
    inspW:     300,
    // §9.2 asks for 6 fps AND A-14 for ≤ 3 % CPU; on a 1440-wide Retina panel
    // the two do not meet. Measured (sclang %CPU, 64 cables, §17 D127): 6 fps
    // 9.71 %, 3 fps 5.30 %, 2 fps 3.46 %, 1 fps ≈ 1.8 %. The cost is the Qt
    // repaint of an 1100×500 view, NOT the drawing: an EMPTY drawFunc at 6 fps
    // measures 7.04 % of the 9.71. The field carries control-domain values whose
    // §5 ceilings run 0.004–30 Hz and whose §D processes are block-slow, so the
    // rate is what gives — raise it here knowingly, it is not free
    fps:       2,      // §9.2 field redraw …
    stripFps:  1,      // … and the state line, which re-validates (D99)
    meterRate: 20,     // §9.2 proxy meter, Hz
    hitPx:     4.0,    // §9.1 click-to-cable distance
    handMax:   0.5     // ±hand the inspector ruler offers (§3.2 is unbounded)
);


// ===== LOGIC — slots, layout, drawing, inspector, lifecycle ==========

// ----- registries (idempotent on file reload) --------------------------
~kfWin        = ~kfWin;          // Window
~kfField      = ~kfField;        // UserView: THE field (rows + cables, §9.2)
~kfStrip      = ~kfStrip;        // UserView: the state line, 1 Hz
~kfRows       = ~kfRows       ? [];   // layout records, one per node
~kfCols       = ~kfCols       ? [];   // ( layer: x: n: ) per column
~kfWinCables  = ~kfWinCables  ? [];   // cable geometry, rebuilt with the rows
~kfColTxt     = ~kfColTxt     ? [];   // StaticText per column header
// A-14: the row LABELS are widgets, not Pen work. 333 Pen.stringAtPoint a frame
// measured 11.75 % of a core at 6 fps — the drawing has to keep the moving
// things (bars, markers, cables) and give the standing ones to Qt once. They are
// created AFTER the field (creation order = stacking order) and carry an OPAQUE
// background, which is what keeps a cable from striking a name through; this is
// NOT the forbidden transparent overlay of §9.2 — nothing here is see-through
~kfRowTxt     = ~kfRowTxt     ? [];   // ( name: fmax: ) StaticTexts per row
~kfRowKeys    = ~kfRowKeys    ? [];   // the row set those labels were built for
~kfWinHiRow   = ~kfWinHiRow;          // index of the row whose label is highlit
~kfInspect    = ~kfInspect    ? ();   // inspector widgets
~kfBtns       = ~kfBtns       ? ();   // header buttons
~kfSel        = ~kfSel        ? ();   // ( cable: <event>, node: [layer, key] )
~kfGuiSync    = ~kfGuiSync;      // deferred inspector refresh; nil = no window
~kfWinStamp   = ~kfWinStamp;     // identity stamp the lazy relayout watches
~kfWinLiveIds = ~kfWinLiveIds;   // the ~kfMeterIds array ~kfWinLiveMap was built from
~kfWinLiveMap = ~kfWinLiveMap ? ();   // node id -> index into ~kfLive
~kfWinOwnsMeter = ~kfWinOwnsMeter ? false;
// Font() allocates: ~uiMono.(9) called per row would build 333 fonts a frame
~kfWinFontRow   = ~uiMono.(9);
~kfWinFontBold  = ~uiMono.(9, true);
~kfWinFontLine  = ~uiMono.(10);

// f_max spans 30 Hz (zeta continuous) down to 1/(2·win_hi) of an `inv` node —
// a fixed two decimals prints the slow end as a flat 0.00, which is the one
// number on the row that decides whether a cable can be routed there at all
~kfWinHzText = { |f|
    case
    { f >= 1 }    { ~uiFmt.(f, 2) }
    { f >= 0.01 } { ~uiFmt.(f, 3) }
    { ~uiFmt.(f, 5) };
};

// hoisted out of the frame: Color:copy allocates, and the window fill is the
// one colour the drawing does not take straight from the palette
~kfWinWinCol = ~uiPal.ink.copy.alpha_(0.18);
~kfWinCurves = [\clip, \fold, \step];
// derived layout: a Qt window is CLAMPED to Window.availableBounds while its
// widgets are not, so every x is measured off the ACCEPTED width — an inspector
// pinned to an absolute 1126 would simply not exist on a narrower screen (D111)
~kfWinGeom = ~kfWinGeom ? ();
~kfWinGeomSet = { |w, nCols|
    var cfg = ~cfg_kfwin;
    var iw = cfg.inspW.min(w * 0.3);
    var ix = w - iw - cfg.margin;
    var fw = ix - (cfg.margin * 2);
    var colW = min(cfg.colW, (fw / nCols.max(1)).floor);
    ~kfWinGeom = ( ix: ix, iw: iw, colW: colW, fieldW: colW * nCols.max(1) );
};
~kfWinPolItems = ["+ direct", "− inverted"];

// ----- helpers ---------------------------------------------------------
~kfWinWins = {
    var wins = ();
    (~kfNodes ? ()).keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        wins[~kfIdOf.(l, k)] = n[\win];
    }};
    wins
};

~kfWinNodeOf = { |lk|
    lk !? { ((~kfNodes ? ())[lk[0].asSymbol] ? ())[lk[1].asSymbol] };
};

// the meter publishes ~kfLive in the order of ~kfMeterIds, and that array is
// REPLACED on every ~kfMeterOn: comparing identity is the whole invalidation
// once a FRAME, not once a row: the map is rebuilt only when the meter replaced
// its id array, and every row then carries its own index into ~kfLive
~kfWinLiveSync = {
    var ids = ~kfMeterIds ? [];
    if(ids !== ~kfWinLiveIds) {
        ~kfWinLiveMap = ();
        ids.do { |lk, i| ~kfWinLiveMap[~kfIdOf.(lk[0], lk[1])] = i };
        ~kfWinLiveIds = ids;
        ~kfRows.do { |r| r[\liveIdx] = ~kfWinLiveMap[r[\id]] };
    };
};

~kfWinLiveOf = { |id|
    var ids = ~kfMeterIds ? [];
    if(ids !== ~kfWinLiveIds) {
        ~kfWinLiveMap = ();
        ids.do { |lk, i| ~kfWinLiveMap[~kfIdOf.(lk[0], lk[1])] = i };
        ~kfWinLiveIds = ids;
    };
    ~kfWinLiveMap[id] !? { |i| (~kfLive ? [])[i] };
};

// distance from a point to a SEGMENT (not to its line): a cable is a segment,
// and the infinite line of a near-vertical cable passes through every row of
// the column above and below it
~kfWinSegDist = { |px, py, ax, ay, bx, by|
    var dx = bx - ax, dy = by - ay, d2 = (dx * dx) + (dy * dy);
    var t = if(d2 < 1e-9) { 0 } { (((px - ax) * dx) + ((py - ay) * dy)) / d2 };
    var qx, qy;
    t = t.clip(0, 1);
    qx = ax + (t * dx); qy = ay + (t * dy);
    (px - qx).hypot(py - qy)
};

// the loop a cable runs in, off the verdict (else the loops the derivation
// wrote into the scheme) — the same source the desk graph reads
~kfWinLoopOf = { |cable|
    var loops = (~kfVerdict !? { |v| v[\loops] })
        ?? { (~kfSchaltung !? { |x| x[\loops] }) ? [] };
    var sid = ~kfIdOf.(cable[\src][0], cable[\src][1]);
    var did = ~kfIdOf.(cable[\dst][0], cable[\dst][1]);
    loops.detect { |lp|
        var ns = (lp[\nodes] ? []).collect(_.asSymbol);
        var i = ns.indexOf(sid);
        i.notNil and: { ns.wrapAt(i + 1) == did };
    };
};

// classes the destination will actually honour: ~kfWireOf forces `clip` on a
// convergence node and `step` on any P node, so offering the others there
// would let the popup claim a curve the graph refuses (D-class silent lie)
~kfWinCurveItems = { |layer, key|
    var n = ~kfWinNodeOf.([layer, key]);
    var cls = ~kfRow.(layer, key) !? { |r| r[0] };
    var allowed = ((~kfClass[cls] ? ())[\curve] ? [\clip]).copy;
    if(n.notNil and: { n[\cables].any { |c| ~kfFoldBands.includes(c[\band] ? \block).not } }) {
        allowed = allowed.reject { |cv| cv == \fold };
    };
    allowed
};
~kfWinCurveLocked = { |layer, key|
    var n = ~kfWinNodeOf.([layer, key]);
    (n.isNil) or: { n[\cables].size >= 2 } or: { (~kfRow.(layer, key) !? { |r| r[0] }) == \P }
};

// ----- the per-node rewire (§9.1 curve popup, delete button) -----------
// EXACTLY the per-node half of ~kfInstall: derive the node fields off the cable
// table, rebuild the fan-out, pull the rest back into the new window through
// the single writer, rebuild the body. A window edit that skipped any of the
// four would leave the registry describing a graph that is not the one playing.
~kfWinRewire = { |layer, key|
    var n = ~kfWinNodeOf.([layer, key]);
    layer = layer.asSymbol; key = key.asSymbol;
    n !? {
        var w = ~kfWireOf.(layer, key);
        n[\win] = w[\win]; n[\winRel] = w[\winRel];
        n[\curve] = w[\curve]; n[\cables] = w[\cables];
        n[\hyst] = w[\hyst]; n[\dwell] = w[\dwell]; n[\cut] = w[\cut];
        ~kfFanOutBuild.value;
        // quiet: ~kfRestApply would rebuild a step body, and the build below
        // does it once anyway
        ~kfRestQuiet = true;
        {
            ~kfRestApply.(layer, key, n[\rest]) !? { |acc|
                ~ungValsSet.(layer, key, n[\spec].map(acc));
            };
        }.protect { ~kfRestQuiet = false };
        ~kfNodeBody.(layer, key);
        // Λ, the excited-loop count and the mode are functions of the edge set
        ~kfVerdictStale = true;
        ~kfGuiRelabel !? (_.value);
        n
    };
};

// the slot of a cable inside its destination — the index the body's controls
// (`g<i>`, `fc<i>`, `s<i>`, `r<i>`) are named after. By IDENTITY, as ~kfGainSet
// does: ~kfInstall replaces the whole table and an index would outlive its cable
~kfWinSlotOf = { |cable|
    var n = ~kfWinNodeOf.(cable[\dst]);
    n !? { n[\cables].detectIndex { |c| c === cable } };
};

// ----- layout ----------------------------------------------------------
// pure data: ~kfRows / ~kfCols / ~kfWinCables. Called from the field's own
// drawFunc when the identity stamp breaks, so every widget touch it owes is
// deferred out of the paint
~kfWinRelayout = {
    var cfg = ~cfg_kfwin;
    var order = (~kfLayerOrder ? [\alpha, \delta, \epsilon, \zeta, \theta])
        .select { |l| ((~kfNodes ? ())[l] ? ()).notEmpty };
    var wins = ~kfWinWins.value;
    var rowOf = ();
    var loops = (~kfVerdict !? { |v| v[\loops] })
        ?? { (~kfSchaltung !? { |x| x[\loops] }) ? [] };
    var inLoop = ();
    var rows = [], cols = [], geo = [];
    loops.do { |lp|
        var ns = (lp[\nodes] ? []).collect(_.asSymbol);
        ns.do { |a, i| inLoop[(a.asString ++ ">" ++ ns.wrapAt(i + 1)).asSymbol] = true };
    };
    order.do { |layer, ci|
        var reg = ~kfNodes[layer];
        var colW = (~kfWinGeom[\colW] ? cfg.colW);
        var x = ci * colW;
        // the layer's OWN declaration order, never the registry's hash order:
        // the tuner and both logs number the parameters this way, and a column
        // that renumbered itself between sessions would make a screenshot lie
        var keys = ((~ungSpecs[layer] !? { |sp| sp.params.collect { |p| p[\key] } }) ? [])
            .select { |k| reg[k].notNil };
        cols = cols.add(( layer: layer, x: x, n: keys.size ));
        keys.do { |k, ri|
            var y = 8 + (ri * cfg.rowH);
            var row = (
                layer: layer, key: k, id: ~kfIdOf.(layer, k), col: ci,
                cls: (~kfRow.(layer, k) !? { |r| r[0] }) ? $?,
                x: x + cfg.colPad, y: y, cy: y + (cfg.rowH * 0.5),
                barX: x + cfg.colPad + cfg.barX,
                // three anchors: where the row's TEXT ends, the lane the cables
                // travel in, and the left edge an arriving cable lands on
                edge: x + colW - cfg.gutter - 2,
                lane: x + colW - 4,
                left: x + 2,
                width: colW - cfg.gutter
            );
            var fmax = ~kfFmaxOf.(layer, k, wins);
            // the node event and the step table are cached INTO the row: both
            // change only with the stamp, and ~kfNodePos rebuilds the 94 Hz
            // lattice on every call — six of those a second for nothing
            row[\node] = reg[k];
            row[\pos] = if(reg[k][\curve] == \step) { ~kfWinPos.(layer, k, reg[k][\win]) } { nil };
            row[\fmaxStr] = fmax !? { |f| ~kfWinHzText.(f) } ? "";
            // the right-aligned x is measured ONCE here: ~uiPenText asks the
            // font for the string bounds, and 111 of those a frame is the most
            // expensive thing the drawing could do (A-14)
            // both labels are cut to the WIDTH OF THEIR TEXT, never to the
            // cell: an opaque cell would blank the row from edge to edge and
            // chop every cable crossing the column into 2 px stubs
            row[\label] = row[\cls].asString ++ " " ++ k;
            row[\labelW] = row[\label].bounds(~kfWinFontRow).width + 6;
            row[\fmaxW] = row[\fmaxStr].bounds(~kfWinFontRow).width + 6;
            row[\fmaxX] = row[\edge] - row[\fmaxW] + 3;
            rows = rows.add(row);
            rowOf[row[\id]] = row;
        };
    };
    (~kfCables ? []).do { |c|
        if(c[\enabled] != false) {
            var a = rowOf[~kfIdOf.(c[\src][0], c[\src][1])];
            var b = rowOf[~kfIdOf.(c[\dst][0], c[\dst][1])];
            if(a.notNil and: { b.notNil }) {
                var e = ( cable: c, intra: (a[\col] == b[\col]),
                    loop: inLoop[(a[\id].asString ++ ">" ++ b[\id]).asSymbol] == true );
                if(e[\intra]) {
                    e[\ax] = a[\edge]; e[\ay] = a[\cy];
                    e[\bx] = b[\edge]; e[\by] = b[\cy];
                    e[\mx] = a[\lane]; e[\my] = (a[\cy] + b[\cy]) * 0.5;
                } {
                    // a cable running LEFTWARDS leaves by the left edge and
                    // arrives at the right one: forced out of the same lane it
                    // would double back over its own column
                    if(b[\col] > a[\col]) {
                        e[\ax] = a[\lane]; e[\bx] = b[\left];
                    } {
                        e[\ax] = a[\left]; e[\bx] = b[\lane];
                    };
                    e[\ay] = a[\cy]; e[\by] = b[\cy];
                    e[\mx] = (e[\ax] + e[\bx]) * 0.5; e[\my] = (e[\ay] + e[\by]) * 0.5;
                };
                geo = geo.add(e);
            };
        };
    };
    ~kfRows = rows; ~kfCols = cols; ~kfWinCables = geo;
    ~kfWinStamp = ~kfWinStampNow.value;
    ~kfWinLiveIds = nil;
    // a selection whose cable left the table is not a selection any more
    if((~kfSel[\cable]).notNil
        and: { geo.any { |e| e[\cable] === ~kfSel[\cable] }.not }) {
        ~kfSel[\cable] = nil;
    };
    {
        ~kfColTxt.do { |t, i|
            var c = cols[i];
            t.string_(if(c.isNil) { "" } {
                (~uiPhi[c[\layer]] ? "") ++ " " ++ c[\layer] ++ " · " ++ c[\n]
            });
        };
        ~kfWinBuildLabels.value;
        ~kfGuiSync !? (_.value);
    }.defer;
    rows.size
};

// The labels are rebuilt only when the ROW SET changes (a layer hot-swap with a
// different parameter list); a mere scheme change moves no row, so it only
// refreshes the f_max column — which does move, an `inv` node reads its ceiling
// off the window of its rate node (§5)
~kfWinBuildLabels = {
    var cfg = ~cfg_kfwin;
    var keys = ~kfRows.collect { |r| r[\id] };
    var win = ~kfWin;
    if(win.notNil) {
        if(keys != ~kfRowKeys) {
            ~kfRowTxt.do { |t| t[\name].remove; t[\fmax].remove };
            ~kfRowTxt = ~kfRows.collect { |r|
                var x = cfg.margin + r[\x], y = cfg.fieldY + r[\y];
                var pick = { ~kfWinSelectRow.(r[\layer], r[\key]) };
                (
                    name: ~uiText.(win,
                        Rect(x - 3, y + 1, r[\labelW].min(r[\barX] - r[\x] - 1), cfg.rowH - 2),
                        r[\label], 9, ~uiPal.ink)
                        .background_(~uiPal.paper).mouseDownAction_(pick),
                    fmax: ~uiText.(win,
                        Rect(cfg.margin + r[\fmaxX] - 3, y + 1, r[\fmaxW], cfg.rowH - 2),
                        r[\fmaxStr], 9, ~uiPal.rule)
                        .background_(~uiPal.paper).mouseDownAction_(pick)
                );
            };
            ~kfRowKeys = keys;
            ~kfWinHiRow = nil;
        } {
            ~kfRowTxt.do { |t, i|
                var r = ~kfRows[i];
                t[\fmax].string_(r[\fmaxStr]);
                t[\fmax].bounds_(Rect(cfg.margin + r[\fmaxX] - 3,
                    cfg.fieldY + r[\y] + 1, r[\fmaxW], cfg.rowH - 2));
            };
        };
        // a destination is named in ink, a node no cable lands on in ink2: the
        // one fact of the row that a glance must give before any number
        ~kfRowTxt.do { |t, i|
            var n = ~kfWinNodeOf.([~kfRows[i][\layer], ~kfRows[i][\key]]);
            t[\name].stringColor_(
                if((n !? { |x| x[\cables].notEmpty }) == true) { ~uiPal.ink } { ~uiPal.ink2 });
        };
    };
};

// what the layout is a function of: the cable table (~kfInstall replaces the
// array), how many of its cables are live (delete only flips a flag IN the
// array), and the per-layer registries (~kfRebind replaces one wholesale)
~kfWinStampNow = {
    [~kfCables, (~kfCables ? []).count { |c| c[\enabled] != false }]
        ++ (~kfLayerOrder ? []).collect { |l| (~kfNodes ? ())[l] }
};
~kfWinStampOk = {
    var now = ~kfWinStampNow.value, was = ~kfWinStamp;
    was.notNil and: { was.size == now.size }
        and: { now.every { |x, i| if(x.isNumber) { x == was[i] } { x === was[i] } } };
};

// ----- the field: 111 rows and the cables over them (§9.1/§9.2) --------
~kfWinDrawCable = { |e, sel|
    var pal = ~uiPal, c = e[\cable];
    var offs, fromX, fromY, dx, dy, d, ux, uy;
    if(sel) {
        Pen.use {
            Pen.strokeColor = pal.rule; Pen.width = 4;
            if(e[\intra]) {
                Pen.moveTo(e[\ax]@e[\ay]); Pen.lineTo(e[\mx]@e[\ay]);
                Pen.lineTo(e[\mx]@e[\by]); Pen.lineTo(e[\bx]@e[\by]);
            } {
                Pen.line(e[\ax]@e[\ay], e[\bx]@e[\by]);
            };
            Pen.stroke;
        };
    };
    Pen.use {
        Pen.strokeColor = pal.ink; Pen.width = ~uiLineWidth;
        Pen.lineDash = ~uiLineDash.((c[\gain] ? 0) / 4, c[\curve] ? \clip);
        if(e[\intra]) {
            // an intra-layer cable is a bracket in its own lane (§9.1) — a
            // straight line would be a zero-length stub inside one column
            offs = if(e[\loop]) { [1.6, -1.6] } { [0] };
            offs.do { |o|
                Pen.moveTo(e[\ax]@(e[\ay] + o)); Pen.lineTo((e[\mx] + o)@(e[\ay] + o));
                Pen.lineTo((e[\mx] + o)@(e[\by] + o)); Pen.lineTo(e[\bx]@(e[\by] + o));
                Pen.stroke;
            };
        } {
            // double line = the cable closes a cycle (precedent ~mixerDrawGraph):
            // the Λ of §4.4 is read on THESE
            offs = if(e[\loop]) { [2, -2] } { [0] };
            offs.do { |o|
                Pen.line((e[\ax] + o)@e[\ay], (e[\bx] + o)@e[\by]); Pen.stroke;
            };
        };
    };
    Pen.use {
        // the head follows the LAST leg of the path: for a bracket that is the
        // horizontal run back into the column, not the diagonal
        fromX = if(e[\intra]) { e[\mx] } { e[\ax] };
        fromY = if(e[\intra]) { e[\by] } { e[\ay] };
        dx = e[\bx] - fromX; dy = e[\by] - fromY;
        d = dx.hypot(dy).max(1); ux = dx / d; uy = dy / d;
        Pen.fillColor = pal.ink;
        Pen.moveTo(e[\bx]@e[\by]);
        Pen.lineTo((e[\bx] - (ux * 7) + (uy * 2.6))@(e[\by] - (uy * 7) - (ux * 2.6)));
        Pen.lineTo((e[\bx] - (ux * 7) - (uy * 2.6))@(e[\by] - (uy * 7) + (ux * 2.6)));
        Pen.fill;
    };
    // an inversion is a dot on the middle of its cable (§9.1)
    if((c[\pol] ? 1) < 0) {
        Pen.use {
            Pen.fillColor = pal.paper; Pen.strokeColor = pal.ink; Pen.width = 1;
            Pen.addArc((e[\mx])@(e[\my]), 3, 0, 2pi); Pen.fillStroke;
        };
    };
};

// Draw order is the whole readability of the panel: cables UNDER the rows, so
// 56 diagonals cannot bury the 111 names, and the SELECTED cable once more on
// top, so the one the inspector is talking about is never the one hidden.
// A-14 lives in this function. The cost of a frame is NOT the number of shapes
// but the number of Pen STATE CHANGES and stroke flushes: one pass per colour,
// one flush per stroke colour, instead of six state changes and two flushes on
// each of 111 rows (measured 10.5 % of a core down to the number in §17).
~kfWinDrawField = { |u|
    var cfg = ~cfg_kfwin, pal = ~uiPal, rows = ~kfRows;
    var barW = cfg.barW, rowH = cfg.rowH, live = ~kfLive ? [];
    var selC = ~kfSel[\cable], selN = ~kfSel[\node], selE = nil, hiRow = nil;
    if(~kfWinStampOk.value.not) { ~kfWinRelayout.value; rows = ~kfRows };
    ~kfWinLiveSync.value;
    Pen.fillColor = pal.paper; Pen.fillRect(Rect(0, 0, u.bounds.width, u.bounds.height));
    Pen.strokeColor = pal.rule; Pen.width = 1;
    ~kfCols.do { |c, i| if(i > 0) { Pen.line((c[\x] - 0.5)@0, (c[\x] - 0.5)@u.bounds.height) } };
    Pen.stroke;
    ~kfWinCables.do { |e|
        if(e[\cable] === selC) { selE = e } { ~kfWinDrawCable.(e, false) };
    };
    // the bar band paints its own ground: a cable crossing it would otherwise be
    // taken for a marker. The label widgets do the same for the names
    Pen.fillColor = pal.paper;
    rows.do { |r|
        if(selN.notNil and: { selN[0] == r[\layer] } and: { selN[1] == r[\key] }) {
            hiRow = r;
        } {
            Pen.fillRect(Rect(r[\barX] - 3, r[\y] + 1, barW + 6, rowH - 2));
        };
    };
    hiRow !? { |r|
        Pen.fillColor = pal.hi;
        Pen.fillRect(Rect(r[\barX] - 3, r[\y] + 1, barW + 6, rowH - 2));
    };
    // the window is drawn ONLY on a destination: a node with no cables has
    // [0, 1] for a window, and filling that would mark all 111 rows
    Pen.fillColor = ~kfWinWinCol;
    rows.do { |r|
        var n = r[\node];
        if(n.notNil and: { n[\cables].notEmpty }) {
            Pen.fillRect(Rect(r[\barX] + (n[\win][0] * barW), r[\cy] - 5,
                (n[\win][1] - n[\win][0]) * barW, 10));
        };
    };
    Pen.strokeColor = pal.rule; Pen.width = 1;
    rows.do { |r| Pen.line(r[\barX]@r[\cy], (r[\barX] + barW)@r[\cy]) };
    Pen.stroke;
    Pen.strokeColor = pal.ink2; Pen.width = 1;
    rows.do { |r|
        var n = r[\node], x;
        if(n.notNil) {
            x = r[\barX] + (n[\rest] * barW);
            Pen.line(x@(r[\cy] - 5), x@(r[\cy] + 5));
            (r[\pos] ? []).do { |p|
                var px = r[\barX] + (p * barW);
                Pen.line(px@(r[\cy] + 3), px@(r[\cy] + 6));
            };
        };
    };
    Pen.stroke;
    Pen.fillColor = pal.ink;
    rows.do { |r|
        var lv = r[\liveIdx] !? { |i| live[i] };
        lv !? { Pen.fillRect(Rect(r[\barX] + (lv.clip(0, 1) * barW) - 1.5, r[\cy] - 4, 3, 8)) };
    };
    selE !? { |e| ~kfWinDrawCable.(e, true) };
};

// ----- hit test: a cable within hitPx, else the row under the click ----
~kfWinHit = { |x, y|
    var cfg = ~cfg_kfwin, best = nil, bd = cfg.hitPx;
    ~kfWinCables.do { |e|
        var d = if(e[\intra]) {
            [~kfWinSegDist.(x, y, e[\ax], e[\ay], e[\mx], e[\ay]),
             ~kfWinSegDist.(x, y, e[\mx], e[\ay], e[\mx], e[\by]),
             ~kfWinSegDist.(x, y, e[\mx], e[\by], e[\bx], e[\by])].minItem
        } {
            ~kfWinSegDist.(x, y, e[\ax], e[\ay], e[\bx], e[\by])
        };
        if(d < bd) { bd = d; best = e[\cable] };
    };
    if(best.notNil) {
        ~kfSel[\cable] = best;
        // the node half follows the cable: reading a cable without the state of
        // the node it lands in is half an answer (§9.1)
        ~kfSel[\node] = [best[\dst][0].asSymbol, best[\dst][1].asSymbol];
    } {
        var r = ~kfRows.detect { |row|
            (x >= (row[\x] - 4)) and: { x <= (row[\x] + row[\width]) }
                and: { y >= row[\y] } and: { y <= (row[\y] + ~cfg_kfwin.rowH) };
        };
        r !? { ~kfSel[\node] = [r[\layer], r[\key]] };
    };
    ~kfGuiSync !? (_.value);
    ~kfField !? (_.refresh);
};

// ----- inspector -------------------------------------------------------
~kfWinLabel = { |lk| (~uiPhi[lk[0].asSymbol] ? "") ++ " " ++ ~kfIdOf.(lk[0], lk[1]) };

// selecting a node by its ROW. The labels are opaque widgets over the field and
// swallow the click that ~kfWinHit would otherwise see, so they carry the same
// action themselves — a name you can read but not click would be worse than a
// name drawn every frame
~kfWinSelectRow = { |layer, key|
    ~kfSel[\node] = [layer.asSymbol, key.asSymbol];
    ~kfGuiSync !? (_.value);
    ~kfField !? (_.refresh);
};

~kfWinFcSpec = { |cable|
    var bnd = ~kfBand[cable[\band] ? \block] ? [0.004, 0.05];
    var fmax = ~kfFmaxOf.(cable[\dst][0], cable[\dst][1], ~kfWinWins.value);
    // the same ceiling the node body clips to: a ruler that offered more would
    // report a τ the Lag never runs at, and Λ/the ladder would drift off the graph
    var hi = min(bnd[1], min(fmax ? bnd[1], ~kfFcCeil.value));
    ControlSpec(bnd[0], max(hi, bnd[0] * 1.0001), \exp)
};

~kfWinNote = { |str| ~kfInspect[\note] !? { |t| { t.string_(str) }.defer } };

// the ONE refresh of the inspector: every edit path and the relayout end here,
// deferred, so nothing touches a widget from inside a paint
~kfWinInspect = {
    {
        if(~kfWin.notNil and: { ~kfInspect.notEmpty }) {
            var c = ~kfSel[\cable], lk = ~kfSel[\node];
            var n = ~kfWinNodeOf.(lk);
            // the selected row is highlit in TWO places: the bar band is Pen
            // work inside the field, the label is a widget outside it — the one
            // background the drawing cannot reach has to be moved by hand
            var hi = lk !? { ~kfRows.detectIndex { |r|
                (r[\layer] == lk[0]) and: { r[\key] == lk[1] } } };
            if(hi != ~kfWinHiRow) {
                ~kfWinHiRow !? { |i| ~kfRowTxt[i] !? { |t|
                    t[\name].background_(~uiPal.paper); t[\fmax].background_(~uiPal.paper) } };
                hi !? { |i| ~kfRowTxt[i] !? { |t|
                    t[\name].background_(~uiPal.hi); t[\fmax].background_(~uiPal.hi) } };
                ~kfWinHiRow = hi;
            };
            if(c.isNil) {
                ~kfInspect[\src].string_("—");
                ~kfInspect[\dst].string_("");
                ~kfInspect[\band].string_("");
                ~kfInspect[\cwin].string_("");
                ~kfInspect[\step].string_("");
                ~kfInspect[\loop].string_("");
                ~uiRulerEnable.(~kfInspect[\gain], false);
                ~uiRulerEnable.(~kfInspect[\fc], false);
                ~uiPopupEnable.(~kfInspect[\pol], false);
                ~uiPopupEnable.(~kfInspect[\curve], false);
                [\zero, \del].do { |k| ~uiBtnEnable.(~kfInspect[k], false) };
            } {
                var dl = c[\dst][0].asSymbol, dk = c[\dst][1].asSymbol;
                var gmax = min(~cfg_kf.gainAbsMax, ~kfGainMax.(dl, dk));
                var fcSpec = ~kfWinFcSpec.(c);
                var lp = ~kfWinLoopOf.(c);
                var items = ~kfWinCurveItems.(dl, dk);
                var locked = ~kfWinCurveLocked.(dl, dk);
                var dn = ~kfWinNodeOf.([dl, dk]);
                ~kfInspect[\src].string_("src  " ++ ~kfWinLabel.(c[\src]));
                ~kfInspect[\dst].string_("dst  " ++ ~kfWinLabel.(c[\dst]));
                ~kfInspect[\band].string_("band " ++ (c[\band] ? \block)
                    ++ " · τ " ++ ~uiFmt.(1 / (2pi * (c[\fc] ? 1)), 2) ++ " s");
                ~kfInspect[\gain][\spec] = ControlSpec(0, gmax.max(0.0001), \lin);
                ~uiRulerSet.(~kfInspect[\gain], (c[\gain] ? 0).clip(0, gmax));
                ~uiRulerEnable.(~kfInspect[\gain], ~kfGainSet.notNil);
                ~kfInspect[\fc][\spec] = fcSpec;
                ~uiRulerSet.(~kfInspect[\fc], (c[\fc] ? fcSpec.minval).clip(fcSpec.minval, fcSpec.maxval));
                ~uiRulerEnable.(~kfInspect[\fc], true);
                ~uiPopupSet.(~kfInspect[\pol], if((c[\pol] ? 1) < 0) { 1 } { 0 });
                ~uiPopupEnable.(~kfInspect[\pol], true);
                ~uiPopupItems.(~kfInspect[\curve], items.collect(_.asString));
                ~uiPopupSet.(~kfInspect[\curve],
                    (items.indexOf(dn !? { |x| x[\curve] } ? \clip) ? 0));
                // locked, not hidden: the node is a convergence or a P node and
                // ~kfWireOf decides its curve — a live popup would claim an edit
                // that the next body build silently reverses
                ~uiPopupEnable.(~kfInspect[\curve], locked.not);
                ~kfInspect[\cwin].string_("win  "
                    ++ ~uiFmt.((dn !? { |x| x[\win][0] }) ? 0, 3) ++ "–"
                    ++ ~uiFmt.((dn !? { |x| x[\win][1] }) ? 1, 3)
                    ++ (if((dn !? { |x| x[\winRel] }) == true) { " · rel ±"
                        ++ ((c[\winDb] ? ~cfg_kf.patchLDb).abs) ++ " dB" } { "" })
                    ++ (if(locked) { " · curve fixed by the node" } { "" }));
                ~kfInspect[\step].string_(if((dn !? { |x| x[\curve] }) == \step) {
                    "step " ++ ~kfWinPos.(dl, dk, dn[\win]).size ++ " pos · hyst "
                        ++ ~uiFmt.(dn[\hyst], 2) ++ " · dwell " ++ dn[\dwell]
                        ++ " s · cut " ++ ~uiFmt.(dn[\cut], 3) ++ " s"
                } { "" });
                ~kfInspect[\loop].string_(if(lp.isNil) { "no cycle through this cable" } {
                    "Λ " ++ ~uiFmt.(lp[\lam], 3) ++ " · inv " ++ lp[\inv]
                        ++ " · T " ++ ~uiFmt.(lp[\period], 2) ++ " s · len " ++ lp[\len]
                });
                ~uiBtnEnable.(~kfInspect[\zero], ~kfGainSet.notNil);
                ~uiBtnEnable.(~kfInspect[\del], true);
            };
            if(n.isNil) {
                ~kfInspect[\nodeId].string_("—");
                ~kfInspect[\nodeWin].string_("");
                ~kfInspect[\nodeCab].string_("");
                ~uiRulerEnable.(~kfInspect[\hand], false);
            } {
                var cls = ((~kfRow.(lk[0], lk[1]) !? { |r| r[0] }) ? $?).asString;
                var fmax = ~kfFmaxOf.(lk[0], lk[1], ~kfWinWins.value);
                var lv = ~kfWinLiveOf.(~kfIdOf.(lk[0], lk[1]));
                var out = ((~kfFanOut[lk[0].asSymbol] ? ())[lk[1].asSymbol] ? []).size;
                ~kfInspect[\nodeId].string_(~kfWinLabel.(lk) ++ "  · " ++ cls
                    ++ " · f_max " ++ (fmax !? { |f| ~kfWinHzText.(f) ++ " Hz" } ? "—"));
                ~kfInspect[\nodeWin].string_("win " ++ ~uiFmt.(n[\win][0], 3) ++ "–"
                    ++ ~uiFmt.(n[\win][1], 3) ++ " · rest " ++ ~uiFmt.(n[\rest], 3)
                    ++ " · live " ++ (lv !? { |x| ~uiFmt.(x, 3) } ? "—"));
                ~kfInspect[\nodeCab].string_("in " ++ n[\cables].size ++ " · out " ++ out
                    ++ " · " ++ n[\curve] ++ " · " ++ ~uiFmt.(n[\spec].map(n[\rest]), 3)
                    ++ " (rest, real)");
                // the hand is WRITE-ONLY (§3.2): nothing reads a node's live hand
                // back, so the ruler is parked at 0 on every selection instead of
                // showing a deviation that may already have been released
                ~uiRulerSet.(~kfInspect[\hand], 0);
                ~uiRulerEnable.(~kfInspect[\hand], ~kfPoke.notNil);
            };
        };
    }.defer;
};

// ----- header state line (§4.4 + §8.4, ONE spelling in module 8) -------
~kfWinDrawStrip = { |u|
    ~uiPenText.(
        if(~kfStripText.isNil) { "koppelfeld off (enableKoppelfeld)" } { ~kfStripText.value },
        0, 3, ~kfWinFontLine, ~uiPal.ink);
};

// ----- §9.3 slot reset: all four traps of contract §6 ------------------
~kfResetSlots = {
    ~kfWin = nil;
    ~kfField = nil;
    ~kfStrip = nil;
    ~kfGuiSync = nil;
    ~kfRows = [];
    ~kfCols = [];
    ~kfWinCables = [];
    ~kfColTxt = [];
    ~kfRowTxt = [];
    ~kfRowKeys = [];
    ~kfWinHiRow = nil;
    ~kfInspect = ();
    ~kfBtns = ();
    ~kfSel = ();
    ~kfWinStamp = nil;
    ~kfWinGeom = ();
    ~kfWinLiveIds = nil;
    ~kfWinLiveMap = ();
    // the meter belongs to whoever switched it on: ~kfLogStart may be holding
    // it, and killing it under an open log closes that log (§12.1)
    if(~kfWinOwnsMeter and: { ~kfMeterOn.notNil }) { ~kfMeterOn.(false) };
    ~kfWinOwnsMeter = false;
};

// ----- build -----------------------------------------------------------
~ungBuildKfWindow = {
    var cfg = ~cfg_kfwin, pal = ~uiPal;
    var w = cfg.winW, h = cfg.winH, scr, winRect, win;
    var ix, iw, fieldW, live, y;
    var fmt2 = { |v| ~uiFmt.(v, 2) }, fmt3 = { |v| ~uiFmt.(v, 3) };

    // close previous window best-effort (destroyed Qt object — contract §6)
    if(~kfWin.notNil) { try { ~kfWin.close } };
    ~kfResetSlots.value;

    live = (~kfNodes ? ()).notNil and: { (~kfNodes ? ()).notEmpty };
    if(live.not) {
        "8b_kfwindow — поля нет (~kfNodes пусто): окно не открыто.".warn;
        nil
    } {
        var order = (~kfLayerOrder ? []).select { |l| ((~kfNodes ? ())[l] ? ()).notEmpty };
        scr = Window.availableBounds;
        w = w.min(scr.width); h = h.min(scr.height);
        ~kfWinGeomSet.(w, order.size);
        ix = ~kfWinGeom[\ix]; iw = ~kfWinGeom[\iw]; fieldW = ~kfWinGeom[\fieldW];
        winRect = Rect(scr.left + ((scr.width - w) / 2).max(0), scr.top, w, h);
        // separate assignment: `win = dict[k] = Window()` returns the DICT (§16.13)
        win = Window("UNGRUND · koppelfeld", winRect).background_(pal.paper);
        ~kfWin = win;

        // --- header ---
        ~uiCap.(win, Rect(cfg.margin, 12, 600, 14), "ungrund · koppelfeld · nord field");
        ~uiTitle.(win, Rect(cfg.margin, 26, 300, 36), "Koppelfeld");
        ~kfStrip = UserView(win, Rect(330, 36, (w - 660).max(200), 20)).background_(pal.paper);
        ~kfStrip.drawFunc_({ |u| ~kfWinDrawStrip.(u) });
        // 1 Hz, and only 1 Hz: reading the line re-validates a verdict aged by a
        // hand edit (D99), and the validator costs up to 20 ms (A-11)
        ~kfStrip.frameRate_(cfg.stripFps).animate_(true);

        ~kfBtns = (
            arm: ~uiBtn.(win, Rect(w - 306, 30, 62, 26), "arm",
                { ~kfArm !? { |f| f.((~cfg_kf !? { |x| x[\armTime] }) ? 4) } }),
            disarm: ~uiBtn.(win, Rect(w - 238, 30, 72, 26), "disarm",
                { ~kfDisarm !? { |f| f.((~cfg_kf !? { |x| x[\armTime] }) ? 4) } }),
            random: ~uiBtn.(win, Rect(w - 160, 30, 74, 26), "random", {
                // the same lock the desk's patch button carries: an act OWNS the
                // scheme, and a hand-derived one would be cut away by its next tier
                if(~konActive == true) {
                    ~kfWinNote.("схема принадлежит акту — random заблокирован");
                } {
                    var sch = ~kfRandomize !? { |f| f.(nil, (~gridComplexity ? 0.5)) };
                    if(sch.isNil) {
                        ~kfWinNote.("патчер отказал — схема не выведена");
                    } {
                        ~kfApply.(sch, (~cfg_kf !? { |x| x[\armTime] }) ? 4);
                        ~kfWinNote.("схема " ++ sch[\seed] ++ " · c "
                            ++ ~uiFmt.(sch[\complexity] ? 0, 2) ++ " · кабелей "
                            ++ (sch[\cables] ? []).size);
                    };
                };
            }),
            close: ~uiBtn.(win, Rect(w - 80, 30, 66, 26), "close", { win.close })
        );
        ~uiRule.(win, Rect(0, 66, w, 1));

        // --- column headers (static text: 5 widgets, not 5 strings a frame) ---
        ~kfColTxt = order.collect { |l, i|
            ~uiText.(win, Rect(cfg.margin + (i * ~kfWinGeom[\colW]) + cfg.colPad, 70,
                ~kfWinGeom[\colW] - 8, 14), "", 9.5, pal.ink2);
        };

        // --- THE field: rows and cables on ONE UserView (§9.2) ---
        ~kfField = UserView(win, Rect(cfg.margin, cfg.fieldY, fieldW, cfg.fieldH))
            .background_(pal.paper);
        ~kfField.drawFunc_({ |u| ~kfWinDrawField.(u) });
        ~kfField.mouseDownAction_({ |u, x, y| ~kfWinHit.(x, y) });
        ~kfField.frameRate_(cfg.fps).animate_(true);
        ~uiRule.(win, Rect(ix - 12, 67, 1, h - 67));

        // --- inspector: the selected cable ---
        ~uiCap.(win, Rect(ix, 76, iw, 14), "inspector · cable");
        ~kfInspect[\src]  = ~uiText.(win, Rect(ix, 92,  iw, 16), "—", 10);
        ~kfInspect[\dst]  = ~uiText.(win, Rect(ix, 108, iw, 16), "",  10);
        ~kfInspect[\band] = ~uiText.(win, Rect(ix, 126, iw, 16), "",  9.5, pal.ink2);
        ~kfInspect[\gain] = ~uiRulerRow.(win, ix, 146, 30, 148, "gain",
            ControlSpec(0, 4, \lin), 0, { |v|
                ~kfSel[\cable] !? { |c| ~kfGainSet !? { |f| f.(c, v) } };
            }, fmt3);
        ~kfInspect[\fc] = ~uiRulerRow.(win, ix, 170, 30, 148, "f_c",
            ControlSpec(0.004, 0.05, \exp), 0.004, { |v|
                ~kfSel[\cable] !? { |c|
                    var slot = ~kfWinSlotOf.(c), n = ~kfWinNodeOf.(c[\dst]);
                    c[\fc] = v;
                    if(slot.notNil) { Ndef(n[\node]).set(("fc" ++ slot).asSymbol, v) };
                    // the ladder V6, Λ and the loop period are all functions of τ
                    ~kfVerdictStale = true;
                    ~kfInspect[\band] !? { |t| t.string_("band " ++ (c[\band] ? \block)
                        ++ " · τ " ++ ~uiFmt.(1 / (2pi * v), 2) ++ " s") };
                };
            }, fmt3);
        ~uiCap.(win, Rect(ix, 196, iw, 14), "pol · curve");
        ~kfInspect[\pol] = ~uiPopup.(win, Rect(ix, 212, 140, 22), ~kfWinPolItems, 0, { |idx|
            ~kfSel[\cable] !? { |c|
                var slot = ~kfWinSlotOf.(c), n = ~kfWinNodeOf.(c[\dst]);
                c[\pol] = if(idx == 1) { -1 } { 1 };
                if(slot.notNil) { Ndef(n[\node]).set(("s" ++ slot).asSymbol, c[\pol]) };
                // the parity of the inversions decides umlauf against ruhe (§4.4)
                ~kfVerdictStale = true;
                ~kfField !? (_.refresh);
            };
        });
        ~kfInspect[\curve] = ~uiPopup.(win, Rect(ix + 150, 212, 140, 22),
            ~kfWinCurves.collect(_.asString), 0, { |idx|
                ~kfSel[\cable] !? { |c|
                    var dl = c[\dst][0].asSymbol, dk = c[\dst][1].asSymbol;
                    var items = ~kfWinCurveItems.(dl, dk);
                    var cv = items[idx.clip(0, items.size - 1)];
                    var n = ~kfWinNodeOf.([dl, dk]);
                    // the curve is a NODE field, not a cable one (V7): written to
                    // every cable of the destination or the next validate rejects
                    // the very edit this popup just made
                    n !? { n[\cables].do { |x| x[\curve] = cv } };
                    ~kfWinRewire.(dl, dk);
                    ~kfGuiSync !? (_.value);
                    ~kfField !? (_.refresh);
                };
            });
        ~kfInspect[\cwin] = ~uiText.(win, Rect(ix, 240, iw, 16), "", 9.5, pal.ink2);
        ~kfInspect[\step] = ~uiText.(win, Rect(ix, 256, iw, 16), "", 9.5, pal.ink2);
        ~kfInspect[\loop] = ~uiText.(win, Rect(ix, 276, iw, 16), "", 10);
        ~kfInspect[\zero] = ~uiBtn.(win, Rect(ix, 298, 138, 24), "zero (null test)", {
            ~kfSel[\cable] !? { |c|
                ~kfGainSet !? { |f| f.(c, 0) };
                ~kfWinNote.("кабель обнулён — нулевой тест D-8: цель обязана вернуться к покою");
                ~kfGuiSync !? (_.value);
            };
        });
        ~kfInspect[\del] = ~uiBtn.(win, Rect(ix + 148, 298, 142, 24), "delete cable", {
            ~kfSel[\cable] !? { |c|
                var dl = c[\dst][0].asSymbol, dk = c[\dst][1].asSymbol;
                // disabled, never removed: §10.3 keeps a dead cable in the table
                // so a preset saved now does not silently reroute the scheme
                c[\enabled] = false;
                ~kfSel[\cable] = nil;
                ~kfWinRewire.(dl, dk);
                ~kfWinNote.("кабель выключен (в таблице остался, enabled: false)");
                ~kfGuiSync !? (_.value);
                ~kfField !? (_.refresh);
            };
        });

        // --- inspector: the selected node ---
        ~uiRule.(win, Rect(ix, 336, iw, 1));
        ~uiCap.(win, Rect(ix, 346, iw, 14), "inspector · node");
        ~kfInspect[\nodeId]  = ~uiText.(win, Rect(ix, 362, iw, 16), "—", 10);
        ~kfInspect[\nodeWin] = ~uiText.(win, Rect(ix, 378, iw, 16), "", 9.5, pal.ink2);
        ~kfInspect[\nodeCab] = ~uiText.(win, Rect(ix, 394, iw, 16), "", 9.5, pal.ink2);
        ~kfInspect[\hand] = ~uiRulerRow.(win, ix, 416, 30, 148, "hand",
            ControlSpec(cfg.handMax.neg, cfg.handMax, \lin, 0, 0), 0, { |v|
                ~kfSel[\node] !? { |lk| ~kfPoke !? { |f| f.(lk[0], lk[1], v) } };
            }, fmt3);
        ~kfInspect[\release] = ~uiBtn.(win, Rect(ix, 444, 138, 24), "release all", {
            ~kfRelease !? (_.value);
            ~uiRulerSet.(~kfInspect[\hand], 0);
            ~kfWinNote.("рука снята со всех 111 узлов");
        });
        ~kfInspect[\note] = ~uiText.(win, Rect(ix, 478, iw, 46), "", 9.5, pal.ink2);

        // --- legend of the drawing ---
        ~uiRule.(win, Rect(ix, 540, iw, 1));
        ~uiCap.(win, Rect(ix, 550, iw, 14), "notation");
        y = 568;
        [
            "строка: класс §F · имя · шкала · f_max",
            "шкала: заливка — окно цели, засечка — покой,",
            "        маркер — живое значение (метр 20 Гц)",
            "штрих кабеля растёт с усилением (·/4)",
            "двойная линия — кабель входит в цикл",
            "точка на середине — инверсия pol = −1",
            "скобка справа от колонки — внутрислойный",
            "клик по линии (< 4 px) — кабель, по строке — узел"
        ].do { |ln|
            ~uiText.(win, Rect(ix, y, iw, 14), ln, 9, pal.ink2);
            y = y + 14;
        };

        // --- meter (§9.2): ours only if nobody else was holding it ---
        ~kfWinOwnsMeter = (~kfMeterOnP !? (_.value)) != true;
        if(~kfWinOwnsMeter and: { ~kfMeterOn.notNil }) { ~kfMeterOn.(true, cfg.meterRate) };

        ~kfGuiSync = ~kfWinInspect;
        ~kfWinRelayout.value;
        ~kfGuiSync.value;

        // guard: only the CURRENT window (or one already taken down by
        // ~appCleanup) may clear the slots — a deferred onClose of an OLD window
        // must not wipe the registries of the NEW one (contract §6, §16.14)
        win.onClose_({
            if(~kfWin.isNil or: { ~kfWin === win }) { ~kfResetSlots.value };
        });
        // a heavy window is placed AFTER its layout: front alone lands it at the
        // Qt default size for a frame and the field draws into the wrong bounds
        { if(~kfWin === win) { win.bounds_(winRect).front } }.defer(0.3);
        win
    };
};

// open the koppelfeld window (deferred to AppClock; the desk button calls this)
~openKoppelfeld = { { ~ungBuildKfWindow.value }.defer };

// a live window is rebuilt on a file reload: the layout constants above are
// baked into ~kfRows at build time, so a reloaded CONFIG would otherwise not
// reach the window that is standing
if(~kfWin.notNil) { ~openKoppelfeld.value };

"8b_kfwindow — окно Nord (~openKoppelfeld): 5 колонок, кабели, инспектор, метр.".postln;
)
