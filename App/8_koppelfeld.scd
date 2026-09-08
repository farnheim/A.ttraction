// App/8_koppelfeld.scd — UNGRUND · KOPPELFELD: one node proxy per parameter,
// 111 across the five layers; a cable lives INSIDE its destination node.
// Node law (§3.1), in the node's own normalized ControlSpec space:
//   x = curve( rest + hand + arm · Σ pol·gain·lag_τ(x_src − rest_src) )
//   value = spec.map(x)                    — exactly ONE channel per control.
// All 111 params are proxied, not only destinations: `n_set` silently drops
// `n_mapa`, so partial proxying would tear the scheme on any ~setParam.
// Stage S2: cables, band/τ, window, clip/fold, arm/disarm, ~kfApply/~kfCut,
// registries, ~kfLambda, validator V1–V13, ~kfPoke.
// Stage S3: curve `step` for the 20 pitch nodes (class P) — ~kfLattice (94 Hz,
// 3-limit), position table per node, hysteresis, dwell, cut ≤ 30 ms.
// Stage S4: the §9.2 proxy meter and the §12.1 live logger.
// Stage S5: the patcher — ~kfGraphFacts, the eight steps of §6, the ordered
// repair, ~kfDeriveScheme/~kfRandomize; the SAME law ~konDerive enters (§17 D85).
// Stage S6: the `patch:` section of a preset (§8.2) — the module owns the
// format, 0_lib only writes the string; live gain ~kfGainSet.
// Stage S7 (the §9 window) lives in 8b_kfwindow.scd, which loads right after.
// Buses: 111 node audio (1 ch) + 1 control for arm; §3.7 — 5x headroom.
// Loads AFTER 0_grid (alphabet: ~gridClassOrder / ~gridLayerOf) and the layers
// (~ungSpecs), and BEFORE the mixer.
// Spec: plans/active/patchbay-koppelfeld.md (§3–§5, §10, §16).


// ===== CONFIG — edit here ============================================
(
~cfg_kf = (
    nodeFade:      0.05,   // node proxy fadeTime, s (§3.3)
    handSlew:      0.02,   // s: slew floor of the rest/hand path (B-4)
    armTime:       4,      // default T_arm, s; score range 0–30 (§10.2)
    selfTestDur:   4.0,    // s: peak-hold window in ~kfSelfTest
    selfTestRetry: 3,      // retry window multiplier for a silent layer
    selfTestFloor: -90,    // dBFS: peak below this counts as silence

    gainAbsMax:    4.0,    // §3.1 absolute gain ceiling, before the class one
    gainMin:       0.08,   // §4.2 lower edge of a routed cable
    fanIn:         3,      // §4.2 inputs per node
    fanOut:        5,      // §4.2 outputs per node
    cableMin:      8,      // §4.2 cable-count floor (NOTE, not a rejection)
    cableMax:      64,     // §4.2 cable-count ceiling (rejection)
    depthMax:      4,      // §4.3 V5: longest path
    ladderRatio:   2.5,    // §4.3 V6: ratio of adjacent τ along a path
    restMargin:    0.1,    // §4.3 V7: rest margin from the window edge
    lamMax:        3.0,    // §4.2 global loop-gain ceiling
    loopExcMax:    3,      // §4.2 excited loops (Λ ≥ 1)
    modeUmlauf:    1.0,    // §4.4 ruhe → umlauf threshold (analytic, D-13)
    modeWanderung: 1.6,    // §4.4 umlauf → wanderung threshold
    incommTol:     0.03,   // §4.4 forbidden neighbourhood around p/q
    incommMax:     4,      // §4.4 p, q ≤ this
    interlayerMin: 0.6,    // §4.3 V10 interlayer cable share

    pHyst:         0.2,    // §3.6 step hysteresis, share of the position gap
    pHystMax:      0.5,    // …and its ceiling: half a gap is a dead band edge to edge
    pDwell:        20,     // §3.6 dwell, s: a step reads as a block, not a move
    pCut:          0.03,   // §3.6 cut, s: dF/dt = 0 between steps
    pPosMax:       5,      // §3.6 positions a scheme window may admit
    pPosMin:       2,      // fewer than two: the cable can never step
    latB:          4,          // 94 · 2^a · 3^b, |b| ≤ this — 3-limit, x5 unreachable
                               // by construction; `a` is bounded by the Hz range only

    // --- §6/§7 the patcher: ~kfRandomize.(seed, c) ---
    kappa:         4,      // §6 step 1: cables per census edge (score constant)
    patchTtier:    30,     // s: T_tier the derivation reads the drawing with (τ_cell = T_tier/rowGap)
    patchRate:     450,    // §6 step 4: f_c = patchRate / (routeLen^γ · τ_cell), Hz·s
    patchGamma:    2.2,    // …and its exponent: routeLen spans x30, the ladder x30000
    patchNarrow:   2,      // f_c lives inside [lo·n, hi/n] of its band — the ×2.5 ladder BY CONSTRUCTION
    patchIntraMax: 0.35,   // §6 step 2: share of intra-layer cables (reference: ≤ 40 %)
    patchGainLo:   0.35,   // §6 step 6: depthGain at c = 0 …
    patchGainHi:   1.10,   // … and at c = 1
    patchLamLo:    0.60,   // §4.4 Λ target of a drawn loop at c = 0 (ruhe) …
    patchLamHi:    2.60,   // … and at c = 1 (wanderung); ≤ lamMax by construction
    patchLoopMax:  3,      // drawn loops taken into one scheme
    patchPeriodScales: [1, 1.12, 1.26, 0.89, 1.41, 0.79, 1.59, 0.71, 0.63],
                           // deterministic scan that pulls loop periods apart (V8)
    patchWinLo:    0.10,   // window floor …
    patchWinSpan:  0.20,   // … its scramble span …
    patchWinWidth: 0.55,   // … and its width; the top stays ≤ 0.85
    patchWinMin:   0.25,   // narrower than this and the node is not a destination at all
    patchRestLo:   0.15,   // §6: the rest of a destination, scrambled inside …
    patchRestHi:   0.85,   // … this range and then pulled into the window
    patchLDb:      3,      // dB: §5.1 an L window is ±3 dB around the §K.4 level
    patchPosWin:   3,      // positions of the lattice a P window admits (V7 wants 2–5)
    patchPosGap:   0.25,   // …and how far past the outer ones it opens, in shares of the smallest gap
    patchEpsGap:   0.001,  // §C.5: the gap a derived epsilon window keeps from its partner's edge (V12)
    patchSeedTries: 8,     // deterministic seed walk when ~gridGenerate refuses
    patchRepairMax: 6      // repair passes before the patcher refuses whole
);


// ===== LOGIC — canon, nodes, cables, Λ, validator, arm, self-test ====

// ----- §4.2 ceilings BY DESTINATION CLASS ------------------------------
~kfClass = (
    L: ( gain: 0.30, bands: [\block],                         curve: [\clip] ),
    // reference 5.1 leaves the P gain as "— (step mode)": the ceiling that
    // matters is the position table, not the slope. 1.0 lets a full-scale
    // source deviation cross the whole window and no more
    P: ( gain: 1.0,  bands: [\block],                         curve: [\step] ),
    S: ( gain: 1.6,  bands: [\rauheit, \puls, \gang, \block], curve: [\clip, \fold] ),
    D: ( gain: 1.2,  bands: [\rauheit, \puls, \gang, \block], curve: [\clip] ),
    W: ( gain: 1.4,  bands: [\puls, \gang, \block],           curve: [\clip, \fold] ),
    E: ( gain: 1.0,  bands: [\gang, \block],                  curve: [\clip] ),
    G: ( gain: 0.6,  bands: [\block],                         curve: [\clip] ),
    M: ( gain: 2.0,  bands: [\rauheit, \puls, \gang, \block], curve: [\clip, \fold] )
);
~kfBand = ( rauheit: [8, 120], puls: [0.5, 8], gang: [0.05, 0.5], block: [0.004, 0.05] );
// a drawn loop runs only through classes whose curve may FOLD: the fold corner
// is what keeps a cycle inside its window, so the two lists are one list
~kfLoopClasses = ~kfClass.keys.asArray
    .select { |c| ((~kfClass[c][\curve]) ? []).includes(\fold) };
// §13 q5: fold only in gang/block — a Fold corner in B1 (8–120 Hz) throws
// sidebands at 16–240 Hz that no §C card has material for
~kfFoldBands = [\gang, \block];

// SR/(8·blockSize) = ControlRate/8: a cable filter cannot live faster than one
// block. The node body clamps f_c to the same value, so the validator MUST
// reject anything above it — else analysis τ (Λ, loop period, V6 ladder)
// diverges from the τ of the live Lag
~kfFcCeil = {
    var sr = (s.sampleRate ? s.options.sampleRate) ? 44100;
    sr / (8 * (s.options.blockSize ? 64))
};

// `reread` event names that are DELIBERATELY not layer parameters; anything
// else dangling is a typo or a rename, and ~kfTableAudit rejects it
~kfRereadEvents = [\fragment];

// ----- §5.1–5.5: §F class and band ceiling f_max for each of the 111 nodes.
// `~spec_<class>` rows do not carry these fields (the layer has no use for
// them), so the table lives here; ~kfTableAudit reconciles it with ~ungSpecs.
// Format: key: [ class, f_max Hz ] or [ class, f_max, ( extra invariants ) ];
// `wmin`/`wmax` — node window bounds, `gmax` — destination gain ceiling,
// `inv` — reread is given as a PERIOD, not a rate (f_max = 1/(2·win_hi)).
~kfNodeTable = (
    alpha: (
        n1: [\P, 0.05], n2: [\P, 0.05], n3: [\P, 0.05], n4: [\P, 0.05], n5: [\P, 0.05],
        n6: [\P, 0.05], n7: [\P, 0.05], n8: [\P, 0.05], n9: [\P, 0.05], n10: [\P, 0.05],
        amp: [\L, 0.05],
        density: [\D, 8],
        contact: [\M, 8],
        decay: [\E, 0.5],
        disperse: [\M, 8],
        oil: [\M, 8],
        muffle: [\M, 8],
        bright: [\S, 8],
        metalAmt: [\M, 8],
        metalRing: [\E, 0.5],
        metalWeight: [\M, 8],
        bodyLevel: [\M, 8],
        drive: [\M, 8, ( wmax: 0.667 )],
        sprGain: [\M, 8],
        swayRate: [\D, 0.01],
        cutTop: [\S, 8],
        cutOil: [\S, 8]
    ),
    delta: (
        f1: [\P, 0.05], f2: [\P, 0.05], f3: [\P, 0.05], f4: [\P, 0.05], f5: [\P, 0.05],
        amp: [\L, 0.05],
        voiced: [\M, 2], breath: [\M, 2], shimmer: [\M, 2], ring: [\M, 2],
        metal: [\M, 2], breathDepth: [\M, 2], voiceLevel: [\M, 2],
        bright: [\S, 0.25],
        detune: [\W, 0.25],
        driftRate: [\D, 0.01],
        jitter: [\W, 0.25],
        vowelSel: [\S, 0.25],
        vowelDrift: [\S, 0.25],
        formWidth: [\W, 0.25],
        formTrack: [\S, 0.25],
        beatRate: [\D, 0.025],
        plateQ: [\E, 0.25],
        plateSpread: [\W, 0.25],
        breathRate: [\D, 0.01],
        panWidth: [\G, 0.05],
        panRate: [\G, 0.005]
    ),
    epsilon: (
        freqLo: [\S, 0.45], freqHi: [\S, 0.45],
        m1: [\P, 0.05], m2: [\P, 0.05], m3: [\P, 0.05], m4: [\P, 0.05],
        flowCeil: [\S, 0.45],
        mLevel: [\M, 0.45, ( wmin: 0.1 )],
        mWidth: [\W, 0.1, ( wmax: 0.811 )],
        mBreath: [\D, 0.01],
        flowLevel: [\M, 0.45, ( wmin: 0.1 )],
        diffDepth: [\M, 0.45],
        streakLevel: [\M, 0.45, ( wmin: 0.1 )],
        streakWidth: [\W, 0.45],
        driftPeriod: [\D, 0.45, ( inv: true )],
        surfDepth: [\M, 0.45],
        surfRate: [\D, 0.025],
        decorrWidth: [\G, 0.05],
        amp: [\L, 0.05]
    ),
    zeta: (
        bedHpf: [\S, 30], bedLpf: [\S, 30], bedHumpFreq: [\S, 30], subFreq: [\S, 30],
        fineHpf: [\S, 30], popHpf: [\S, 30],
        bodyFreq: [\S, 0.1],
        amp: [\L, 0.05],
        bedAmp: [\M, 30], bedHumpAmt: [\M, 30], bedDriftDepth: [\M, 30],
        subAmt: [\M, 30], fineAmt: [\M, 30], popAmt: [\M, 30], bodyAmt: [\M, 30],
        bedHumpRq: [\W, 8],
        bedDriftRate: [\D, 0.01],
        fineRate: [\D, 2.5],
        fineDecay: [\E, 0.5],
        fineAmpMin: [\M, 2.5],
        popRate: [\D, 0.1],
        popDecay: [\E, 0.1],
        popAmpMin: [\M, 0.1],
        bodyRing: [\E, 0.1],
        panWidth: [\G, 0.05],
        panRate: [\G, 0.01]
    ),
    theta: (
        fragOct: [\P, 0.05],
        ioi0: [\D, 0.17, ( gmax: 0.6 )],
        decel: [\D, 0.17, ( gmax: 0.6 )],
        ioiMax: [\D, 0.17, ( gmax: 0.6 )],
        popScale: [\D, 0.17, ( gmax: 0.6 )],
        gapScale: [\D, 0.17, ( gmax: 0.6 )],
        density: [\D, 0.17, ( gmax: 0.6 )],
        edgeWidth: [\W, 0.5],
        edgeAmp: [\M, 0.5],
        decayScale: [\E, 0.5],
        spread: [\G, 0.05],
        amp: [\L, 0.05]
    )
);

// ----- addressing and access -------------------------------------------
~kfNodeKey = { |layer, key| ("kf_" ++ layer ++ "_" ++ key).asSymbol };
~kfIdOf    = { |layer, key| (layer.asString ++ "." ++ key.asString).asSymbol };
~kfRow     = { |layer, key| (~kfNodeTable[layer.asSymbol] ? ())[key.asSymbol] };

~kfParamOf = { |layer, key|
    var sp = ~ungSpecs[layer.asSymbol];
    sp !? { sp.params.detect { |p| p[\key] == key.asSymbol } };
};
~kfSpecOfNode = { |layer, key| ~kfParamOf.(layer, key) !? { |p| p[\spec] } };
~kfRereadOf   = { |layer, key| (~kfParamOf.(layer, key) !? { |p| p[\reread] }) ? \cont };

~kfGainMax = { |layer, key|
    var row = ~kfRow.(layer, key);
    if(row.isNil) { 0 } {
        var g = min((~kfClass[row[0]] ? ())[\gain] ? 0, ~cfg_kf.gainAbsMax);
        min(g, (row[2] ? ())[\gmax] ? g);
    };
};

// §5: for seg/event nodes the ceiling is DYNAMIC — half the SLOWEST reread
// rate reachable in this scheme (the lower window bound of the rate node).
// An `inv` node declares a PERIOD: the wider the window up, the rarer the read.
~kfFmaxOf = { |layer, key, wins|
    var row = ~kfRow.(layer, key);
    if(row.isNil) { nil } {
        var f  = row[1];
        var ex = row[2] ? ();
        var rr, rk, rcs, rw;
        if(ex[\inv] == true) {
            var cs = ~kfSpecOfNode.(layer, key);
            if(cs.notNil) {
                var hi = cs.map(((wins ? ())[~kfIdOf.(layer, key)] ? [0, 1])[1]);
                if(hi > 0) { f = min(f, 1 / (2 * hi)) };
            };
        } {
            rr = ~kfRereadOf.(layer, key);
            if(rr.isArray) {
                rk = rr[1];
                if(rk.isNumber) {
                    f = min(f, rk / 2);
                } {
                    rcs = ~kfSpecOfNode.(layer, rk);
                    if(rcs.notNil) {
                        rw = ((wins ? ())[~kfIdOf.(layer, rk)] ? [0, 1]);
                        f = min(f, rcs.map(rw[0]) / 2);
                    };
                };
            };
        };
        f
    };
};

// ----- §3.6: the 94 Hz lattice and the position table of a P node -------
// 94 · 2^a · 3^b only: the major third (x5) is excluded BY CONSTRUCTION, which
// is what closes metric C-6 — there is no state of the field in which a pitch
// node can land on 470 / 940 / 1880 / 4700 Hz
~kfLattice = { |loHz, hiHz|
    var out = [];
    var lo = max(loHz, 1e-6);
    (~cfg_kf.latB.neg .. ~cfg_kf.latB).do { |b|
        var f0 = 94 * (3 ** b);
        // the octave exponent is bounded BY THE Hz RANGE, never by a constant:
        // a fixed |a| ceiling drops the outer 3^±4 columns of the top and bottom
        // octaves, and ~kfWinPos would then return a different number of
        // positions for the SAME interval in a different register — V7 would
        // accept or reject one window depending on its octave
        var aLo = (lo / f0).log2.floor.asInteger - 1;
        var aHi = (hiHz / f0).log2.ceil.asInteger + 1;
        if(aHi >= aLo) {
            (aLo .. aHi).do { |a|
                var f = 94 * (2 ** a) * (3 ** b);
                if(f >= loHz and: { f <= hiHz }) { out = out.add(f) };
            };
        };
    };
    out = out.sort;
    // unique factorization makes duplicates impossible; the filter states the
    // invariant instead of trusting it
    out.select { |f, i| (i == 0) or: { (f - out[i - 1]).abs > (f * 1e-9) } };
};

// The FULL table of a P node, in NORMALIZED coordinates, sorted:
//  · a stepped spec publishes its own grid (theta.fragOct — §C.8 whole octave);
//  · alpha carries its own score table (reference 10.1, open question 1): the
//    spring tones are the DEFAULTS of its own P rows, so the score stays the
//    single source of truth instead of a second copy here;
//  · everything else is the lattice inside the spec range. P specs are in MIDI
//    notes, so the lattice is built in Hz and converted before unmap.
~kfNodePos = { |layer, key|
    var p = ~kfParamOf.(layer, key);
    var row = ~kfRow.(layer, key);
    if(p.isNil or: { row.isNil } or: { row[0] != \P }) { nil } {
        var cs = p[\spec], vals;
        case
        { cs.step > 0 } {
            vals = (cs.minval, cs.minval + cs.step .. cs.maxval);
        }
        { layer.asSymbol == \alpha } {
            vals = ~ungSpecs[\alpha].params
                .select { |q| (~kfRow.(\alpha, q[\key]) !? { |r| r[0] }) == \P }
                .collect { |q| q[\spec].default }.sort;
        }
        { p[\disp] == \note } {
            vals = ~kfLattice.(cs.minval.midicps, cs.maxval.midicps).collect(_.cpsmidi);
        }
        {
            ("8_koppelfeld — P-узел " ++ layer ++ "." ++ key
                ++ ": спек не ступенчатый и не в нотах, таблица решётки не выводится").error;
            vals = nil;
        };
        vals !? {
            vals.collect { |v| cs.unmap(v) }
                .select { |x| (x >= 0) and: { x <= 1 } }.sort
        };
    };
};

// positions the SCHEME window admits (reference 5.1: ≤ 5 of them)
~kfWinPos = { |layer, key, win|
    var w = win ? [0, 1];
    (~kfNodePos.(layer, key) ? []).select { |x| (x >= w[0]) and: { x <= w[1] } };
};

// ----- §5.1: the window of a LEVEL node is relative -------------------
// ONE reading of "the live value of a node": the rest of its node proxy, which
// is what the §C.5 guards of ~kfValidate read (D78). A node that is not built
// yet answers with its spec default, exactly as the validator does.
~kfLiveRest = { |layer, key|
    var n = ((~kfNodes ? ())[layer.asSymbol] ? ())[key.asSymbol];
    if(n.notNil) { n[\rest] } {
        (~kfSpecOfNode.(layer, key) !? { |cs| cs.unmap(cs.default) }) ? 0.5
    };
};

// ±db around a value, in the node's own normalized space. ONE formula, two
// contexts: the derivation applies it to the SPEC DEFAULT (pure, D78), every
// reader of a live window applies it to the live rest.
~kfWinRel = { |cs, v, db|
    var v0 = max(1e-9, cs.map(v));
    var lo = cs.unmap(max(cs.minval, v0 / db.dbamp));
    var hi = cs.unmap(min(cs.maxval, v0 * db.dbamp));
    var need = 2 * ~cfg_kf.restMargin;
    // a level parked ON the floor or ceiling of its spec materializes a window
    // narrower than V7's own floor — or empty. The window then opens to that
    // floor AROUND the live level instead of passing V7 in silence (§17 D91);
    // ~kfValidate says so with a NOTE
    if((hi - lo) < need) {
        var x = v.clip(0, 1);
        lo = (x - (need * 0.5)).clip(0, max(0, 1 - need));
        hi = lo + need;
    };
    [lo.clip(0, 1), hi.clip(0, 1)]
};

// THE materialization point of a cable's window. A cable of class L carries the
// RULE (`winRel` + `winDb`), not a pair of numbers: the derivation may not read
// the live field (D78), while the level of a layer belongs to the hand and the
// preset (reference §6). Every reader of a window goes through here.
~kfWinAbs = { |layer, key, cable|
    var cs = ~kfSpecOfNode.(layer, key);
    if((cable !? { |c| c[\winRel] }) != true or: { cs.isNil }) {
        (cable !? { |c| c[\win] }) ? [0, 1]
    } {
        ~kfWinRel.(cs, ~kfLiveRest.(layer, key), (cable[\winDb] ? ~cfg_kf.patchLDb).abs)
    };
};

// ----- registries ------------------------------------------------------
~kfNodes     = ~kfNodes     ? ();   // \layer -> ( \param -> ( node: spec: rest: win: curve: cables: bus: ) )
~kfCables    = ~kfCables    ? [];   // applied cable table (§4.1 events)
~kfFanOut    = ~kfFanOut    ? ();   // \layer -> ( \param -> [ ( dst: [l,k], slot: i ) ] ) — reverse edges
~kfSchaltung = ~kfSchaltung;        // the applied scheme
~kfVerdict   = ~kfVerdict;          // validator verdict of the last ~kfApply
~kfVerdictStale = ~kfVerdictStale ? false;   // …and whether a hand edit outdated it
~kfArmed     = ~kfArmed ? false;
// ~kfRestApply rebuilds a step body so the bus follows the new rest at once;
// the builders below write rest and build the body themselves, and set this
~kfRestQuiet = ~kfRestQuiet ? false;

// ----- arm: ONE kr proxy for the whole field (§10.2) -------------------
~kfArmBus = {
    if(Ndef(\kf_arm).source.isNil) {
        Ndef(\kf_arm, { \g.kr(0).varlag(\t.kr(~cfg_kf.armTime)) });
        // fadeTime 0: varlag drives the ramp, a proxy crossfade would double it
        Ndef(\kf_arm).fadeTime = 0;
        Ndef(\kf_arm).wakeUp;
    };
    Ndef(\kf_arm).bus !? { |b| b.index };
};

~kfArm = { |t|
    t = t ? ~cfg_kf.armTime;
    ~kfArmBus.value;
    // \t BEFORE \g in one bundle: VarLag reads the time when its input changes
    Ndef(\kf_arm).set(\t, t, \g, 1);
    ~kfArmed = true;
    t
};

~kfMaxTau = {
    var taus = ~kfCables.select { |c| c[\enabled] != false }.collect { |c| 1 / (2pi * c[\fc]) };
    if(taus.isEmpty) { 0 } { taus.maxItem };
};

~kfRelease = { |layer, key|
    ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        if((layer.isNil or: { l == layer.asSymbol })
            and: { key.isNil or: { k == key.asSymbol } }) {
            Ndef(n[\node]).set(\hand, 0);
        };
    }};
};

