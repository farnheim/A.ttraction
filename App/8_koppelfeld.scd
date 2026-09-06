// App/8_koppelfeld.scd — UNGRUND · KOPPELFELD: one node proxy per parameter,
// 111 across the five layers; a cable lives INSIDE its destination node.
// Node law (§3.1), in the node's own normalized ControlSpec space:
//   x = curve( rest + hand + arm · Σ pol·gain·lag_τ(x_src − rest_src) )
//   value = spec.map(x)                    — exactly ONE channel per control.
// All 111 params are proxied, not only destinations: `n_set` silently drops
// `n_mapa`, so partial proxying would tear the scheme on any ~setParam.
// Stage S2: cables, band/τ, window, clip/fold, arm/disarm, ~kfApply/~kfCut,
// registries, ~kfLambda, validator V1–V13, ~kfPoke. Curve `step` (class P) is
// stage S3; until then V9 rejects every cable into a P node (class ceiling 0).
// Buses: 111 node audio (1 ch) + 1 control for arm; §3.7 — 5x headroom.
// Loads AFTER the layers (needs ~ungSpecs) and BEFORE the mixer.
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
    interlayerMin: 0.6     // §4.3 V10 interlayer cable share
);


// ===== LOGIC — canon, nodes, cables, Λ, validator, arm, self-test ====

// ----- §4.2 ceilings BY DESTINATION CLASS ------------------------------
~kfClass = (
    L: ( gain: 0.30, bands: [\block],                         curve: [\clip] ),
    P: ( gain: 0,    bands: [\block],                         curve: [\step] ),
    S: ( gain: 1.6,  bands: [\rauheit, \puls, \gang, \block], curve: [\clip, \fold] ),
    D: ( gain: 1.2,  bands: [\rauheit, \puls, \gang, \block], curve: [\clip] ),
    W: ( gain: 1.4,  bands: [\puls, \gang, \block],           curve: [\clip, \fold] ),
    E: ( gain: 1.0,  bands: [\gang, \block],                  curve: [\clip] ),
    G: ( gain: 0.6,  bands: [\block],                         curve: [\clip] ),
    M: ( gain: 2.0,  bands: [\rauheit, \puls, \gang, \block], curve: [\clip, \fold] )
);
~kfBand = ( rauheit: [8, 120], puls: [0.5, 8], gang: [0.05, 0.5], block: [0.004, 0.05] );
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

// ----- registries ------------------------------------------------------
~kfNodes     = ~kfNodes     ? ();   // \layer -> ( \param -> ( node: spec: rest: win: curve: cables: bus: ) )
~kfCables    = ~kfCables    ? [];   // applied cable table (§4.1 events)
~kfFanOut    = ~kfFanOut    ? ();   // \layer -> ( \param -> [ ( dst: [l,k], slot: i ) ] ) — reverse edges
~kfSchaltung = ~kfSchaltung;        // the applied scheme
~kfVerdict   = ~kfVerdict;          // validator verdict of the last ~kfApply
~kfArmed     = ~kfArmed ? false;

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
~kfRestBounds = { |n|
    if(n[\cables].isEmpty) { [0, 1] } {
        var lo = n[\win][0] + ~cfg_kf.restMargin;
        var hi = n[\win][1] - ~cfg_kf.restMargin;
        if(lo > hi) { var m = (n[\win][0] + n[\win][1]) * 0.5; [m, m] } { [lo, hi] };
    };
};

