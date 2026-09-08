// App/synths/theta.scd — UNGRUND class 8/8 `theta`, §C.8 `splitter` (2026-07-17):
// anschlag cascade (5 micro-impulses, 1.07 ms) + korn (1–3 modes of the 94 Hz
// lattice, size law T20 = min(40 ms, 45100/f)) + kante; population exhaustion
// §D.2: IOI_k = ioi0 * decel^k * versatz. NO random / noise / nonlinearity
// (Axiom III: period, not draw); the layer is dry — §K.2 send 0.0 is a BAN.
// Specs: plans/active/theta-crystalline-decay.md (iteration M1–M4) over
// docs/features/theta/dsp-spec.md (base); reference + implementation notes:
// docs/features/theta/fragment-reference.md. ~spec_theta is source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — an octave index only: class pitches are a fixed table BY
// PREMISE. Wheels, the 41 rows, the size law, the cascade and the trims are
// score, not CONFIG: edited by hand and rerun (gamma precedent).
~spec_theta = (
    name: \theta,
    params: [
        // --- group \freq ---
        // no disp: an octave index is not a frequency; round in LOGIC holds the
        // lattice. reread [\event, \fragment]: a fragment is not a parameter, the
        // whole arrival law sets its rate; the 0.05 Hz band ceiling is static (§5.5)
        ( key: \fragOct, group: \freq,
          spec: ControlSpec(-1, 0, \lin, 1, 0), reread: [\event, \fragment], arMod: \latch ),

        // --- group \tone: the arrival law (NEVER lagged — they latch at the
        // population boundary, where Dgeom/Ddup re-poll their kr inputs) ---
        ( key: \ioi0, group: \tone, unit: " s",
          spec: ControlSpec(0.012, 0.120, \exp, 0, 0.018), reread: \pop, arMod: \demand ),  // head IOI; \exp — a time constant over 10:1
        ( key: \decel, group: \tone,
          spec: ControlSpec(1.05, 1.40, \lin, 0, 1.22), reread: \pop, arMod: \demand ),  // decel <= 1 is unreachable by construction
        ( key: \ioiMax, group: \tone, unit: " s",
          spec: ControlSpec(0.4, 1.5, \lin, 0, 0.60), reread: \pop, arMod: \demand ),  // exhaustion floor -> kMax
        ( key: \popScale, group: \tone,
          spec: ControlSpec(0.5, 2.0, \lin, 0, 1.0), reread: \pop, arMod: \demand ),  // scales wheel 6
        ( key: \gapScale, group: \tone,
          spec: ControlSpec(0.3, 3.0, \lin, 0, 1.0), reread: \pop, arMod: \demand ),  // scales wheel 7
        // \lin on purpose (\exp excludes 0 = hard off); the exponential lives in
        // 6**(1-2d) on the inter-population gap. Do NOT "harmonize" with alpha.
        // Two consumers: a continuous off-gate and gapMul once per population —
        // the SLOWEST one is declared (§5.5)
        ( key: \density, group: \tone,
          spec: ControlSpec(0, 1, \lin, 0, 0.5), reread: \pop, arMod: \demand ),  // layer mean 0..~6 /s; <=0.02 = off-gate

        // --- group \tone: the contact + level ---
        ( key: \edgeWidth, group: \tone,
          spec: ControlSpec(0.2, 1.0, \lin, 0, 0.7), reread: [\event, \fragment], arMod: \freq ),  // scales wheel 2's rq; narrow = clean ping, wide = grain survives
        ( key: \edgeAmp, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.45), reread: [\event, \fragment], arMod: \lin ),  // kante level vs the mode sum; 0.0 = a bell (a control, not a defect)
        ( key: \decayScale, group: \tone,
          spec: ControlSpec(0.3, 1.0, \lin, 0, 0.68), reread: [\event, \fragment], arMod: \freq ),  // can only SHORTEN the size law
        ( key: \spread, group: \tone,
          spec: ControlSpec(0.0, 1.0, \lin, 0, 0.8), reread: [\event, \fragment], arMod: \latch ),  // scales wheel 4; never moves one position
        ( key: \amp, group: \tone,
          spec: ControlSpec(0.0, 0.30, \lin, 0, 0.09), reread: \cont, arMod: \lin )  // §K.4; §F band −24…−10 dBFS peak
    ]
);


