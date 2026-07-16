// App/synths/gamma.scd — UNGRUND class 3/8 `gamma` (granular cluster of sines).
// REAL LAYER, premise §C.3 `flockung` as amended 2026-07-16 (drip events):
// four FIXED drip points on the 94 Hz lattice (501.3 / 564 / 752 /
// 1002.7 Hz), each a damped sine grain that begins above its lattice
// position and SETTLES DOWN onto it (amendment (c) — rising glide is
// forbidden). Grains arrive in clusters of 3–8 scattered over a short
// window, clusters separated by a BOUNDED random interval (amendment (d)
// — never Dust's unbounded tail, Axiom III). The layer is DRY: no reverb,
// delay or resonator inside it — the cave's ≈ 0.95 s tail is the §K.1
// send (0.35), applied at the mixer.
// Reference: docs/features/gamma/drip-reference.md; measurement basis:
// docs/features/epsilon/cave-reference.md. Tuning via 0_lib.scd;
// ~spec_gamma is the single source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — the four fixed drip points + the settle ratio; MIDI
// defaults are exact cpsmidi of the Hz lattice (94 × 16/3, 6, 8, 32/3).
// group \tone — grain shape / arrival law / space / level.
~spec_gamma = (
    name: \gamma,
    params: [
        // --- group \freq: drip points (MIDI notes, 80–1200 Hz) + settle ---
        ( key: \d1,     group: \freq, disp: \note, spec: ControlSpec(39.49, 86.37, \lin, 0, 71.26) ),  // 501.3 Hz ×16/3
        ( key: \d2,     group: \freq, disp: \note, spec: ControlSpec(39.49, 86.37, \lin, 0, 73.30) ),  // 564 Hz ×6
        ( key: \d3,     group: \freq, disp: \note, spec: ControlSpec(39.49, 86.37, \lin, 0, 78.28) ),  // 752 Hz ×8
        ( key: \d4,     group: \freq, disp: \note, spec: ControlSpec(39.49, 86.37, \lin, 0, 83.26) ),  // 1002.7 Hz ×32/3
        ( key: \settle, group: \freq,             spec: ControlSpec(1.0, 1.35, \lin, 0, 1.16) ),  // onset ratio ABOVE the point; <1 forbidden

        // --- group \tone: grain shape ---
        ( key: \atk,        group: \tone, unit: " ms", spec: ControlSpec(1,     20,   \lin, 0, 4)    ),  // §F flockung 5–20 ms row
        ( key: \decay,      group: \tone, unit: " ms", spec: ControlSpec(40,    180,  \lin, 0, 91)   ),  // to −20 dB; measured median
        ( key: \settleTime, group: \tone, unit: " ms", spec: ControlSpec(30,    150,  \lin, 0, 110)  ),  // the glide's own duration
        ( key: \bodyQ,      group: \tone,              spec: ControlSpec(0.005, 0.05, \exp, 0, 0.02) ),  // onset bandwidth (tracks the glide)

        // --- group \tone: arrival law (bounded, clustered — NOT Poisson) ---
        ( key: \clusterLo,  group: \tone, unit: " s",  spec: ControlSpec(1.0,   6.0,  \lin, 0, 1.6)  ),  // bounded interval floor
        ( key: \clusterHi,  group: \tone, unit: " s",  spec: ControlSpec(2.0,   20,   \lin, 0, 9.4)  ),  // bounded interval ceiling
        ( key: \grains,     group: \tone,              spec: ControlSpec(3,     8,    \lin, 1, 6)    ),  // §C.3 hard max 8
        ( key: \window,     group: \tone, unit: " s",  spec: ControlSpec(0.2,   1.5,  \lin, 0, 0.9)  ),  // cluster window; onsets scatter inside

        // --- group \tone: level + space ---
        ( key: \grainAmp,   group: \tone,              spec: ControlSpec(0.05,  0.25, \lin, 0, 0.18) ),  // §C.3 per-grain band
        ( key: \spread,     group: \tone,              spec: ControlSpec(0.0,   1.0,  \lin, 0, 0.8)  ),  // scales the four FIXED pans
        ( key: \amp,        group: \tone,              spec: ControlSpec(0.0,   0.4,  \lin, 0, 0.22) )   // §F band −24…−9 dBFS
    ]
);