// releaseHand: false — drop the gain WITHOUT dropping the hand. ~kfApply goes
// this way: a scheme change (~kfCut on a form boundary included) is not a
// release, and ~kfPoke is the only entry for the live hand — losing it on every
// boundary would erase the performer with a step mid-sound
~kfDisarm = { |t, releaseHand = true|
    t = t ? ~cfg_kf.armTime;
    ~kfArmBus.value;
    Ndef(\kf_arm).set(\t, t, \g, 0);
    ~kfArmed = false;
    // cancelled unconditionally: with releaseHand false the hand STAYS, and a
    // release armed by an EARLIER disarm would otherwise land mid-~kfApply and
    // wipe the performer anyway — exactly what the flag promises not to do
    ~kfHandTask !? { |tk| tk.stop }; ~kfHandTask = nil;
    if(releaseHand) {
        // the hand goes AFTER the gain: for T + max τ the cables still carry the
        // old deviation, and an instant hand reset would step through them
        ~kfHandTask = fork { (t + ~kfMaxTau.value).wait; ~kfRelease.value; ~kfHandTask = nil };
    };
    t
};

// ~kfPoke — the ONLY entry for the live hand (§3.2): rest is silent downstream
// because d = x − rest does not change when rest moves
~kfPoke = { |layer, key, delta|
    var n = (~kfNodes[layer.asSymbol] ? ())[key.asSymbol];
    if(n.isNil) {
        ("8_koppelfeld — ~kfPoke: нет узла " ++ layer ++ "." ++ key).warn; nil
    } {
        Ndef(n[\node]).set(\hand, delta);
        delta
    };
};

// ----- node rest -------------------------------------------------------
~kfRestOf = { |layer, p|
    var v = (~ungVals[layer] ? ())[p[\key]] ? p[\spec].default;
    p[\spec].unmap(v).clip(0, 1);
};

// a DESTINATION rest must sit inside the window with the V7 margin: the node
// body clips anyway, but ~ungVals, the tuner and ~savePreset would store the
// unclipped value and the preset would stop reproducing what sounds. A node
// without cables has no window, so no margin applies to it
~kfRestBounds = { |n, layer, key|
    if(n[\cables].isEmpty) { [0, 1] } {
        // a step node is bounded by its POSITIONS, not by the window margin: the
        // margin keeps a clipping node off its dead edge, while a step node at
        // its lowest position is still free to step up. Five positions of the
        // 94 Hz lattice span ≈ 0.15 of a pitch spec — narrower than 2·restMargin,
        // so the margin rule would make every legal P window unreachable
        var ps = if(n[\curve] == \step and: { layer.notNil }) {
            ~kfWinPos.(layer, key, n[\win])
        } { [] };
        if(ps.notEmpty) { [ps.first, ps.last] } {
            // a RELATIVE window is measured in dB around the live level, and the
            // level sits at its centre by construction: the normalized margin is
            // a different metric, and applying it here would pull the level of
            // the layer off the value the hand and the preset set (§17 D91)
            if(n[\winRel] == true) { n[\win] } {
                var lo = n[\win][0] + ~cfg_kf.restMargin;
                var hi = n[\win][1] - ~cfg_kf.restMargin;
                if(lo > hi) { var m = (n[\win][0] + n[\win][1]) * 0.5; [m, m] } { [lo, hi] };
            };
        };
    };
};

// footgun 7: a source rest is DUPLICATED into every outgoing cable (\rN).
// The drift is inaudible but breaks the null test and shifts the destination
// rest point — hence exactly one writer, updating both sides via ~kfFanOut.
~kfRestApply = { |layer, key, rn|
    var n = (~kfNodes[layer.asSymbol] ? ())[key.asSymbol];
    if(n.isNil) { nil } {
        var b = ~kfRestBounds.(n, layer.asSymbol, key.asSymbol);
        n[\rest] = rn.clip(b[0], b[1]);
        // a P destination is quantized in the graph, so its rest is snapped here
        // too: otherwise ~ungVals, the tuner and the preset would carry an aim
        // that no reachable state of the node ever sounds. Only positions that
        // satisfy the V7 margin are eligible, or the next validate would reject
        // the very rest this function just installed
        if(n[\curve] == \step) {
            var ps = ~kfWinPos.(layer, key, n[\win]);
            if(ps.notEmpty) { n[\rest] = ps.minItem { |x| (x - n[\rest]).abs } };
        };
        Ndef(n[\node]).set(\rest, n[\rest]);
        ((~kfFanOut[layer.asSymbol] ? ())[key.asSymbol] ? []).do { |e|
            var dn = (~kfNodes[e[\dst][0]] ? ())[e[\dst][1]];
            dn !? { Ndef(dn[\node]).set(("r" ++ e[\slot]).asSymbol, n[\rest]) };
        };
        // a step body BAKES the index of its start position from the rest it sees
        // at build time, and its dwell sweep restarts with it (D32): a bare
        // \rest write would leave the bus on the old position for up to dwell
        // seconds while ~ungVals, the tuner and a preset taken now show the new
        // one. The builders write rest and rebuild the body themselves — they
        // raise ~kfRestQuiet instead of paying for the build twice
        if((n[\curve] == \step) and: { n[\bus].notNil } and: { ~kfRestQuiet.not }) {
            ~kfNodeBody.(layer.asSymbol, key.asSymbol);
        };
        n[\rest]
    };
};

// returns the ACCEPTED value in real units (not the requested one), nil when
// there is no node: ~ungVals must hold what sounds, not what was asked for
~kfRest = { |layer, key, v|
    var cs = ~kfSpecOfNode.(layer, key);
    if(cs.isNil) { nil } {
        var rn = ~kfRestApply.(layer, key, cs.unmap(v));
        rn !? { cs.map(rn) }
    };
};

// the node owns the control; ~setParam (0_lib) must route here or Ndef.set
// drops the mapping. Returns the accepted number, nil = not our node.
~kfRestSet = { |layer, key, v| ~kfRest.(layer, key, v) };

// ----- wiring: destination cables, window, curve ------------------------
~kfWireOf = { |layer, key|
    var id = ~kfIdOf.(layer, key);
    var mine = ~kfCables.select { |c|
        (c[\enabled] != false) and: { ~kfIdOf.(c[\dst][0], c[\dst][1]) == id };
    };
    var win = if(mine.isEmpty) { [0, 1] } { ~kfWinAbs.(layer, key, mine[0]) };
    var winRel = mine.notEmpty and: { mine[0][\winRel] == true };
    var curve = if(mine.isEmpty) { \clip } { (mine[0][\curve] ? \clip) };
    var isP = (~kfRow.(layer, key) !? { |r| r[0] }) == \P;
    // V9: a convergence node must clip — a fold over the sum of three cables
    // reflects the already-summed signal and loses each contribution
    if(mine.size >= 2) { curve = \clip };
    // …but a P node is quantized whatever its fan-in: the forced clip above
    // would put a pitch node back on a continuum, and reference 3.1 forbids
    // addressing class P as a continuous value in ANY reachable state
    if(isP and: { mine.notEmpty }) { curve = \step };
    (
        cables: mine, win: win, winRel: winRel, curve: curve,
        hyst:  if(mine.isEmpty) { ~cfg_kf.pHyst  } { mine[0][\hyst]  ? ~cfg_kf.pHyst  },
        dwell: if(mine.isEmpty) { ~cfg_kf.pDwell } { mine[0][\dwell] ? ~cfg_kf.pDwell },
        cut:   if(mine.isEmpty) { ~cfg_kf.pCut   } { mine[0][\cut]   ? ~cfg_kf.pCut   }
    )
};

~kfFanOutBuild = {
    ~kfFanOut = ();
    ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        n[\cables].do { |c, i|
            var sl = c[\src][0].asSymbol, sk = c[\src][1].asSymbol;
            if(~kfFanOut[sl].isNil) { ~kfFanOut[sl] = () };
            ~kfFanOut[sl][sk] = (~kfFanOut[sl][sk] ? []).add(
                ( dst: [l, k], slot: i )
            );
        };
    }};
};

// a cable whose src or dst left the spec is DISABLED with a warning and stays
// in the table (§10.3) — rerouting to a neighbour is forbidden
~kfPrune = {
    ~kfCables.do { |c|
        if(c[\enabled] != false) {
            var okS = ~kfSpecOfNode.(c[\src][0], c[\src][1]).notNil;
            var okD = ~kfSpecOfNode.(c[\dst][0], c[\dst][1]).notNil;
            if(okS.not or: { okD.not }) {
                c[\enabled] = false;
                ("8_koppelfeld — кабель " ++ c[\src][0] ++ "." ++ c[\src][1] ++ " -> "
                    ++ c[\dst][0] ++ "." ++ c[\dst][1]
                    ++ " ВЫКЛЮЧЕН: узел пропал из spec (перенаправление запрещено)").warn;
            };
        };
    };
};

// ----- node plan (§3.1/§3.4) -------------------------------------------
// The resolved wiring of ONE node, language side: cables that actually have a
// source, their band bounds, the position table of a step node. The live body
// below and the NRT graph of `.claude/Tools/log_patch.scd` are BOTH built from
// this plan — an offline log that measured a different graph than the one that
// sounds would be worse than no log at all.
// The plan MUTATES the registry of a degraded P node (\curve -> \clip and the
// rest through ~setParam) unless `commit: false` is passed: a caller that only
// INSPECTS a node must pass it, or looking at the field rewrites the field.
~kfNodePlan = { |layer, key, warn = true, commit = true|
    var n = (~kfNodes[layer.asSymbol] ? ())[key.asSymbol];
    if(n.isNil) { nil } {
        var cs   = n[\spec];
        var rest = n[\rest];
        var wlo  = n[\win][0], whi = n[\win][1];
        var fold = (n[\curve] == \fold);
        var step = (n[\curve] == \step);
        var degraded = false;
        var pos, bnds, gaps, idx0;
        var wired = [];
        // windows of ALL nodes — the dynamic f_max is read off the rate node
        var wins = ();
        if(n[\cables].notEmpty) {
            ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, m|
                wins[~kfIdOf.(l, k)] = m[\win];
            }};
        };
        n[\cables].do { |c, i|
            var sn = (~kfNodes[c[\src][0].asSymbol] ? ())[c[\src][1].asSymbol];
            var bnd, hi;
            if(sn.isNil or: { sn[\bus].isNil }) {
                if(warn) {
                    ("8_koppelfeld — узел " ++ layer ++ "." ++ key ++ ": источник "
                        ++ c[\src][0] ++ "." ++ c[\src][1]
                        ++ " ещё не построен, кабель пропущен").warn;
                };
            } {
                bnd = ~kfBand[c[\band] ? \block] ? [0.004, 0.05];
                hi  = min(bnd[1], (~kfFmaxOf.(layer, key, wins) ? bnd[1]));
                wired = wired.add((
                    slot: i, src: [c[\src][0].asSymbol, c[\src][1].asSymbol],
                    bus: sn[\bus], spec: sn[\spec], rest: sn[\rest],
                    fc: c[\fc], fcLo: bnd[0], fcHi: hi,
                    pol: c[\pol] ? 1, gain: c[\gain] ? 0,
                    gmax: ~kfGainMax.(layer, key)
                ));
            };
        };
        // §3.6 step machine, prepared on the language side: the window admits a
        // handful of positions, so the boundaries between them and the gap of
        // each boundary are CONSTANTS in the graph — no Buffer, no index lookup
        if(step) {
            pos = ~kfWinPos.(layer, key, n[\win]);
            if(pos.size < ~cfg_kf.pPosMin) {
                ("8_koppelfeld — P-узел " ++ layer ++ "." ++ key ++ ": окно " ++ n[\win]
                    ++ " содержит " ++ pos.size ++ " позиций таблицы (нужно ≥ "
                    ++ ~cfg_kf.pPosMin ++ "), ступень недостижима — узел остаётся clip").error;
                step = false;
                degraded = true;
                // the registry must state what the body IS: ~kfRestBounds and
                // ~kfRestApply branch on \curve, and a \step registry over a
                // clipping body snaps the rest onto lattice positions the body
                // never visits. Reachable past the validator: a layer hot-swap
                // under a live scheme, or a direct ~kfInstall. The rest goes
                // back through ~setParam for the same reason as in ~kfBuildLayer:
                // the store must carry what the clipping body will sound
                if(commit) {
                    n[\curve] = \clip;
                    ~setParam.(layer.asSymbol, key.asSymbol, cs.map(rest));
                    rest = n[\rest];
                };
            } {
                bnds = (0 .. pos.size - 2).collect { |i| (pos[i] + pos[i + 1]) * 0.5 };
                gaps = (0 .. pos.size - 2).collect { |i| pos[i + 1] - pos[i] };
                idx0 = bnds.count { |b| rest > b };
            };
        };
        (
            node: n[\node], spec: cs, rest: rest, wlo: wlo, whi: whi,
            fold: fold, step: step, degraded: degraded,
            pos: pos, bnds: bnds, gaps: gaps, idx0: idx0,
            hyst: n[\hyst], dwell: n[\dwell], cut: n[\cut], wired: wired
        )
    };
};

// ----- node body (§3.1/§3.3/§3.4) --------------------------------------
~kfNodeBody = { |layer, key, warn = true|
    var n = (~kfNodes[layer.asSymbol] ? ())[key.asSymbol];
    var p = ~kfNodePlan.(layer, key, warn);
    if(p.notNil) {
        var cs   = p[\spec];
        var rest = p[\rest];
        var wlo  = p[\wlo], whi = p[\whi];
        var fold = p[\fold], step = p[\step];
        var pos  = p[\pos], bnds = p[\bnds], gaps = p[\gaps], idx0 = p[\idx0];
        var wired = p[\wired];
        var armBus = ~kfArmBus.value;
        // EXACTLY ONE channel: a two-channel node would go through n_mapan and
        // cover the NEIGHBOURING layer control — silent corruption (§3.3)
        Ndef(n[\node], {
            var acc = 0, u, x;
            wired.do { |w|
                // InFeedback is NORMATIVE (§3.4): exactly one block of delay per
                // edge whatever the node order, and a cycle has no order
                var raw = InFeedback.ar(w[\bus], 1);
                var dev = w[\spec].unmap(raw) - ("r" ++ w[\slot]).asSymbol.ar(w[\rest]);
                // time-constant backstop: ControlRate.ir/8 = SR/(8·blockSize)
                // ≈ 86 Hz — no filter lives faster than one block
                var fc  = ("fc" ++ w[\slot]).asSymbol.ar(w[\fc])
                    .clip(w[\fcLo], min(w[\fcHi], ControlRate.ir * 0.125));
                var band = Lag.ar(dev, 1.0995 / fc);
                acc = acc + (("s" ++ w[\slot]).asSymbol.ar(w[\pol])
                    * ("g" ++ w[\slot]).asSymbol.ar(w[\gain]).clip(0, w[\gmax])
                    * band);
            };
            // contract §5: slew belongs to the PATH, the layer keeps only a floor.
            // The cable contribution declares its slew (band τ), rest/hand had none
            // at all — sequencer, MIDI, tuner and ~kfPoke stepped in one block over
            // layers that had dropped their own 0.2–0.3 s lags (B-4). spec.map runs
            // AFTER the smoothing, so stepped specs (theta.fragOct) stay stepped
            u = Lag.ar(\rest.ar(rest) + \hand.ar(0), \slew.ar(~cfg_kf.handSlew));
            if(wired.notEmpty and: { armBus.notNil }) {
                u = u + (acc * In.kr(armBus, 1));
            };
            x = case
            { step } {
                // hysteresis as a WIDENED boundary, not as an index distance:
                // going up asks u to overshoot the boundary by hyst·gap, going
                // down to undershoot it by the same — the pair `up ≤ dn` makes a
                // chatter across one boundary impossible by arithmetic
                var prev = LocalIn.ar(1, idx0);
                var hyst = \hyst.ar(p[\hyst]).clip(~cfg_kf.pHyst, ~cfg_kf.pHystMax);
                var up = 0, dn = 0, wantUp, wantDn, tgt, free, idx, stepV;
                bnds.do { |b, i|
                    up = up + (u > (b + (hyst * gaps[i])));
                    dn = dn + (u > (b - (hyst * gaps[i])));
                };
                wantUp = up > prev;
                wantDn = dn < prev;
                tgt = (wantUp * up) + (wantDn * dn)
                    + ((1 - wantUp) * (1 - wantDn) * prev);
                // dwell measured on the FED-BACK index: one block late, which is
                // nothing against 20 s, and it needs no second state variable
                free = Sweep.ar(Changed.ar(prev), 1) > \dwell.ar(p[\dwell]).max(~cfg_kf.pDwell);
                idx = prev + (free * (tgt - prev));
                LocalOut.ar(idx);
                stepV = pos[0];
                gaps.do { |g, i| stepV = stepV + ((idx > (i + 0.5)) * g) };
                // the cut, and nothing but the cut: between steps the value is a
                // constant, so dF/dt = 0 holds by construction (C-6)
                Lag.ar(stepV, \cut.ar(p[\cut]).clip(0, ~cfg_kf.pCut))
            }
            { fold } {
                Fold.ar(u, \wlo.ar(wlo), \whi.ar(whi))
            }
            {
                Clip.ar(u, \wlo.ar(wlo), \whi.ar(whi))
            };
            cs.map(x)
        });
        Ndef(n[\node]).fadeTime = ~cfg_kf.nodeFade;
        Ndef(n[\node]).wakeUp;
        n[\bus] = Ndef(n[\node]).bus !? { |b| b.index };
        if(Ndef(n[\node]).numChannels != 1) {
            ("8_koppelfeld — узел " ++ n[\node] ++ " не одноканальный ("
                ++ Ndef(n[\node]).numChannels ++ ")").error;
        };
    };
};

~kfDropLayer = { |layer|
    (~kfNodes[layer] ? ()).keysValuesDo { |key, n|
        // unmap BEFORE clear: a cleared proxy would leave the layer an `n_mapa`
        // onto a dead bus, and the control would silently freeze on garbage
        Ndef(layer).unmap(key);
        Ndef(n[\node]).clear;
    };
    ~kfNodes[layer] = nil;
};

