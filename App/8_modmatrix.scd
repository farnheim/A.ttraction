// App/8_modmatrix.scd — UNGRUND · MODULATION MATRIX: cross-layer coupling of
// the 16 principal tone-forming parameters. Each line is a kr modulator whose
// FREQUENCY is driven by another modulator's output (a single 16-cycle ring
// across all five layers) — "частота одного параметра управляет другим". Each
// line's DEPTH (influence level 0..1) is surfaced as a fader in the mixer
// window (2_mixer.scd, nil-safe panel), with a "рандом связей" button ->
// ~modRandomize (rate/fm/depth, topology untouched). Loads BEFORE the mixer so
// the panel can read ~modKeys; ON by default (~cfg_app.enableModMatrix).
// Automation precedent: 3_lfo.scd. Reference + full table:
// docs/features/parameters-ru.md.


// ===== CONFIG — edit here ============================================
(
// Each line: ( target: \layer, param: \key, shape: \noise|\sine, rate: baseHz,
//   src: <0..15 index of the modulator that drives THIS one's frequency>,
//   fm: <octaves of frequency coupling>, depth: <initial influence 0..1> ).
// Range + centre come from the target's ControlSpec (~ungSpecOf) — no numbers
// hardcoded here. src forms one ring: 0→4→7→10→13→1→5→8→11→14→2→6→9→12→15→3→0
// (alpha→delta→epsilon→zeta→theta→alpha…), so every layer both drives and is
// driven — the "общая связь слоёв".
// NOTE theta rows (13–15): ioi0/decel are never lagged and latch at the
// population boundary; a slow kr drift is legitimate (the layer re-polls once
// per population, its .clip stands) but keep their depth low — a §C.8 premise
// concern, not a bug. See docs/features/parameters-ru.md.
~cfg_modmtx = (
    lines: [
        ( target: \alpha,   param: \density,     shape: \noise, rate: 0.050, src: 3,  fm: 0.8, depth: 0.25 ),
        ( target: \alpha,   param: \oil,         shape: \noise, rate: 0.033, src: 13, fm: 0.7, depth: 0.30 ),
        ( target: \alpha,   param: \bright,      shape: \noise, rate: 0.070, src: 14, fm: 0.9, depth: 0.20 ),
        ( target: \alpha,   param: \metalAmt,    shape: \noise, rate: 0.045, src: 15, fm: 0.8, depth: 0.20 ),
        ( target: \delta,   param: \windForce,   shape: \noise, rate: 0.028, src: 0,  fm: 0.7, depth: 0.25 ),
        ( target: \delta,   param: \metal,       shape: \noise, rate: 0.061, src: 1,  fm: 0.9, depth: 0.22 ),
        ( target: \delta,   param: \vowelSel,    shape: \sine,  rate: 0.037, src: 2,  fm: 0.8, depth: 0.25 ),
        ( target: \epsilon, param: \mWidth,      shape: \noise, rate: 0.023, src: 4,  fm: 0.6, depth: 0.18 ),
        ( target: \epsilon, param: \flowCeil,    shape: \noise, rate: 0.052, src: 5,  fm: 0.9, depth: 0.22 ),
        ( target: \epsilon, param: \flowLevel,   shape: \noise, rate: 0.031, src: 6,  fm: 0.7, depth: 0.20 ),
        ( target: \zeta,    param: \bedHumpFreq, shape: \noise, rate: 0.066, src: 7,  fm: 1.0, depth: 0.22 ),
        ( target: \zeta,    param: \fineRate,    shape: \noise, rate: 0.043, src: 8,  fm: 0.8, depth: 0.25 ),
        ( target: \zeta,    param: \popRate,     shape: \noise, rate: 0.026, src: 9,  fm: 0.7, depth: 0.22 ),
        ( target: \theta,   param: \edgeWidth,   shape: \noise, rate: 0.048, src: 10, fm: 0.8, depth: 0.15 ),
        ( target: \theta,   param: \ioi0,        shape: \noise, rate: 0.021, src: 11, fm: 0.6, depth: 0.10 ),
        ( target: \theta,   param: \decel,       shape: \noise, rate: 0.035, src: 12, fm: 0.6, depth: 0.10 )
    ]
);


// ===== LOGIC — coupled modulator network =============================
// Two kr proxies per line: modmtx_osc_i (raw bipolar oscillator, its frequency
// FM'd by modmtx_osc_<src>) and modmtx_map_i (osc shaped into the target's
// spec range around the param's current centre, scaled by depth). Forward ring
// references resolve through the shared kr bus (JITLib), the closed loop costs
// one control block of latency (like InFeedback), never an error.
// Idempotent reload via ~modActive: unmap the target FIRST, then clear the two
// proxies (clear before unmap would leave the target on a freed bus — 3_lfo.scd
// precedent).
~modShort = [
    "a.dens", "a.oil",  "a.brgt", "a.metl",
    "d.wind", "d.metl", "d.vwl",
    "e.mwid", "e.ceil", "e.flow",
    "z.hump", "z.fine", "z.pop",
    "t.edge", "t.ioi",  "t.decl"
];

~modOscKey = { |i| ("modmtx_osc_" ++ i).asSymbol };
~modMapKey = { |i| ("modmtx_map_" ++ i).asSymbol };

(~modActive ? []).do { |e|
    Ndef(e[\target]).unmap(e[\param]);
    Ndef(e[\mapKey]).clear;
    Ndef(e[\oscKey]).clear;
};

~modKeys   = [];   // per-line descriptor read by the mixer panel (index, label, depth, enabled)
~modActive = [];   // osc/map keys + target/param of the current run (cleanup above)

~cfg_modmtx.lines.do { |line, i|
    var layer  = line[\target].asSymbol;
    var param  = line[\param].asSymbol;
    var shape  = line[\shape];
    var srcOscKey = ~modOscKey.(line[\src]);
    var oscKey = ~modOscKey.(i);
    var mapKey = ~modMapKey.(i);
    var pspec, cspec, center, centerN;

    pspec = ~ungSpecOf.(layer) !? { |s| s.params.detect { |p| p[\key] == param } };

    if(pspec.isNil) {
        // layer not loaded (e.g. a ~cfg_app.layers subset) — panel shows the row disabled
        ("8_modmatrix — строка " ++ i ++ ": слой " ++ layer ++ " не загружен, связь пропущена").warn;
        ~modKeys = ~modKeys.add((
            index: i, label: ~modShort[line[\src]] ++ "→" ++ ~modShort[i],
            target: layer, param: param, depth: line[\depth], enabled: false
        ));
    } {
        cspec   = pspec[\spec];
        center  = (~ungVals[layer] !? { ~ungVals[layer][param] }) ? cspec.default;
        centerN = cspec.unmap(center);

        Ndef(oscKey, { |rate = 0.05, fm = 0.8|
            var srcSig = Ndef(srcOscKey).kr(1);
            var freq = (rate * (2 ** (fm * srcSig))).clip(0.001, 30);
            var osc = switch(shape,
                \sine,  { SinOsc.kr(freq) },
                \noise, { LFNoise2.kr(freq) },
                { LFNoise2.kr(freq) }
            );
            osc.clip(-1, 1)
        });
        Ndef(oscKey).set(\rate, line[\rate], \fm, line[\fm]);

        // depth 0 -> constant centre (no influence). .map drives the param; while
        // a line is active the tuner slider shows but does not move it (3_lfo.scd
        // behaviour). Work in normalised spec space so the swing stays in range
        // and is perceptually even on \exp params.
        Ndef(mapKey, { |depth = 0|
            var oscSig = Ndef(oscKey).kr(1);
            cspec.map((centerN + (depth * oscSig)).clip(0, 1))
        });
        Ndef(mapKey).set(\depth, line[\depth]);

        Ndef(layer).map(param, Ndef(mapKey));

        ~modKeys = ~modKeys.add((
            index: i, label: ~modShort[line[\src]] ++ "→" ++ ~modShort[i],
            target: layer, param: param, depth: line[\depth], enabled: true
        ));
        ~modActive = ~modActive.add((
            oscKey: oscKey, mapKey: mapKey, target: layer, param: param
        ));
    };
};

// live depth setter (mixer fader / MIDI): ~modDepthSet.(i, 0.4)
~modDepthSet = { |i, v|
    var line = ~cfg_modmtx.lines[i];
    var entry = ~modKeys[i];
    if(entry.notNil and: { entry[\enabled] }) {
        Ndef(~modMapKey.(i)).set(\depth, v);
        line[\depth] = v;
        entry[\depth] = v;
        if(~modmatrixGuiSync.notNil) { ~modmatrixGuiSync.(i, v) };
    };
};

// randomize the modulation parameters: rate (slow-LFO band), fm (coupling
// octaves, kept ≤ 1.2 so the ring stays stable) and depth (influence). All
// three are .set-able NamedControls -> live, no proxy rebuild. src/shape (the
// coupling topology) are left intact so the ring stays a single cycle.
// ~modRandomize.() = all connections; ~modRandomize.(5) = one. theta rows keep
// a lower depth ceiling (§C.8 caution, see parameters-ru.md).
~modRandomize = { |i|
    var doLine = { |idx|
        var line  = ~cfg_modmtx.lines[idx];
        var entry = ~modKeys[idx];
        var depthMax, newRate, newFm, newDepth;
        if(entry.notNil and: { entry[\enabled] }) {
            depthMax = if(line[\target].asSymbol == \theta, 0.2, 0.5);
            newRate  = 0.01.exprand(0.12);
            newFm    = 0.3.rrand(1.2);
            newDepth = 0.0.rrand(depthMax);
            Ndef(~modOscKey.(idx)).set(\rate, newRate, \fm, newFm);
            Ndef(~modMapKey.(idx)).set(\depth, newDepth);
            line[\rate] = newRate; line[\fm] = newFm; line[\depth] = newDepth;
            entry[\depth] = newDepth;
            if(~modmatrixGuiSync.notNil) { ~modmatrixGuiSync.(idx, newDepth) };
        };
    };
    if(i.isNil) { ~cfg_modmtx.lines.size.do { |idx| doLine.(idx) } } { doLine.(i) };
    ("8_modmatrix — рандом модуляции: "
        ++ if(i.isNil, { "все связи" }, { "связь " ++ i })).postln;
};

// set by the mixer window (nil without GUI); mirrors ~mixerGuiSync
~modmatrixGuiSync = ~modmatrixGuiSync;

("8_modmatrix — модуляционная матрица: активных связей "
    ++ ~modActive.size ++ "/" ++ ~cfg_modmtx.lines.size
    ++ " (глубины -> микшер)").postln;
)
