// App/synths/theta.scd — UNGRUND class 8/8 `theta` (gridded percussion aggregate).
// REAL LAYER, premise §C.8 `schotter` as established 2026-07-16 (the `firnis`
// card it replaces is struck for the record): the composite percussive event
// on a discrete grid. A strike is an AGGREGATE of four strata fused into one
// event ≤ 400 ms — `anschlag` (one impulse, ≤ 2 ms, invariant), `staub`
// (band-passed noise burst), `sättigung` (saturation of anschlag+staub, with
// optional ring modulation of the noise), `körper` (2–4 damped modes on the
// 94 Hz 3-limit lattice, excited BY the saturated bed, never by a clean click).
// The grid is the material: the ear audits POSITION, not pulse. Position law
// repeats every 420 steps (8.4 min); the eight coprime timbre wheels repeat
// once per ~4.775e9 cells (~36 years). There is NO random generator in this
// class — unpredictability is a period, not a draw (Axiom III).
// The layer is DRY: no reverb, delay, feedback or resonator outside a mode's
// own ≤ 390 ms decay — space is a mixer fact (§K.1 send 0.18; §K.2 send 0.0 is
// a FORBIDDEN move, not a preference: the delay's taps place phantom events
// off the grid).
// Spec: plans/active/theta-schotter-spec.md; reference:
// docs/features/theta/percussion-reference.md. Tuning via 0_lib.scd;
// ~spec_theta is the single source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — the modes' octave index + the noise band's two edges.
// group \tone — the grid law / the aggregate / level.
// The eight wheel tables and the eleven mode rows are internal constants
// (score, not CONFIG — gamma's voice->point precedent): they are audited by
// editing them and re-executing, never by a runtime parameter (§C.8 forbids
// a runtime audit/freeze parameter).
~spec_theta = (
    name: \theta,
    params: [
        // --- group \freq ---
        ( key: \modeOct, group: \freq,                          spec: ControlSpec(-1, 1, \lin, 1, 0)        ),  // integer octave; x2^n stays lattice-exact
        ( key: \gritLo,  group: \freq, unit: " Hz", disp: \hz,   spec: ControlSpec(200, 2000, \exp, 0, 300)  ),  // noise band floor (off-lattice by definition)
        ( key: \gritHi,  group: \freq, unit: " Hz", disp: \hz,   spec: ControlSpec(2000, 9000, \exp, 0, 9000) ),

        // --- group \tone: the grid (NEVER lagged — clamp/snap only) ---
        ( key: \step,    group: \tone, unit: " s",  spec: ControlSpec(0.7, 4.0, \lin, 0,   1.2) ),  // the frame; unmarked, never accented
        ( key: \lit,     group: \tone,              spec: ControlSpec(1, 7, \lin, 1,       3)   ),  // density = lit/step; clipped to min(divSeq)
        ( key: \divA,    group: \tone,              spec: ControlSpec(3, 7, \lin, 2,       5)   ),  // divSeq[0] — snapped to {3,5,7} internally
        ( key: \divB,    group: \tone,              spec: ControlSpec(3, 7, \lin, 2,       7)   ),  // divSeq[1]
        ( key: \divC,    group: \tone,              spec: ControlSpec(3, 7, \lin, 2,       3)   ),  // divSeq[2]
        ( key: \divD,    group: \tone,              spec: ControlSpec(3, 7, \lin, 2,       7)   ),  // divSeq[3]
        ( key: \scatter, group: \tone,              spec: ControlSpec(1, 16, \lin, 1,      4)   ),  // snapped to {1,2,4,8,11,13,16} (coprime to 105)
        ( key: \rotate,  group: \tone,              spec: ControlSpec(1, 16, \lin, 1,      1)   ),  // same snap set

        // --- group \tone: the aggregate ---
        ( key: \modeAmp,    group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.6)  ),  // mode stratum vs the saturated bed
        ( key: \gritQ,      group: \tone,              spec: ControlSpec(0.1, 1.4, \lin, 0, 0.5)  ),  // wide = surface, narrow = ping (loudness-normalised)
        ( key: \gritAmp,    group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.5)  ),
        ( key: \driveMax,   group: \tone, unit: " dB", spec: ControlSpec(0, 27, \lin, 0,   18)    ),  // scales wheel 5; 0 = linear
        ( key: \ringDepth,  group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.45) ),  // RM wet on `staub` ONLY
        ( key: \decayScale, group: \tone,              spec: ControlSpec(0.4, 1.0, \lin, 0, 1.0)  ),  // ceiling 1.0 holds the card's 400 ms bound
        ( key: \spread,     group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.8)  ),  // scales wheel 7; never moves one position
        ( key: \amp,        group: \tone,              spec: ControlSpec(0.0, 0.35, \lin, 0, 0.16) )  // §K.4; §F band −20…−8 dBFS peak
    ]
);