~kfBuildLayer = { |layer|
    var spec = ~ungSpecs[layer];
    if(spec.isNil) {
        ("8_koppelfeld — слой " ++ layer ++ " не загружен, узлы не построены").warn;
    } {
        var reg = ();
        ~kfDropLayer.(layer);
        ~kfPrune.value;
        spec.params.do { |p|
            var key = p[\key];
            if(p[\reread].isNil or: { p[\arMod].isNil }) {
                ("8_koppelfeld — " ++ layer ++ "." ++ key
                    ++ ": строка spec без reread/arMod, принято \\cont/\\lin").warn;
            };
            reg[key] = (
                node: ~kfNodeKey.(layer, key), spec: p[\spec], rest: ~kfRestOf.(layer, p),
                win: [0, 1], winRel: false, curve: \clip, cables: [], bus: nil,
                hyst: ~cfg_kf.pHyst, dwell: ~cfg_kf.pDwell, cut: ~cfg_kf.pCut
            );
        };
        ~kfNodes[layer] = reg;
        reg.keysValuesDo { |key, n|
            var w = ~kfWireOf.(layer, key);
            n[\win] = w[\win]; n[\winRel] = w[\winRel];
            n[\curve] = w[\curve]; n[\cables] = w[\cables];
            n[\hyst] = w[\hyst]; n[\dwell] = w[\dwell]; n[\cut] = w[\cut];
        };
        // before the bodies, and the fan-out before that: a hot-swapped layer
        // carries the rest it had in ~ungVals, which under a live scheme can sit
        // outside the node window. Same disease D-11/D25 closed for ~setParam and
        // ~kfInstall — route through ~setParam so ~ungVals, tuner and preset hold
        // what the graph accepts instead of what the layer asked for
        ~kfFanOutBuild.value;
        ~kfRestQuiet = true;
        {
            reg.keysValuesDo { |key, n|
                if(n[\cables].notEmpty) {
                    ~kfRestApply.(layer, key, n[\rest]) !? { |acc|
                        ~ungValsSet.(layer, key, n[\spec].map(acc));
                    };
                };
            };
        }.protect { ~kfRestQuiet = false };
        // two passes: a body build needs the source bus, so pass one gives every
        // node of the layer a body and a bus (cables whose source has no bus yet
        // are skipped silently), pass two rebuilds the destinations over ready
        // buses. At load time there are no cables, so pass two is empty
        reg.keysValuesDo { |key, n| ~kfNodeBody.(layer, key, false) };
        reg.keysValuesDo { |key, n| if(n[\cables].notEmpty) { ~kfNodeBody.(layer, key) } };
        // \rN of an OUTSIDE destination survives the rebuild in its nodeMap and
        // outlives the fresh default of the new body: re-send every rest that
        // feeds a cable, through the single writer
        ~kfRestQuiet = true;
        {
            reg.keysValuesDo { |key, n|
                if(((~kfFanOut[layer.asSymbol] ? ())[key] ? []).notEmpty) {
                    ~kfRestApply.(layer, key, n[\rest]);
                };
            };
        }.protect { ~kfRestQuiet = false };
        // one bundle per layer: 111 separate `map` calls at start is a visible stall
        s.bind {
            reg.keysValuesDo { |key, n| Ndef(layer).map(key, Ndef(n[\node])) };
        };
    };
};

// the layer registration tail calls this after its Ndef.set loop (contract §3):
// that loop DROPS the mapping, and without a rebind the layer silently falls
// off the scheme
~kfRebind = { |layer|
    layer = layer.asSymbol;
    // notEmpty, not just notNil: ~kfClear EMPTIES the registry, and ~appCleanup
    // runs before the layers load. On nil-only guard every layer tail would
    // rebuild the whole field that the module load then throws away
    if(~kfNodes.notNil and: { ~kfNodes.notEmpty }) {
        ~kfBuildLayer.(layer);
        // the rebuilt layer got NEW bus indices; bodies of external destinations
        // still hold the old ones — rebuild only those (node->layer map untouched)
        ~kfCables.do { |c|
            if((c[\enabled] != false) and: { c[\src][0].asSymbol == layer }
                and: { c[\dst][0].asSymbol != layer }) {
                ~kfNodeBody.(c[\dst][0], c[\dst][1]);
            };
        };
        ~kfMeterRebuild.value;
    };
};

// ----- Λ, cycles, mode (§4.4) ------------------------------------------
~kfAdjacency = { |cables|
    var adj = ();
    cables.do { |c|
        var sid = ~kfIdOf.(c[\src][0], c[\src][1]);
        adj[sid] = (adj[sid] ? []).add(( to: ~kfIdOf.(c[\dst][0], c[\dst][1]), cable: c ));
    };
    adj
};

~kfLambda = { |sch|
    var cfg = ~cfg_kf;
    var cables = (sch[\cables] ? []).select { |c| c[\enabled] != false };
    var adj = ~kfAdjacency.(cables);
    var indeg = ();
    var starts = adj.keys.asArray.sort { |a, b| a.asString < b.asString };
    var effFold;
    var found = (), tooLong = [], dfs;
    var loops, lamMax, dom, mode, incomm = [], notes = [];
    cables.do { |c|
        var did = ~kfIdOf.(c[\dst][0], c[\dst][1]);
        indeg[did] = (indeg[did] ? 0) + 1;
    };
    // EFFECTIVE destination curve: ~kfWireOf forces clip on a convergence node,
    // so a fold declared in the cable never reaches the graph. Λ and mode must
    // describe the graph that sounds, not the one that is written down
    effFold = { |c|
        ((c[\curve] ? \clip) == \fold)
            and: { (indeg[~kfIdOf.(c[\dst][0], c[\dst][1])] ? 0) < 2 };
    };
    dfs = { |start, node, seen, edges|
        (adj[node] ? []).do { |e|
            if(e[\to] == start) {
                var cyc = seen ++ [];
                var ed  = edges ++ [e[\cable]];
                var canon = cyc.collect(_.asString);
                // dedup by minimal rotation: a cycle is recorded once, from its
                // lowest-named vertex
                if(canon.minItem == start.asString) {
                    if(ed.size > cfg.depthMax) {
                        tooLong = tooLong.add(( nodes: cyc, len: ed.size ));
                    } {
                        found[cyc.join($>).asSymbol] = ( nodes: cyc, edges: ed );
                    };
                };
            } {
                if(seen.includes(e[\to]).not and: { edges.size < cfg.depthMax }) {
                    dfs.(start, e[\to], seen ++ [e[\to]], edges ++ [e[\cable]]);
                };
            };
        };
    };
    starts.do { |v| dfs.(v, v, [v], []) };

    // a self-loop (len 1) belongs to V1, not V8: in the cycle list it would
    // poison Λmax and the declared mode
    loops = found.values.select { |c| c[\edges].size >= 2 }.collect { |c|
        var lam = c[\edges].inject(1) { |a, e| a * (e[\gain] ? 0) };
        var inv = c[\edges].count { |e| (e[\pol] ? 1) < 0 };
        var tau = c[\edges].inject(0) { |a, e| a + (1 / (2pi * e[\fc])) };
        (
            nodes: c[\nodes], len: c[\edges].size, lam: lam, inv: inv,
            tau: tau, period: 2 * tau,
            fold: c[\edges].any { |e| effFold.(e) }
        );
    };
    loops = loops.sort { |a, b| a[\lam] > b[\lam] };
    lamMax = if(loops.isEmpty) { 0 } { loops[0][\lam] };
    dom = loops.first;

    mode = \ruhe;
    if(lamMax >= cfg.modeUmlauf) {
        if(dom[\inv].odd) {
            mode = if(lamMax > cfg.modeWanderung and: { dom[\fold] }) { \wanderung } { \umlauf };
        } {
            notes = notes.add("Λmax " ++ lamMax.round(0.01)
                ++ " ≥ порога при ЧЁТНОМ числе инверсий доминирующего цикла: "
                ++ "предельное множество на границе окна, режим заявлен ruhe");
        };
        if(lamMax > cfg.modeWanderung and: { dom[\fold].not }) {
            notes = notes.add("Λmax " ++ lamMax.round(0.01)
                ++ " > " ++ cfg.modeWanderung ++ ", но fold в доминирующем цикле нет — "
                ++ "wanderung не заявлен");
        };
    };

    // incommensurability: no period ratio closer than incommTol to any p/q
    loops.do { |a, i|
        loops.copyRange(i + 1, loops.size - 1).do { |b|
            var r = max(a[\period], b[\period]) / max(1e-9, min(a[\period], b[\period]));
            (1..cfg.incommMax).do { |p| (1..cfg.incommMax).do { |q|
                var f = p / q;
                // IRREDUCIBLE fractions only: (2,2) and (4,4) are the same 1/1,
                // (4,2) the same 2/1 — one loop pair produced four identical
                // entries and inflated the violation count in the rejection
                if(p.gcd(q) == 1 and: { f >= 1 } and: { (r - f).abs <= (f * cfg.incommTol) }) {
                    incomm = incomm.add((
                        a: a[\nodes], b: b[\nodes], ratio: r, near: [p, q]
                    ));
                };
            }};
        };
    };
    ( loops: loops, lamMax: lamMax, mode: mode, tooLong: tooLong,
      incomm: incomm, notes: notes, adj: adj, indeg: indeg )
};

// ----- validator V1–V13 (§4.3) -----------------------------------------
~kfValidate = { |sch|
    var cfg = ~cfg_kf;
    var raw = (sch[\cables] ? []);
    var cables = raw.select { |c| c[\enabled] != false };
    var errs = [], notes = [];
    var wins = (), rels = (), curves = (), rests = (), indeg = (), outdeg = ();
    var steps = (), stepDef = ( hyst: ~cfg_kf.pHyst, dwell: ~cfg_kf.pDwell, cut: ~cfg_kf.pCut );
    var lam, adj, depths = [], maxDepth = 0, interlayer = 0;
    var layIn = (), layOut = (), census = (), degenerate = ();
    var restOf, reach, name;

    name = ~kfIdTag;

    // the scheme's rest overrides the live node state; a node the scheme does
    // not rest (every class L node — its level belongs to the hand) is read
    // through the ONE live accessor the relative windows are built from
    (sch[\rest] ? ()).keysValuesDo { |l, e| e.keysValuesDo { |k, v|
        rests[~kfIdOf.(l, k)] = v.clip(0, 1);
    }};
    restOf = { |l, k| rests[~kfIdOf.(l, k)] ?? { ~kfLiveRest.(l, k) } };

    // V1 + V2 + destination window/curve + layer census
    cables.do { |c|
        var sid = ~kfIdOf.(c[\src][0], c[\src][1]);
        var did = ~kfIdOf.(c[\dst][0], c[\dst][1]);
        var sl = c[\src][0].asSymbol, dl = c[\dst][0].asSymbol;
        if(sid == did) { errs = errs.add("V1 самопетля: " ++ name.(sid)) };
        indeg[did] = (indeg[did] ? 0) + 1;
        outdeg[sid] = (outdeg[sid] ? 0) + 1;
        if(~kfSpecOfNode.(c[\src][0], c[\src][1]).isNil) {
            errs = errs.add("V0 источника нет в spec: " ++ name.(sid));
        };
        if(~kfSpecOfNode.(c[\dst][0], c[\dst][1]).isNil) {
            errs = errs.add("V0 цели нет в spec: " ++ name.(did));
        };
        if(~kfRow.(c[\dst][0], c[\dst][1]).isNil) {
            errs = errs.add("V0 цели нет в таблице §5: " ++ name.(did));
        };
        if(wins[did].isNil) {
            wins[did] = ~kfWinAbs.(c[\dst][0], c[\dst][1], c);
            rels[did] = (c[\winRel] == true);
            curves[did] = c[\curve] ? \clip;
            steps[did] = stepDef.collect { |v, f| c[f] ? v };
        } {
            if(wins[did] != ~kfWinAbs.(c[\dst][0], c[\dst][1], c)) {
                errs = errs.add("V7 два кабеля в " ++ name.(did) ++ " объявляют РАЗНОЕ окно "
                    ++ wins[did] ++ " и " ++ ~kfWinAbs.(c[\dst][0], c[\dst][1], c));
            };
            if(rels[did] != (c[\winRel] == true)) {
                errs = errs.add("V7 два кабеля в " ++ name.(did) ++ " объявляют РАЗНЫЙ род "
                    ++ "окна (относительное ±дБ / абсолютное)");
            };
            if(curves[did] != (c[\curve] ? \clip)) {
                errs = errs.add("V7 два кабеля в " ++ name.(did) ++ " объявляют РАЗНУЮ кривую");
            };
            // hyst/dwell/cut are NODE fields, and ~kfWireOf reads them off the
            // first cable only: a second cable declaring its own would run
            // unheard, and V9 checks each cable's floor as if both applied
            stepDef.keysDo { |f|
                var mine = c[f] ? stepDef[f];
                if(steps[did][f] != mine) {
                    errs = errs.add("V7 два кабеля в " ++ name.(did) ++ " объявляют РАЗНЫЙ "
                        ++ f ++ ": " ++ steps[did][f] ++ " и " ++ mine);
                };
            };
        };
        if(sl != dl) {
            interlayer = interlayer + 1;
            census[(sl.asString ++ ">" ++ dl.asString).asSymbol] = true;
        };
        layOut[sl] = (layOut[sl] ? 0) + 1;
        layIn[dl] = (layIn[dl] ? 0) + 1;
    };

    indeg.keysValuesDo { |k, v|
        if(v > cfg.fanIn) { errs = errs.add("V2 фан-ин " ++ v ++ " > " ++ cfg.fanIn ++ ": " ++ name.(k)) };
    };
    outdeg.keysValuesDo { |k, v|
        if(v > cfg.fanOut) { errs = errs.add("V2 фан-аут " ++ v ++ " > " ++ cfg.fanOut ++ ": " ++ name.(k)) };
    };
    if(cables.size > cfg.cableMax) {
        errs = errs.add("кабелей " ++ cables.size ++ " > потолка " ++ cfg.cableMax);
    };
    if(cables.size < cfg.cableMin) {
        notes = notes.add("кабелей " ++ cables.size ++ " < " ++ cfg.cableMin
            ++ " (гарантия патчера, не инвариант схемы)");
    };

    // V9: band, curve and gain by destination class + the sampling law
    cables.do { |c|
        var did = ~kfIdOf.(c[\dst][0], c[\dst][1]);
        var row = ~kfRow.(c[\dst][0], c[\dst][1]);
        if(row.notNil) {
            var cls = row[0];
            var cl = ~kfClass[cls] ? ();
            var bnd = ~kfBand[c[\band] ? \block];
            var gmax = ~kfGainMax.(c[\dst][0], c[\dst][1]);
            var fmax = ~kfFmaxOf.(c[\dst][0], c[\dst][1], wins);
            var fcCeil = ~kfFcCeil.value;
            var curve = c[\curve] ? \clip;
            var tag = name.(~kfIdOf.(c[\src][0], c[\src][1])) ++ " -> " ++ name.(did);
            if(bnd.isNil) {
                errs = errs.add("V9 неизвестная полоса " ++ c[\band] ++ ": " ++ tag);
            } {
                if((cl[\bands] ? []).includes(c[\band] ? \block).not) {
                    errs = errs.add("V9 полоса " ++ c[\band] ++ " не допущена классом "
                        ++ cls ++ ": " ++ tag);
                };
                if(c[\fc] < bnd[0] or: { c[\fc] > bnd[1] }) {
                    errs = errs.add("V9 f_c " ++ c[\fc] ++ " вне полосы " ++ c[\band]
                        ++ " " ++ bnd ++ ": " ++ tag);
                };
            };
            if(c[\fc] > fcCeil) {
                errs = errs.add("V9 f_c " ++ c[\fc] ++ " > блочного предела "
                    ++ fcCeil.round(0.01) ++ " Гц (SR/(8·blockSize)): тело узла "
                    ++ "зажало бы полосу, и τ анализа разошёлся бы с τ фильтра: " ++ tag);
            };
            if(fmax.notNil and: { c[\fc] > fmax }) {
                errs = errs.add("V9 закон опроса: f_c " ++ c[\fc] ++ " > f_max "
                    ++ fmax.round(0.0001) ++ ": " ++ tag);
            };
            if((cl[\curve] ? []).includes(curve).not) {
                errs = errs.add("V9 кривая " ++ curve ++ " не допущена классом " ++ cls ++ ": " ++ tag);
            };
            // §3.6: the step parameters are node-level, but a cable may compose
            // them; canon floors are checked here and clamped again in the graph
            if(curve == \step) {
                if((c[\hyst] ? cfg.pHyst) < cfg.pHyst) {
                    errs = errs.add("V9 гистерезис " ++ c[\hyst] ++ " < " ++ cfg.pHyst
                        ++ " — дребезг на границе зоны: " ++ tag);
                };
                if((c[\hyst] ? cfg.pHyst) > cfg.pHystMax) {
                    errs = errs.add("V9 гистерезис " ++ c[\hyst] ++ " > " ++ cfg.pHystMax
                        ++ " — граф зажимает там же, схема заявила бы неотработанное: " ++ tag);
                };
                if((c[\dwell] ? cfg.pDwell) < cfg.pDwell) {
                    errs = errs.add("V9 простой " ++ c[\dwell] ++ " с < " ++ cfg.pDwell
                        ++ " с — ступень читается как движение, а не как блок: " ++ tag);
                };
                if((c[\cut] ? cfg.pCut) > cfg.pCut) {
                    errs = errs.add("V9 рез " ++ c[\cut] ++ " с > " ++ cfg.pCut
                        ++ " с — глайд высоты: " ++ tag);
                };
            };
            if(curve == \fold and: { ~kfFoldBands.includes(c[\band] ? \block).not }) {
                errs = errs.add("V9 fold вне полос " ++ ~kfFoldBands ++ ": " ++ tag);
            };
            if(c[\gain] > gmax) {
                errs = errs.add("V9 gain " ++ c[\gain] ++ " > потолка класса " ++ cls
                    ++ " (" ++ gmax ++ "): " ++ tag);
            };
            if(c[\gain] < cfg.gainMin) {
                errs = errs.add("V9 gain " ++ c[\gain] ++ " < " ++ cfg.gainMin
                    ++ " — кабель не проведён: " ++ tag);
            };
            if((c[\pol] ? 1).abs != 1) { errs = errs.add("V9 pol не ±1: " ++ tag) };
            // per NODE, not per cable: three cables into one degenerate target
            // filed the same sentence three times
            if(fmax.notNil and: { fmax < (~kfBand[\block][0] * 2) }
                and: { degenerate[did].isNil }) {
                degenerate[did] = true;
                notes = notes.add("узел " ++ name.(did) ++ ": f_max " ++ fmax.round(0.0001)
                    ++ " < 2× пола B4 — цель формально легальна, практически вырождена");
            };
        };
    };

    // V7: window, rest, per-node bounds from the §5 table
    wins.keysValuesDo { |did, w|
        var parts = did.asString.split($.);
        var l = parts[0].asSymbol, k = parts[1].asSymbol;
        var r = restOf.(l, k);
        var ex = (~kfRow.(l, k) !? { |row| row[2] }) ? ();
        var isP = (~kfRow.(l, k) !? { |row| row[0] }) == \P;
        var pos = if(isP) { ~kfWinPos.(l, k, w) } { [] };
        if(w[0] < 0 or: { w[1] > 1 }) { errs = errs.add("V7 окно вне [0,1]: " ++ name.(did) ++ " " ++ w) };
        if(w[0] >= w[1]) {
            errs = errs.add("V7 wlo ≥ whi: " ++ name.(did) ++ " " ++ w);
        } {
            case
            // §3.6 / reference 5.1: the window of a P destination is a SUBSET of
            // the node table, at most five positions. Its rest is measured in
            // POSITIONS, not in width: five points of the 94 Hz lattice span
            // ≈ 0.15 of a pitch spec, so the 2·restMargin width rule would make
            // every legal P window illegal, and a step node parked on its lowest
            // position is still free to step up — unlike a clipping one
            { isP } {
                if(pos.size > cfg.pPosMax) {
                    errs = errs.add("V7 окно P-узла " ++ name.(did) ++ " " ++ w ++ " допускает "
                        ++ pos.size ++ " позиций таблицы > " ++ cfg.pPosMax);
                };
                if(pos.size < cfg.pPosMin) {
                    errs = errs.add("V7 окно P-узла " ++ name.(did) ++ " " ++ w ++ " допускает "
                        ++ pos.size ++ " позиций таблицы < " ++ cfg.pPosMin
                        ++ " — ступень недостижима");
                } {
                    if(r < pos.first or: { r > pos.last }) {
                        errs = errs.add("V7 покой " ++ r.round(0.001)
                            ++ " вне позиций таблицы окна [" ++ pos.first.round(0.001) ++ ", "
                            ++ pos.last.round(0.001) ++ "]: " ++ name.(did));
                    };
                };
            }
            // §5.1 / D91: a RELATIVE window is ±winDb around the live level, and
            // the level is its centre by construction. The normalized restMargin
            // is a different metric — measuring it here would reject every legal
            // window of class L and pull the layer level off what the hand set
            { rels[did] == true } {
                if(r < w[0] or: { r > w[1] }) {
                    errs = errs.add("V7 живой покой " ++ r.round(0.001)
                        ++ " вне относительного окна " ++ w ++ ": " ++ name.(did));
                };
                if((w[1] - w[0]) <= ((2 * cfg.restMargin) + 1e-9)) {
                    notes = notes.add("окно " ++ name.(did)
                        ++ " вырождено (живой уровень у края спека): раскрыто до пола 2·"
                        ++ cfg.restMargin ++ " — ±" ++ (~cfg_kf.patchLDb) ++ " дБ не поместились");
                };
            }
            // a window narrower than 2·restMargin admits NO legal rest at all;
            // without this the failure surfaced as a confusing complaint about the
            // rest, and ~kfRestBounds collapsed the rest onto the midpoint
            { (w[1] - w[0]) < (2 * cfg.restMargin) } {
                errs = errs.add("V7 ширина окна " ++ (w[1] - w[0]).round(0.001) ++ " < 2·"
                    ++ cfg.restMargin ++ ": ни одно значение покоя не лежит в окне "
                    ++ w ++ " с зазором: " ++ name.(did));
            }
            {
                if(r < (w[0] + cfg.restMargin) or: { r > (w[1] - cfg.restMargin) }) {
                    errs = errs.add("V7 покой " ++ r.round(0.001) ++ " ближе " ++ cfg.restMargin
                        ++ " к границе окна " ++ w ++ ": " ++ name.(did));
                };
            };
        };
        ex[\wmin] !? { |v| if(w[0] < v) {
            errs = errs.add("V7 нижняя граница окна " ++ w[0] ++ " < канона " ++ v ++ ": " ++ name.(did));
        }};
        ex[\wmax] !? { |v| if(w[1] > v) {
            errs = errs.add("V7 верхняя граница окна " ++ w[1] ++ " > канона " ++ v ++ ": " ++ name.(did));
        }};
    };

    // Λ and cycles (V8)
    lam = ~kfLambda.(( cables: cables ));
    adj = lam[\adj];
    lam[\tooLong].do { |c|
        errs = errs.add("V8 цикл длины " ++ c[\len] ++ " > " ++ cfg.depthMax ++ ": "
            ++ c[\nodes].collect { |n| name.(n) }.join(" > "));
    };
    lam[\loops].do { |l|
        if(l[\lam] > cfg.lamMax) {
            errs = errs.add("V8 Λ " ++ l[\lam].round(0.001) ++ " > " ++ cfg.lamMax ++ ": "
                ++ l[\nodes].collect { |n| name.(n) }.join(" > "));
        };
    };
    if(lam[\loops].count { |l| l[\lam] >= 1 } > cfg.loopExcMax) {
        errs = errs.add("V8 возбуждённых петель " ++ lam[\loops].count { |l| l[\lam] >= 1 }
            ++ " > " ++ cfg.loopExcMax);
    };
    lam[\incomm].do { |x|
        errs = errs.add("Λ несоизмеримость: отношение периодов " ++ x[\ratio].round(0.001)
            ++ " ближе " ++ (cfg.incommTol * 100) ++ " % к " ++ x[\near][0] ++ "/" ++ x[\near][1]);
    };
    notes = notes ++ lam[\notes];
    // §4.4: the declared mode IS a function of Λmax. A scheme's `mode` field
    // (§4.1) is the patcher's intent, not the truth; a mismatch is reported but
    // the V11 mode bans follow the derived one
    if(sch[\mode].notNil and: { sch[\mode] != lam[\mode] }) {
        notes = notes.add("режим схемы заявлен " ++ sch[\mode] ++ ", выведен из Λmax "
            ++ lam[\lamMax].round(0.001) ++ " как " ++ lam[\mode]
            ++ " — V11 применяется по ВЫВЕДЕННОМУ (§4.4)");
    };
    block {
        var said = ();
        cables.do { |c|
            var did = ~kfIdOf.(c[\dst][0], c[\dst][1]);
            if((c[\curve] ? \clip) == \fold and: { (lam[\indeg][did] ? 0) >= 2 }
                and: { said[did].isNil }) {
                said[did] = true;
                notes = notes.add("fold объявлен в узел схождения " ++ name.(did)
                    ++ " (indeg " ++ lam[\indeg][did] ++ ") — принудительно понижен до clip; "
                    ++ "Λ, режим и V11 считаются по clip");
            };
        };
    };

    reach = { |from, maxD|
        var seen = [from], frontier = [from], d = 0;
        while({ frontier.notEmpty and: { maxD.isNil or: { d < maxD } } }) {
            var nxt = [];
            frontier.do { |v| (adj[v] ? []).do { |e|
                if(seen.includes(e[\to]).not) { seen = seen.add(e[\to]); nxt = nxt.add(e[\to]) };
            }};
            frontier = nxt; d = d + 1;
        };
        seen.copyRange(1, seen.size - 1)
    };

    // V3: no path of length ≤ 4 between a P and a D node of the SAME layer
    // (§F pitch↔density)
    ~kfNodeTable.keysValuesDo { |l, rows| rows.keysValuesDo { |k, row|
        if((row[0] == \P) or: { row[0] == \D }) {
            var from = ~kfIdOf.(l, k);
            var other = if(row[0] == \P) { \D } { \P };
            if(adj[from].notNil) {
                reach.(from, cfg.depthMax).do { |t|
                    var p = t.asString.split($.);
                    if(p[0].asSymbol == l) {
                        var trow = ~kfRow.(l, p[1].asSymbol);
                        if(trow.notNil and: { trow[0] == other }) {
                            errs = errs.add("V3 §F путь ≤ " ++ cfg.depthMax ++ " между "
                                ++ row[0] ++ " и " ++ other ++ " одного слоя: "
                                ++ name.(from) ++ " ~> " ++ name.(t));
                        };
                    };
                };
            };
        };
    }};

    // V4: no path of ANY length from an E node to a G node (§F decay↔spatial)
    ~kfNodeTable.keysValuesDo { |l, rows| rows.keysValuesDo { |k, row|
        if(row[0] == \E) {
            var from = ~kfIdOf.(l, k);
            if(adj[from].notNil) {
                reach.(from, nil).do { |t|
                    var p = t.asString.split($.);
                    var trow = ~kfRow.(p[0].asSymbol, p[1].asSymbol);
                    if(trow.notNil and: { trow[0] == \G }) {
                        errs = errs.add("V4 §F путь E -> G: " ++ name.(from) ++ " ~> " ++ name.(t));
                    };
                };
            };
        };
    }};

    // V5 (depth, length presence) + V6 (τ ladder) in one simple-path walk
    block {
        var lens = (), bad = (), walk;
        walk = { |node, seen, prev, d|
            if(d > maxDepth) { maxDepth = d };
            if(d <= cfg.depthMax) {
                lens[d] = true;
                (adj[node] ? []).do { |e|
                    if(seen.includes(e[\to]).not) {
                        if(prev.notNil) {
                            // the ladder is checked along SIMPLE paths only: a
                            // cycle's closing edge does not extend the path, or
                            // no cycle could ever satisfy it
                            var tPrev = 1 / (2pi * prev[\fc]);
                            var tCur  = 1 / (2pi * e[\cable][\fc]);
                            if(tCur < (tPrev * cfg.ladderRatio)) {
                                var tag = (name.(~kfIdOf.(prev[\src][0], prev[\src][1]))
                                    ++ " -> " ++ name.(node) ++ " -> " ++ name.(e[\to]));
                                bad[tag.asSymbol] = ( tPrev: tPrev, tCur: tCur );
                            };
                        };
                        walk.(e[\to], seen ++ [e[\to]], e[\cable], d + 1);
                    };
                };
            };
        };
        adj.keys.asArray.do { |v| walk.(v, [v], nil, 0) };
        depths = lens.keys.asArray.select { |d| d > 0 }.sort;
        if(maxDepth > cfg.depthMax) {
            errs = errs.add("V5 глубина " ++ maxDepth ++ " > " ++ cfg.depthMax);
        };
        bad.keysValuesDo { |tag, v|
            errs = errs.add("V6 лестница: τ " ++ v[\tCur].round(0.001) ++ " с после "
                ++ v[\tPrev].round(0.001) ++ " с (нужно ×" ++ cfg.ladderRatio ++ "): " ++ tag);
        };
        if(cables.notEmpty and: { (1..cfg.depthMax).any { |d| depths.includes(d).not } }) {
            notes = notes.add("V5 присутствуют длины " ++ depths ++ ", не все 1.."
                ++ cfg.depthMax ++ " (гарантия патчера, не инвариант схемы)");
        };
    };

    // V10: interlayer share, in/out per layer, census connectivity
    if(cables.notEmpty) {
        var frac = interlayer / cables.size;
        if(frac < cfg.interlayerMin) {
            notes = notes.add("V10 межслойных " ++ (frac * 100).round(0.1) ++ " % < "
                ++ (cfg.interlayerMin * 100) ++ " % (гарантия патчера)");
        };
        (~activeLayers ? ~kfNodes.keys.asArray).do { |l|
            if((layIn[l] ? 0) == 0) { notes = notes.add("V10 слой " ++ l ++ " без входа") };
            if((layOut[l] ? 0) == 0) { notes = notes.add("V10 слой " ++ l ++ " без выхода") };
        };
    };

    // V11: mode bans
    lam[\loops].do { |l|
        if(l[\nodes].any { |nid| nid.asString.split($.)[0] == "epsilon" }) {
            errs = errs.add("V11 §C.5: петля через epsilon — движение, читаемое "
                ++ "как периодическое: " ++ l[\nodes].collect { |n| name.(n) }.join(" > "));
        };
    };
    block {
        var arrival = [\ioi0, \decel, \ioiMax, \popScale, \gapScale, \density];
        var pTargets = cables.select { |c| (~kfRow.(c[\dst][0], c[\dst][1]) !? { |r| r[0] }) == \P };
        var pPerLayer = ();
        // reference 3.1 p.5 counts stepping NODES, not cables: two cables into one
        // pitch node are still one walking fundamental, and the count must not
        // call that a chord progression
        var pNodes = (), pTags;
        if(lam[\mode] == \wanderung) {
            cables.do { |c|
                if(c[\src][0].asSymbol == \theta and: { arrival.includes(c[\src][1].asSymbol) }) {
                    errs = errs.add("V11 wanderung-источник в семействе прибытия theta: "
                        ++ name.(~kfIdOf.(c[\src][0], c[\src][1])));
                };
            };
        };
        pTargets.do { |c|
            var l = c[\dst][0].asSymbol;
            var did = ~kfIdOf.(c[\dst][0], c[\dst][1]);
            if(pNodes[did].isNil) {
                pNodes[did] = c;
                pPerLayer[l] = (pPerLayer[l] ? 0) + 1;
            };
        };
        pTags = { |l| pNodes.keys.asArray.sort { |a, b| a.asString < b.asString }
            .select { |did| (l.isNil) or: { did.asString.split($.)[0] == l.asString } }
            .collect { |did| name.(did) }.join(", ") };
        pPerLayer.keysValuesDo { |l, n|
            if(n > 1) {
                errs = errs.add("V11 P-целей в слое " ++ l ++ ": " ++ n ++ " > 1: " ++ pTags.(l));
            };
        };
        if(pNodes.size > 2) {
            errs = errs.add("V11 P-целей всего " ++ pNodes.size ++ " > 2: " ++ pTags.(nil));
        };
        if((pPerLayer[\delta] ? 0) > 1) {
            errs = errs.add("V11 P-целей delta > 1: " ++ pTags.(\delta));
        };
        // "…and their bands must be incommensurable" (reference 3.1 p.5): two
        // fundamentals stepping on commensurable clocks read as a progression,
        // which composition.md excludes outright
        if(pNodes.size == 2) {
            var fcs = pNodes.values.collect { |c| c[\fc] }.sort;
            var r = fcs[1] / max(1e-9, fcs[0]);
            // both P clocks live in ONE band (B4 0.004–0.05), so their ratio runs
            // to 12.5, while a p/q grid with p,q ≤ 4 stops at 4: a 1:8 capture —
            // the plainest progression there is — passed it untouched. The ratio
            // is folded INTO THE OCTAVE and the grid with it (log distance mod 1),
            // which catches 8, 6 and 12 as the 1, 3/2 and 3/2 they are, and keeps
            // the forbidden set as sparse as before instead of rejecting everything
            var oct = r.log2, tol = (1 + cfg.incommTol).log2;
            var near = nil, best = 1;
            (1..cfg.incommMax).do { |p| (1..cfg.incommMax).do { |q|
                var f = p / q;
                if(p.gcd(q) == 1 and: { f >= 1 }) {
                    var d = (oct - f.log2).mod(1.0);
                    d = min(d, 1 - d);
                    if(d <= tol and: { d < best }) { best = d; near = [p, q] };
                };
            }};
            near !? {
                errs = errs.add("V11 полосы двух P-целей соизмеримы: отношение "
                    ++ r.round(0.001) ++ " в октавном приведении ближе "
                    ++ (cfg.incommTol * 100) ++ " % к " ++ near[0] ++ "/" ++ near[1]
                    ++ ": " ++ pTags.(nil));
            };
        };
    };

    // V12: epsilon freqLo ≤ freqHi in ALL reachable states;
    // mLevel ≥ flowLevel − 6 dB
    block {
        var span = { |k|
            var cs = ~kfSpecOfNode.(\epsilon, k);
            var w = wins[~kfIdOf.(\epsilon, k)];
            var r = restOf.(\epsilon, k);
            if(cs.isNil) { nil } {
                if(w.isNil) { [cs.map(r), cs.map(r)] } { [cs.map(w[0]), cs.map(w[1])] };
            };
        };
        var lo = span.(\freqLo), hi = span.(\freqHi);
        var ml = span.(\mLevel), fl = span.(\flowLevel);
        if(lo.notNil and: { hi.notNil } and: { lo[1] > hi[0] }) {
            errs = errs.add("V12 " ++ name.(~kfIdOf.(\epsilon, \freqLo)) ++ " верх "
                ++ lo[1].round(0.01) ++ " > " ++ name.(~kfIdOf.(\epsilon, \freqHi))
                ++ " низ " ++ hi[0].round(0.01));
        };
        if(ml.notNil and: { fl.notNil } and: { ml[0] < (fl[1] * 0.5) }) {
            errs = errs.add("V12 " ++ name.(~kfIdOf.(\epsilon, \mLevel)) ++ " низ "
                ++ ml[0].round(0.001) ++ " < " ++ name.(~kfIdOf.(\epsilon, \flowLevel))
                ++ " верх − 6 dB (" ++ (fl[1] * 0.5).round(0.001) ++ ")");
        };
    };

    // V13: theta.density may cross the 0.02 threshold on a B4 cable only
    block {
        var did = ~kfIdOf.(\theta, \density);
        var w = wins[did];
        if(w.notNil and: { w[0] < 0.02 }) {
            cables.do { |c|
                if(~kfIdOf.(c[\dst][0], c[\dst][1]) == did and: { (c[\band] ? \block) != \block }) {
                    errs = errs.add("V13 " ++ name.(did) ++ " пересекает 0.02 по полосе "
                        ++ c[\band] ++ " — разрешена только B4 (block)");
                };
            };
        };
    };

    (
        valid: errs.isEmpty, errors: errs, notes: notes,
        cables: cables.size, disabled: raw.size - cables.size,
        targets: wins.size,
        interlayer: if(cables.isEmpty) { 0 } { interlayer / cables.size },
        depths: depths, maxDepth: maxDepth,
        loops: lam[\loops], lamMax: lam[\lamMax], mode: lam[\mode]
    )
};

