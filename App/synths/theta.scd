// App/synths/theta.scd — UNGRUND class 8/8 `theta` (struck fragment population).
// REAL LAYER, premise §C.8 `splitter` as established 2026-07-17 (the `schotter`
// card it replaces is struck in its entirety; the `firnis` card before it too).
// A FRAGMENT is two strata and no more — `anschlag` (a fixed cascade of five
// micro-impulses, span 1.07 ms, IDENTICAL for every fragment) exciting `korn`
// (1–3 damped modes on the 94 Hz 3-limit lattice) plus `kante` (the same
// cascade through one BPF at the fragment's highest mode). The material is
// (1) each fragment's SIZE, heard as pitch and decay correlated by the size law
// T20 = min(40 ms, 45100/f), and (2) the population's EXHAUSTION, heard as
// density thinning from a fused head (≈ 56 /s) to a discrete tail (≈ 2 /s) —
// §D.2 `halbwertszeit` at event scale, IOI_k = ioi0 * decel^k * versatz[...].
// Both resolve by ear, from the sound alone, with no parameters in hand (§C
// preamble admission test, 2026-07-17).
// There is NO random generator, NO noise generator and NO nonlinearity in this
// class — unpredictability is a period, not a draw (Axiom III): six per-fragment
// wheels (41·17·31·29·11·23 = 158530559 fragments ≈ 1.7 years) plus the
// population-size wheel (7), which advances once per POPULATION — see the wheel-6
// note in LOGIC and deviation D2 (ruled 2026-07-17). The Limiter is the only
// nonlinear object and must stay inert at every composed state (§C.8's ×5 arg).
// The layer is DRY: no reverb, delay, feedback or resonator outside a mode's
// own ≤ 150 ms decay — space is a mixer fact (§K.1 send 0.16; §K.2 send 0.0 is
// a FORBIDDEN move, not a preference: a feedback echo replenishes at constant
// density exactly what the class's law is exhausting).
// Spec: plans/active/theta-splitter-population.md; reference:
// docs/features/theta/fragment-reference.md. Tuning via 0_lib.scd;
// ~spec_theta is the single source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — the modes' octave index, and nothing else: the class's pitch
// is a fixed table BY PREMISE, so a second \freq row would be dead CONFIG.
// group \tone — the arrival law (five density controls) / the contact / level.
// The seven wheel tables, the 41 fragment rows, the size law, the cascade and
// the dev-calibrated trims are internal constants (score, not CONFIG —
// gamma's voice->point precedent): they are audited by editing them and
// re-executing, never by a runtime parameter (§F discards a parameter that
// maps to no audible dimension).
~spec_theta = (
    name: \theta,
    params: [
        // --- group \freq ---
        // no `disp`: an octave index is not a frequency. `step: 1` is correct
        // for the tuner's slider, but the graph is what enforces the lattice —
        // ControlSpec:map ignores `step`, see the round in LOGIC.
        ( key: \fragOct, label: "октава мод",    group: \freq,             spec: ControlSpec(-1, 0, \lin, 1, 0)          ),

        // --- group \tone: the arrival law (NEVER lagged — they latch at the
        // population boundary, where Dgeom/Ddup re-poll their kr inputs) ---
        ( key: \ioi0, label: "IOI головы",       group: \tone, unit: " s", spec: ControlSpec(0.012, 0.120, \exp, 0, 0.018) ),  // head IOI; \exp — a time constant over 10:1
        ( key: \decel, label: "замедление",      group: \tone,             spec: ControlSpec(1.05, 1.40, \lin, 0, 1.22)  ),  // decel <= 1 is unreachable by construction
        ( key: \ioiMax, label: "потолок истощ.",     group: \tone, unit: " s", spec: ControlSpec(0.4, 1.5, \lin, 0, 0.60)    ),  // exhaustion floor -> kMax
        ( key: \popScale, label: "разм. популяции",   group: \tone,             spec: ControlSpec(0.5, 2.0, \lin, 0, 1.0)     ),  // scales wheel 6
        ( key: \gapScale, label: "пауза",   group: \tone,             spec: ControlSpec(0.3, 3.0, \lin, 0, 1.0)     ),  // scales wheel 7

        // --- group \tone: the contact + level ---
        ( key: \edgeWidth, label: "ширина контакта",  group: \tone,             spec: ControlSpec(0.2, 1.0, \lin, 0, 0.7)     ),  // scales wheel 2's rq; narrow = clean ping, wide = grain survives
        ( key: \edgeAmp, label: "уровень контакта",    group: \tone,             spec: ControlSpec(0.0, 1.0, \lin, 0, 0.45)    ),  // kante level vs the mode sum; 0.0 = a bell (a control, not a defect)
        ( key: \decayScale, label: "масшт. затух.", group: \tone,             spec: ControlSpec(0.3, 1.0, \lin, 0, 1.0)     ),  // can only SHORTEN the size law
        ( key: \spread, label: "разброс пан.",     group: \tone,             spec: ControlSpec(0.0, 1.0, \lin, 0, 0.8)     ),  // scales wheel 4; never moves one position
        ( key: \amp, label: "громкость",        group: \tone,             spec: ControlSpec(0.0, 0.30, \lin, 0, 0.09)   )   // §K.4; §F band −24…−10 dBFS peak
    ]
);


