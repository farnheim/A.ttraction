// App/3_lfo.scd — UNGRUND · LFO: central registry of all parameter
// automation. One kr-Ndef per line in ~cfg_lfo.lines, routed via
// Ndef(target).map(param, ...). Adding automation = adding a line.
// Load after mixer, before sequencer (docs/architecture/app/README.md).


// ===== CONFIG — edit here ============================================
(
// Each line: ( target: \layer, param: \name, shape: \sine|\tri|\noise|\noise0,
//              rate: Hz, min: lo, max: hi )
// target may also be the mixer: \mix_<layer> param \vol, or a send
// aggregator \fxsendRev / \fxsendDly param \send_<layer> (see 2_mixer.scd).
~cfg_lfo = (
    lines: [
        // alpha: very slow volume breathing (§C.1)
        ( target: \alpha,   param: \amp,    shape: \noise,  rate: 0.03, min: 0.16, max: 0.24 ),

        // delta: slow Q drift (§C.4)
        ( target: \delta,    param: \rq,     shape: \sine,   rate: 0.05, min: 0.015, max: 0.03 ),

        // epsilon: drift of the comb sweep top (§C.5)
        ( target: \epsilon, param: \freqHi, shape: \noise,  rate: 0.012, min: 600, max: 1000 ),

        // theta: slow AM rate drift (scintillation, §C.8)
        ( target: \theta,   param: \lfnRate, shape: \tri,   rate: 0.02, min: 0.08, max: 0.16 ),

        // mixer: slow breathing of theta's reverb send
        ( target: \fxsendRev, param: \send_theta, shape: \sine, rate: 0.025, min: 0.45, max: 0.70 )
    ]
);


// ===== LOGIC — automation engine =====================================
// Идемпотентный reload по СОБСТВЕННОМУ реестру ~lfoActive (Ndef.all — не ключи
// прокси, контракт §6); выжившие строки остаются смапленными (без разрыва),
// исчезнувшие: unmap target СНАЧАЛА, потом clear (иначе target на чужой шине)
~lfoNewKeys = ~cfg_lfo.lines.collect { |line, i|
    ("lfo_" ++ i ++ "_" ++ line.target ++ "_" ++ line.param).asSymbol;
};
(~lfoActive ? []).do { |e|
    if(~lfoNewKeys.includes(e[\key]).not) {
        Ndef(e[\target]).unmap(e[\param]);
        Ndef(e[\key]).clear;
    };
};

~lfoKeys   = [];   // public key registry (read by 5_control and 7_viz)
~lfoActive = [];   // key/target/param of the current run (for cleanup above)

~cfg_lfo.lines.do { |line, i|
    var lfoKey = ("lfo_" ++ i ++ "_" ++ line.target ++ "_" ++ line.param).asSymbol;
    var shape  = line.shape;
    var lo = line.min, hi = line.max;

    Ndef(lfoKey, { |rate = 0.05|
        var osc = switch(shape,
            \sine,   { SinOsc.kr(rate) },
            \tri,    { LFTri.kr(rate) },
            \noise,  { LFNoise2.kr(rate) },     // smooth drift
            \noise0, { LFNoise0.kr(rate) },     // stepped
            { LFNoise2.kr(rate) }
        );
        osc.range(lo, hi)
    });
    Ndef(lfoKey).set(\rate, line.rate);

    // .map, не .set: kr-прокси маппится через контрольную шину
    Ndef(line.target.asSymbol).map(line.param, Ndef(lfoKey));

    ~lfoKeys   = ~lfoKeys.add(lfoKey);
    ~lfoActive = ~lfoActive.add((
        key: lfoKey, target: line.target.asSymbol, param: line.param.asSymbol
    ));
};

("3_lfo — активно строк автоматизации: " ++ ~lfoKeys.size).postln;
)