~kfVerdictPost = { |v, tag|
    ("8_koppelfeld — " ++ (tag ? "валидатор") ++ ": " ++ (if(v[\valid]) { "OK" } { "ОТКАЗ" })
        ++ " · кабелей " ++ v[\cables] ++ " (выкл " ++ v[\disabled] ++ ")"
        ++ " · целей " ++ v[\targets]
        ++ " · межслойных " ++ (v[\interlayer] * 100).round(0.1) ++ " %"
        ++ " · глубины " ++ v[\depths]
        ++ " · петель " ++ v[\loops].size
        ++ " · Λmax " ++ v[\lamMax].round(0.001)
        ++ " · режим " ++ v[\mode]).postln;
    v[\loops].do { |l|
        ("    петля " ++ l[\nodes].collect(_.asString).join(" > ")
            ++ " · Λ " ++ l[\lam].round(0.001) ++ " · инверсий " ++ l[\inv]
            ++ " · Στ " ++ l[\tau].round(0.01) ++ " с · T ≈ " ++ l[\period].round(0.01) ++ " с").postln;
    };
    v[\notes].do { |n| ("    NOTE " ++ n).postln };
    v[\errors].do { |e| ("    ОШИБКА " ++ e).postln };
    v
};

// ----- §6 derivation from a grid act + §7 the patcher -------------------
// The census / drawn-loop law of reading 2 lives HERE: ~konDerive calls
// ~kfGraphFacts instead of carrying its own copy (S6 moves the rest of
// reading 2 over as well). The glyph -> layer table belongs to 0_grid, whose
// alphabet it is, and which loads before both readers.
~kfLayerOrder = ~gridClassOrder;

~kfGraphFacts = { |grid, tTier|
    var g = grid[\graph];
    var tt = tTier ? ~cfg_kf.patchTtier;
    var nodes = g[\nodes], edges = g[\edges];
    var tiers = g[\tiers], rowGap = g[\rowGap];
    var layerIdx = (), nodeLayer, census, loopPair, loopSelf, cab;
    ~kfLayerOrder.do { |l, k| layerIdx[l] = k };
    nodeLayer = nodes.collect { |n| ~gridLayerOf[n[\ch]] };
    census = Array.fill(5, { Array.fill(5, 0) });
    edges.do { |e|
        var a = layerIdx[nodeLayer[e[\src]]], b = layerIdx[nodeLayer[e[\dst]]];
        census[a][b] = census[a][b] + 1;
    };
    // a drawn loop A<->B: both directions non-zero AND at least one edge of the
    // pair is a back edge (Konstruktion amendment II)
    loopPair = Array.fill(5, { Array.fill(5, false) });
    (0..4).do { |a| (0..4).do { |b|
        if((a < b) and: { census[a][b] > 0 } and: { census[b][a] > 0 }
            and: { edges.any { |e|
                var ea = layerIdx[nodeLayer[e[\src]]];
                var eb = layerIdx[nodeLayer[e[\dst]]];
                (e[\ret] == true) and: {
                    ((ea == a) and: { eb == b }) or: { (ea == b) and: { eb == a } };
                };
            } })
        { loopPair[a][b] = true; loopPair[b][a] = true };
    } };
    // an intra-layer drawn loop: reference 2.5 admits intra-layer modulation as
    // such (what §F bars is the intra-layer PATH between forbidden classes, and
    // that is checked on reachability), and a back edge inside one layer is as
    // drawn a feedback as one between two. ~konDerive never reads the diagonal,
    // so `loopPair` keeps the letter of amendment II and this rides beside it.
    loopSelf = Array.fill(5, false);
    (0..4).do { |a|
        loopSelf[a] = (census[a][a] >= 2) and: { edges.any { |e|
            (e[\ret] == true) and: { layerIdx[nodeLayer[e[\src]]] == a }
                and: { layerIdx[nodeLayer[e[\dst]]] == a };
        }};
    };
    // c_AB = mean(indeg of the destinations) / mean(outdeg of the sources) over
    // the edges of ONE layer pair, degrees taken over the FULL graph
    cab = Array.fill(5, { Array.fill(5, 1.0) });
    (0..4).do { |a| (0..4).do { |b|
        var ab = edges.select { |e|
            (layerIdx[nodeLayer[e[\src]]] == a) and: { layerIdx[nodeLayer[e[\dst]]] == b };
        };
        if(ab.notEmpty) {
            var din = ab.collect { |e| nodes[e[\dst]][\indeg] ? 1 }.mean;
            var dout = ab.collect { |e| nodes[e[\src]][\outdeg] ? 1 }.mean;
            cab[a][b] = (din / max(1e-9, dout)).clip(0.25, 4);
        };
    } };
    (
        seed: grid[\seed], complexity: grid[\complexity], tTier: tt,
        tiers: tiers, rowGap: rowGap, tauCell: tt / max(1, rowGap),
        layerIdx: layerIdx, nodeLayer: nodeLayer, nodes: nodes,
        census: census, loopPair: loopPair, loopSelf: loopSelf, cAB: cab,
        edgeTab: edges.collect { |e|
            ( src: nodeLayer[e[\src]], dst: nodeLayer[e[\dst]],
              srcI: e[\src], dstI: e[\dst],
              ret: e[\ret] == true, strong: e[\strong] == true,
              routeLen: e[\routeLen] ? 1 )
        }
    )
};

// ----- the bounded chance of §7: one deterministic stream ---------------
// `baseN` of ~konDerive spelled as a function: a golden-ratio scramble over
// (seed, edge index, graph features). No `rand` and no `scramble` anywhere in
// the derivation — A-3 (the same (seed, c) bit for bit) is the point of a seed.
// one irrational per POSITION of the argument list; a call may pass no more
// numbers than the table holds, or `i % size` would fold two positions onto one
// irrational and correlate them. Every call site passes four
~kfPhi = [0.6180339887, 2.6180339887, 0.7548776662, 0.5698402910];
~kfScramble = { |nums| nums.sum { |v, i| (v ? 0) * ~kfPhi[i % ~kfPhi.size] }.abs.frac };
// the scramble is ONE stream, so a second draw at the same point of the
// derivation must be salted apart. The values are arbitrary and only have to
// DIFFER — structure, not tuning
~kfSalt = ( slotJ: 7, nodeU: 1000, winRest: 3, loopKey: 3,
            srcKey: 0.37, dstKey: 0.19 );

// a node id inside an error message is a TAG, not prose: ~kfPatchRepair has to
// find the cable an error names, and `alpha.n1` is a substring of `alpha.n10`
// (measured: three such pairs among the 111 nodes). The delimiters make the
// match exact. Every error that NAMES a node renders it through here — pass 5
// addresses it by that name. The two errors that carry no node are the two no
// pass addresses by name: V5 depth (pass 4 cuts it structurally, ~kfStep8Ladder)
// and the cable ceiling, which is a refusal and not a repair
~kfIdTag = { |nid| "«" ++ nid.asString ++ "»" };

~kfBandOrder = [\rauheit, \puls, \gang, \block];
~kfBandIdx = { |b| (~kfBandOrder.indexOf(b) ? 3) + 1 };

// A cable's f_c lives in the MIDDLE of its band, never at the edge: the ladder
// (V6) needs τ to grow ×2.5 from rung to rung while the raw bands touch (B1 at
// 8 Hz and B2 at 8 Hz are one and the same τ). Narrowed by `patchNarrow` on
// both sides the worst adjacent ratio is ×4, so the ladder holds BY
// CONSTRUCTION and step 8 has nothing left to cut.
~kfBandNarrow = { |b|
    var r = ~kfBand[b] ? [0.004, 0.05], n = ~cfg_kf.patchNarrow;
    [r[0] * n, r[1] / n]
};
~kfBandOfFc = { |fc|
    // in the gap between two narrowed ranges the SLOWER band wins: a τ short of
    // the next rung would break the ×2.5 step
    case
    { fc >= ~kfBandNarrow.(\rauheit)[0] } { \rauheit }
    { fc >= ~kfBandNarrow.(\puls)[0] }    { \puls }
    { fc >= ~kfBandNarrow.(\gang)[0] }    { \gang }
    { \block }
};

~kfPatchKeys = { |layer|
    var sp = ~ungSpecs[layer.asSymbol];
    if(sp.isNil) { [] } {
        sp.params.collect { |p| p[\key] }.select { |k| ~kfRow.(layer, k).notNil };
    };
};