// ===== LOGIC — synthesis =============================================
// One persistent graph: no per-event Synths, no Routine, no Tdef, no Buffer,
// no doneAction. Grid + wheels are demand-rate streams inside the proxy
// (gamma's precedent), so hot-swap is idempotent and orphans nothing.
// Grid scheduler -> ar position mask -> round-robin over 8 voices -> per-voice
// aggregate (anschlag + staub -> tanh -> output path AND mode excitation) ->
// fixed pan -> sum -> LeakDC -> Limiter.
Ndef(\theta, { |modeOct = 0, gritLo = 300, gritHi = 9000,
    step = 1.2, lit = 3, divA = 5, divB = 7, divC = 3, divD = 7,
    scatter = 4, rotate = 1,
    modeAmp = 0.6, gritQ = 0.5, gritAmp = 0.5, driveMax = 18,
    ringDepth = 0.45, decayScale = 1.0, spread = 0.8, amp = 0.16|

    var nyq, fund = 94;
    var nVoices = 8;

    // --- wheel 1: the eleven mode rows (ratios of 94 Hz, all 2^i*3^j) in the
    // fixed non-monotone order [0,5,9,3,7,1,10,4,8,2,6]; 3-mode rows repeat
    // slot 0's ratio in slot 3 with gate 0. A monotone table reads as a sweep,
    // and a sweep is a gesture.
    var modeR = [
        #[2,   1.5, 1,  4.5,  2,    3,  4.5,  4,  6,  1,  8 ],
        #[3,   3,   3,  9,    6,    8,  8,    6,  9,  4,  12],
        #[4.5, 6,   12, 13.5, 13.5, 12, 13.5, 16, 12, 6,  16],
        #[2,   12,  1,  4.5,  2,    3,  16,   4,  16, 9,  8 ]
    ];
    var modeG3 = #[0, 1, 0, 0, 0, 0, 1, 0, 1, 1, 0];
    // wheel 2 — mode decay, ms to −20 dB (13). Top 130: T60 = 3*T20, so
    // 3 * 0.130 * decayScale(max 1.0) = 390 ms < the card's 400 ms bound.
    var decayTable = #[34, 8, 96, 21, 130, 52, 13, 78, 27, 110, 17, 63, 43];
    // wheel 3 — grit centre as a normalised exponent u (17); log-mapped
    // between gritLo and gritHi
    var gritUTable = #[0.35, 0.94, 0.06, 0.71, 0.24, 0.59, 0.88, 0.12, 0.47,
        1.0, 0.29, 0.65, 0.0, 0.82, 0.41, 0.18, 0.76];
    // wheel 4 — grit duration, ms to −60 dB (19)
    var gritDurTable = #[22, 7, 61, 14, 90, 33, 4, 47, 18, 74, 11, 39, 26, 82,
        9, 55, 30, 16, 68];
    // wheel 5 — drive, normalised (23), x driveMax dB
    var driveTable = #[0.62, 0.11, 0.88, 0.34, 0.75, 0.05, 0.51, 0.96, 0.23,
        0.69, 0.42, 1.0, 0.17, 0.57, 0.81, 0.0, 0.46, 0.92, 0.28, 0.73, 0.09,
        0.65, 0.38];
    // wheel 6 — ring carrier, Hz (5): 0 = off; 188/282/564/1128 = 94 x 2/3/6/12.
    // NOT scaled by modeOct: it modulates noise, carries no lattice obligation,
    // and no control reaches it — hence no Nyquist clamp is owed (a clamp here
    // would be dead DSP).
    var ringTable = #[0, 282, 1128, 188, 564];
    // wheel 7 — pan (29), ((i*11 mod 29)/28)*0.8 − 0.4; bounds exactly ±0.4 at
    // spread 1.0 (§F)
    var panTable = #[-0.400, -0.086, 0.229, -0.286, 0.029, 0.343, -0.171,
        0.143, -0.371, -0.057, 0.257, -0.257, 0.057, 0.371, -0.143, 0.171,
        -0.343, -0.029, 0.286, -0.229, 0.086, 0.400, -0.114, 0.200, -0.314,
        0.000, 0.314, -0.200, 0.114];
    // wheel 8 — event level, dB (31), −0.2*(i*7 mod 31); .dbamp at graph build
    var levelTable = [0, -1.4, -2.8, -4.2, -5.6, -0.8, -2.2, -3.6, -5.0, -0.2,
        -1.6, -3.0, -4.4, -5.8, -1.0, -2.4, -3.8, -5.2, -0.4, -1.8, -3.2,
        -4.6, -6.0, -1.2, -2.6, -4.0, -5.4, -0.6, -2.0, -3.4, -4.8]
        .collect { |db| db.dbamp };
    // scatter/rotate snap: index 0..15 (control 1..16) -> a value coprime to
    // 105 = 3*5*7, so it is coprime to EVERY admissible division. Sliders show
    // plateaus; that is the price of "the randomiser must not produce one".
    var coprimeTable = #[1, 2, 4, 4, 4, 8, 8, 8, 8, 11, 11, 13, 13, 13, 16, 16];
    // the step counter wraps at lcm(4,3,5,7) = 420 — divisible by the divSeq
    // index cycle AND by every admissible division, so the wrap is mask-exact.
    // Unwrapped, m*rotate would leave float32's integer range after ~2 weeks
    // of uptime and the grid would silently rot.
    var mWrap = 420;

    // --- dev-calibrated internals (not parameters), measured 2026-07-16 at
    // 44.1 k. A single-sample impulse's energy is sample-rate dependent, so
    // `makeup` shifts slightly at 48 k — calibrate at the render rate, never
    // "fix" it with an SR-dependent constant.
    var anschlagTrim = 0.5;    // impulse weight in the bed. Raising it RAISES crest
                               // (the click is peak without energy: 1.5 -> crest 31.8)
    var satTrim      = 1.0;    // direct (saturated bed) path vs the mode stratum;
                               // with modeTrim 0.10 this lands 6-12 kHz at rel -16.5
    var modeTrim     = 0.10;   // Ringz is ~6x hotter than its excitation (measured on
                               // a 20 ms burst), and the modes are the loudest stratum
    var bwRef        = 1200;   // bwNorm reference: BPF noise RMS ~ sqrt(rq*f).
                               // Verified: gritQ 0.1 vs 1.4 = 0.35 dB RMS delta
    var satExp       = -0.78;  // tanh loudness-rise compensation. Calibrated against
                               // the drive-neutrality check: driveMax 0 vs 27 = 0.18 dB
                               // RMS delta (-0.6 as specced left +2.4 dB, under-compensating)
    var makeup       = 3.83;   // lands peak -8.2 dBFS at amp 0.16 (target -9 +-3).
                               // RMS then lands -40, NOT the spec's -26: crest is ~29-32
                               // for this material (modes-only crest is 29.1 with the
                               // click removed entirely), so peak -9 and RMS -26 cannot
                               // both hold. Peak is the §F/limiter-safety metric, so it wins.

    var divAL, divBL, divCL, divDL, stepL, litL, scatterV, rotateV, modeOctL;
    var gritLoL, gritHiL, gritQL, driveMaxL, decayScaleL, spreadL, modeFund;
    var modeAmpL, gritAmpL, ringDepthL;
    var cStream, nStream, mStream, durStream, wheelStreams, tCell, vals;
    var c, n, m, mask, tFire, vIdx, sig;
    var wModeR, wG3, wDecay, wGritU, wGritDur, wDrive, wRing, wPan, wLevel;

    nyq = SampleRate.ir * 0.45;

    // --- grid controls: snapped/clamped, NEVER lagged. A lag here would make
    // an onset land BETWEEN cells while it settles, breaking the ±5 ms
    // identity metric transiently. Contract §5's lag rule is about zipper
    // noise on continuously read signals; these are read once per cell at a
    // discrete instant.
    // ControlSpec's `step` rounds to a MULTIPLE of step, not to lo + k*step —
    // ControlSpec(3,7,\lin,2,5) happily maps to 4 and 6, and a fractional or
    // even division is not a division. Every integer control snaps here.
    divAL = (((divA.clip(3, 7) - 3) / 2).round(1) * 2) + 3;
    divBL = (((divB.clip(3, 7) - 3) / 2).round(1) * 2) + 3;
    divCL = (((divC.clip(3, 7) - 3) / 2).round(1) * 2) + 3;
    divDL = (((divD.clip(3, 7) - 3) / 2).round(1) * 2) + 3;
    stepL    = step.clip(0.7, 4.0);
    litL     = lit.round(1).clip(1, 7);
    scatterV = Select.kr(scatter.round(1).clip(1, 16) - 1, coprimeTable);
    rotateV  = Select.kr(rotate.round(1).clip(1, 16) - 1, coprimeTable);

    // round AFTER lag: the octave must be an exact integer at EVERY instant,
    // because a per-event Latch could otherwise freeze a mode on 2**0.37 —
    // off-lattice, and permanently so for that event's whole ring
    modeOctL = modeOct.lag(0.2).round(1).clip(-1, 1);
    modeFund = fund * (2 ** modeOctL);

    // Nyquist clamps AFTER lag, via SampleRate.ir
    gritLoL     = gritLo.lag(0.2).clip(200, nyq);
    gritHiL     = gritHi.lag(0.2).clip(2000, nyq);
    gritQL      = gritQ.lag(0.2).clip(0.1, 1.4);
    driveMaxL   = driveMax.lag(0.2).clip(0, 27);
    decayScaleL = decayScale.lag(0.2).clip(0.4, 1.0);
    spreadL     = spread.lag(0.2).clip(0, 1);
    modeAmpL    = modeAmp.lag(0.1).clip(0, 1);
    gritAmpL    = gritAmp.lag(0.1).clip(0, 1);
    ringDepthL  = ringDepth.lag(0.1).clip(0, 1);

    // --- block 1: the grid scheduler (demand rate) ---
    // NO demand-rate arithmetic anywhere: every live grid control enters as a
    // kr INPUT to a demand UGen, which re-polls it at the pull. kr inputs are
    // not streams and therefore cannot desynchronise. (Verified 2026-07-16:
    // Dseries/Dser DO re-poll their kr length/repeats when the enclosing Dseq
    // resets them — the new division takes effect at the next step boundary,
    // the in-flight step completing at the old length.)
    cStream = Dseq([ Dseries(0, 1, divAL), Dseries(0, 1, divBL),
                     Dseries(0, 1, divCL), Dseries(0, 1, divDL) ], inf);
    nStream = Dseq([ Dser([divAL], divAL), Dser([divBL], divBL),
                     Dser([divCL], divCL), Dser([divDL], divDL) ], inf);
    // Ddup's two inputs are top-level streams that nothing ever resets, so no
    // reset propagates into them — the reason it is safe HERE and would not be
    // nested inside a repeating Dseq (a reset would restart the step counter
    // every cycle, freezing divSeq on divA). Used ONLY here, because a step
    // counter cannot be built from constants. (Dstutter is the deprecated alias
    // of this and warns on every load.)
    mStream = Ddup(Dseq([divAL, divBL, divCL, divDL], inf),
                   Dseq((0..(mWrap - 1)), inf));
    durStream = Dseq([ Dser([stepL / divAL], divAL), Dser([stepL / divBL], divBL),
                       Dser([stepL / divCL], divCL), Dser([stepL / divDL], divDL) ], inf);
    // TDuty pulls durStream once per cell, in the SAME control block as the
    // Demand.ar below — so durStream[k] is cell k's outgoing interval and the
    // whole grid stays in phase. Do NOT prepend a ControlDur.ir start latency
    // here: measured 2026-07-16, it inserts one extra pull on TDuty's side
    // only, which puts every Demand stream one cell AHEAD of the durations —
    // the mask then reads the NEXT cell's n, and ~10 % of steps fire 2 or 4
    // events instead of `lit`. Every band and level metric still passes in that
    // state; only the trigger ground truth catches it (the tell is a step with
    // n=3 and an unlit cell, which the law makes impossible).
    tCell = TDuty.ar(durStream);

    // --- block 2: the wheel odometer (demand rate) ---
    // A wheel of length L IS Dseq(<L-element table>, inf): it wraps at L by
    // construction — no counter, no modulo, no Dbufrd, no Buffer. All wheels
    // are pulled by the SAME Demand.ar as the counters, so they advance once
    // per CELL, lit or unlit — which is what severs pitch <-> density
    // structurally (§F): `lit` and `step` decide how much of a fixed timbre
    // field you hear and can never reach a mode frequency.
    // modeG0..G2 are constant 1, so only the varying gate needs a wheel.
    wheelStreams = modeR.collect { |t| Dseq(t, inf) }
        ++ [ Dseq(modeG3, inf), Dseq(decayTable, inf), Dseq(gritUTable, inf),
             Dseq(gritDurTable, inf), Dseq(driveTable, inf), Dseq(ringTable, inf),
             Dseq(panTable, inf), Dseq(levelTable, inf) ];

    // THE PULL-COUNT INVARIANT IS THE WHOLE GRID: every stream here is pulled
    // exactly ONCE per cell by this one Demand.ar (durStream once per cell by
    // TDuty), and all pulls for cell k land in the same control block. A
    // stream named twice in one demand-rate expression is pulled TWICE and
    // desynchronises permanently; a second Demand, a Dpoll or a viz tap added
    // later breaks the grid silently. This is why the mask below is ar.
    vals = Demand.ar(tCell, 0, [cStream, nStream, mStream] ++ wheelStreams);
    // name every output at the point of the pull: positional vals[i] indices
    // across a 15-channel Demand are a silent-failure class of their own (a
    // mis-indexed wheel still passes every level and band metric)
    c = vals[0]; n = vals[1]; m = vals[2];
    wModeR   = vals[3..6];
    wG3      = vals[7];
    wDecay   = vals[8];
    wGritU   = vals[9];
    wGritDur = vals[10];
    wDrive   = vals[11];
    wRing    = vals[12];
    wPan     = vals[13];
    wLevel   = vals[14];

    // the position law, at audio rate: cell c of step m fires iff
    // ((c*scatter + m*rotate) mod n) < min(lit, n). At ar, n is a plain signal
    // and may be used twice for free. All operands are small integers exact in
    // float32 (max 6*16 + 419*16 = 6800).
    mask  = (((c * scatterV) + (m * rotateV)) % n) < litL.min(n);
    tFire = tCell * mask;

    // --- block 3: deterministic round-robin over the voice bank ---
    // Stepper, not TIRand: there is NO random generator in this class (§C.8).
    // At the maximum density (lit 7 / step 0.7 = 10 /s) a voice is reused
    // after 0.8 s > the 0.39 s ring, so no allocation can ever steal an
    // anschlag — the class's only unrecoverable failure — structurally.
    vIdx = Stepper.ar(tFire, 0, 0, nVoices - 1, 1);

    sig = Mix.fill(nVoices, { |v|
        var trig, anschlag, centre, bwNorm, staub, gritDurL, ringF, depth;
        var bedRaw, bedNorm, pre, satNorm, sat, satOut;
        var decayL, ringT, gate3, gateSum, modeFs, modes;
        var panW, levelW, voice;

        trig = tFire * ((vIdx - v).abs < 0.5);

        // --- stage 1: freeze the event. The Demand.ar outputs change on EVERY
        // cell, so a voice reading them live would be re-tuned mid-ring. Every
        // per-event quantity is latched at THIS voice's trigger, and the
        // MAPPED value is latched, so the whole event is constant for its life.

        // --- stage 2: anschlag — the trigger itself, shaped. Decay2's decay
        // arg is the −60 dB time, so 1.8 ms => ≤ 2 ms total. INVARIANT across
        // every event and unreachable from any parameter — which is what makes
        // loudness <-> attack-sharpness structurally impossible (§F) rather
        // than merely forbidden. The fixed HPF also strips the unipolar
        // impulse's DC before the saturator (a nonlinearity on a DC-offset
        // signal is an asymmetric distortion); the LPF holds the class's 9 kHz
        // composite ceiling.
        anschlag = Decay2.ar(trig, 0.0002, 0.0018);
        anschlag = LPF.ar(HPF.ar(anschlag, 300), 9000);

        // --- stage 3: staub — band-passed noise burst.
        centre = Latch.ar(gritLoL * ((gritHiL / gritLoL) ** wGritU), trig)
            .clip(200, nyq);
        // bandwidth normalisation is mandatory: a BPF's noise output RMS is
        // proportional to sqrt(rq*f), so without it `gritQ` would move loudness
        // (§F: one parameter, one dimension) and the grit-centre wheel would
        // become a per-event loudness wheel.
        bwNorm   = (bwRef / (gritQL * centre)).sqrt;
        gritDurL = Latch.ar(wGritDur, trig) * 0.001;
        staub    = BPF.ar(WhiteNoise.ar, centre, gritQL) * bwNorm;
        staub    = staub * Decay2.ar(trig, 0.001, gritDurL);

        // --- stage 4: ring modulation, on the FILTERED NOISE only. A 2-pole
        // BPF has a transmission zero at DC, so its output is DC-free by
        // construction and the carrier cannot feed through — no extra HPF is
        // warranted. NEVER between tones: 3:2 emits 94*5 = 470 Hz, the excluded
        // third (the only 3-limit-closed RM ratios are 2:1 and 1:3).
        ringF = Latch.ar(wRing, trig);
        depth = (ringDepthL * (ringF > 0) * 2) - 1;
        staub = XFade2.ar(staub, staub * SinOsc.ar(ringF), depth);

        // --- stages 5–6: sättigung. bedNorm's amplitude is independent of
        // gritAmp, so the tanh's operating point — i.e. the aggregate's
        // bandwidth — is set by driveMax ALONE; satOut restores the stratum
        // sum's level afterwards, so gritAmp maps loudness only. Without this
        // pair, loudness would widen bandwidth (§F's own textbook example).
        bedRaw  = (anschlag * anschlagTrim) + (staub * gritAmpL);
        bedNorm = bedRaw / (anschlagTrim + gritAmpL).max(0.1);
        pre     = (Latch.ar(wDrive, trig) * driveMaxL).dbamp;
        satNorm = pre.max(1) ** satExp;
        sat     = (bedNorm * pre).tanh * satNorm;
        satOut  = sat * (anschlagTrim + gritAmpL);

        // --- stage 7: körper — the modes, excited by the NORMALISED saturated
        // bed, so mode loudness tracks modeAmp only and a mode never rings from
        // a clean click. Ringz's decaytime is the −60 dB time while the wheel
        // is specified to −20 dB, hence the x3: 3 * 0.130 * 1.0 = 390 ms holds
        // the card's 400 ms bound BY CONSTRUCTION, with no clip engaging. The
        // clamp ships belt-and-braces so editing the table cannot break the card.
        decayL = Latch.ar(wDecay, trig) * 0.001;
        ringT  = (3 * decayL * decayScaleL).clip(0.012, 0.39);
        gate3  = Latch.ar(wG3, trig);
        // power normalisation, so a 4-mode row is not systematically louder
        // than a 3-mode row
        gateSum = 3 + gate3;
        modeFs  = wModeR.collect { |r| Latch.ar(r * modeFund, trig).clip(40, nyq) };
        // THE ×5 PROOF'S STRUCTURAL HALF, and it is a one-line invariant: `sat`
        // feeds Ringz; Ringz output goes ONLY to the sum. The modes must never
        // re-enter the saturator, and no glue compressor/saturator may ever be
        // added after this sum — a memoryless nonlinearity on a lattice tone
        // emits 5*94*a, precisely the excluded third.
        modes = Mix([
            Ringz.ar(sat, modeFs[0], ringT),
            Ringz.ar(sat, modeFs[1], ringT),
            Ringz.ar(sat, modeFs[2], ringT),
            Ringz.ar(sat, modeFs[3], ringT) * gate3
        ]) / gateSum.sqrt;

        // --- stages 8–9 ---
        levelW = Latch.ar(wLevel, trig);
        panW   = Latch.ar(wPan, trig);
        voice  = ((satOut * satTrim) + (modes * modeAmpL * modeTrim)) * levelW;
        // fixed per cell, |pan| ≤ 0.4 at spread 1.0 (§F). `spread` scales the
        // whole table and can never move one position: no pan LFO, no per-event
        // drift, no LFNoise1 anywhere in this layer.
        Pan2.ar(voice, panW * spreadL);
    });

    // --- stage 10: condition ---
    sig = sig * makeup * amp.lag(0.05);
    sig = LeakDC.ar(sig);
    // the Limiter is a NONLINEARITY too and must stay inert at every composed
    // state — a limiter engaging waveshapes lattice tones (§C.8's first
    // forbidden move). It is here only as the randomiser-stress safety brick,
    // and that state is not a composed one.
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