// ===== LOGIC — synthesis =============================================
// One persistent graph, the whole scheduler demand-rate inside the proxy (gamma
// precedent): hot-swap is idempotent. Scheduler -> odometer -> ONE global
// cascade -> round-robin over 14 voices -> (korn + kante) -> pan -> LeakDC ->
// Limiter.
Ndef(\theta, {
    // ar controls: declaration order = ~spec_theta row order. The arrival family
    // and spread get NO slew at all — they are reread (per population / per
    // fragment), not continuous (contract §5)
    var fragOct    = \fragOct.ar(0);
    var ioi0       = \ioi0.ar(0.018);
    var decel      = \decel.ar(1.22);
    var ioiMax     = \ioiMax.ar(0.60);
    var popScale   = \popScale.ar(1.0);
    var gapScale   = \gapScale.ar(1.0);
    var density    = \density.ar(0.5);
    var edgeWidth  = \edgeWidth.ar(0.7).lag(0.002);
    var edgeAmp    = \edgeAmp.ar(0.45).lag(0.005);
    var decayScale = \decayScale.ar(0.68).lag(0.002);
    var spread     = \spread.ar(0.8);
    var amp        = \amp.ar(0.09).lag(0.005);

    var nyq, fund = 94;
    // 12 is provably steal-free, 14 is headroom for table edits; a stolen onset
    // is verified by counting, not by ear — see the reference Implementation notes
    var nVoices = 14;

    // --- wheel 1: 41 fragment rows (ratios of 94 Hz, 2^i*3^j) ---
    // 13/17/11 rows by mode count, pairwise distinct, the low-ratio row is
    // non-monotone (monotone = sweep = gesture); unused slots REPEAT r0 =>
    // max(r0,r1,r2) is always the row's top mode (the kante BPF centre)
    var rowR0 = #[27, 16, 64, 12, 48, 24, 81, 18, 96, 36, 32, 54, 12, 72, 24,
        16, 81, 27, 54, 12, 48, 48, 64, 18, 24, 32, 36, 12, 64, 16, 72, 48, 18,
        16, 54, 32, 12, 64, 36, 18, 72];
    var rowR1 = #[27, 36, 81, 12, 54, 32, 81, 27, 96, 48, 32, 72, 16, 72, 27,
        16, 96, 32, 54, 18, 48, 81, 72, 24, 24, 96, 36, 27, 64, 24, 81, 64, 18,
        32, 96, 54, 24, 96, 54, 36, 96];
    var rowR2 = #[27, 16, 96, 12, 48, 64, 81, 18, 96, 96, 32, 54, 32, 72, 24,
        16, 81, 81, 54, 12, 48, 48, 64, 54, 24, 32, 36, 36, 64, 16, 72, 96, 18,
        48, 54, 32, 27, 64, 81, 18, 72];
    var rowN = #[1, 2, 3, 1, 2, 3, 1, 2, 1, 3, 1, 2, 3, 1, 2, 1, 2, 3, 1, 2, 1,
        2, 2, 3, 1, 2, 1, 3, 1, 2, 2, 3, 1, 3, 2, 2, 3, 2, 3, 2, 2];
    // wheel 2 — kante edge width, rq (17), 0.05–0.9, non-monotone
    var rqTable = #[0.33, 0.90, 0.12, 0.58, 0.05, 0.71, 0.24, 0.47, 0.83, 0.16,
        0.64, 0.09, 0.40, 0.77, 0.29, 0.54, 0.20];
    // wheel 3 — event level (31), −8…0 dB. (i*7) % 31 is a full-period
    // permutation (7 coprime to 31): non-monotone by construction, no
    // hand-tuned table to mistype. Mean ≈ −4.0 dB.
    var levelTable = (0..30).collect { |i| (-8 * ((i * 7) % 31) / 30).dbamp };
    // wheel 4 — pan (29), bounds exactly ±0.4 at spread 1.0 (§F), non-monotone
    var panTable = (0..28).collect { |i| (((i * 11) % 29) / 28 * 0.8) - 0.4 };
    // wheel 5 — versatz (11): deviation of the arrival law. Mean EXACTLY 1.000
    // (else the decel^{2N/3} exhaustion analysis breaks); audit: eleven 1.0 would
    // be a pure ritardando — the anti-gesture proof of Axiom III
    var versatz = #[1.05, 0.60, 1.38, 0.72, 1.65, 0.55, 1.20, 0.82, 1.50, 0.68,
        0.85];
    // wheel 6 — population size N (7), 8–28; at defaults kMax=18 truncates to a
    // mean of 15.0 — correct (a population ends at k=N OR IOI>ioiMax)
    var popTable = #[18, 26, 11, 22, 8, 28, 14];
    // wheel 7 — inter-population gap, s (23), 0.8–6.0, non-monotone; mean 3.022
    var gapTable = #[2.6, 5.1, 1.2, 3.8, 0.8, 4.4, 2.1, 6.0, 1.5, 3.2, 0.9, 4.9,
        2.4, 1.8, 5.6, 1.1, 3.5, 2.8, 4.1, 1.4, 5.3, 2.0, 3.0];

    // --- anschlag: the class arrival law at the third scale. Onsets
    // 0/0.080/0.232/0.521/1.070 ms come from TIMES, not samples (SR invariance in
    // ms; not a Buffer — that would be a sample, Axiom II). See Implementation notes.
    var cascC0 = 0.00008, cascCl = 1.9, cascAcc = 0.0;
    var cascTimes, cascLevels = #[1.0, 0.62, 0.85, 0.48, 0.71];
    // class constants, NEVER scaled by fragOct (that would be a hidden second
    // \freq); check the 12–20 kHz band with FFT ONLY — the tool's band RMS lies on
    // 2-pole skirts (trap 2026-07-17, see Implementation notes)
    var cascHP = 400, cascLP = 9024, cascHPn = 2, cascLPn = 2;
    // LOAD-BEARING width: > the 1.07 ms cascade span and < the 6.6 ms minimum
    // IOI; lowering the ioi0 floor or the versatz minimum breaks the global
    // cascade SILENTLY
    var cascGate = 0.0025;

    // --- dev calibrations (not parameters), measured 2026-07-17 at 44.1 k,
    // SR-dependent — recalibrate at the render rate (Implementation notes)
    var t60Ref   = 0.045;  // mode energy normalization: without it size would drive
                           // level (~-3 dB/oct); from the pitch-only T60, NEVER
                           // from decayScale
    // the law was MEASURED on the cascade (spec deviation D1: the spec's law is
    // inverted, do not apply — a BPF impulse peak grows with BANDWIDTH, so
    // narrower is QUIETER)
    var edgeRqExp = 0.85, edgeFExp = 0.4;
    var edgeRef  = 280;    // puts the kante peak on the korn peak at edgeAmp 1.0 =>
                           // the 0.45 default leaves contact ~7 dB under the modes
    var edgeTrim = 1.0;    // kante stratum vs mode sum at the default edgeAmp
    var makeup   = 0.58;   // peak -12 dBFS at amp 0.09; the §F peak metric beats RMS

    var fragOctL, fragFund, edgeWidthL, edgeAmpL, decayScaleL, spreadL;
    var ioi0L, decelL, ioiMaxL, popScaleL, gapScaleL, densK, densAr, gapMul, kMax, nEffA, nEffB;
    var kStream, isFirst, geom, durs, tEvt, vals;
    var wR0, wR1, wR2, wN, wRq, wLevel, wPan;
    var imp, casc, vIdx, sig;

    nyq = SampleRate.ir * 0.45;

    // round AFTER lag: ControlSpec:map ignores step, so ~rndFreq can hand over
    // -0.5 (off the lattice); rounding before the lag does not help
    fragOctL = fragOct.round(1).clip(-1, 0);
    fragFund = fund * (2 ** fragOctL);

    edgeWidthL  = edgeWidth.clip(0.2, 1.0);
    edgeAmpL    = edgeAmp.clip(0, 1);
    decayScaleL = decayScale.clip(0.3, 1.0);
    spreadL     = spread.clip(0, 1);

    // --- block 1: the population scheduler (demand rate) ---
    // the five density controls are clamped and NEVER lagged: they are read once
    // per population, at the boundary (Dgeom/Ddup re-poll on a Dseq reset) — a lag
    // would bend the law while it settles ("density-control latching").
    // A2K is MANDATORY: a Demand UGen polls its kr/ir input on its own pull, ar
    // cannot go there — no error is raised, the stream freezes or drifts silently,
    // and every level metric still passes (§5.5, footgun 15)
    ioi0L     = A2K.kr(ioi0).clip(0.012, 0.120);
    decelL    = A2K.kr(decel).clip(1.05, 1.40);
    ioiMaxL   = A2K.kr(ioiMax).clip(0.4, 1.5);
    popScaleL = A2K.kr(popScale).clip(0.5, 2.0);
    gapScaleL = A2K.kr(gapScale).clip(0.3, 3.0);
    // two consumers at DIFFERENT reread rates: gapMul reads once per population
    // (through A2K), the off-gate reads continuously and so stays ar
    densK     = A2K.kr(density).clip(0, 1);
    densAr    = density.clip(0, 1);
    // the inter-population term ONLY: a multiplier on the whole durs (or on ioi0)
    // would bend the §D.2 arrival law and silently re-couple density to it; the
    // 6.6 ms ioi0 floor carries the 2.5 ms global cascade gate (footgun 8)
    gapMul    = 6 ** (1 - (2 * densK));

    // the exit test is closed over kr (by the law BEFORE the versatz deviation):
    // IOI_k > ioiMax resolves exactly, with no demand branching
    kMax = ((ioiMaxL / ioi0L).log / decelL.log).floor + 1;

    // WHEEL 6 STEPS ONCE PER POPULATION, not per fragment — spec deviation D2
    // (the spec recipe measurably freezes the population size; RULED 2026-07-17).
    // Two INDEPENDENT copies: a stream named twice in one demand expression is
    // pulled twice; both reset on pull 0 => lockstep by construction.
    // kMax/popScale are kr inputs with one pull per population: latching is free.
    nEffA = (Dseq(popTable, inf) * popScaleL).min(kMax).round(1).clip(2, 64);
    nEffB = (Dseq(popTable, inf) * popScaleL).min(kMax).round(1).clip(2, 64);

    // phase counter: the flag and the geometric law reset ON THE SAME pull and
    // read ONE nEff (the spec's flag construct drifts — measured 2026-07-17,
    // exhaustion ratio 0.81 with every other metric green)
    kStream = Dseq([ Dseries(0, 1, nEffB) ], inf);
    // the gap is NOT an event: it rides on the first fragment's input interval =>
    // exactly nEff pulls per population, so the odometer and "no terminal event"
    // hold structurally
    isFirst = kStream < 0.5;
    // THE LOAD-BEARING LINE OF THE LAYER: ioi0 enters through the Dgeom START
    // (`ioi0L * geom` would bend the law on every pull — invisible to parse,
    // inaudible by ear); the start is ioi0/decel because of the one-pull offset
    // between TDuty and Demand.ar; do NOT "fix" it via ControlDur.ir — that
    // desynchronizes the nodes forever. Footgun 2.
    geom = Dseq([ Dgeom(ioi0L / decelL, decelL, nEffA) ], inf);
    durs = (geom * Dseq(versatz, inf))
        + (isFirst * Dseq(gapTable, inf) * gapScaleL * gapMul);
    // the gate is SINGLE-POINT, every clock consumer reads tEvt: one consumer on
    // the raw TDuty would desynchronize round-robin from the odometer silently
    // (all level metrics still pass). At density<=0.02 the durs streams inside
    // TDuty keep running while the value wheels freeze (no pulls) — the mutual
    // phase drift is harmless: the wheels are coprime and phaseless by
    // construction, so "resynchronizing" would be new state for nothing. Do NOT
    // lag density (the off-gate must not wait on a lag)
    tEvt = TDuty.ar(durs) * (densAr > 0.02);

    // --- block 2: the wheel odometer (demand rate) ---
    // a wheel of length L IS Dseq(table, inf). PULL INVARIANT: every stream is
    // pulled exactly once per fragment by THIS ONE Demand.ar; a second Demand /
    // Dpoll / viz tap breaks the odometer silently (all level metrics still pass)
    // — footgun 1. Hence the mode gates below are derived on ar (ar is reusable).
    vals = Demand.ar(tEvt, 0, [
        Dseq(rowR0, inf), Dseq(rowR1, inf), Dseq(rowR2, inf), Dseq(rowN, inf),
        Dseq(rqTable, inf), Dseq(levelTable, inf), Dseq(panTable, inf)
    ]);
    // name at the pull point: positional vals[i] is its own class of silent failure
    wR0 = vals[0]; wR1 = vals[1]; wR2 = vals[2]; wN = vals[3];
    wRq = vals[4]; wLevel = vals[5]; wPan = vals[6];

    // --- block 3: contact cascade — GLOBAL, one for all voices (cascades
    // provably do not overlap: min IOI 6.6 ms > the 1.07 ms span; a voice takes
    // its own through cascGate). DelayN, not DelayC: interpolation would smear
    // the one-sample front (Implementation notes).
    cascTimes = [0.0] ++ (0..3).collect { |i|
        cascAcc = cascAcc + (cascC0 * (cascCl ** i)); cascAcc
    };
    // the TDuty output is already a band-limited discrete impulse; nothing in the
    // layer can alias (that needs a nonlinearity or resampling, both banned)
    imp  = tEvt;
    casc = Mix(cascTimes.collect { |t, i|
        if(t <= 0) { imp * cascLevels[i] } { DelayN.ar(imp, 0.002, t) * cascLevels[i] }
    });
    cascHPn.do { casc = HPF.ar(casc, cascHP) };
    cascLPn.do { casc = LPF.ar(casc, cascLP) };

    // --- block 4: deterministic round-robin (Stepper, not TIRand: a random UGen
    // in this layer annuls the class — §C.8)
    vIdx = Stepper.ar(tEvt, 0, 0, nVoices - 1, 1);

    sig = Mix.fill(nVoices, { |v|
        var trig, gate, excite, nMod, g1, g2, ratios, freqs, fLow, ringT, target, envT;
        var modes, fTop, rqL, edgeNorm, kante, levelW, panW, voice;

        trig = tEvt * ((vIdx - v).abs < 0.5);
        gate   = Trig.ar(trig, cascGate);
        excite = casc * gate;

        // event freeze: the MAPPED value is latched (Latch(ratio*fund), not
        // Latch(ratio)*fund) — a moving fragOct will not retune a ringing mode
        nMod = Latch.ar(wN, trig);
        g1   = nMod > 1.5;
        g2   = nMod > 2.5;
        ratios = [wR0, wR1, wR2];
        // the clamp never engages by construction — it insures future table edits
        freqs = ratios.collect { |r| Latch.ar(r * fragFund, trig).clip(20, nyq) };

        // korn: the size law is ONE PER FRAGMENT off the lowest mode (R1
        // 2026-07-19: "pitch and decay are one fact"; a shared decay = common-fate
        // fusion, the tail centroid does not slide). min works because unused slots
        // REPEAT r0. Ringz always runs on the FULL law — decayScale does not touch
        // it (Ringz welds T60 to bandwidth: short ring = wide resonance = plastic);
        // the audible shortening is the Decay2 envelope over the mode sum, and the
        // product of exponentials is exact: 1/T = 1/T_ringz + 1/T_env. Ringz/Decay2
        // decaytime is the -60 dB time => T60 = 3*T20; clamp ringT, NOT T20
        // (clipping T20 would permit a breach of the card's 15 ms floor)
        fLow   = freqs[0].min(freqs[1]).min(freqs[2]);
        ringT  = (3 * (45.1 / fLow).min(0.040)).clip(0.015, 0.120);
        target = (ringT * decayScaleL).clip(0.015, 0.150);
        // the .max(0.0002) guard is load-bearing: as target -> ringT (the 15 ms
        // floor, upper rows) envT >= ~1 s and the envelope is INERT (base F4
        // semantics); a naive .max(0.003) would drop the floor to ~12.5 ms
        envT   = (ringT * target / (ringT - target).max(0.0002)).clip(0.001, 10);
        // power normalization: a 3-mode row is no louder than a 1-mode row; eNorm
        // comes from the pitch-only law (ringT), NEVER from decayScale/envT —
        // "shorter = quieter" IS the law, compensating it would erase it
        modes = Mix([
            Ringz.ar(excite, freqs[0], ringT),
            Ringz.ar(excite, freqs[1], ringT) * g1,
            Ringz.ar(excite, freqs[2], ringT) * g2
        ]) / nMod.max(1).sqrt
            * Decay2.ar(trig, 0.001, envT)
            * (t60Ref / ringT).sqrt;

        // kante: the same cascade through one BPF on the row's TOP mode; narrow rq
        // = a clean ping, wide rq = the cascade grain survives into the fragment
        fTop     = freqs[0].max(freqs[1]).max(freqs[2]);
        rqL      = (Latch.ar(wRq, trig) * edgeWidthL).clip(0.01, 1.0);
        edgeNorm = edgeRef / ((rqL ** edgeRqExp) * (fTop ** edgeFExp));
        kante    = BPF.ar(excite, fTop, rqL) * edgeNorm
            * Decay2.ar(trig, 0.0002, 0.0025);

        levelW = Latch.ar(wLevel, trig);
        panW   = Latch.ar(wPan, trig);
        voice  = (modes + (kante * edgeAmpL * edgeTrim)) * levelW;
        // pan is fixed per fragment, |pan| <= 0.4 at spread 1.0 (§F): spread scales
        // the whole table, there is no pan LFO and no positional drift. The LATCH is
        // load-bearing: without it a cable would move an ALREADY SOUNDING fragment
        Pan2.ar(voice, panW * Latch.ar(spreadL, trig));
    });

    // --- block 5: condition ---
    sig = sig * makeup * amp;
    sig = LeakDC.ar(sig);
    // the Limiter is the only nonlinearity and must stay silent in every COMPOSED
    // state; it is here only as randomizer insurance
    sig = Limiter.ar(sig, 0.95);
    sig
});

// register spec + apply defaults (self-sufficient: 0_lib only needed for
// interactive random/presets/GUI after the full App load)
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\theta] = ~spec_theta;
~ungVals[\theta]  = ();
~spec_theta.params.do { |p|
    Ndef(\theta).set(p.key, p.spec.default);
    ~ungVals[\theta][p.key] = p.spec.default;
};
Ndef(\theta).fadeTime = 0.5;   // event class: cut, not faded
// the Ndef.set loop above DROPS the koppelfeld node mapping (n_set > n_mapa) —
// without a rebind, reloading this file silently cuts the layer off the scheme
~kfRebind !? { |f| f.(\theta) };

("synths/theta — spec зарегистрирован ("
    ++ ~spec_theta.params.size ++ " параметров); ~openTuner.(\\theta)").postln;
)