~kfPatchNodeNum = { |layer, key|
    (((~kfLayerOrder.indexOf(layer.asSymbol) ? 0) * 100)
        + ((~kfPatchKeys.(layer).indexOf(key.asSymbol) ? 0) + 1))
};

// ----- §6 step 1: cable budget ------------------------------------------
~kfStep1Budget = { |facts, cfg|
    (cfg.kappa * facts[\census].sum { |row| row.sum })
        .round.asInteger.clip(cfg.cableMin, cfg.cableMax)
};

// ----- §6 step 2: layer pair --------------------------------------------
// every census edge yields κ cables in the direction it is drawn; the diagonal
// (intra-layer) is admitted only up to `patchIntraMax` of the table, and the
// interlayer slots are cycled to keep |cables| = budget exactly
~kfStep2Pairs = { |facts, budget, cfg|
    var slots = [], inter, intra, take, out, byKey;
    // ROUND ROBIN over `j`: with κ·ΣK over the ceiling the cut would otherwise
    // take the first edges whole and leave whole layers of the drawing unwired
    // (V10 "layer without an input"). One cable per drawn edge comes first.
    byKey = { |a, b|
        (a[\j] < b[\j]) or: { (a[\j] == b[\j]) and: {
            (a[\key] < b[\key]) or: { (a[\key] == b[\key]) and: { a[\ei] < b[\ei] } } } };
    };
    facts[\edgeTab].do { |e, ei|
        cfg.kappa.do { |j|
            slots = slots.add((
                src: e[\src], dst: e[\dst], ret: e[\ret], strong: e[\strong],
                routeLen: e[\routeLen] ? 1, ei: ei, j: j,
                key: ~kfScramble.([facts[\seed], ei + 1, (j + 1) * ~kfSalt[\slotJ],
                    facts[\tiers]])
            ));
        };
    };
    slots = slots.sort(byKey);
    inter = slots.select { |x| x[\src] != x[\dst] };
    intra = slots.select { |x| x[\src] == x[\dst] };
    take = (budget * cfg.patchIntraMax).floor.asInteger;
    out = (inter ++ intra.copyRange(0, take - 1)).sort(byKey);
    if(out.size > budget) { out = out.copyRange(0, budget - 1) };
    while { (out.size < budget) and: { inter.notEmpty } } {
        out = out.add(inter[out.size mod: inter.size]);
    };
    out
};

// ----- §6 step 3: class and concrete node -------------------------------
// The KIND of the drawn edge picks the family of classes (rule 6 strength: a
// strong coupling addresses the identity classes S/P/W/E, a weak one the
// balance classes M/D/G/L); the node inside the family is the scramble. As a
// SOURCE a node that already has an incoming cable ranks first — that is where
// drawn depth comes from. `st` is read, never written.
~kfStep3Node = { |facts, layer, role, strong, st, u, filter|
    var keys = ~kfPatchKeys.(layer.asSymbol);
    var idn = (~kfLayerOrder.indexOf(layer.asSymbol) ? 0) + 1;
    var fam = if(strong) { [\S, \P, \W, \E] } { [\M, \D, \G, \L] };
    keys.select { |k| filter.(k) }.collect { |k|
        var cls = ~kfRow.(layer, k)[0];
        var id = ~kfIdOf.(layer, k);
        var chain = if((role == \src) and: { (st[\inE][id] ? []).notEmpty }) { 0 } { 2 };
        [ k, chain + if(fam.includes(cls)) { 0 } { 1 }
            + ~kfScramble.([facts[\seed], (u * ~kfSalt[\nodeU]) + 1, idn,
                (keys.indexOf(k) ? 0) + 1]) ]
    }.sort { |a, b|
        (a[1] < b[1]) or: { (a[1] == b[1]) and: { a[0].asString < b[0].asString } };
    }.collect { |r| r[0] }
};

// ----- §6 step 4: the band ----------------------------------------------
// f_c = patchRate / (routeLen^γ · τ_cell) — the long drawn route gives the slow
// cable — then clipped to f_max of the destination (§5) and to the fastest band
// its class admits. The exponent is the price of the drawing: routeLen spans
// ×30 while the ladder spans ×30000, so the raw ratio cannot reach four bands.
~kfStep4Band = { |facts, routeLen, cfg|
    cfg.patchRate / ((max(1, routeLen) ** cfg.patchGamma) * max(1e-9, facts[\tauCell]))
};

~kfPatchFcFor = { |layer, key, win, wantF, wins|
    var row = ~kfRow.(layer, key);
    if(row.isNil) { nil } {
        var bands = (~kfClass[row[0]] ? ())[\bands] ? [\block];
        var fastest = ~kfBandOrder.detect { |b| bands.includes(b) } ? \block;
        var w2 = wins.copy;
        var fmax, ceil, floor, fc;
        w2[~kfIdOf.(layer, key)] = win;
        fmax = ~kfFmaxOf.(layer, key, w2) ? 1e9;
        ceil = min(min(~kfBandNarrow.(fastest)[1], fmax), ~kfFcCeil.value);
        floor = ~kfBandNarrow.(\block)[0];
        if(ceil < floor) { nil } {
            fc = wantF.clip(floor, ceil);
            ( band: ~kfBandOfFc.(fc), fc: fc, floor: floor, ceil: ceil )
        };
    };
};

// ----- §6 step 5: polarity is the KIND of the edge ----------------------
// a forward edge is +1, a drawn back edge is −1 — the inversion that turns the
// c axis into the mode axis (one inversion in a two-node cycle is odd)
~kfStep5Pol = { |ret| if(ret == true) { -1 } { 1 } };

// ----- §6 step 6: gain --------------------------------------------------
// gain = clip(depthGain(c) · c_AB, gainMin, gain_max(class)). For a loop the
// reference's (1 + 0.5·loop) is replaced by the Λ TARGET of the c axis: the two
// gains of a cycle multiply to Λ, and Λ IS the mode, so the axis must own it.
~kfStep6Gain = { |gmax, w, isLoop, c, lamT, cfg|
    var base = cfg.patchGainLo + ((cfg.patchGainHi - cfg.patchGainLo) * c);
    var g = if(isLoop) { lamT.sqrt * w } { base * w };
    g.clip(cfg.gainMin, max(cfg.gainMin, gmax))
};

// ----- §6 step 7: curve -------------------------------------------------
// convergence node (indeg ≥ 2) => clip; a drawn loop => fold, but only classes
// M/S/W and only in gang/block (§13 q5); P is always step; the rest clip
~kfStep7Curve = { |cls, indeg, isLoop, band|
    case
    { cls == \P } { \step }
    { indeg >= 2 } { \clip }
    { isLoop and: { ~kfLoopClasses.includes(cls) } and: { ~kfFoldBands.includes(band) } } { \fold }
    { \clip }
};

// ----- §6 step 8: ladder normalization ----------------------------------
// Along every maximal directed path τ must not fall (V6) and the path may not
// need a fifth rung (V5). The band structure of step 4 makes both true by
// construction, so this step is the PROOF and not the repair: it walks the
// simple paths and returns the indices of the cables to cut. A non-empty return
// means step 4 or the ceilings of §5 were edited.
~kfStep8Ladder = { |cables, cfg|
    var adj = (), cut = [], walk, tau;
    tau = { |c| 1 / (2pi * max(1e-9, c[\fc])) };
    cables.do { |c, i|
        var sid = ~kfIdOf.(c[\src][0], c[\src][1]);
        adj[sid] = (adj[sid] ? []).add(( to: ~kfIdOf.(c[\dst][0], c[\dst][1]), i: i, c: c ));
    };
    walk = { |node, seen, prev, n|
        (adj[node] ? []).do { |e|
            if(seen.includes(e[\to]).not) {
                case
                { (n + 1) > cfg.depthMax } { cut = cut.add(e[\i]) }
                { prev.notNil and: { tau.(e[\c]) < (tau.(prev[\c]) * cfg.ladderRatio) } } {
                    cut = cut.add(e[\i]);
                }
                { walk.(e[\to], seen ++ [e[\to]], e, n + 1) };
            };
        };
    };
    adj.keys.asArray.sort { |a, b| a.asString < b.asString }.do { |v| walk.(v, [v], nil, 0) };
    cut.as(Set).asArray.sort
};

// ----- windows and rests (§6, after step 8) -----------------------------
// The act owns windows, curves, bands and the RESTS OF ITS DESTINATIONS — of
// them only: a node the act does not address keeps its preset (reference §6).
// Every destination carries a rest without exception: V7 wants the rest inside
// the window with the margin, and a scheme with no `rest:` section is rejected
// the moment a live value sits outside the new window.
~kfPatchWinP = { |layer, key, u, cfg|
    var pos = ~kfNodePos.(layer, key);
    // two positions is the ARITHMETIC floor, whatever `pPosMin` says: with one
    // there is no gap by which to open the window, and a cable into a node with
    // a single position can never step at all
    if(pos.isNil or: { pos.size < max(2, cfg.pPosMin) }) { nil } {
        var k = min(cfg.patchPosWin, pos.size);
        var span = max(1, pos.size - k + 1);
        var i0 = (u * span).floor.asInteger.clip(0, span - 1);
        var sel = pos.copyRange(i0, i0 + k - 1);
        var gaps = (0 .. pos.size - 2).collect { |i| pos[i + 1] - pos[i] };
        var eps = gaps.minItem * cfg.patchPosGap;
        // the rest of a step node is a POSITION of its table, never the middle
        // of the window: ~kfRestApply snaps it there anyway, and the preset has
        // to hold what will sound
        [[(sel.first - eps).clip(0, 1), (sel.last + eps).clip(0, 1)], sel[sel.size div: 2]]
    };
};

// [ window, rest, relative? ]. A window of class L is NOT a pair of numbers
// the act owns: §5.1 gives ±`patchLDb` dB around the LEVEL of the layer, the
// level belongs to the hand and the preset (reference §6), and the derivation
// may not read the live field (D78). So the cable carries the RULE, the window
// returned here is the same rule against the SPEC DEFAULT — the derivation's own
// pure reference frame — and no rest is derived for the node at all: it already
// has one, and it is the hand's.
~kfPatchWin = { |layer, key, u, ur, st, ctx, cfg|
    var row = ~kfRow.(layer, key);
    var cs = ~kfSpecOfNode.(layer, key);
    if(row.isNil or: { cs.isNil }) { nil } {
        var cls = row[0], ex = row[2] ? ();
        var lo, hi, other, wmin;
        case
        { cls == \P } { ~kfPatchWinP.(layer, key, u, cfg) }
        { cls == \L } {
            [~kfWinRel.(cs, (ctx[\rest][~kfIdOf.(layer, key)] ? 0.5), cfg.patchLDb), nil, true]
        }
        {
            lo = cfg.patchWinLo + (cfg.patchWinSpan * u);
            hi = lo + cfg.patchWinWidth;
            ex[\wmin] !? { |v| lo = max(lo, v) };
            ex[\wmax] !? { |v| hi = min(hi, v) };
            // the §C.5 canon of the epsilon pairs, in the node's own space (V12):
            // freqLo may never reach over freqHi in ANY state of the window, and
            // the mode stratum may never sink 6 dB under the flow it carries.
            // The other side of the pair is read where the validator reads it —
            // its window if the act addresses it, its resting value otherwise
            other = { |k, edge|
                var w = st[\wins][~kfIdOf.(\epsilon, k)];
                if(w.notNil) { w[edge] } { ctx[\rest][~kfIdOf.(\epsilon, k)] ? 0.5 };
            };
            if(layer.asSymbol == \epsilon) {
                var csm = ~kfSpecOfNode.(\epsilon, \mLevel);
                var csf = ~kfSpecOfNode.(\epsilon, \flowLevel);
                case
                { key.asSymbol == \freqLo } { hi = min(hi, other.(\freqHi, 0) - cfg.patchEpsGap) }
                { key.asSymbol == \freqHi } { lo = max(lo, other.(\freqLo, 1) + cfg.patchEpsGap) }
                { (key.asSymbol == \mLevel) and: { csf.notNil } } {
                    lo = max(lo, cs.unmap(csf.map(other.(\flowLevel, 1)) * 0.5) + cfg.patchEpsGap);
                }
                { (key.asSymbol == \flowLevel) and: { csm.notNil } } {
                    hi = min(hi, cs.unmap(csm.map(other.(\mLevel, 0)) * 2) - cfg.patchEpsGap);
                }
                { };
            };
            lo = lo.clip(0, 1); hi = hi.clip(0, 1);
            wmin = cfg.patchWinMin;
            if((hi - lo) < wmin) { nil } {
                [[lo, hi], (cfg.patchRestLo + ((cfg.patchRestHi - cfg.patchRestLo) * ur))
                    .clip(lo + cfg.restMargin, hi - cfg.restMargin), false]
            };
        };
    };
};

// ----- §F on REACHABILITY, not on the direct edge (reference 2.5) -------
~kfPatchFOk = { |a, b|
    var pa = a.asString.split($.), pb = b.asString.split($.);
    var ra = ~kfRow.(pa[0].asSymbol, pa[1].asSymbol);
    var rb = ~kfRow.(pb[0].asSymbol, pb[1].asSymbol);
    if(ra.isNil or: { rb.isNil }) { true } {
        ((ra[0] == \E) and: { rb[0] == \G }).not and: {
            ((pa[0] == pb[0]) and: {
                ((ra[0] == \P) and: { rb[0] == \D })
                    or: { (ra[0] == \D) and: { rb[0] == \P } };
            }).not;
        };
    };
};

~kfPatchIncomm = { |t1, t2, cfg|
    var r = max(t1, t2) / max(1e-9, min(t1, t2));
    (1..cfg.incommMax).every { |p| (1..cfg.incommMax).every { |q|
        var f = p / q;
        (p.gcd(q) != 1) or: { f < 1 } or: { (r - f).abs > (f * cfg.incommTol) };
    }};
};

// V11: two stepping fundamentals on commensurable clocks read as a chord
// progression, and the ratio is judged IN THE OCTAVE (both P clocks live in B4)
~kfPatchIncommOct = { |f1, f2, cfg|
    var oct = (max(f1, f2) / max(1e-9, min(f1, f2))).log2;
    var tol = (1 + cfg.incommTol).log2;
    (1..cfg.incommMax).every { |p| (1..cfg.incommMax).every { |q|
        var f = p / q, d;
        if((p.gcd(q) != 1) or: { f < 1 }) { true } {
            d = (oct - f.log2).mod(1.0);
            min(d, 1 - d) > tol
        };
    }};
};

