// App/synths/eta.scd — UNGRUND class 7/8 `eta` (composed silence).
// REAL (empty by definition).  // TODO: iterate this layer
// Premise §C.7: NO UGens — planned silence as an event with a duration;
// the implementation lives in the scheduler (4_sequencer.scd). The silent
// Ndef placeholder below only keeps the folder glob and the mixer handling
// all 8 classes uniformly (silence is a register, Axiom V).


// ===== CONFIG — edit here ============================================
(
~cfg_eta = (
    // eta has no timbral parameters — only a duration, owned by the
    // scheduler (4_sequencer.scd: timeline)
    note: "silence is a register"
);


// ===== LOGIC — synthesis (intentionally silent) ======================
Ndef(\eta, { Silent.ar(2) });
Ndef(\eta).fadeTime = 0.5;
)