// footgun 7: a source rest is DUPLICATED into every outgoing cable (\rN).
// The drift is inaudible but breaks the null test and shifts the destination
// rest point — hence exactly one writer, updating both sides via ~kfFanOut.
~kfRestApply = { |layer, key, rn|
    var n = (~kfNodes[layer.asSymbol] ? ())[key.asSymbol];
    if(n.isNil) { nil } {
        var b = ~kfRestBounds.(n);
        n[\rest] = rn.clip(b[0], b[1]);
        Ndef(n[\node]).set(\rest, n[\rest]);
        ((~kfFanOut[layer.asSymbol] ? ())[key.asSymbol] ? []).do { |e|
            var dn = (~kfNodes[e[\dst][0]] ? ())[e[\dst][1]];
            dn !? { Ndef(dn[\node]).set(("r" ++ e[\slot]).asSymbol, n[\rest]) };
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
    var win = if(mine.isEmpty) { [0, 1] } { (mine[0][\win] ? [0, 1]) };
    var curve = if(mine.isEmpty) { \clip } { (mine[0][\curve] ? \clip) };
    // V9: a convergence node must clip — a fold over the sum of three cables
    // reflects the already-summed signal and loses each contribution
    if(mine.size >= 2) { curve = \clip };
    ( cables: mine, win: win, curve: curve )
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

// ----- node body (§3.1/§3.3/§3.4) --------------------------------------
~kfNodeBody = { |layer, key, warn = true|
    var n = (~kfNodes[layer.asSymbol] ? ())[key.asSymbol];
    if(n.notNil) {
        var cs   = n[\spec];
        var rest = n[\rest];
        var wlo  = n[\win][0], whi = n[\win][1];
        var fold = (n[\curve] == \fold);
        var armBus = ~kfArmBus.value;
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
                    slot: i, bus: sn[\bus], spec: sn[\spec], rest: sn[\rest],
                    fc: c[\fc], fcLo: bnd[0], fcHi: hi,
                    pol: c[\pol] ? 1, gain: c[\gain] ? 0,
                    gmax: ~kfGainMax.(layer, key)
                ));
            };
        };
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
            x = if(fold) {
                Fold.ar(u, \wlo.ar(wlo), \whi.ar(whi))
            } {
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
                win: [0, 1], curve: \clip, cables: [], bus: nil
            );
        };
        ~kfNodes[layer] = reg;
        reg.keysValuesDo { |key, n|
            var w = ~kfWireOf.(layer, key);
            n[\win] = w[\win]; n[\curve] = w[\curve]; n[\cables] = w[\cables];
        };
        // two passes: a body build needs the source bus, so pass one gives every
        // node of the layer a body and a bus (cables whose source has no bus yet
        // are skipped silently), pass two rebuilds the destinations over ready
        // buses. At load time there are no cables, so pass two is empty
        reg.keysValuesDo { |key, n| ~kfNodeBody.(layer, key, false) };
        reg.keysValuesDo { |key, n| if(n[\cables].notEmpty) { ~kfNodeBody.(layer, key) } };
        ~kfFanOutBuild.value;
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
    dom = loops.detect { |l| true };

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
    var wins = (), curves = (), rests = (), indeg = (), outdeg = ();
    var lam, adj, depths = [], maxDepth = 0, interlayer = 0;
    var layIn = (), layOut = (), census = ();
    var restOf, winOf, reach, name;

    name = { |nid| nid.asString };

    // the scheme's rest overrides the live node state
    ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        rests[~kfIdOf.(l, k)] = n[\rest];
    }};
    (sch[\rest] ? ()).keysValuesDo { |l, e| e.keysValuesDo { |k, v|
        rests[~kfIdOf.(l, k)] = v.clip(0, 1);
    }};
    restOf = { |l, k|
        rests[~kfIdOf.(l, k)] ? ((~kfSpecOfNode.(l, k) !? { |cs| cs.unmap(cs.default) }) ? 0.5);
    };

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
            wins[did] = c[\win] ? [0, 1];
            curves[did] = c[\curve] ? \clip;
        } {
            if(wins[did] != (c[\win] ? [0, 1])) {
                errs = errs.add("V7 два кабеля в " ++ name.(did) ++ " объявляют РАЗНОЕ окно "
                    ++ wins[did] ++ " и " ++ (c[\win] ? [0, 1]));
            };
            if(curves[did] != (c[\curve] ? \clip)) {
                errs = errs.add("V7 два кабеля в " ++ name.(did) ++ " объявляют РАЗНУЮ кривую");
            };
        };
        if(sl != dl) {
            interlayer = interlayer + 1;
            census[(sl.asString ++ ">" ++ dl.asString).asSymbol] = true;
        };
        layOut[sl] = (layOut[sl] ? 0) + 1;
        layIn[dl] = (layIn[dl] ? 0) + 1;
    };
    winOf = { |l, k| wins[~kfIdOf.(l, k)] ? [0, 1] };

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
            if(curve == \step) {
                errs = errs.add("V9 кривая step — этап S3, на S2 не реализована: " ++ tag);
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
            if(fmax.notNil and: { fmax < (~kfBand[\block][0] * 2) }) {
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
        if(w[0] < 0 or: { w[1] > 1 }) { errs = errs.add("V7 окно вне [0,1]: " ++ name.(did) ++ " " ++ w) };
        if(w[0] >= w[1]) {
            errs = errs.add("V7 wlo ≥ whi: " ++ name.(did) ++ " " ++ w);
        } {
            // a window narrower than 2·restMargin admits NO legal rest at all;
            // without this the failure surfaced as a confusing complaint about the
            // rest, and ~kfRestBounds collapsed the rest onto the midpoint
            if((w[1] - w[0]) < (2 * cfg.restMargin)) {
                errs = errs.add("V7 ширина окна " ++ (w[1] - w[0]).round(0.001) ++ " < 2·"
                    ++ cfg.restMargin ++ ": ни одно значение покоя не лежит в окне "
                    ++ w ++ " с зазором: " ++ name.(did));
            } {
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
            ++ c[\nodes].collect(_.asString).join(" > "));
    };
    lam[\loops].do { |l|
        if(l[\lam] > cfg.lamMax) {
            errs = errs.add("V8 Λ " ++ l[\lam].round(0.001) ++ " > " ++ cfg.lamMax ++ ": "
                ++ l[\nodes].collect(_.asString).join(" > "));
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
    block { |brk|
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
        brk.value;
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
    block { |brk|
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
        brk.value;
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
                ++ "как периодическое: " ++ l[\nodes].collect(_.asString).join(" > "));
        };
    };
    block { |brk|
        var arrival = [\ioi0, \decel, \ioiMax, \popScale, \gapScale, \density];
        var pTargets = cables.select { |c| (~kfRow.(c[\dst][0], c[\dst][1]) !? { |r| r[0] }) == \P };
        var pPerLayer = ();
        if(lam[\mode] == \wanderung) {
            cables.do { |c|
                if(c[\src][0].asSymbol == \theta and: { arrival.includes(c[\src][1].asSymbol) }) {
                    errs = errs.add("V11 wanderung-источник в семействе прибытия theta: "
                        ++ c[\src][1]);
                };
            };
        };
        pTargets.do { |c| var l = c[\dst][0].asSymbol; pPerLayer[l] = (pPerLayer[l] ? 0) + 1 };
        pPerLayer.keysValuesDo { |l, n|
            if(n > 1) { errs = errs.add("V11 P-целей в слое " ++ l ++ ": " ++ n ++ " > 1") };
        };
        if(pTargets.size > 2) { errs = errs.add("V11 P-целей всего " ++ pTargets.size ++ " > 2") };
        if((pPerLayer[\delta] ? 0) > 1) { errs = errs.add("V11 P-целей delta > 1") };
        brk.value;
    };

    // V12: epsilon freqLo ≤ freqHi in ALL reachable states;
    // mLevel ≥ flowLevel − 6 dB
    block { |brk|
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
            errs = errs.add("V12 epsilon: freqLo верх " ++ lo[1].round(0.01)
                ++ " > freqHi низ " ++ hi[0].round(0.01));
        };
        if(ml.notNil and: { fl.notNil } and: { ml[0] < (fl[1] * 0.5) }) {
            errs = errs.add("V12 epsilon: mLevel низ " ++ ml[0].round(0.001)
                ++ " < flowLevel верх − 6 dB (" ++ (fl[1] * 0.5).round(0.001) ++ ")");
        };
        brk.value;
    };

    // V13: theta.density may cross the 0.02 threshold on a B4 cable only
    block { |brk|
        var did = ~kfIdOf.(\theta, \density);
        var w = wins[did];
        if(w.notNil and: { w[0] < 0.02 }) {
            cables.do { |c|
                if(~kfIdOf.(c[\dst][0], c[\dst][1]) == did and: { (c[\band] ? \block) != \block }) {
                    errs = errs.add("V13 theta.density пересекает 0.02 по полосе "
                        ++ c[\band] ++ " — разрешена только B4 (block)");
                };
            };
        };
        brk.value;
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

// ----- applying a scheme (§10.2): a cut, not a crossfade ---------------
~kfInstall = { |sch|
    var was = [];
    ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        if(n[\cables].notEmpty) { was = was.add([l, k]) };
    }};
    ~kfCables = (sch[\cables] ? []).collect { |c| c.copy };
    ~kfPrune.value;
    // the node -> layer mapping is NOT rebuilt (footgun 9): only bodies change
    ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        var w = ~kfWireOf.(l, k);
        n[\win] = w[\win]; n[\curve] = w[\curve]; n[\cables] = w[\cables];
    }};
    ~kfFanOutBuild.value;
    // destination rests are brought into the NEW window through ~setParam:
    // ~ungVals, tuner and preset must carry what sounds, not what was asked
    ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        if(n[\cables].notEmpty) { ~setParam.(l, k, n[\spec].map(n[\rest])) };
    }};
    was.do { |lk| ~kfNodeBody.(lk[0], lk[1]) };
    ~kfNodes.keysValuesDo { |l, reg| reg.keysValuesDo { |k, n|
        if(n[\cables].notEmpty and: { was.any { |lk| (lk[0] == l) and: { lk[1] == k } }.not }) {
            ~kfNodeBody.(l, k);
        };
    }};
    // rest AFTER wiring: ~kfRest needs a finished ~kfFanOut
    (sch[\rest] ? ()).keysValuesDo { |l, e| e.keysValuesDo { |k, v|
        var cs = ~kfSpecOfNode.(l, k);
        cs !? { ~setParam.(l, k, cs.map(v.clip(0, 1))) };
    }};
    ~kfSchaltung = sch;
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

// tear the whole field down — called from ~appCleanup BEFORE
// Ndef.all.do(_.clear): Cmd-. kills synths but NOT nodeMaps
~kfClear = {
    ~kfApplyTask !? { |tk| tk.stop }; ~kfApplyTask = nil;
    ~kfHandTask  !? { |tk| tk.stop }; ~kfHandTask  = nil;
    (~kfNodes ? ()).keys.asArray.do { |l| ~kfDropLayer.(l) };
    Ndef(\kf_arm).clear;
    ~kfNodes = ();
    ~kfCables = [];
    ~kfFanOut = ();
    ~kfSchaltung = nil;
    ~kfVerdict = nil;
    ~kfArmed = false;
};

~kfArmBus.value;
(~activeLayers ? ~ungSpecs.keys.asArray.sort).do { |l| ~kfBuildLayer.(l) };
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