// ----- the assembler: the eight steps into one `schaltung` --------------
// Pure: it reads the tables (~kfNodeTable, ~ungSpecs, ~cfg_kf) and the facts of
// ONE grid act, and touches no live state — `ctx` carries the resting values
// the derivation reasons against, and ~kfRandomize fills it from the SPEC
// DEFAULTS, not from the field (§17 D78). Nothing here builds an Ndef.
~kfSchemeFromGraph = { |facts, ctx|
    var cfg = ~cfg_kf;
    var c = (facts[\complexity] ? 0.5).clip(0, 1);
    var budget = ~kfStep1Budget.(facts, cfg);
    var slots = ~kfStep2Pairs.(facts, budget, cfg);
    var lamT = cfg.patchLamLo + ((cfg.patchLamHi - cfg.patchLamLo) * c);
    var wander = lamT > cfg.modeWanderung;
    var arrival = [\ioi0, \decel, \ioiMax, \popScale, \gapScale, \density];
    var st = ( wins: (), rests: (), rels: (), bands: (), inE: (), outE: (),
               cables: [], pNodes: [], pLayers: [], notes: [] );
    var anc, desc, fOk, ladderOk, winOf, bandFor, addCable, dstList, srcList, place;
    var loopPairs = [], legs = [], restSec = ();
    var lidx = facts[\layerIdx], cens = facts[\census];

    desc = { |id|
        var seen = [id], front = [id];
        while { front.notEmpty } {
            var nxt = [];
            front.do { |v| (st[\outE][v] ? []).do { |e|
                if(seen.includes(e[\to]).not) { seen = seen.add(e[\to]); nxt = nxt.add(e[\to]) };
            }};
            front = nxt;
        };
        seen
    };
    anc = { |id|
        var seen = [id], front = [id];
        while { front.notEmpty } {
            var nxt = [];
            front.do { |v| (st[\inE][v] ? []).do { |e|
                if(seen.includes(e[\from]).not) { seen = seen.add(e[\from]); nxt = nxt.add(e[\from]) };
            }};
            front = nxt;
        };
        seen
    };
    fOk = { |sid, did|
        var a = anc.(sid), b = desc.(did);
        a.every { |x| b.every { |y| ~kfPatchFOk.(x, y) } };
    };
    // The reciprocal edge of a two-node cycle is EXCLUDED here: a simple path
    // never walks u -> v -> u, so the validator never checks that pair — and no
    // cycle could satisfy the ladder if it did, since walking a cycle from each
    // of its nodes would ask one rung to be both the fastest and the slowest.
    // That is also why every cycle of this patcher is a PAIR.
    ladderOk = { |sid, did, bi|
        ((st[\outE][did] ? []).every { |e| (e[\to] == sid) or: { bi < e[\bi] } })
            and: { (st[\inE][sid] ? []).every { |e| (e[\from] == did) or: { e[\bi] < bi } } };
    };
    winOf = { |layer, key|
        var did = ~kfIdOf.(layer, key);
        if(st[\wins][did].notNil) { [st[\wins][did], st[\rests][did], st[\rels][did]] } {
            var num = ~kfPatchNodeNum.(layer, key);
            var li = lidx[layer.asSymbol] ? 0;
            ~kfPatchWin.(layer, key,
                ~kfScramble.([facts[\seed], num, (0..4).sum { |a| cens[a][li] }, facts[\tiers]]),
                ~kfScramble.([facts[\seed], num * ~kfSalt[\winRest], cens[li].sum,
                    facts[\tauCell]]),
                st, ctx, cfg)
        };
    };
    // a second cable into one node inherits the node's band: the ladder rank of
    // a node has to be ONE number, and V7 wants one window and one curve there
    bandFor = { |layer, key, win, wantF|
        var bf = ~kfPatchFcFor.(layer, key, win, wantF, st[\wins]);
        if(bf.isNil) { nil } {
            var band = st[\bands][~kfIdOf.(layer, key)] ? bf[\band];
            var rng = ~kfBandNarrow.(band);
            var lo = max(rng[0], bf[\floor]), hi = min(rng[1], bf[\ceil]);
            if(lo > hi) { nil } { [band, bf[\fc].clip(lo, hi)] };
        };
    };
    addCable = { |sl, sk, dl, dk, band, fc, pol, gain, win, rest, rel|
        var sid = ~kfIdOf.(sl, sk), did = ~kfIdOf.(dl, dk), bi = ~kfBandIdx.(band);
        var cab = ( src: [sl.asSymbol, sk.asSymbol], dst: [dl.asSymbol, dk.asSymbol],
                    pol: pol, gain: gain, fc: fc, band: band, curve: \clip );
        // a relative cable carries the RULE and no numbers: `win` would be a
        // second, silently stale answer to the question ~kfWinAbs answers
        if(rel == true) { cab[\winRel] = true; cab[\winDb] = cfg.patchLDb } { cab[\win] = win };
        st[\cables] = st[\cables].add(cab);
        st[\outE][sid] = (st[\outE][sid] ? []).add(( to: did, bi: bi, c: cab ));
        st[\inE][did]  = (st[\inE][did] ? []).add(( from: sid, bi: bi, c: cab ));
        st[\wins][did] = win; st[\rels][did] = (rel == true); st[\bands][did] = band;
        rest !? { st[\rests][did] = rest };
        if((~kfRow.(dl, dk)[0] == \P) and: { st[\pNodes].includes(did).not }) {
            st[\pNodes] = st[\pNodes].add(did);
            st[\pLayers] = st[\pLayers].add(dl.asSymbol);
        };
        cab
    };
    dstList = { |layer, strong, u, loopLeg|
        ~kfStep3Node.(facts, layer, \dst, strong, st, u, { |k|
            var cls = ~kfRow.(layer, k)[0], did = ~kfIdOf.(layer, k);
            ((st[\inE][did] ? []).size < cfg.fanIn)
                and: { (cls != \P) or: {
                    st[\pNodes].includes(did) or: {
                        (st[\pNodes].size < 2) and: { st[\pLayers].includes(layer.asSymbol).not };
                    };
                }}
                and: { loopLeg.not or: { ~kfLoopClasses.includes(cls) } };
        });
    };
    srcList = { |layer, strong, u, excludeId|
        ~kfStep3Node.(facts, layer, \src, strong, st, u, { |k|
            var sid = ~kfIdOf.(layer, k);
            (sid != excludeId) and: { (st[\outE][sid] ? []).size < cfg.fanOut }
                and: { wander.not or: { (layer.asSymbol != \theta) or: { arrival.includes(k).not } } };
        });
    };
    // one slot -> one cable, or nil when the drawing asks for a pair the canon
    // does not admit; the budget then falls short and the report says by how much
    place = { |sl|
        var wantF = ~kfStep4Band.(facts, sl[\routeLen], cfg);
        var pol = ~kfStep5Pol.(sl[\ret]);
        var dstL = sl[\dst].asSymbol, srcL = sl[\src].asSymbol;
        var wantB = ~kfBandOfFc.(wantF.clip(~kfBandNarrow.(\block)[0], ~kfBandNarrow.(\rauheit)[1]));
        var cand = dstList.(dstL, sl[\strong], sl[\key], false);
        var out = nil;
        // the drawn ratio first: a destination that can actually TAKE the band
        // the route length asks for is tried before one that would clip it to a
        // slower rung. Without this pass the fast bands stay empty (G7) even
        // where the drawing is short and the layer ceiling high
        cand = cand.select { |dk|
            var wr = winOf.(dstL, dk);
            var bf = wr !? { bandFor.(dstL, dk, wr[0], wantF) };
            bf.notNil and: { bf[0] == wantB };
        } ++ cand;
        cand.do { |dk|
            if(out.isNil) {
                var did = ~kfIdOf.(dstL, dk);
                var wr = winOf.(dstL, dk);
                var bf = wr !? { bandFor.(dstL, dk, wr[0], wantF) };
                if(bf.notNil) {
                    var bi = ~kfBandIdx.(bf[0]);
                    srcList.(srcL, sl[\strong], sl[\key] + ~kfSalt[\srcKey], did).do { |sk|
                        if(out.isNil) {
                            var sid = ~kfIdOf.(srcL, sk);
                            var dup = st[\cables].any { |cb|
                                (~kfIdOf.(cb[\src][0], cb[\src][1]) == sid)
                                    and: { ~kfIdOf.(cb[\dst][0], cb[\dst][1]) == did };
                            };
                            // a cycle is CLOSED ONLY BY A DRAWN BACK EDGE (the
                            // loop phase above): a pair that closes by accident
                            // carries two forward polarities, so its Λ counts
                            // toward the ceiling and its inversions are even —
                            // a mode the vocabulary has no name for (§13)
                            var closes = (st[\inE][sid] ? []).any { |e| e[\from] == did };
                            if(dup.not and: { closes.not } and: { ladderOk.(sid, did, bi) }
                                and: { fOk.(sid, did) }) {
                                out = addCable.(srcL, sk, dstL, dk, bf[0], bf[1], pol,
                                    ~kfStep6Gain.(~kfGainMax.(dstL, dk),
                                        facts[\cAB][lidx[srcL]][lidx[dstL]], false, c, lamT, cfg),
                                    wr[0], wr[1], wr[2]);
                            };
                        };
                    };
                };
            };
        };
        out
    };

    // ----- the drawn loops come first: they are the spine of the piece ---
    // §6 step 5 — a drawn back edge is the inversion, and a layer pair drawn in
    // both directions with a back edge among them is the cycle. epsilon is
    // barred (§C.5: no motion that reads as periodic) and there are at most
    // `patchLoopMax` of them (V8 admits three excited ones).
    (0..4).do { |a| (0..4).do { |b|
        if((a < b) and: { facts[\loopPair][a][b] }
            and: { ~kfLayerOrder[a] != \epsilon } and: { ~kfLayerOrder[b] != \epsilon }) {
            loopPairs = loopPairs.add([a, b,
                ~kfScramble.([facts[\seed], (a * 5) + b + 1, cens[a][b], cens[b][a]])]);
        };
    } };
    (0..4).do { |a|
        if((facts[\loopSelf] ? [])[a] == true and: { ~kfLayerOrder[a] != \epsilon }) {
            loopPairs = loopPairs.add([a, a,
                ~kfScramble.([facts[\seed], (a * 5) + a + 1, cens[a][a], facts[\tiers]])]);
        };
    };
    loopPairs = loopPairs.sort { |x, y|
        (x[2] < y[2]) or: { (x[2] == y[2]) and: { ((x[0] * 5) + x[1]) < ((y[0] * 5) + y[1]) } };
    }.copyRange(0, min(cfg.patchLoopMax, cfg.loopExcMax) - 1);

    loopPairs.do { |lp|
        var la = ~kfLayerOrder[lp[0]], lb = ~kfLayerOrder[lp[1]];
        var retE = facts[\edgeTab].detect { |e| e[\ret] and: {
            ((e[\src] == la) and: { e[\dst] == lb }) or: { (e[\src] == lb) and: { e[\dst] == la } };
        }};
        var placed = false;
        if(retE.notNil) {
            var xL = retE[\src], yL = retE[\dst];
            var fwdE = facts[\edgeTab].detect { |e|
                e[\ret].not and: { e[\src] == yL } and: { e[\dst] == xL };
            };
            var wantR = ~kfStep4Band.(facts, retE[\routeLen], cfg);
            var wantF = ~kfStep4Band.(facts, (fwdE !? { |e| e[\routeLen] }) ? 1, cfg);
            var w1 = facts[\cAB][lidx[xL]][lidx[yL]], w2 = facts[\cAB][lidx[yL]][lidx[xL]];
            var norm = max(1e-9, (w1 * w2).sqrt);
            var uKey = ~kfScramble.([facts[\seed], (lp[0] * 5) + lp[1] + ~kfSalt[\loopKey],
                facts[\tiers], 1]);
            dstList.(yL, retE[\strong], uKey, true).do { |vk|
                if(placed.not) {
                    dstList.(xL, retE[\strong], uKey + ~kfSalt[\dstKey], true).do { |uk|
                        if(placed.not) {
                            var uid = ~kfIdOf.(xL, uk), vid = ~kfIdOf.(yL, vk);
                            var wu = winOf.(xL, uk), wv = winOf.(yL, vk);
                            var bv = if(wv.notNil and: { uid != vid })
                                { bandFor.(yL, vk, wv[0], wantR) };
                            var bu = if(wu.notNil and: { uid != vid })
                                { bandFor.(xL, uk, wu[0], wantF) };
                            if(bv.notNil and: { bu.notNil }
                                and: { ladderOk.(uid, vid, ~kfBandIdx.(bv[0])) }
                                and: { ladderOk.(vid, uid, ~kfBandIdx.(bu[0])) }
                                and: { fOk.(uid, vid) } and: { fOk.(vid, uid) }) {
                                var c1 = addCable.(xL, uk, yL, vk, bv[0], bv[1], -1,
                                    ~kfStep6Gain.(~kfGainMax.(yL, vk), w1 / norm, true, c, lamT, cfg),
                                    wv[0], wv[1], wv[2]);
                                var c2 = addCable.(yL, vk, xL, uk, bu[0], bu[1], 1,
                                    ~kfStep6Gain.(~kfGainMax.(xL, uk), w2 / norm, true, c, lamT, cfg),
                                    wu[0], wu[1], wu[2]);
                                legs = legs.add([c1, c2]);
                                placed = true;
                            };
                        };
                    };
                };
            };
            if(placed.not) {
                st[\notes] = st[\notes].add("петля " ++ la ++ " <-> " ++ lb
                    ++ " нарисована, но узлов, допускающих её полосу, не нашлось");
            };
        };
    };

    // loop periods pairwise incommensurable (V8): the f_c pair of a loop is
    // scaled INSIDE its own band until T = 2·Στ clears every p/q, p,q ≤ 4
    block {
        // the pairs already kept are the reference: reading `legs` while it is
        // being shortened would let a dropped pair compare against ITSELF
        // (ratio 1/1, never incommensurable) and take the next return with it
        var kept = [];
        legs.do { |pair|
            var done = false;
            var tOf = { |sc| 2 * pair.sum { |cb| 1 / (2pi * (cb[\fc] / sc)) } };
            var prev = kept.collect { |pp| 2 * pp.sum { |cb| 1 / (2pi * cb[\fc]) } };
            cfg.patchPeriodScales.do { |sc|
                if(done.not) {
                    // four of the scales are < 1, so f_c GROWS: the ceiling of
                    // §5 (f_max of the destination) and the block limit have to
                    // travel with the band, else V9 catches what this fixed
                    var inRange = pair.every { |cb|
                        var rng = ~kfBandNarrow.(cb[\band]);
                        var fmax = ~kfFmaxOf.(cb[\dst][0], cb[\dst][1], st[\wins]) ? 1e9;
                        var hi = min(min(rng[1], fmax), ~kfFcCeil.value);
                        ((cb[\fc] / sc) >= rng[0]) and: { (cb[\fc] / sc) <= hi };
                    };
                    if(inRange and: { prev.every { |t| ~kfPatchIncomm.(t, tOf.(sc), cfg) } }) {
                        pair.do { |cb| cb[\fc] = cb[\fc] / sc };
                        done = true;
                    };
                };
            };
            if(done) { kept = kept.add(pair) } {
                var victim = pair[0];
                var sid = ~kfIdOf.(victim[\src][0], victim[\src][1]);
                var did = ~kfIdOf.(victim[\dst][0], victim[\dst][1]);
                st[\notes] = st[\notes].add("период петли "
                    ++ victim[\dst].collect(_.asString).join(".")
                    ++ " не разведён с предыдущими — возвратный кабель снят");
                st[\cables] = st[\cables].reject { |cb| cb === victim };
                st[\outE][sid] = (st[\outE][sid] ? []).reject { |e| e[\c] === victim };
                st[\inE][did] = (st[\inE][did] ? []).reject { |e| e[\c] === victim };
            };
        };
        legs = kept;
    };

    // ----- the rest of the budget ----------------------------------------
    slots.do { |sl| if(st[\cables].size < budget) { place.(sl) } };

    // ----- §6 step 7: the curve, over the FINAL indegrees -----------------
    st[\wins].keys.asArray.do { |did|
        var parts = did.asString.split($.);
        var row = ~kfRow.(parts[0].asSymbol, parts[1].asSymbol);
        var ins = st[\inE][did] ? [];
        var isLoop = ins.any { |e| (st[\outE][did] ? []).any { |o| o[\to] == e[\from] } };
        var curve = ~kfStep7Curve.(row[0], ins.size, isLoop, st[\bands][did] ? \block);
        ins.do { |e| e[\c][\curve] = curve };
    };

    // ----- two P destinations: their clocks must not be commensurable -----
    if(st[\pNodes].size == 2) {
        var first = (st[\inE][st[\pNodes][0]] ? []).collect { |e| e[\c] };
        var second = (st[\inE][st[\pNodes][1]] ? []).collect { |e| e[\c] };
        var f0 = first[0] !? { |cb| cb[\fc] };
        var done = first.isEmpty or: { second.isEmpty }
            or: { ~kfPatchIncommOct.(f0, second[0][\fc], cfg) };
        cfg.patchPeriodScales.do { |sc|
            if(done.not) {
                var f1 = f0 * sc;
                // four of the scales are > 1 here, so f_c GROWS: the ceilings of
                // §5 travel with the band exactly as in the loop block above, or
                // V9 catches what this fixed
                var inRange = second.every { |cb|
                    var rng = ~kfBandNarrow.(cb[\band] ? \block);
                    var fmax = ~kfFmaxOf.(cb[\dst][0], cb[\dst][1], st[\wins]) ? 1e9;
                    var hi = min(min(rng[1], fmax), ~kfFcCeil.value);
                    (f1 >= rng[0]) and: { f1 <= hi };
                };
                if(inRange and: { ~kfPatchIncommOct.(f0, f1, cfg) }) {
                    second.do { |cb| cb[\fc] = f1 };
                    done = true;
                };
            };
        };
        if(done.not) {
            st[\notes] = st[\notes].add("полосы двух P-целей не разведены — вторая снята");
            st[\cables] = st[\cables].reject { |cb| second.includes(cb) };
        };
    };

    // ----- §6 step 8: the ladder, as a proof ------------------------------
    block {
        var cut = ~kfStep8Ladder.(st[\cables], cfg);
        if(cut.notEmpty) {
            st[\notes] = st[\notes].add("шаг 8: срезано хвостов пути — " ++ cut.size);
            st[\cables] = st[\cables].reject { |cb, i| cut.includes(i) };
        };
    };

    // ----- a rest for EVERY destination the act OWNS ----------------------
    // …and only for those: the level of a layer (class L) is the hand's, and a
    // relative window is built around it instead of replacing it (§17 D91)
    st[\cables].do { |cb|
        var dl = cb[\dst][0], dk = cb[\dst][1];
        st[\rests][~kfIdOf.(dl, dk)] !? { |r|
            if(restSec[dl].isNil) { restSec[dl] = () };
            restSec[dl][dk] = r;
        };
    };

    (
        seed: facts[\seed], complexity: c, armTime: cfg.armTime,
        rest: restSec, cables: st[\cables],
        report: ( budget: budget, placed: st[\cables].size,
                  deficit: budget - st[\cables].size, lamTarget: lamT,
                  drawnLoops: legs.size, notes: st[\notes] )
    )
};

// ----- deterministic repair (§7): ordered, bounded, and never partial ----
// The eight steps hold V1–V13 by construction; this is the net under them, and
// every fix is a NUMBER pulled to the ceiling the canon states, never a rule
// bent. What cannot be pulled is CUT — and if errors survive `patchRepairMax`
// passes the patcher refuses whole (precedent ~konGenerate), leaving the live
// scheme untouched.
~kfPatchRepair = { |sch, v, ctx, cfg|
    var cables = (sch[\cables] ? []).select { |x| x[\enabled] != false }.collect { |x| x.copy };
    var wins = (), rests = (), drop = [], lam, restSec = ();
    var idOf = { |lk| ~kfIdOf.(lk[0], lk[1]) };

    // 1. per cable: gain, band, f_c and curve to the ceiling of the class
    cables.do { |cb, i|
        var dl = cb[\dst][0], dk = cb[\dst][1];
        var row = ~kfRow.(dl, dk);
        if(row.isNil or: { ~kfSpecOfNode.(dl, dk).isNil }
            or: { ~kfSpecOfNode.(cb[\src][0], cb[\src][1]).isNil }) {
            drop = drop.add(i);
        } {
            var cls = row[0];
            var cl = ~kfClass[cls] ? ();
            var gmax = ~kfGainMax.(dl, dk);
            cb[\pol] = if((cb[\pol] ? 1) < 0) { -1 } { 1 };
            cb[\gain] = (cb[\gain] ? 0).clip(cfg.gainMin, max(cfg.gainMin, gmax));
            if(gmax < cfg.gainMin) { drop = drop.add(i) };
            if((cl[\bands] ? [\block]).includes(cb[\band] ? \block).not) { cb[\band] = \block };
            if(cls == \P) { cb[\curve] = \step } {
                if((cl[\curve] ? [\clip]).includes(cb[\curve] ? \clip).not) { cb[\curve] = \clip };
                if((cb[\curve] == \fold) and: { ~kfFoldBands.includes(cb[\band]).not }) {
                    cb[\curve] = \clip;
                };
            };
            wins[idOf.(cb[\dst])] = ~kfWinAbs.(dl, dk, cb);
        };
    };
    // windows are needed whole before f_c: the sampling law reads the window of
    // the rate node, so a clamp done per cable would use a half-built table
    cables.do { |cb, i|
        var dl = cb[\dst][0], dk = cb[\dst][1];
        if(drop.includes(i).not) {
            var rng = ~kfBandNarrow.(cb[\band] ? \block);
            var fmax = ~kfFmaxOf.(dl, dk, wins) ? 1e9;
            var ceil = min(min(rng[1], fmax), ~kfFcCeil.value);
            if(ceil < rng[0]) { drop = drop.add(i) } { cb[\fc] = (cb[\fc] ? rng[0]).clip(rng[0], ceil) };
        };
    };

    // 2. per destination: the window inside the canon, the rest inside the
    // window (P: on a position of its table), one window and one curve per node
    wins.keysDo { |did|
        var parts = did.asString.split($.);
        var l = parts[0].asSymbol, k = parts[1].asSymbol;
        var row = ~kfRow.(l, k);
        var mine = cables.select { |cb, i| (idOf.(cb[\dst]) == did) and: { drop.includes(i).not } };
        if(row.notNil and: { mine.notEmpty } and: { mine[0][\winRel] == true }) {
            // neither the window nor the rest of a relative destination is the
            // scheme's to pull: ~kfWinAbs derives the window from the live level
            // and the level is the hand's (§17 D91). One curve per node still holds
            mine.do { |cb| cb[\curve] = mine[0][\curve] };
        };
        if(row.notNil and: { mine.notEmpty } and: { mine[0][\winRel] != true }) {
            var ex = row[2] ? ();
            var w = (mine[0][\win] ? [0, 1]).copy;
            var r = ((sch[\rest] ? ())[l] ? ())[k];
            var pos;
            w[0] = w[0].clip(0, 1); w[1] = w[1].clip(0, 1);
            ex[\wmin] !? { |x| w[0] = max(w[0], x) };
            ex[\wmax] !? { |x| w[1] = min(w[1], x) };
            if(row[0] == \P) {
                pos = ~kfWinPos.(l, k, w);
                if(pos.size > cfg.pPosMax) {
                    pos = ~kfNodePos.(l, k).select { |x| (x >= w[0]) and: { x <= w[1] } }
                        .copyRange(0, cfg.pPosMax - 1);
                    w = [pos.first, pos.last];
                };
                if(pos.size < cfg.pPosMin) {
                    var re = ~kfPatchWinP.(l, k, 0.5, cfg);
                    if(re.isNil) {
                        cables.do { |cb, i| if(idOf.(cb[\dst]) == did) { drop = drop.add(i) } };
                    } { w = re[0]; r = re[1] };
                    pos = ~kfWinPos.(l, k, w);
                };
                if(pos.notEmpty) { r = pos.minItem { |x| (x - (r ? 0.5)).abs } };
            } {
                if((w[1] - w[0]) < (2 * cfg.restMargin)) {
                    cables.do { |cb, i| if(idOf.(cb[\dst]) == did) { drop = drop.add(i) } };
                } {
                    r = (r ? ((w[0] + w[1]) * 0.5)).clip(w[0] + cfg.restMargin, w[1] - cfg.restMargin);
                };
            };
            mine.do { |cb| cb[\win] = w; cb[\curve] = mine[0][\curve] };
            rests[did] = r;
        };
    };

    cables = cables.reject { |cb, i| drop.includes(i) };
    drop = [];

    // 3. fan-in / fan-out: the surplus cable is the LAST drawn one
    block {
        var fin = (), fout = ();
        cables.do { |cb, i|
            var s = idOf.(cb[\src]), d = idOf.(cb[\dst]);
            fin[d] = (fin[d] ? 0) + 1; fout[s] = (fout[s] ? 0) + 1;
            if(fin[d] > cfg.fanIn or: { fout[s] > cfg.fanOut }) { drop = drop.add(i) };
        };
        cables = cables.reject { |cb, i| drop.includes(i) };
        drop = [];
    };

    // 4. the ladder (§6 step 8) and the loops (V8)
    block {
        var cut = ~kfStep8Ladder.(cables, cfg);
        cables = cables.reject { |cb, i| cut.includes(i) };
    };
    lam = ~kfLambda.(( cables: cables ));
    lam[\loops].do { |lp, li|
        if(lp[\lam] > cfg.lamMax) {
            var sc = ((cfg.lamMax * 0.99) / max(1e-9, lp[\lam])) ** (1 / max(1, lp[\len]));
            cables.do { |cb|
                var s = idOf.(cb[\src]), d = idOf.(cb[\dst]);
                if(lp[\nodes].includes(s) and: { lp[\nodes].includes(d) }) {
                    cb[\gain] = (cb[\gain] * sc).clip(cfg.gainMin, ~kfGainMax.(cb[\dst][0], cb[\dst][1]));
                };
            };
        };
    };
    // an excited loop over the ceiling, a loop through epsilon and a pair of
    // commensurable periods are all cut the same way: the RETURN cable goes,
    // and the pair stops being a cycle at all
    block {
        var kill = [], exc = 0;
        lam[\loops].do { |lp, li|
            var bad = lp[\nodes].any { |nid| nid.asString.split($.)[0] == "epsilon" };
            if(lp[\lam] >= 1) { exc = exc + 1; if(exc > cfg.loopExcMax) { bad = true } };
            lam[\loops].copyRange(0, li - 1).do { |pp|
                if(~kfPatchIncomm.(pp[\period], lp[\period], cfg).not) { bad = true };
            };
            if(bad) { kill = kill.add(lp[\nodes]) };
        };
        kill.do { |ns|
            var victim = cables.detect { |cb|
                (ns.includes(idOf.(cb[\src]))) and: { ns.includes(idOf.(cb[\dst])) }
                    and: { (cb[\pol] ? 1) < 0 };
            } ?? {
                cables.detect { |cb|
                    (ns.includes(idOf.(cb[\src]))) and: { ns.includes(idOf.(cb[\dst])) };
                };
            };
            victim !? { cables = cables.reject { |cb| cb === victim } };
        };
    };

    // 5. whatever the four passes above did not name is cut by its own error
    // message: the first surviving error names its cable, and that cable goes
    if(v.notNil and: { v[\errors].notEmpty } and: { cables.notEmpty }) {
        var msg = v[\errors].first;
        var tagged = { |lk| msg.contains(~kfIdTag.(idOf.(lk))) };
        var victim = cables.select { |cb| tagged.(cb[\src]) and: { tagged.(cb[\dst]) } }.last
            ?? { cables.select { |cb| tagged.(cb[\dst]) }.last }
            ?? { cables.select { |cb| tagged.(cb[\src]) }.last };
        victim !? { cables = cables.reject { |cb| cb === victim } };
    };

    cables.do { |cb|
        var dl = cb[\dst][0], dk = cb[\dst][1];
        var r = if(cb[\winRel] == true) { nil } {
            rests[idOf.(cb[\dst])] ?? { ((sch[\rest] ? ())[dl] ? ())[dk] ? 0.5 };
        };
        r !? {
            if(restSec[dl].isNil) { restSec[dl] = () };
            restSec[dl][dk] = r;
        };
    };
    sch.copy.putAll(( cables: cables, rest: restSec ))
};