// ===== LOGIC — synthesis =============================================
// One persistent graph: no per-event Synths, no Routine, no Tdef, no Buffer,
// no doneAction. The whole population scheduler is demand-rate streams inside
// the proxy (gamma's precedent), so hot-swap is idempotent and orphans nothing.
// Scheduler -> odometer -> ONE global contact cascade -> round-robin over 14
// voices -> per-voice (korn + kante) -> fixed pan -> sum -> LeakDC -> Limiter.
Ndef(\theta, { |fragOct = 0, ioi0 = 0.018, decel = 1.22, ioiMax = 0.60,
    popScale = 1.0, gapScale = 1.0, edgeWidth = 0.7, edgeAmp = 0.45,
    decayScale = 1.0, spread = 0.8, amp = 0.09|

    var nyq, fund = 94;
    // 12 is provably steal-free at the worst reachable state (any cyclic window
    // of 12 versatz entries sums >= 11.55 => 0.184 s > the 0.120 s worst tail);
    // 14 is the margin that survives a table edit lowering versatz's minimum or
    // raising a row's T20. A stolen onset is a missing member of the population
    // and is this class's only unrecoverable failure — and at the fused head it
    // is INAUDIBLE as a fault, so it is verified by count, never by ear.
    var nVoices = 14;

    // --- wheel 1: the 41 fragment rows (ratios of 94 Hz, all 2^i*3^j) ---
    // 13 one-mode / 17 two-mode / 11 three-mode; every row pairwise distinct,
    // every row's modes span <= x3, the sequence of lowest ratios non-monotone
    // (a monotone table reads as a register sweep, and a sweep is a gesture),
    // biased toward COMPLEX ratios: simple pairs (2:1, 3:2, 4:3) fuse into a
    // PITCH, complex ones into an inharmonic-flavoured object, which is what
    // the class wants. Only 13 one-mode rows can exist (13 lattice points, rows
    // pairwise distinct) — the reference's 17/14/10 is unsatisfiable.
    // Unused slots REPEAT r0, so max(r0, r1, r2) is always the row's highest
    // ratio — which is the kante BPF's centre.
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
    // wheel 5 — versatz (11), the deflection of the arrival law. Its mean is
    // EXACTLY 1.000, not approximately: versatz must not bias the law's trend,
    // and the exhaustion metric (= decel^{2N/3} analytically) only holds if it
    // doesn't. min 0.55 / max 1.65, non-monotone, no two adjacent within 15 %.
    // THE AUDIT: set these to eleven 1.0s and re-execute — the ritardando
    // appears, and the ascent fraction goes to 1.00. That single edit is the
    // anti-gesture proof (Axiom III discharged with no generator).
    var versatz = #[1.05, 0.60, 1.38, 0.72, 1.65, 0.55, 1.20, 0.82, 1.50, 0.68,
        0.85];
    // wheel 6 — population size N (7), 8–28, non-monotone. At defaults kMax=18
    // truncates it to [18,18,11,18,8,18,14], mean 15.0 — expected and correct
    // (the population ends at k=N OR IOI>ioiMax, whichever first).
    var popTable = #[18, 26, 11, 22, 8, 28, 14];
    // wheel 7 — inter-population gap, s (23), 0.8–6.0, non-monotone; mean 3.022
    var gapTable = #[2.6, 5.1, 1.2, 3.8, 0.8, 4.4, 2.1, 6.0, 1.5, 3.2, 0.9, 4.9,
        2.4, 1.8, 5.6, 1.1, 3.5, 2.8, 4.1, 1.4, 5.3, 2.0, 3.0];

    // --- the anschlag: the class's own arrival law at a third scale.
    // IOI_i = cascC0 * cascCl^i, i = 0..3 => onsets 0/0.080/0.232/0.521/1.070
    // ms, span 1.070 ms. The times are the card's specification and the KERNEL
    // IS SR-DEPENDENT IN SAMPLES (48 at 44.1 k, 52 at 48 k) while being
    // SR-invariant in ms — so it is computed from the times and never
    // hardcoded as a 48-sample table, which would make the contact law change
    // with the render rate. Not a Buffer either: that is a sample (Axiom II).
    var cascC0 = 0.00008, cascCl = 1.9, cascAcc = 0.0;
    var cascTimes, cascLevels = #[1.0, 0.62, 0.85, 0.48, 0.71];
    // The class's fixed ceiling and DC fix. Both are class CONSTANTS and must
    // NEVER be scaled by fragOct — scaling either would make it a second,
    // hidden \freq control. 400 Hz sits below the class floor (564 Hz), so the
    // HPF removes the unipolar impulse's DC without touching the material.
    // Pole counts are the spec's (4-pole HPF is 2 x HPF.ar, 4-pole LPF is
    // 2 x LPF.ar). The 4-pole LPF holds the firnis bound with 17 dB to spare:
    // 12–20 kHz measures −39.3 rel by FFT (bound: ≤ −22).
    // DO NOT trust render_measure.sh's band RMS for this row, and this is the
    // trap that cost the most on 2026-07-17: its bands are 2-pole
    // highpass/lowpass pairs, whose skirts cannot resolve a 22 dB gap between
    // ADJACENT bands. It reported 12–20 kHz at −13.7 rel — a ≤ −22 "failure"
    // that is almost entirely 6–12 kHz (only 17 dB away, and the class's second
    // loudest band) leaking through a 2-pole skirt. Verify this row by FFT.
    var cascHP = 400, cascLP = 9024, cascHPn = 2, cascLPn = 2;
    // 2.5 ms: this gate width is LOAD-BEARING. It claims one voice's copy of
    // the ONE global cascade and must stay above the cascade's 1.070 ms span
    // and below the minimum reachable IOI (ioi0 0.012 * versatz 0.55 = 6.6 ms),
    // so it can never catch a neighbour's cascade. Lowering ioi0's floor or
    // versatz's minimum breaks the global-cascade optimisation SILENTLY.
    var cascGate = 0.0025;

    // --- dev-calibrated internals (not parameters), measured 2026-07-17 at
    // 44.1 k. A single-sample impulse's energy is sample-rate dependent, so
    // these shift slightly at 48 k — calibrate at the render rate, never "fix"
    // them with an SR-dependent constant.
    var t60Ref   = 0.045;  // per-mode energy normalisation reference. NOT cosmetic:
                           // Ringz's energy scales with its decay time and the size law
                           // makes decay a function of pitch, so without this SIZE WOULD
                           // CONTROL LOUDNESS (~ -3 dB/oct tilt), the level wheel would be
                           // swamped by the row wheel and the anti-accent clause defeated.
                           // Derived from the pitch-only T60, never from decayScale — a
                           // decayScale-compensated norm would make the decay law
                           // loudness-neutral, and shorter-is-quieter IS the law.
    // edgeNorm's law, MEASURED 2026-07-17 on the shipped cascade, not derived.
    // The spec's law is inverted and must not be used: it argues SC's BPF is
    // unity-gain at centre so an impulse's peak is ~1 regardless of rq, hence
    // energy ~ 1/(rq*f) and "NARROWER IS LOUDER" => edgeNorm = (rq*f/ref).sqrt.
    // The premise is false — a BPF's IMPULSE peak scales with its BANDWIDTH, so
    // narrower is QUIETER. Measured raw BPF peak of the cascade at f = 2538:
    // rq 0.01 -> -62.1 dB, 0.0693 -> -45.9, 0.231 -> -37.1, 0.9 -> -28.9
    // => amplitude ~ rq^0.85; and at rq 0.231: f 1128 -> -42.1, 9024 -> -34.3
    // => ~ f^0.4 (the cascade's own 9024 LPF flattens the top). Applying the
    // spec's sqrt(rq*f) would multiply the loudest settings by the most and
    // DOUBLE the error, breaking edgeWidth's §F loudness-neutrality outright.
    var edgeRqExp = 0.85, edgeFExp = 0.4;
    var edgeRef  = 280;    // lands the kante's peak on the korn's (~ -4.6 dB) at
                           // edgeAmp/edgeTrim 1.0, so edgeAmp's default 0.45 puts the
                           // contact ~7 dB under the modes: a real, subordinate stratum.
                           // At edgeRef 1200 with the spec's law the kante sat ~32 dB
                           // under the korn — inaudible, and edgeAmp was a DEAD control.
    var edgeTrim = 1.0;    // kante stratum vs the mode sum, at edgeAmp's default
    var makeup   = 0.58;    // lands peak -12 dBFS at amp 0.09 (target -12 +-3). Peak is the
                           // §F and limiter-safety metric and WINS any conflict with RMS.

    var fragOctL, fragFund, edgeWidthL, edgeAmpL, decayScaleL, spreadL;
    var ioi0L, decelL, ioiMaxL, popScaleL, gapScaleL, kMax, nEffA, nEffB;
    var kStream, isFirst, geom, durs, tFrag, vals;
    var wR0, wR1, wR2, wN, wRq, wLevel, wPan;
    var imp, casc, vIdx, sig;

    nyq = SampleRate.ir * 0.45;

    // round AFTER the lag: ControlSpec:map does NOT apply `step` (map is
    // warp.map(value); step is only applied in constrain), so ~rndFreq.(\theta)
    // can hand this arg -0.5 and 2 ** -0.5 is OFF-LATTICE — a §C.8-violating
    // state reachable by one button press. Rounding before the lag would not
    // help: a Latch during the lag's settle would freeze a mode on 2 ** 0.37,
    // permanently, for that event's whole ring.
    fragOctL = fragOct.lag(0.2).round(1).clip(-1, 0);
    fragFund = fund * (2 ** fragOctL);

    edgeWidthL  = edgeWidth.lag(0.1).clip(0.2, 1.0);
    edgeAmpL    = edgeAmp.lag(0.1).clip(0, 1);
    decayScaleL = decayScale.lag(0.2).clip(0.3, 1.0);
    spreadL     = spread.lag(0.2).clip(0, 1);

    // --- block 1: the population scheduler (demand rate) ---
    // The five density controls are clamped and NEVER lagged: they are not
    // continuously-read signals (contract §5's lag rule is about zipper noise)
    // — they are sampled ONCE PER POPULATION, at a discrete instant, because
    // Dgeom and Ddup re-poll their kr inputs only when the enclosing Dseq
    // resets them, and that reset instant IS the population boundary. Lagging
    // decel would bend the law while the lag settles, which is exactly what the
    // exhaustion metric measures.
    ioi0L     = ioi0.clip(0.012, 0.120);
    decelL    = decel.clip(1.05, 1.40);
    ioiMaxL   = ioiMax.clip(0.4, 1.5);
    popScaleL = popScale.clip(0.5, 2.0);
    gapScaleL = gapScale.clip(0.3, 3.0);

    // the exit test is CLOSED-FORM at kr, so no demand-rate branching exists:
    // IOI_k > ioiMax on the un-deflected law ioi0*decel^k solves exactly.
    // It is evaluated on the law BEFORE the versatz deflection, because versatz
    // is defined as a deflection OF the law, not part of its trend — which is
    // the faithful reading and makes the exit deterministic in k.
    kMax = ((ioiMaxL / ioi0L).log / decelL.log).floor + 1;

    // WHEEL 6 ADVANCES ONCE PER POPULATION, NOT ONCE PER FRAGMENT. This is a
    // deliberate deviation from the spec's footgun 3, which prescribes a kr read
    // off an ar fragment counter — `Select.kr(A2K.kr(Stepper.ar(tFrag, ...)) % 7,
    // popTable)` — to avoid "collapsing the period to 7 populations". MEASURED
    // 2026-07-17: that construct collapses the period to ONE. The sampling
    // interval IS nEff, so the read index advances by nEff per population; the
    // moment nEff ≡ 0 (mod 7) the index never moves again and the population
    // size FREEZES. At the shipped defaults it froze at 14 permanently, after
    // the walk 18 -> 8 -> 18 -> 11 -> 14 -> 14 -> 14... Wheel 6's period is 7
    // populations here, which is worse than the spec wanted and strictly better
    // than what the spec's own recipe delivers. RULED 2026-07-17 (deviation D2,
    // option a): the per-fragment period is the six per-fragment wheels alone —
    // 41*17*31*29*11*23 = 158530559 fragments ≈ 1.7 years at 3 /s — and the card,
    // reference and spec prose are corrected to match. Not 11.7 years.
    // Two INDEPENDENT copies of the wheel: each is pulled exactly once per
    // population, at its own child's reset, and both children reset at pull 0 of
    // every cycle — so both read the same index in the same control block and
    // stay in lockstep BY CONSTRUCTION. They are separate streams because a
    // stream named twice in one demand-rate expression is pulled twice.
    // kMax and popScale are kr inputs to an expression pulled once per
    // population, so they latch at the population boundary for free — no Latch,
    // no .lag, and structurally.
    nEffA = (Dseq(popTable, inf) * popScaleL).min(kMax).round(1).clip(2, 64);
    nEffB = (Dseq(popTable, inf) * popScaleL).min(kMax).round(1).clip(2, 64);

    // The population's phase counter. It exists so that the run-length flag and
    // the geometric law RESET AT THE SAME PULL and therefore read the SAME nEff.
    // The spec's flag construct is broken here for the same class of reason:
    // `Dseq([ Dseq([1],1), Ddup(nEff-1, Dseq([0],1)) ], inf)` puts the Ddup
    // AFTER a one-item Dseq, so Ddup re-polls its count at pull 1 while Dgeom
    // polls at pull 0 — the two take different cycle lengths, drift apart
    // PERMANENTLY, and the gap starts landing inside the geometric run.
    // Measured 2026-07-17: the exhaustion ratio collapsed to 0.81 (target >= 8)
    // while the layer's mean rate, band profile and every level metric passed.
    // Dseries and Dgeom are structurally identical here (Dseq([child], inf), one
    // child, nEff items per cycle), so they reset together — by construction,
    // not by luck.
    kStream = Dseq([ Dseries(0, 1, nEffB) ], inf);
    // the gap is NOT AN EVENT: it rides on the population's first fragment's
    // INCOMING interval. That gives exactly nEff demand pulls per population, so
    // every wheel advances exactly once per FRAGMENT and the odometer's period
    // argument survives; it also discharges "no terminal event" structurally —
    // no gap event exists, the last fragment is an ordinary fragment, and only
    // the silence after it is longer.
    isFirst = kStream < 0.5;
    // ioi0 ENTERS THROUGH Dgeom's START ARGUMENT. This is the single most
    // important line in the layer. Writing `durs = ioi0L * geom * versatzS`
    // instead would make ioi0 a kr input to a demand-rate BinaryOpUGen, which
    // re-polls it at EVERY pull — ioi0 would then bend the law mid-population,
    // which is precisely what the exhaustion metric measures. Invisible to a
    // parse check and inaudible at slow slider moves.
    // It starts at ioi0/decel, not ioi0, because TDuty pulls the interval
    // PRECEDING each fire while Demand.ar pulls AT the fire — a one-pull offset
    // between the two demand nodes. This makes the realised IOI between fire 0
    // and fire 1 equal ioi0 * versatz[1], i.e. the head rate is the nominal
    // 1/ioi0. Do NOT "fix" it by prepending ControlDur.ir: measured 2026-07-16
    // on the shipped schotter, that desynchronises the two nodes permanently.
    geom = Dseq([ Dgeom(ioi0L / decelL, decelL, nEffA) ], inf);
    durs = (geom * Dseq(versatz, inf)) + (isFirst * Dseq(gapTable, inf) * gapScaleL);
    tFrag = TDuty.ar(durs);

    // --- block 2: the wheel odometer (demand rate) ---
    // A wheel of length L IS Dseq(<L-element table>, inf): it wraps at L by
    // construction — no counter, no modulo, no Dbufrd, no Buffer.
    // THE PULL-COUNT INVARIANT: every stream here is pulled exactly ONCE per
    // fragment by this ONE Demand.ar (durs once per fragment by TDuty), and all
    // pulls for fragment k land in the same control block. A stream named twice
    // in one demand-rate expression is pulled TWICE and desynchronises
    // PERMANENTLY; a second Demand, a Dpoll or a viz tap added later breaks the
    // odometer silently — every band and level metric still passes. This is why
    // the mode gates below are derived at ar (ar signals are free to reuse;
    // streams are not).
    vals = Demand.ar(tFrag, 0, [
        Dseq(rowR0, inf), Dseq(rowR1, inf), Dseq(rowR2, inf), Dseq(rowN, inf),
        Dseq(rqTable, inf), Dseq(levelTable, inf), Dseq(panTable, inf)
    ]);
    // name every output at the point of the pull: positional vals[i] indices
    // are a silent-failure class of their own (a mis-indexed wheel still passes
    // every level and band metric)
    wR0 = vals[0]; wR1 = vals[1]; wR2 = vals[2]; wN = vals[3];
    wRq = vals[4]; wLevel = vals[5]; wPan = vals[6];

    // --- block 3: the contact cascade — GLOBAL, built once, not per voice ---
    // Legitimate because cascades PROVABLY never overlap: the minimum reachable
    // IOI is 6.6 ms and the cascade spans 1.07 ms, so the global signal is
    // unambiguous at every instant and each voice claims its own with cascGate.
    // DelayN, NOT DelayC: DelayC interpolates and would smear each
    // micro-impulse across a 4-sample cubic kernel, breaking the card's claim
    // that each micro-impulse rises in one sample. DelayN rounds to the nearest
    // sample at the cost of <= +-11 us placement error, which does not
    // accumulate.
    cascTimes = [0.0] ++ (0..3).collect { |i|
        cascAcc = cascAcc + (cascC0 * (cascCl ** i)); cascAcc
    };
    // TDuty's output IS a one-sample impulse — already the bandlimited
    // discrete-time impulse, with no supra-Nyquist content to fold. Nothing in
    // this layer can alias: aliasing needs a nonlinearity or a resampling, and
    // the card bans every nonlinearity; Ringz and BPF are linear IIR filters.
    imp  = tFrag;
    casc = Mix(cascTimes.collect { |t, i|
        if(t <= 0) { imp * cascLevels[i] } { DelayN.ar(imp, 0.002, t) * cascLevels[i] }
    });
    cascHPn.do { casc = HPF.ar(casc, cascHP) };
    cascLPn.do { casc = LPF.ar(casc, cascLP) };

    // --- block 4: deterministic round-robin over the voice bank ---
    // Stepper, not TIRand: there is NO random generator in this class (§C.8).
    // If a random UGen appears in this layer, the class is void.
    vIdx = Stepper.ar(tFrag, 0, 0, nVoices - 1, 1);

    sig = Mix.fill(nVoices, { |v|
        var trig, gate, excite, nMod, g1, g2, ratios, freqs, t20s, ringTs, eNorms;
        var modes, fTop, rqL, edgeNorm, kante, levelW, panW, voice;

        trig = tFrag * ((vIdx - v).abs < 0.5);
        gate   = Trig.ar(trig, cascGate);
        excite = casc * gate;

        // --- freeze the event. The Demand.ar outputs change at EVERY fragment,
        // so a voice reading them live would be re-tuned mid-ring. Every
        // per-event quantity is latched at THIS voice's trigger, and the MAPPED
        // value is latched (Latch(ratio * fund), never Latch(ratio) * fund), so
        // fragOct moving mid-ring cannot re-tune a sounding mode off-lattice.
        nMod = Latch.ar(wN, trig);
        g1   = nMod > 1.5;
        g2   = nMod > 2.5;
        ratios = [wR0, wR1, wR2];
        // the clamp never engages (the top mode is 9024 Hz and fragOct can only
        // lower it, vs 19845 at 44.1 k) — it ships because a clamp that never
        // engages is cheap and a table edit that reaches Nyquist is not
        freqs = ratios.collect { |r| Latch.ar(r * fragFund, trig).clip(20, nyq) };

        // --- korn: the size law. T20 = min(40 ms, 45100 Hz*ms / f); Ringz's
        // decaytime IS the −60 dB time, so pass T60 = 3*T20, not T20.
        // CLAMP ringT, NOT T20: the reference's proposed T20.clip(0.003, 0.050)
        // permits 3 * 0.003 = 9 ms, which is BELOW the card's own 15 ms floor —
        // the clamp as written would permit the violation it exists to prevent.
        // The floor engages by construction: at fragOct 0, x96 gives T60 = 15.0
        // ms EXACTLY, so any decayScale < 1.0 breaks the floor on the top rows.
        // decayScale therefore becomes progressively inert on the highest rows
        // as it is lowered while still shortening the lower ones — a
        // reachable-state clamp, not a composed-state one.
        t20s   = freqs.collect { |f| (45.1 / f).min(0.040) };
        ringTs = t20s.collect { |t| (3 * t * decayScaleL).clip(0.015, 0.150) };
        eNorms = t20s.collect { |t| (t60Ref / (3 * t)).sqrt };
        // power normalisation, so a 3-mode row is not systematically louder
        // than a 1-mode row
        modes = Mix([
            Ringz.ar(excite, freqs[0], ringTs[0]) * eNorms[0],
            Ringz.ar(excite, freqs[1], ringTs[1]) * eNorms[1] * g1,
            Ringz.ar(excite, freqs[2], ringTs[2]) * eNorms[2] * g2
        ]) / nMod.max(1).sqrt;

        // --- kante: the same cascade through one BPF at the row's HIGHEST mode
        // (unused slots repeat r0, so the max is exact). This is where "свой
        // характер ударов" lives: narrow rq = a clean tuned ping, wide rq = the
        // cascade's grain survives into the fragment.
        fTop     = freqs[0].max(freqs[1]).max(freqs[2]);
        rqL      = (Latch.ar(wRq, trig) * edgeWidthL).clip(0.01, 1.0);
        edgeNorm = edgeRef / ((rqL ** edgeRqExp) * (fTop ** edgeFExp));
        kante    = BPF.ar(excite, fTop, rqL) * edgeNorm
            * Decay2.ar(trig, 0.0002, 0.0025);

        levelW = Latch.ar(wLevel, trig);
        panW   = Latch.ar(wPan, trig);
        voice  = (modes + (kante * edgeAmpL * edgeTrim)) * levelW;
        // fixed per fragment, |pan| <= 0.4 at spread 1.0 (§F). `spread` scales
        // the whole table and can never move one position: no pan LFO, no
        // per-fragment drift, no LFNoise1 anywhere in this layer.
        Pan2.ar(voice, panW * spreadL);
    });

    // --- block 5: condition ---
    sig = sig * makeup * amp.lag(0.05);
    sig = LeakDC.ar(sig);
    // the Limiter is a NONLINEARITY and must stay inert at every composed state
    // — it is the one mechanism by which this class could emit the excluded
    // third (a limiter engaging waveshapes lattice tones). It is here only as
    // the randomiser-stress safety brick, and that state is not a composed one.
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

("synths/theta — spec зарегистрирован ("
    ++ ~spec_theta.params.size ++ " параметров); ~openTuner.(\\theta)").postln;
)
