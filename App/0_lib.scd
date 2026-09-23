// App/0_lib.scd — NET · the one field. Every machine publishes its parameters,
// its inner variables and its output as audio-rate sources, and takes audio-rate
// modulation into the same parameters, variables and one audio input. A cell of
// the matrix is one synth: source bus -> depth -> destination bus. Nothing else.

(
// ===== CONFIG — edit here ============================================
~cfg_net = (
    diceDensity: 0.03,
    diceDepth:   0.5,
    wander:      0.0,
    wanderRate:  0.3,
    cellLag:     0.08,
    driftPeriod: 3.0,
    driftAmt:    0.08
);


// ===== LOGIC =========================================================
~ungSpecs  = ~ungSpecs  ? ();
~ungVals   = ~ungVals   ? ();
~netBus    = ~netBus    ? ();
~netCells  = ~netCells  ? Dictionary.new;
~netHooks  = ~netHooks  ? ();
~netViews  = ~netViews  ? ();

~ungPresetRoot = ((~appDir ? (thisProcess.nowExecutingPath !? (_.dirname))) ? "")
    +/+ "presets";

~ungSpecOf = { |layer| ~ungSpecs[layer.asSymbol] };
~netLayers = {
    (~activeLayers ? ~ungSpecs.keys.asArray.sort).select { |l| ~ungSpecs[l].notNil }
};
~netSrcKeys = { |spec|
    spec.params.collect(_.key) ++ (spec[\vars] ? []).collect(_.key) ++ [\out]
};
~netDstKeys = { |spec|
    spec.params.collect(_.key) ++ (spec[\vars] ? []).collect(_.key) ++ [\in]
};
~netAllSrc = { ~netLayers.value.collect { |l| ~netSrcKeys.(~ungSpecs[l]).collect { |k| [l, k] } }.flatten(1) };
~netAllDst = { ~netLayers.value.collect { |l| ~netDstKeys.(~ungSpecs[l]).collect { |k| [l, k] } }.flatten(1) };

// the same arithmetic on numbers and on UGens: ControlSpec:map rounds and
// clips in the language and is not safe to hand a UGen
~netMap = { |sp, u|
    if(sp.warp.isKindOf(ExponentialWarp)) {
        sp.minval * ((sp.maxval / sp.minval) ** u)
    } { sp.minval + (u * (sp.maxval - sp.minval)) }
};
~netUnmap = { |sp, x|
    if(sp.warp.isKindOf(ExponentialWarp)) {
        (x / sp.minval).log / (sp.maxval / sp.minval).log
    } { (x - sp.minval) / (sp.maxval - sp.minval) }
};

~netAlloc = { |name, n|
    var b = ~netBus[name];
    if(b.isNil or: { b[\n] != n }) {
        b !? { b[\tap].free; b[\mod].free };
        b = ( n: n, tap: Bus.audio(s, n), mod: Bus.audio(s, n) );
        ~netBus[name] = b;
    };
    b
};

// a machine body gets `io`:
//   io.par(\key)          -> the parameter, live, in its own units
//   io.node(\key, sig)    -> an inner variable made public: tapped and modulated
//   io.feed               -> the audio that other machines pour into this one
//   io.emit([l, r])       -> last line of the body
// everything the closure needs is captured here: the Ndef builds the graph
// outside this environment
~netMachine = { |spec, body|
    var name = spec.name, srcKeys = ~netSrcKeys.(spec), dstKeys = ~netDstKeys.(spec);
    var n = srcKeys.size, bus = ~netAlloc.(name, n);
    var tapIdx = bus[\tap].index, modIdx = bus[\mod].index;
    var map = ~netMap, unmap = ~netUnmap;
    var specs = (), vspecs = ();
    spec.params.do { |p| specs[p.key] = p.spec };
    (spec[\vars] ? []).do { |v| vspecs[v.key] = v.spec };
    {
        var mods = InFeedback.ar(modIdx, n);
        var taps = Array.fill(n, { List.new });
        var cache = ();
        var port = { |key|
            var i = dstKeys.indexOf(key);
            if(i.isNil) { Error("net: " ++ name ++ " has no port " ++ key).throw };
            i
        };
        var io = (
            par: { |self, key|
                var i, sp, u;
                if(cache[key].isNil) {
                    i  = port.(key);
                    sp = specs[key];
                    u  = (key.ar(unmap.(sp, sp.default).clip(0, 1)).lag(0.005) + mods[i]).clip(0, 1);
                    taps[i].add((u * 2) - 1);
                    cache[key] = map.(sp, u);
                };
                cache[key]
            },
            node: { |self, key, sig|
                var i = port.(key), sp = vspecs[key], u;
                u = (unmap.(sp, sig.clip(sp.minval, sp.maxval)) + mods[i]).clip(0, 1);
                u.asArray.do { |x| taps[i].add((x * 2) - 1) };
                map.(sp, u)
            },
            feed: { |self|
                if(cache[\in].isNil) { cache[\in] = LeakDC.ar(mods[port.(\in)]).clip2(1) };
                cache[\in]
            },
            emit: { |self, sig|
                sig = Sanitize.ar(sig);
                taps[n - 1].add(sig.asArray.sum * (1 / sig.asArray.size));
                Out.ar(tapIdx, Sanitize.ar(taps.collect { |l|
                    if(l.isEmpty) { DC.ar(0) } { l.asArray.sum * (1 / l.size) }
                }));
                sig
            }
        );
        body.(io)
    }
};

~netRegister = { |spec, fade = 2|
    var name = spec.name;
    ~ungSpecs[name] = spec;
    ~ungVals[name]  = ~ungVals[name] ? ();
    spec.params.do { |p| ~setParam.(name, p.key, ~ungVals[name][p.key] ? p.spec.default) };
    Ndef(name).fadeTime = fade;
    ("net · " ++ name ++ " · " ++ ~netSrcKeys.(spec).size ++ " sources · "
        ++ ~netDstKeys.(spec).size ++ " destinations").postln;
};


// ----- parameters (base values; modulation rides on top in the graph) -----
~netParam = { |layer, key|
    ~ungSpecOf.(layer) !? { |sp| sp.params.detect { |p| p.key == key } }
};
~setParam = { |layer, key, v|
    var p;
    layer = layer.asSymbol; key = key.asSymbol;
    p = ~netParam.(layer, key);
    if(p.notNil) {
        v = p.spec.constrain(v);
        Ndef(layer).set(key, p.spec.unmap(v));
        if(~ungVals[layer].isNil) { ~ungVals[layer] = () };
        ~ungVals[layer][key] = v;
        ~netHooks.do { |f| f.(layer, key, v) };
    };
    v
};
~netGet = { |layer, key|
    (~ungVals[layer] !? { |d| d[key] }) ?? { ~netParam.(layer, key) !? { |p| p.spec.default } }
};
~netDefaults = { |layer|
    ~ungSpecOf.(layer).params.do { |p| ~setParam.(layer, p.key, p.spec.default) };
};
~netDiceBase = { |layer, amt = 1.0|
    ~ungSpecOf.(layer).params.do { |p|
        var u = p.spec.unmap(~netGet.(layer, p.key));
        ~setParam.(layer, p.key, p.spec.map(u.blend(1.0.rand, amt)));
    };
};


// ----- cells ---------------------------------------------------------
SynthDef(\net_cell, { |src = 0, dst = 0, depth = 0, wander = 0, wrate = 0.3, rmul = 1, lagT = 0.08|
    var d = depth.lag(lagT);
    var w = LFNoise2.ar((wrate * rmul).clip(0.001, 400));
    d = d * ((1 - wander.lag(0.1)) + (w * wander.lag(0.1)));
    Out.ar(dst, InFeedback.ar(src) * d);
}).add;

~netSrcIndex = { |l, k|
    var sp = ~ungSpecs[l], b = ~netBus[l];
    if(sp.isNil or: { b.isNil }) { nil } {
        ~netSrcKeys.(sp).indexOf(k) !? { |i| b[\tap].index + i }
    }
};
~netDstIndex = { |l, k|
    var sp = ~ungSpecs[l], b = ~netBus[l];
    if(sp.isNil or: { b.isNil }) { nil } {
        ~netDstKeys.(sp).indexOf(k) !? { |i| b[\mod].index + i }
    }
};
~netCellKey = { |sl, sk, dl, dk| (sl ++ "." ++ sk ++ ">" ++ dl ++ "." ++ dk).asSymbol };

~netEnsureGroup = {
    if(~netGroup.isNil or: { ~netGroup.isPlaying.not }) {
        ~netGroup = Group.tail(s);
        NodeWatcher.register(~netGroup, true);
    };
    ~netGroup
};

~netSpawn = { |c|
    var si = ~netSrcIndex.(c[\src][0], c[\src][1]);
    var di = ~netDstIndex.(c[\dst][0], c[\dst][1]);
    c[\node] !? { |nd| nd.free; c[\node] = nil };
    if(si.notNil and: { di.notNil } and: { s.serverRunning }) {
        c[\node] = Synth(\net_cell, [
            src: si, dst: di, depth: c[\depth], rmul: c[\rmul],
            wander: ~cfg_net.wander, wrate: ~cfg_net.wanderRate, lagT: ~cfg_net.cellLag
        ], ~netEnsureGroup.value);
    };
};

// after any layer (re)load: a bus may have moved, and a cell holds indices
~netRewire = {
    if(s.serverRunning) {
        ~netGroup !? { |g| if(g.isPlaying) { g.free } };
        ~netGroup = nil;
        ~netCells.do { |c| c[\node] = nil; ~netSpawn.(c) };
    };
};

~netPut = { |sl, sk, dl, dk, depth|
    var key = ~netCellKey.(sl, sk, dl, dk), c = ~netCells[key];
    depth = depth.clip(-1, 1);
    if(depth.abs < 0.0005) {
        c !? { c[\node] !? { |nd| nd.free }; ~netCells.removeAt(key) };
    } {
        if(c.isNil) {
            c = ( src: [sl, sk], dst: [dl, dk], depth: depth, rmul: exprand(0.25, 4.0) );
            ~netCells[key] = c;
            ~netSpawn.(c);
        } {
            c[\depth] = depth;
            if(c[\node].notNil) { c[\node].set(\depth, depth) } { ~netSpawn.(c) };
        };
    };
};
~netSet = { |sl, sk, dl, dk, depth| ~netPut.(sl, sk, dl, dk, depth); ~netChanged.value };
~netDepth = { |sl, sk, dl, dk|
    ~netCells[~netCellKey.(sl, sk, dl, dk)] !? { |c| c[\depth] } ? 0
};
~netChanged = { ~netViews.do { |f| f.value } };

~netClear = { |notify = true|
    ~netCells.do { |c| c[\node] !? { |nd| nd.free } };
    ~netCells = Dictionary.new;
    if(notify) { ~netChanged.value };
};

~netRandDepth = { |depth| depth * (1.0.rand ** 2) * [-1, 1].choose };

~netDice = { |density, depth, clear = true|
    var srcs = ~netAllSrc.value, dsts = ~netAllDst.value;
    density = density ? ~cfg_net.diceDensity;
    depth   = depth   ? ~cfg_net.diceDepth;
    if(clear) { ~netClear.(false) };
    srcs.do { |a|
        dsts.do { |b|
            if((a != b) and: { density.coin }) {
                ~netPut.(a[0], a[1], b[0], b[1], ~netRandDepth.(depth));
            };
        };
    };
    ~netChanged.value;
    ("net · dice · " ++ ~netCells.size ++ " cells").postln;
};
~netDiceRow = { |sl, sk, density, depth|
    density = (density ? ~cfg_net.diceDensity) * 4;
    ~netAllDst.value.do { |b|
        ~netPut.(sl, sk, b[0], b[1], if(density.coin) { ~netRandDepth.(depth ? ~cfg_net.diceDepth) } { 0 });
    };
    ~netChanged.value;
};
~netDiceCol = { |dl, dk, density, depth|
    density = (density ? ~cfg_net.diceDensity) * 4;
    ~netAllSrc.value.do { |a|
        ~netPut.(a[0], a[1], dl, dk, if(density.coin) { ~netRandDepth.(depth ? ~cfg_net.diceDepth) } { 0 });
    };
    ~netChanged.value;
};
~netClearRow = { |sl, sk|
    ~netCells.values.select { |c| c[\src] == [sl, sk] }
        .do { |c| ~netPut.(sl, sk, c[\dst][0], c[\dst][1], 0) };
    ~netChanged.value;
};
~netClearCol = { |dl, dk|
    ~netCells.values.select { |c| c[\dst] == [dl, dk] }
        .do { |c| ~netPut.(c[\src][0], c[\src][1], dl, dk, 0) };
    ~netChanged.value;
};

~netShake = { |amt|
    amt = amt ? ~cfg_net.driftAmt;
    ~netCells.values.do { |c|
        ~netPut.(c[\src][0], c[\src][1], c[\dst][0], c[\dst][1],
            c[\depth] + (amt * rrand(-1.0, 1.0)));
    };
    ~netChanged.value;
};
~netMutate = { |n, depth|
    var cells = ~netCells.values.asArray, srcs = ~netAllSrc.value, dsts = ~netAllDst.value;
    n = n ? (cells.size * 0.1).ceil.asInteger.max(1);
    cells.scramble.keep(n.min(cells.size)).do { |c|
        ~netPut.(c[\src][0], c[\src][1], c[\dst][0], c[\dst][1], 0);
    };
    n.do {
        var a = srcs.choose, b = dsts.choose;
        if(a != b) { ~netPut.(a[0], a[1], b[0], b[1], ~netRandDepth.(depth ? ~cfg_net.diceDepth)) };
    };
    ~netChanged.value;
};

~netWander = { |amt, rate|
    amt  !? { ~cfg_net.wander = amt.clip(0, 1) };
    rate !? { ~cfg_net.wanderRate = rate.clip(0.001, 400) };
    ~netGroup !? { |g| g.set(\wander, ~cfg_net.wander, \wrate, ~cfg_net.wanderRate) };
};

~netDrift = { |on = true|
    ~netDriftTask !? { |t| t.stop };
    ~netDriftTask = nil;
    if(on) {
        ~netDriftTask = Routine({
            loop {
                ~netShake.(~cfg_net.driftAmt);
                if(0.3.coin) { ~netMutate.(1) };
                (~cfg_net.driftPeriod * exprand(0.5, 2.0)).wait;
            }
        }).play(AppClock);
    };
    ~netDriftTask.notNil
};


// ----- presets: base values + levels + the matrix, one file -----
~ungPresetDir = {
    var root = ~ungPresetRoot;
    if(File.exists(root).not) { File.mkdir(root) };
    root
};
~listPresets = {
    (~ungPresetDir.value +/+ "*.scd").pathMatch
        .collect { |p| PathName(p).fileNameWithoutExtension }.sort
};
~savePreset = { |name|
    var path, e, ls = ();
    name = (name ? "").asString;
    if(name.isEmpty) { name = "net_" ++ Date.getDate.stamp };
    path = ~ungPresetDir.value +/+ (name ++ ".scd");
    ~netLayers.value.do { |l|
        var d = ();
        ~ungSpecOf.(l).params.do { |p| d[p.key] = ~netGet.(l, p.key) };
        ls[l] = d;
    };
    e = (
        layers: ls,
        mixer:  ~cfg_mixer !? { |m| (
            master: m.master,
            levels: m.levels.collect(_.copy),
            muted:  (~mixMuted ? ()).keys.asArray.select { |l| ~mixMuted[l] == true },
            solo:   ~mixSoloCur
        ) },
        fx:     ~cfg_effects !? { |fx| (
            rev_mode: fx.rev_mode, dly_mode: fx.dly_mode, bass: fx.rev_bass, treble: fx.rev_treble
        ) },
        wander: [~cfg_net.wander, ~cfg_net.wanderRate],
        cells:  ~netCells.values.asArray.collect { |c| c[\src] ++ c[\dst] ++ [c[\depth]] }
    );
    File.use(path, "w", { |f|
        f.write("// net preset · " ++ name ++ " · " ++ Date.getDate.stamp ++ "\n"
            ++ e.asCompileString ++ "\n");
    });
    ("preset saved -> " ++ path).postln;
    path
};
~loadPreset = { |name|
    var path = ~ungPresetDir.value +/+ (name.asString ++ ".scd"), e;
    if(File.exists(path).not) { ("preset не найден: " ++ path).warn; nil } {
        e = path.load;
        if(e.isKindOf(Event).not) { ("preset повреждён: " ++ path).warn; nil } {
            e[\layers] !? { |ls|
                ls.keysValuesDo { |l, vals|
                    if(~ungSpecOf.(l).notNil) {
                        vals.keysValuesDo { |k, v| if(~netParam.(l, k).notNil) { ~setParam.(l, k, v) } };
                    };
                };
            };
            e[\mixer] !? { |m|
                if(~mixSet.notNil) {
                    m[\levels] !? { |rows|
                        rows.keysValuesDo { |l, lv|
                            if((~mixerLayers ? []).includes(l.asSymbol)) {
                                lv.keysValuesDo { |which, v| ~mixSet.(l.asSymbol, which, v) };
                            };
                        };
                    };
                    m[\master] !? { |v| ~masterSet.(v) };
                    m[\muted] !? { |ml|
                        ~mixMuted = ();
                        ml.do { |l| ~mixMuted[l.asSymbol] = true };
                        ~mixSoloCur = m[\solo] !? (_.asSymbol);
                        ~mixApplyLevels.value;
                        ~mixerRefreshMute.value;
                        ~mixerRefreshSolo.value;
                    };
                };
            };
            e[\fx] !? { |fx|
                if(~cfg_effects.notNil) {
                    [
                        [\rev_mode, \mode,   [\space_echo_rev], [\rev_mode]],
                        [\dly_mode, \mode,   [\space_echo_dly], [\dly_mode]],
                        [\bass,     \bass,   [\space_echo_rev, \space_echo_dly], [\rev_bass, \dly_bass]],
                        [\treble,   \treble, [\space_echo_rev, \space_echo_dly], [\rev_treble, \dly_treble]]
                    ].do { |row|
                        fx[row[0]] !? { |v|
                            row[2].do { |n| Ndef(n).set(row[1], v) };
                            row[3].do { |k| ~cfg_effects[k] = v };
                        };
                    };
                    ~mixerFx !? { |wid|
                        wid[\revMode] !? { |p| ~uiPopupSet.(p, (~cfg_effects.rev_mode - 1).clip(0, 11)) };
                        wid[\dlyMode] !? { |p| ~uiPopupSet.(p, (~cfg_effects.dly_mode - 1).clip(0, 11)) };
                        wid[\bass]    !? { |r| ~uiRulerSet.(r, ~cfg_effects.rev_bass) };
                        wid[\treble]  !? { |r| ~uiRulerSet.(r, ~cfg_effects.rev_treble) };
                        { wid[\dlyGlyph] !? (_.refresh); wid[\revGlyph] !? (_.refresh) }.defer;
                    };
                };
            };
            e[\wander] !? { |w| ~netWander.(w[0], w[1]) };
            e[\cells]  !? { |cs|
                ~netClear.(false);
                cs.do { |c| ~netPut.(c[0], c[1], c[2], c[3], c[4]) };
            };
            ~netChanged.value;
            ~netHooks.do { |f| f.(nil, nil, nil) };
            ("preset loaded <- " ++ path.basename).postln;
            e
        }
    }
};

"0_lib — поле готово (~netDice, ~netSet, ~openMatrix, ~openMachines).".postln;
)