// ----- §7 guarantees G1–G10 --------------------------------------------
// G4 (census connectivity), G5 (an excited loop) and G6 (depths 1–4) are NOT
// reachable at low `c` and saying otherwise would be a lie about the drawing:
// the back-edge quota of 0_grid is floor(c·N/4), so below `patchGuardC` there
// are no returns at all — no inversion, no cycle, no long route, and §6 step 5
// states outright that c = 0 is `ruhe`. Below the threshold they are reported
// as NOTES; above it they are guarantees.
~kfGuarantees = { |sch, v, facts, cfg|
    var c = (facts !? { |f| f[\complexity] }) ? 1;
    var cables = (sch[\cables] ? []).select { |x| x[\enabled] != false };
    var e = v[\errors] ? [];
    var has = { |code| e.any { |x| x.beginsWith(code) } };
    var g = (), bands, cens = (), strong = true, order;
    var drawnLoop, drawnBands, drawnBandSet;
    var note = { |ok, txt| if(ok) { nil } { txt } };
    order = ((~activeLayers ? ~kfLayerOrder).asArray).select { |l| ~ungSpecs[l].notNil };
    if(order.isEmpty) { order = ~kfLayerOrder };
    cables.do { |cb|
        var a = cb[\src][0].asSymbol, b = cb[\dst][0].asSymbol;
        cens[(a.asString ++ ">" ++ b.asString).asSymbol] = true;
    };
    order.do { |a|
        var seen = [a], front = [a];
        while { front.notEmpty } {
            var nxt = [];
            front.do { |x| order.do { |y|
                if(seen.includes(y).not
                    and: { cens[(x.asString ++ ">" ++ y.asString).asSymbol] == true }) {
                    seen = seen.add(y); nxt = nxt.add(y);
                };
            }};
            front = nxt;
        };
        if(seen.size < order.size) { strong = false };
    };
    drawnBandSet = if(facts.isNil) { [] } {
        facts[\edgeTab].collect { |x|
            ~kfBandOfFc.(~kfStep4Band.(facts, x[\routeLen], cfg)
                .clip(~kfBandNarrow.(\block)[0], ~kfBandNarrow.(\rauheit)[1]));
        }.as(Set).asArray;
    };
    // "the bands the composition of targets ADMITS" is a statement about the
    // drawn EDGE and its destination layer together, not about the scheme's
    // targets as a bag: one node carries exactly one rung, so a single zeta
    // target would otherwise "admit" all four bands at once and make
    // stratification unsatisfiable by arithmetic. A band is admitted when some
    // drawn route asks for it INTO a layer that holds a node whose class and §5
    // ceiling can take it — that is the opportunity the derivation may not skip.
    bands = ~kfBandOrder.select { |b|
        facts.notNil and: { facts[\edgeTab].any { |x|
            (~kfBandOfFc.(~kfStep4Band.(facts, x[\routeLen], cfg)
                .clip(~kfBandNarrow.(\block)[0], ~kfBandNarrow.(\rauheit)[1])) == b)
            and: { ~kfPatchKeys.(x[\dst]).any { |k|
                var row = ~kfRow.(x[\dst], k);
                row.notNil and: { ((~kfClass[row[0]] ? ())[\bands] ? []).includes(b) }
                    and: { (~kfFmaxOf.(x[\dst], k, ()) ? 0) >= ~kfBandNarrow.(b)[0] };
            }};
        }};
    };
    // epsilon is barred from every cycle (§C.5), so a pair drawn through it is
    // not a loop candidate at all — counting it here would demand a loop the
    // canon forbids
    drawnLoop = facts.notNil and: {
        ((0..4).any { |a| (0..4).any { |b|
            (a < b) and: { facts[\loopPair][a][b] }
                and: { ~kfLayerOrder[a] != \epsilon } and: { ~kfLayerOrder[b] != \epsilon };
        } })
            or: { (facts[\loopSelf] ? []).any { |x, i| (x == true)
                and: { ~kfLayerOrder[i] != \epsilon } } };
    };
    drawnBands = drawnBandSet.size;
    g[\G1] = has.("V1").not and: { has.("V3").not } and: { has.("V4").not };
    g[\G2] = has.("V9").not and: { has.("V7").not } and: { has.("V12").not } and: { has.("V13").not };
    g[\G3] = has.("V6").not and: { ~kfStep8Ladder.(cables, cfg).isEmpty };
    g[\G4] = (v[\interlayer] >= cfg.interlayerMin)
        and: { order.every { |l|
            cables.any { |cb| cb[\src][0].asSymbol == l } and: {
                cables.any { |cb| cb[\dst][0].asSymbol == l } };
        }} and: { strong };
    g[\G5] = (v[\loops].count { |l| l[\lam] >= 1 } >= 1)
        and: { v[\loops].size <= cfg.loopExcMax } and: { has.("Λ несоизмеримость").not };
    g[\G6] = (1..cfg.depthMax).every { |d| v[\depths].includes(d) };
    g[\G7] = bands.every { |b| cables.any { |cb| (cb[\band] ? \block) == b } };
    g[\G8] = (cables.size >= cfg.cableMin) and: { cables.size <= cfg.cableMax }
        and: { has.("V2").not };
    g[\G9] = cables.every { |cb| (cb[\gain] ? 0) >= cfg.gainMin };
    g[\G10] = has.("V11").not;
    g[\drawnLoop] = drawnLoop;
    g[\drawnBands] = drawnBands;
    g[\notes] = [
        note.(g[\G1], "G1 §F-инварианты нарушены (V1/V3/V4)"),
        note.(g[\G2], "G2 канон узла нарушен (V7/V9/V12/V13)"),
        note.(g[\G3], "G3 лестница τ не держится (V6/шаг 8)"),
        note.(g[\G4], "G4 связность census/межслойная доля не держится"),
        note.(g[\G5], "G5 возбуждённой петли нет"),
        note.(g[\G6], "G6 присутствуют не все глубины 1–4 (" ++ v[\depths] ++ ")"),
        note.(g[\G7], "G7 полоса без единого кабеля: "
            ++ bands.reject { |b| cables.any { |cb| (cb[\band] ? \block) == b } }),
        note.(g[\G8], "G8 кабелей " ++ cables.size ++ " вне 8–64"),
        note.(g[\G9], "G9 есть кабель с усилением < " ++ cfg.gainMin),
        note.(g[\G10], "G10 несоизмеримость P-целей не держится (V11)")
    ].reject(_.isNil);
    if(drawnLoop.not) {
        g[\notes] = g[\notes].collect { |x|
            if(x.beginsWith("G4") or: { x.beginsWith("G5") }) {
                x ++ " — в рисунке (c " ++ c ++ ") нет ни одной замкнутой пары, "
                    ++ "гарантия неприменима"
            } { x };
        };
    };
    if(drawnBands < cfg.depthMax) {
        g[\notes] = g[\notes].collect { |x|
            if(x.beginsWith("G6")) {
                x ++ " — рисунок даёт " ++ drawnBands ++ " полос(ы) из " ++ cfg.depthMax
                    ++ ", четвёртой ступени в нём нет"
            } { x };
        };
    };
    g
};

// the resting context of ANY derivation is the SPEC, never the live field: a
// scheme must be a function of its drawing alone, and reading ~kfNodes here
// would make the same act derive differently under a different preset. The
// canon guards of §5 that need the rest of a node the derivation does not
// address are therefore measured against its DEFAULT; ~kfValidate reads the
// live value and may object — see §17 D78
~kfSpecRest = {
    var ctx = ( rest: () );
    ~ungSpecs.keysValuesDo { |l, sp| sp.params.do { |p|
        ctx[\rest][~kfIdOf.(l, p[\key])] = p[\spec].unmap(p[\spec].default);
    }};
    ctx
};

// reference §6: the eight steps, the ordered repair and the verdict over ONE
// drawing. BOTH readers of a grid act enter here — ~kfRandomize with the
// drawing of its own seed, ~konDerive with the drawing of the piece — so the
// law of derivation has exactly one implementation, as the census law does
// (§17 D85). Refusal is loud and whole: nil, and the live scheme untouched
~kfDeriveScheme = { |facts, tag|
    var cfg = ~cfg_kf;
    var ctx = ~kfSpecRest.value;
    var sch = ~kfSchemeFromGraph.(facts, ctx);
    var v = ~kfValidate.(sch), passes = 0, gr;
    while { v[\valid].not and: { passes < cfg.patchRepairMax } } {
        sch = ~kfPatchRepair.(sch, v, ctx, cfg);
        v = ~kfValidate.(sch);
        passes = passes + 1;
    };
    if(v[\valid].not) {
        ("8_koppelfeld — " ++ (tag ? "деривация") ++ ": схема НЕ выведена, после "
            ++ passes ++ " проходов ремонта осталось нарушений: "
            ++ v[\errors].size).error;
        v[\errors].do { |x| ("    ОШИБКА " ++ x).postln };
        nil
    } {
        // G8 (§7) is a GUARANTEE of the patcher, and the validator files the
        // floor as a NOTE — correct for a scheme written by hand, silent for a
        // derived one: the repair cuts cables (fan-in, ladder, the second P
        // target), and a scheme under the floor would have gone out as a success
        // with the broken guarantee riding in the report. The refusal is the one
        // of `valid.not`: loud, whole, live scheme untouched
        if(v[\cables] < cfg.cableMin) {
            ("8_koppelfeld — " ++ (tag ? "деривация") ++ ": схема НЕ выведена, кабелей "
                ++ v[\cables] ++ " < пола " ++ cfg.cableMin ++ " — гарантия G8 §7 не "
                ++ "держится (ремонт снял кабели за " ++ passes ++ " проход(ов))").error;
            v[\notes].do { |x| ("    NOTE " ++ x).postln };
            nil
        } {
            gr = ~kfGuarantees.(sch, v, facts, cfg);
            sch[\mode] = v[\mode];
            sch[\loops] = v[\loops];
            sch[\report] = (sch[\report] ? ()).putAll((
                complexity: facts[\complexity],
                cables: v[\cables], targets: v[\targets],
                interlayer: v[\interlayer], depths: v[\depths],
                maxDepth: v[\maxDepth], lamMax: v[\lamMax], mode: v[\mode],
                loops: v[\loops].size, repairs: passes, valid: true,
                guarantees: gr,
                notes: ((sch[\report] ? ())[\notes] ? []) ++ gr[\notes] ++ v[\notes]
            ));
            sch
        };
    };
};

// ----- §7 the patcher: a patch in one click is a seed -------------------
~kfRandomize = { |seed, c = 0.5|
    var cfg = ~cfg_kf;
    if(~konActive == true) {
        ("8_koppelfeld — ~kfRandomize отключён при активном акте Konstruktion: "
            ++ "случайная схема разрушила бы выведенную пьесу (~konActive)").error;
        nil
    } {
        var grid, used, sch, passes = 0;
        seed = (seed ? Date.seed).asInteger;
        c = c.clip(0, 1);
        // ~gridGenerate refuses after ~cfg_grid.graphTries graphs; the walk over
        // the neighbouring seeds is deterministic and the seed that DREW is
        // written into the report — a silent substitution would break A-3
        while { grid.isNil and: { passes < cfg.patchSeedTries } } {
            used = seed + passes;
            grid = ~gridGenerate.(c, used);
            passes = passes + 1;
        };
        if(grid.isNil) {
            ("8_koppelfeld — ~kfRandomize: сетка не нарисовалась за "
                ++ cfg.patchSeedTries ++ " seed'ов от " ++ seed ++ " (c = " ++ c
                ++ ") — схема НЕ выведена").error;
            nil
        } {
            sch = ~kfDeriveScheme.(~kfGraphFacts.(grid, cfg.patchTtier),
                "~kfRandomize: seed " ++ seed ++ " · c " ++ c);
            // the seed that DREW is written into the report — a silent
            // substitution would break A-3
            sch !? { sch[\report].putAll(( seed: seed, gridSeed: used )) };
            sch
        };
    };
};

// ----- applying a scheme (§10.2): a cut, not a crossfade ---------------
~kfInstall = { |sch|
    var was = [];
    // the log is closed BEFORE ~kfCables moves, so the file ends on data of the
    // scheme its own preamble describes: the analyser judges occupancy by
    // `# win=`, D-9/D-10 by `# loops=` and the mode verdict by `# mode=`, and
    // rows recorded after a scheme change would be read against the old one
    ~kfLogFile !? {
        "8_koppelfeld — схема сменилась под открытым логом, лог закрыт".warn;
        ~kfLogStop.value;
    };
    ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        if(n[\cables].notEmpty) { was = was.add([l, k]) };
    }};
    ~kfCables = (sch[\cables] ? []).collect { |c| c.copy };
    ~kfPrune.value;
    // the node -> layer mapping is NOT rebuilt (footgun 9): only bodies change
    ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        var w = ~kfWireOf.(l, k);
        n[\win] = w[\win]; n[\winRel] = w[\winRel];
        n[\curve] = w[\curve]; n[\cables] = w[\cables];
        n[\hyst] = w[\hyst]; n[\dwell] = w[\dwell]; n[\cut] = w[\cut];
    }};
    ~kfFanOutBuild.value;
    // both rest passes run QUIET: each is followed by the very body build that
    // ~kfRestApply would otherwise trigger per node
    ~kfRestQuiet = true;
    // destination rests are brought into the NEW window through ~setParam:
    // ~ungVals, tuner and preset must carry what sounds, not what was asked
    // normalized in, normalized written: ~setParam takes a value in real units
    // and hands it back through `unmap(map(x))`, which on an exp ControlSpec
    // moves the last bit on every pass — a preset would restore the scheme all
    // but bit for bit, and applying one scheme twice would creep
    {
        ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
            if(n[\cables].notEmpty) {
                ~kfRestApply.(l, k, n[\rest]) !? { |acc|
                    ~ungValsSet.(l, k, n[\spec].map(acc));
                };
            };
        }};
        // the scheme's rest goes in BEFORE the bodies (and after ~kfFanOut,
        // which ~kfRest needs): a P body bakes the index of its start position
        // from the rest it sees at build time, and a rest arriving afterwards
        // would leave the machine sounding one position while ~ungVals stores
        // another until the dwell expires. \rN written now survives the rebuild
        // in the nodeMap (D26)
        (sch[\rest] ? ()).keysValuesDo { |l, e| e.keysValuesDo { |k, v|
            var cs = ~kfSpecOfNode.(l, k);
            cs !? {
                ~kfRestApply.(l, k, v.clip(0, 1)) !? { |acc|
                    ~ungValsSet.(l, k, cs.map(acc));
                };
            };
        }};
    }.protect { ~kfRestQuiet = false };
    was.do { |lk| ~kfNodeBody.(lk[0], lk[1]) };
    ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        if(n[\cables].notEmpty and: { was.any { |lk| (lk[0] == l) and: { lk[1] == k } }.not }) {
            ~kfNodeBody.(l, k);
        };
    }};
    ~kfSchaltung = sch;
    // ~kfPrune may have disabled a cable the verdict still counts: Λ, the
    // excited-loop count and the mode are all functions of the edge set
    ~kfVerdictStale = ~kfCables.any { |c| c[\enabled] == false };
    // §8.4: the mixer rebuilds its per-cable gain strips here. ~kfInstall runs
    // inside the fork of ~kfApply, so the .defer is owed by the GUI side
    ~kfGuiRelabel !? (_.value);
};

~kfApply = { |sch, armT|
    var t = armT ? (sch[\armTime] ? ~cfg_kf.armTime);
    var v = ~kfVerdictPost.(~kfValidate.(sch), "apply");
    ~kfVerdict = v;
    if(v[\valid].not) {
        ("8_koppelfeld — схема НЕ применена: " ++ v[\errors].size
            ++ " нарушение(й) V1–V13 (без частичных артефактов)").error;
        nil
    } {
        ~kfApplyTask !? { |tk| tk.stop };
        ~kfDisarm.(t, false);
        ~kfApplyTask = fork {
            (t + 0.05).wait;
            ~kfInstall.(sch);
            ~kfArm.(t);
            ~kfApplyTask = nil;
        };
        v
    };
};

// a cut on a form block boundary (Axiom IV): the same path with T = 0
~kfCut = { |sch| ~kfApply.(sch, 0) };

// ----- §8.2 the `patch:` section of a preset ---------------------------
// The module owns the FORMAT; 0_lib only drops the string into the file.
// The section is written off the LIVE registries, never off ~kfSchaltung: a
// preset must record what sounds, and a gain corrected by hand lives in
// ~kfCables and nowhere else.
~kfSchemeLive = {
    var sch = ~kfSchaltung ? ();
    var rest = ();
    ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        // only destinations: the other 111 − |targets| nodes hold the values of
        // the `layers` section, and a rest written for them would be a second
        // answer to the same question (§8.2)
        if(n[\cables].notEmpty) {
            if(rest[l].isNil) { rest[l] = () };
            rest[l][k] = n[\rest];
        };
    }};
    (
        seed: sch[\seed], complexity: sch[\complexity],
        armTime: sch[\armTime] ? ~cfg_kf.armTime,
        rest: rest,
        // disabled cables included: §10.3 keeps them in the table, and a preset
        // that dropped them would silently reroute the scheme on the next save
        cables: (~kfCables ? []).collect { |c| c.copy }
    )
};

// A preset that reads back as a DIFFERENT double is not a preset. round(0.0001)
// of the sections in 0_lib cannot be used here: `fc` lives at the 0.004 floor of
// band `block`, and rounding would push a cable out of its band (V9). Shortest
// literal that parses back to the very same value — verified for both `.asFloat`
// and the interpreter's own reading of the literal (2026-09-07).
// The CLASS is kept too: a Float printed as "1" comes back an Integer, and
// Integer does not answer `asStringPrec` (the S5 crash of log_patch.scd).
~kfNumText = { |v|
    if(v.isKindOf(Integer)) { v.asString } {
        var x = v.asFloat, out = nil;
        [6, 9, 12, 17].do { |p|
            if(out.isNil) {
                var t = x.asStringPrec(p);
                if(t.asFloat == x) { out = t };
            };
        };
        out = out ? x.asStringPrec(17);
        if(out.includes($.).not and: { out.includes($e).not }) { out = out ++ ".0" };
        out
    }
};

~kfLitText = { |v|
    case
    { v.isKindOf(Symbol) } { "\\" ++ v }
    { v.isKindOf(Boolean) } { v.asString }
    { v.isKindOf(SequenceableCollection) } {
        "[" ++ v.collect { |x| ~kfLitText.(x) }.join(", ") ++ "]"
    }
    { v.isKindOf(Number) } { ~kfNumText.(v) }
    { v.asString };
};

// fixed order, and only the keys a cable actually carries: a class L cable
// carries the RULE of its window (`winRel`/`winDb`) and never a pair of numbers
// (§17 D91) — an expanded window would measure the preset, not the scheme
~kfCableFields = [\src, \dst, \pol, \gain, \fc, \band, \curve, \win, \winRel,
    \winDb, \hyst, \dwell, \cut, \enabled];

~kfSchemeText = { |sch|
    var e = sch ? ();
    var rest = e[\rest] ? ();
    var lines = [], cabs;
    [\seed, \complexity, \armTime].do { |k|
        e[k] !? { |v| lines = lines.add("        " ++ k ++ ": " ++ ~kfLitText.(v)) };
    };
    // Event key order is HASH order: a section written straight off it would
    // differ between two saves of one scheme, and the stage criterion is that
    // save and load agree character for character
    if(rest.notEmpty) {
        var ls = rest.keys.asArray.sort { |a, b| a.asString < b.asString }.collect { |l|
            var ks = rest[l].keys.asArray.sort { |a, b| a.asString < b.asString };
            "            " ++ l ++ ": ( "
                ++ ks.collect { |k| k ++ ": " ++ ~kfLitText.(rest[l][k]) }.join(", ")
                ++ " )";
        };
        lines = lines.add("        rest: (\n" ++ ls.join(",\n") ++ "\n        )");
    };
    cabs = (e[\cables] ? []).collect { |c|
        "            ( " ++ ~kfCableFields.select { |f| c[f].notNil }
            .collect { |f| f ++ ": " ++ ~kfLitText.(c[f]) }.join(", ") ++ " )";
    };
    lines = lines.add("        cables: [\n" ++ cabs.join(",\n") ++ "\n        ]");
    "(\n" ++ lines.join(",\n") ++ "\n    )"
};

// what ~savePreset asks for: the whole section, or nil when there is no scheme
~kfPresetSection = {
    if((~kfCables ? []).isEmpty) { nil } {
        "    patch: " ++ ~kfSchemeText.(~kfSchemeLive.value)
    }
};

~kfSchemeFromPreset = { |e|
    var src = e ? ();
    var rest = (), out;
    (src[\rest] ? ()).keysValuesDo { |l, ks|
        var sec = ();
        ks.keysValuesDo { |k, v| sec[k.asSymbol] = v };
        rest[l.asSymbol] = sec;
    };
    out = (
        armTime: src[\armTime] ? ~cfg_kf.armTime, rest: rest,
        cables: (src[\cables] ? []).collect { |c|
            var cb = c.copy;
            cb[\src] = cb[\src].collect(_.asSymbol);
            cb[\dst] = cb[\dst].collect(_.asSymbol);
            cb[\band]  !? { |b| cb[\band]  = b.asSymbol };
            cb[\curve] !? { |b| cb[\curve] = b.asSymbol };
            cb
        }
    );
    src[\seed] !? { |v| out[\seed] = v };
    src[\complexity] !? { |v| out[\complexity] = v };
    // the mark has to happen BEFORE ~kfValidate, or the validator counts fan-in,
    // loops and bands over a node that does not exist. Same sense as ~kfPrune:
    // disabled with a warning, never rerouted to a neighbour (§10.3)
    out[\cables].do { |cb|
        if(cb[\enabled] != false) {
            var okS = ~kfSpecOfNode.(cb[\src][0], cb[\src][1]).notNil;
            var okD = ~kfSpecOfNode.(cb[\dst][0], cb[\dst][1]).notNil;
            if(okS.not or: { okD.not }) {
                cb[\enabled] = false;
                ("8_koppelfeld — кабель пресета " ++ cb[\src][0] ++ "." ++ cb[\src][1]
                    ++ " -> " ++ cb[\dst][0] ++ "." ++ cb[\dst][1]
                    ++ " ВЫКЛЮЧЕН: узла нет в spec (перенаправление запрещено)").warn;
            };
        };
    };
    out
};