// ===== LOGIC — synthesis =============================================
// One persistent graph, no per-event Synths and no Routine: the arrival
// law is a demand-rate stream driving TDuty (idempotent on hot-swap).
// Scheduler -> slot lottery over 8 voices (weighted toward the low drip
// points) -> per-voice damped sine with a downward settle -> fixed pan
// per point -> sum -> LeakDC -> Limiter.
Ndef(\gamma, { |d1 = 71.26, d2 = 73.30, d3 = 78.28, d4 = 83.26, settle = 1.16,
    atk = 4, decay = 91, settleTime = 110, bodyQ = 0.02,
    clusterLo = 1.6, clusterHi = 9.4, grains = 6, window = 0.9,
    grainAmp = 0.18, spread = 0.8, amp = 0.22|

    var nyq;
    // fixed per point (§F: a drip point does not move) — all ≤ ±0.4 at
    // spread 1.0; `spread` scales all four together and cannot move one
    var panPos   = #[-0.30, 0.15, -0.10, 0.35];
    // voice -> drip point. NOT uniform, and the weighting is read straight
    // off the reference's own annotations: d1 is the measured f0 MEDIAN
    // (492) and d3 the p90 (771), which only holds if the low points fire
    // far more often — four equiprobable points would put the median at
    // ~658 Hz and the p90 at ~1003. Two voices on d1/d2/d3 also let a point
    // overlap itself instead of cutting its own tail.
    var voicePoint = #[0, 0, 0, 1, 1, 2, 2, 3];
    var voices     = 8;
    // Env.perc(atk, T, 1, -4) passes −20 dB at 0.5375·T, so T = decay/0.5375
    // makes the `decay` arg mean exactly what the reference measures
    var decayToT = 1.86;
    // bounded exponential per-grain amplitude (many small, few large — the
    // zeta precedent); bounded, so the crest stays auditable
    var grainAmpLo = 0.3;
    // lands peak -17 dBFS / RMS -38 at the spec defaults (delta precedent:
    // tune internals, never spec defaults)
    var makeup = 3.5;
    // skews the bounded cluster interval toward its floor: a UNIFORM draw
    // on [1.6, 9.4] has mean 5.5 s and yields ~0.97 events/s — half the
    // measured 1.84/s. The endpoints stay the two auditable controls.
    var clusterSkew = 4;
    var settleL, atkL, decayL, settleTimeL, bodyQL, grainsL, windowL;
    var clusterLoL, clusterHiL, spreadL, meanGap, isLast, durs;
    var tGrain, slot, dFreqs, sig;

    nyq = SampleRate.ir * 0.45;

    settleL     = settle.lag(0.2).clip(1.0, 1.35);
    atkL        = atk.lag(0.2).clip(1, 20) * 0.001;
    decayL      = decay.lag(0.2).clip(40, 180) * 0.001;
    settleTimeL = settleTime.lag(0.2).clip(30, 150) * 0.001;
    bodyQL      = bodyQ.lag(0.2).clip(0.005, 0.05);
    spreadL     = spread.lag(0.2).clip(0, 1);
    // density controls: lag 0.3 per the contract
    grainsL     = grains.lag(0.3).clip(3, 8).round(1);
    windowL     = window.lag(0.3).clip(0.2, 1.5);
    clusterLoL  = clusterLo.lag(0.3).clip(1.0, 6.0);
    // Hi is held above Lo: an inverted pair would make (Hi/Lo) < 1 and
    // invert the skew — the randomiser can reach that combination
    clusterHiL  = clusterHi.lag(0.3).clip(2.0, 20).max(clusterLoL * 1.05);

    // the arrival law: `grains` − 1 within-cluster gaps, then ONE bounded
    // cluster gap. Bounded by construction (Axiom III), auditable by
    // sweeping clusterLo/clusterHi; a cluster ends within
    // window + decay < 2 s (§C.3), a structural guarantee.
    meanGap = windowL / grainsL;
    isLast  = Dseq([Ddup(grainsL - 1, Dseq([0], 1)), Dseq([1], 1)], inf);
    durs    = Dswitch1([
        Dwhite(meanGap * 0.35, meanGap * 1.65),
        clusterLoL * ((clusterHiL / clusterLoL) ** (Dwhite(0, 1) ** clusterSkew))
    ], isLast);
    tGrain = TDuty.ar(durs);

    // slot lottery: one uniform draw over the voices, whose point mapping
    // carries the weighting (§F is satisfied — each point's PITCH is fixed;
    // only which point fires varies, which the reference lists under
    // "does vary")
    slot = TIRand.ar(0, voices - 1, tGrain);

    dFreqs = [d1, d2, d3, d4].collect { |n| n.lag(0.2).midicps };

    sig = Mix.fill(voices, { |v|
        var point = voicePoint[v];
        var trig, top, base, glide, freq, env, amt, grain;
        trig = tGrain * ((slot - v).abs < 0.5);
        // Nyquist clamp on the TOP of the glide (the settle raises the
        // onset frequency), then divide back — never clamp the target
        top   = (dFreqs[point] * settleL).clip(80, nyq);
        base  = top / settleL;
        // the leading 0-time segment is REQUIRED, not cosmetic: EnvGen only
        // restarts a SINGLE-segment Env once, at synth start — it ignores
        // every later trigger, and the settle silently never fires (grains
        // then sit on their lattice point from the first sample). Verified
        // against Env.perc, which retriggers because it has two segments.
        glide = EnvGen.ar(Env([1.0, settleL, 1.0], [0, settleTimeL], \exp), trig);
        freq  = base * glide;
        env   = EnvGen.ar(Env.perc(atkL, decayL * decayToT, 1, -4), trig);
        amt   = TExpRand.ar(grainAmpLo, 1.0, trig);
        // one damped sine per grain (§C.3 amendment (a)); Resonz TRACKS the
        // glide, so it shapes the onset's spectral spread only — it is not
        // a resonator ringing on its own (the layer must stay dry)
        grain = SinOsc.ar(freq) * env;
        grain = Resonz.ar(grain, freq, bodyQL) * 2;
        Pan2.ar(grain * amt, panPos[point] * spreadL);
    });

    sig = sig * makeup * grainAmp.lag(0.05) * amp.lag(0.05);
    sig = LeakDC.ar(sig);
    // the randomiser can stack grains 8 × grainAmp 0.25 × amp 0.4
    sig = Limiter.ar(sig, 0.95);
    sig
});

// register spec + apply defaults (self-sufficient: 0_lib only needed for
// interactive random/presets/GUI after the full App load)
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\gamma] = ~spec_gamma;
~ungVals[\gamma]  = ();
~spec_gamma.params.do { |p|
    Ndef(\gamma).set(p.key, p.spec.default);
    ~ungVals[\gamma][p.key] = p.spec.default;
};
Ndef(\gamma).fadeTime = 0.5;   // event class: cut, not faded; in-flight grains complete

("synths/gamma — spec зарегистрирован ("
    ++ ~spec_gamma.params.size ++ " параметров); ~openTuner.(\\gamma)").postln;
)