// ----- the hand on a cable gain (§9.1 inspector, §8.4 gain strips) ------
// The cable event here is the SAME object the node registry carries: ~kfWireOf
// selects out of ~kfCables and ~kfInstall stores the selection into the node,
// so ~kfNodePlan, the next body build and ~kfPresetSection all read this write.
~kfGainSet = { |cable, v|
    if(cable.isNil) { nil } {
        var dl = cable[\dst][0].asSymbol, dk = cable[\dst][1].asSymbol;
        var n = (~kfNodes[dl] ? ())[dk];
        var g = v.clip(0, min(~cfg_kf.gainAbsMax, ~kfGainMax.(dl, dk)));
        var slot = n !? { n[\cables].detectIndex { |c| c === cable } };
        cable[\gain] = g;
        if(n.notNil and: { slot.notNil }) {
            Ndef(n[\node]).set(("g" ++ slot).asSymbol, g);
        };
        ~kfVerdictStale = true;
        g
    }
};

// Λ, the excited-loop count and the mode are functions of the gains, so a hand
// edit makes the verdict of the last ~kfApply a statement about a graph that no
// longer stands. Recomputed no more often than asked (both state strips ask once
// a second) and SILENTLY: ~kfVerdictPost is the voice of an apply, not of a knob
~kfVerdictRefresh = {
    if(~kfVerdictStale == true) {
        ~kfVerdict = ~kfValidate.(~kfSchemeLive.value);
        ~kfVerdictStale = false;
    };
    ~kfVerdict
};

// ONE sentence stating the condition of the field: the desk strip (§8.4) and
// the header of the koppelfeld window (§9.1) are two VIEWS of it, never two
// spellings — the module owns the format, exactly as it owns the preset section.
// Reading it refreshes a verdict aged by a hand edit, so every caller must be a
// slow one: both strips redraw at 1 Hz.
~kfStripText = {
    var v = ~kfVerdictRefresh.value;
    var rep = ~kfReport.value;
    // a NOTE is half the verdict: V10 files an unpatched layer as a note, so
    // "ok" alone would show a scheme that never touches epsilon as complete
    var notes = (v !? { |x| (x[\notes] ? []).size }) ? 0;
    // the parens are load-bearing: `++` after the last block of a bare `case`
    // would append to that BLOCK, not to the string the case returns
    var verdict = (case
        { v.isNil }   { "no verdict" }
        { v[\valid] } { "V1–V13 ok" }
        { "V1–V13 · " ++ v[\errors].size ++ " error" ++ if(v[\errors].size == 1) { "" } { "s" } })
        ++ if(notes > 0) { " · " ++ notes ++ " note" ++ if(notes == 1) { "" } { "s" } } { "" };
    (rep[\mode] ? "—").asString
        ++ " · Λmax " ++ ~uiFmt.(rep[\lamMax] ? 0, 2)
        ++ " · cables " ++ rep[\cables] ++ "/" ++ ~cfg_kf.cableMax
        ++ if((rep[\disabled] ? 0) > 0) { " (off " ++ rep[\disabled] ++ ")" } { "" }
        ++ " · interlayer " ++ ~uiFmt.((rep[\interlayer] ? 0) * 100, 1) ++ " %"
        ++ " · " ++ verdict
        ++ " · " ++ if(rep[\armed] == true) { "armed" } { "disarmed" };
};

// ----- reconcile the §5 table with ~ungSpecs, name by name --------------
~kfTableAudit = {
    var miss = [], extra = [], dangling = [];
    ~ungSpecs.keysValuesDo { |l, sp|
        var rows = ~kfNodeTable[l];
        if(rows.isNil) { miss = miss.add(l.asString ++ ".* (слоя нет в таблице §5)") } {
            sp.params.do { |p|
                if(rows[p[\key]].isNil) { miss = miss.add(l.asString ++ "." ++ p[\key]) };
            };
            rows.keys.do { |k|
                if(sp.params.any { |p| p[\key] == k }.not) { extra = extra.add(l.asString ++ "." ++ k) };
            };
        };
        // a reread reference to a missing key silently drops the sampling law
        // and falls back to the static ceiling — a typo and a rename look
        // exactly like a deliberate event name otherwise
        sp.params.do { |p|
            var rr = p[\reread];
            if(rr.isArray) {
                var rk = rr[1];
                if(rk.isKindOf(Symbol)
                    and: { sp.params.any { |q| q[\key] == rk }.not }
                    and: { ~kfRereadEvents.includes(rk).not }) {
                    dangling = dangling.add(l.asString ++ "." ++ p[\key]
                        ++ " -> [" ++ rr[0] ++ ", " ++ rk ++ "]");
                };
            };
        };
    };
    if(miss.notEmpty) {
        ("8_koppelfeld — таблица §5 НЕ покрывает: " ++ miss.sort.join(", ")).error;
    };
    if(extra.notEmpty) {
        ("8_koppelfeld — в таблице §5 лишние строки: " ++ extra.sort.join(", ")).error;
    };
    if(dangling.notEmpty) {
        ("8_koppelfeld — ВИСЯЧАЯ ссылка reread (закон опроса молча падает на "
            ++ "статический потолок): " ++ dangling.sort.join(", ")
            ++ ". Допустимые имена событий без параметра: " ++ ~kfRereadEvents).error;
    };
    ( missing: miss, extra: extra, dangling: dangling )
};

// ----- A-13: a silent wire-buffer failure is made LOUD ------------------
// the metric is PEAK HOLD, not RMS: an event layer (theta is silent ~76 % of
// the time) would false-alarm on any short RMS window. Silent layers are
// re-measured over a window three times longer before the failure is raised.
~kfPeakHold = { |layers, dur, action|
    // an empty list is a legal configuration (mixer off, no proxy playing), but
    // `Out.kr(bus, [])` does NOT build ("Out missing input at index 1") and
    // would take the app build down at the self-test step
    if(layers.isEmpty) { action.(()) } {
        var bus = Bus.control(s, layers.size);
        var probe = {
            Out.kr(bus, layers.collect { |l|
                A2K.kr(Peak.ar(Mix(InFeedback.ar(Ndef(l).bus.index, 2)).abs, Impulse.ar(0)))
            });
            Silent.ar(1)
        }.play(s, addAction: \addToTail);
        fork {
            dur.wait;
            bus.getn(layers.size, { |vals|
                var res = ();
                layers.do { |l, i| res[l] = vals.asArray[i].ampdb };
                probe.free; bus.free;
                action.(res);
            });
        };
    };
};

~kfSelfTest = { |action|
    // `?` is an ordinary message, BOTH operands evaluate: a bare ~kfNodes.keys
    // would throw "Message 'keys' not understood" once the registry is cleared
    var layers = (~activeLayers ? (~kfNodes ? ()).keys.asArray)
        .select { |l| Ndef(l).isPlaying };
    var floor = ~cfg_kf.selfTestFloor;
    var say = { |res, silent|
        ("8_koppelfeld — self-test (пик за окно): " ++ layers.collect { |l|
            l ++ " " ++ (res[l] ? -999).round(0.1) ++ " dB" }.join(" · ")).postln;
        if(silent.notEmpty) {
            ("8_koppelfeld — МОЛЧАТ слои: " ++ silent.join(", ")
                ++ ". Первая гипотеза — numWireBufs (действует только с БУТА, "
                ++ "s.options после бута врёт): поднять в 1_app.scd И "
                ++ ".claude/Tools/render_layer.scd, перезапустить").error;
        };
        action !? { action.(res, silent) };
    };
    ~kfPeakHold.(layers, ~cfg_kf.selfTestDur, { |res|
        var quiet = layers.select { |l| (res[l] ? -999) < floor };
        if(quiet.isEmpty) {
            say.(res, []);
        } {
            // second pass over suspects only: for an event layer the gap between
            // populations is legitimately longer than the first window
            ~kfPeakHold.(quiet, ~cfg_kf.selfTestDur * ~cfg_kf.selfTestRetry, { |res2|
                var silent = quiet.select { |l| (res2[l] ? -999) < floor };
                quiet.do { |l| res[l] = res2[l] };
                say.(res, silent);
            });
        };
    });
};

~kfReport = {
    var idx = [], v = ~kfVerdict;
    ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        idx = idx.add(Ndef(n[\node]).bus.index) } };
    (
        layers: ~kfNodes.keys.asArray.sort,
        nodes:  idx.size,
        cables: ~kfCables.count { |c| c[\enabled] != false },
        disabled: ~kfCables.count { |c| c[\enabled] == false },
        targets: if(v.isNil) { 0 } { v[\targets] },
        interlayer: if(v.isNil) { 0 } { v[\interlayer] },
        depths: if(v.isNil) { [] } { v[\depths] },
        loops:  if(v.isNil) { 0 } { v[\loops].size },
        lamMax: if(v.isNil) { 0 } { v[\lamMax] },
        mode:   if(v.isNil) { \ruhe } { v[\mode] },
        valid:  if(v.isNil) { true } { v[\valid] },
        armed:  ~kfArmed,
        maxTau: ~kfMaxTau.value,
        busLo:  if(idx.isEmpty) { nil } { idx.minItem },
        busHi:  if(idx.isEmpty) { nil } { idx.maxItem },
        busTotal: s.options.numAudioBusChannels
    );
};


// ----- §9.2 proxy meter + §12.1 live logger ----------------------------
// ONE OSC message for all 111 values, not one SendReply per node: 111 · 20/s
// would be 2 220 messages a second on the language thread. The S7 window reads
// the same ~kfLive array the logger writes.
~kfLive       = ~kfLive       ? [];
~kfMeterIds   = ~kfMeterIds   ? [];
~kfMeterRate  = ~kfMeterRate  ? 20;
~kfCmdPeriod  = ~kfCmdPeriod;
~kfLogFile    = ~kfLogFile;
~kfLogTask    = ~kfLogTask;
~kfLogT0      = ~kfLogT0;
~kfLogOwnsMeter = ~kfLogOwnsMeter ? false;
~kfLogCols    = ~kfLogCols    ? [];

// the ONLY honest predicate for "the meter is running": Ndef(\kf_meter).source
// survives Cmd-., the non-permanent OSCdef does not (AbstractResponderFunc
// registers itself with CmdPeriod), and without the responder no value ever
// reaches ~kfLive or the log
~kfMeterOnP = { OSCdef.all[\kfvals].notNil };

~kfMeterFree = {
    OSCdef.all[\kfvals] !? { |d| d.free };
    Ndef(\kf_meter).clear;
    ~kfMeterIds = [];
    // ~kfLive is a READING surface (S7): a frozen last frame left behind is
    // indistinguishable from a live field
    ~kfLive = [];
};

// Channel order for BOTH logs: layers sorted, params in the order their layer
// declares them. Any other order (registry hash order) would make a live log
// and an NRT log of the same scheme incomparable — and D-14 compares them.
~kfLogIds = {
    var out = [];
    (~kfNodes ? ()).keys.asArray.sort.do { |l|
        ((~ungSpecs[l] !? { |sp| sp.params.collect { |p| p[\key] } }) ? []).do { |k|
            if((~kfNodes[l] ? ())[k].notNil) { out = out.add([l, k]) };
        };
    };
    out
};

~kfLogIdStr = { |ids| ids.collect { |lk| ~kfIdOf.(lk[0], lk[1]).asString } };

// the `#` preamble both log forms carry: for a CSV it is the head of the file,
// for a 111-channel wav the sidecar `<out.wav>.meta`. The analyser needs the
// windows (occupancy, sticking) and the loop periods (D-9, D-10) — a bare
// matrix of numbers cannot be judged against §11.D at all.
~kfLogMeta = { |ids, rate, source, skip = 0|
    var sch = ~kfSchaltung ? ();
    var v = ~kfVerdict;
    var loops = if(v.isNil) { [] } { v[\loops] };
    var num = { |x| x.asFloat.asStringPrec(6) };
    var per = { |field| ids.collect { |lk|
        var n = ~kfNodes[lk[0]][lk[1]];
        ~kfIdOf.(lk[0], lk[1]).asString ++ ":" ++ field.(n)
    }.join(",") };
    String.streamContents { |o|
        o << "# koppelfeld log v1 · source=" << source
          << " · seed=" << (sch[\seed] ? "-")
          << " · c=" << (sch[\complexity] ? "-")
          << " · mode=" << (if(v.isNil) { \ruhe } { v[\mode] })
          << " · rate=" << num.(rate)
          << " · skip=" << num.(skip)
          << " · cables=" << ~kfCables.count { |c| c[\enabled] != false }
          << " · t0=" << Date.localtime.stamp << "\n";
        o << "# nodes=" << ~kfLogIdStr.(ids).join(",") << "\n";
        o << "# win=" << per.({ |n| num.(n[\win][0]) ++ ":" ++ num.(n[\win][1]) }) << "\n";
        o << "# rest=" << per.({ |n| num.(n[\rest]) }) << "\n";
        o << "# curve=" << per.({ |n| n[\curve].asString }) << "\n";
        o << "# edges=" << ~kfCables.select { |c| c[\enabled] != false }.collect { |c|
            ~kfIdOf.(c[\src][0], c[\src][1]).asString ++ ">" ++ ~kfIdOf.(c[\dst][0], c[\dst][1]).asString
                ++ ":" ++ num.(c[\pol] ? 1) ++ ":" ++ num.(c[\gain] ? 0)
                ++ ":" ++ num.(c[\fc]) ++ ":" ++ (c[\band] ? \block)
        }.join(",") << "\n";
        o << "# loops=" << loops.collect { |l|
            l[\nodes].collect(_.asString).join(">") ++ ":" ++ num.(l[\lam])
                ++ ":" ++ num.(l[\tau]) ++ ":" ++ num.(l[\period])
        }.join(";") << "\n";
    };
};

~kfMeterOn = { |on = true, rate = 20|
    if(on) {
        var ids = ~kfLogIds.value.select { |lk| ~kfNodes[lk[0]][lk[1]][\bus].notNil };
        // the log's header fixes its columns once; rows of another width land
        // either dropped or shifted onto foreign ids in readCsv. Compared
        // against ~kfLogCols and NOT ~kfMeterIds — ~kfLogStart arms the meter
        // with the file already open and would otherwise close its own log.
        // No recursion: ~kfLogStop nils ~kfLogFile before it touches the meter
        if(~kfLogFile.notNil and: { ~kfLogIdStr.(ids) != ~kfLogCols }) {
            "8_koppelfeld — под открытым логом сменился состав узлов, лог закрыт".warn;
            ~kfLogStop.value;
        };
        ~kfMeterIds = ids;
        ~kfMeterRate = rate;
        ~kfLive = 0 ! ids.size;
        if(ids.isEmpty) {
            "8_koppelfeld — метр: узлов на шинах нет, включать нечего".warn;
            ~kfMeterFree.value;
        } {
            Ndef(\kf_meter, {
                // node buses carry MAPPED values; every metric of §11.D is
                // stated in normalized space, so the meter unmaps once here
                // instead of teaching the analyser 111 specs
                var vals = ids.collect { |lk|
                    var n = ~kfNodes[lk[0]][lk[1]];
                    n[\spec].unmap(InFeedback.ar(n[\bus], 1))
                };
                SendReply.kr(Impulse.kr(rate), '/kfvals', A2K.kr(vals));
                DC.kr(0)
            });
            Ndef(\kf_meter).fadeTime = 0;
            Ndef(\kf_meter).wakeUp;
            OSCdef(\kfvals, { |msg|
                ~kfLive = msg.copyRange(3, msg.size - 1);
                ~kfLogFile !? { |f|
                    var t = Main.elapsedTime;
                    ~kfLogT0 = ~kfLogT0 ? t;
                    f.write((t - ~kfLogT0).asStringPrec(7) ++ ","
                        ++ ~kfLive.collect { |x| x.asStringPrec(5) }.join(",") ++ "\n");
                };
            }, '/kfvals', s.addr);
        };
    } {
        // switching the meter off cuts the rows an open log lives on: the file
        // would be closed by its own `dur` truncated under a full-size header
        if(~kfLogFile.notNil) {
            "8_koppelfeld — метр выключен под открытым логом, лог закрыт".warn;
            ~kfLogStop.value;
        };
        ~kfMeterFree.value;
    };
    on
};

// a hot-swapped layer gets NEW bus indices, and Ndef(\kf_meter) carries the OLD
// ones baked into its graph: without a rebuild the meter goes on reading
// whatever now sits on the freed buses, and an open log records it under a
// header that still names the swapped layer
~kfMeterRebuild = {
    if(~kfMeterOnP.value) { ~kfMeterOn.(true, ~kfMeterRate) };
};

// ~kfLogStart.(path, dur, rate) — the REFERENCE log (§12.1): real time, the
// sounding graph, one row per meter tick. The NRT logger is the fast one; this
// one is what it is checked against (D-14).
~kfLogStart = { |path, dur = 300, rate = 20|
    var ids, owns;
    ~kfLogStop.value;
    ids = ~kfLogIds.value.select { |lk| ~kfNodes[lk[0]][lk[1]][\bus].notNil };
    if(ids.isEmpty) {
        "8_koppelfeld — ~kfLogStart: поле узлов пусто, лог не открыт".error;
        nil
    } {
        // ownership is decided BEFORE the header: a borrowed meter keeps its own
        // rate (a log has no right to degrade the window that switched it on,
        // and ~kfLogStop restores nothing), and the header must name the rate
        // the rows actually arrive at
        owns = ~kfMeterOnP.value.not;
        if(owns.not) { rate = ~kfMeterRate };
        ~kfLogFile = File(path.standardizePath, "w");
        if(~kfLogFile.isOpen.not) {
            ("8_koppelfeld — ~kfLogStart: не открыть " ++ path).error;
            ~kfLogFile = nil;
            nil
        } {
            ~kfLogT0 = nil;
            ~kfLogOwnsMeter = owns;
            ~kfLogCols = ~kfLogIdStr.(ids);
            ~kfLogFile.write(~kfLogMeta.(ids, rate, "live", 0));
            ~kfLogFile.write("t," ++ ~kfLogCols.join(",") ++ "\n");
            // an owned meter is armed AFTER the file: an OSC tick arriving
            // between the two would write a row with no header above it
            if(owns) { ~kfMeterOn.(true, rate) };
            // the task drops its OWN handle before stopping: Routine:stop called
            // from inside the routine is `nil.alwaysYield`, so a ~kfLogStop that
            // began by stopping this task would abort right there and never
            // close the file
            ~kfLogTask = fork { dur.wait; ~kfLogTask = nil; ~kfLogStop.value };
            ("8_koppelfeld — лог начат: " ++ path ++ " · " ++ ids.size
                ++ " узлов · " ++ rate ++ " Гц · " ++ dur ++ " с"
                ++ if(owns) { " · метр наш" } { " · метр чужой, частота его" }).postln;
            path
        };
    };
};

~kfLogStop = {
    ~kfLogTask !? { |tk| tk.stop }; ~kfLogTask = nil;
    ~kfLogFile !? { |f|
        // the handle is dropped BEFORE the meter is touched: ~kfMeterOn closes
        // an open log itself, and a ~kfLogFile still set here would send the
        // two into each other
        f.close;
        ~kfLogFile = nil;
        ~kfLogCols = [];
        // the meter belongs to whoever switched it on: the S7 window may be
        // holding it, and a log ending must not blind the window
        if(~kfLogOwnsMeter) { ~kfMeterOn.(false) };
        ~kfLogOwnsMeter = false;
        "8_koppelfeld — лог закрыт".postln;
    };
};

// Cmd-. frees the non-permanent OSCdef and kills the meter synth, but the `dur`
// fork runs on TempoClock.default, which CmdPeriod.run leaves alone (as it does
// ~kfApplyTask and ~kfHandTask), and an open File is no server resource at all:
// the hook has to stop the task AND close the file, or the log stays open with
// its tail unflushed while the next ~kfMeterOn re-registers the OSCdef, which
// then appends rows into that stale handle with no header
~kfCmdPeriod !? { |f| CmdPeriod.remove(f) };
~kfCmdPeriod = { ~kfLogStop.value };
CmdPeriod.add(~kfCmdPeriod);

// tear the whole field down — called from ~appCleanup BEFORE
// Ndef.all.do(_.clear): Cmd-. kills synths but NOT nodeMaps
~kfClear = {
    ~kfLogStop.value;
    ~kfMeterOn.(false);
    ~kfApplyTask !? { |tk| tk.stop }; ~kfApplyTask = nil;
    ~kfHandTask  !? { |tk| tk.stop }; ~kfHandTask  = nil;
    (~kfNodes ? ()).keys.asArray.do { |l| ~kfDropLayer.(l) };
    Ndef(\kf_arm).clear;
    ~kfNodes = ();
    ~kfCables = [];
    ~kfFanOut = ();
    ~kfSchaltung = nil;
    ~kfVerdict = nil;
    ~kfVerdictStale = false;
    ~kfArmed = false;
};

~kfArmBus.value;
(~activeLayers ? ~ungSpecs.keys.asArray.sort).do { |l| ~kfBuildLayer.(l) };
~kfMeterRebuild.value;
~kfTableAudit.value;
// no scheme applied yet — arm goes up at once: the identity scheme (0 cables)
// does not depend on it, and the first ~kfPoke must be audible
~kfArm.(0);

("8_koppelfeld — узлов " ++ ~kfReport.value[\nodes]
    ++ " на " ++ ~kfReport.value[\layers].size ++ " слоях, кабелей "
    ++ ~kfReport.value[\cables] ++ "; шины "
    ++ ~kfReport.value[\busLo] ++ "–" ++ ~kfReport.value[\busHi]
    ++ " из " ++ ~kfReport.value[\busTotal]).postln;
)
