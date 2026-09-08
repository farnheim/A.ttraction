// App/5_control.scd — UNGRUND · CONTROL: MIDI CC -> target mapping table
// plus one generic MIDIdef(\ung_cc) (fixed key: re-running replaces, never
// stacks). Adding a controller = adding a line to ~cfg_ctrl.map.
// Load after mixer/lfo (docs/architecture/app/README.md).


// ===== CONFIG — edit here ============================================
(
// Each line: ( cc: N, type: \layer|\mixVol|\mixSendRev|\mixSendDly|\lfoRate|\master,
//              target: \layer (or lfo index for \lfoRate),
//              param: \name (only for type \layer), min: lo, max: hi )
~cfg_ctrl = (
    channel: nil,    // nil = any MIDI channel
    // min/max are in the UNIT OF THE TARGET's spec row: a \freq row of a layer is
    // in MIDI NOTES, and Hz numbers there drive the control past its own clip
    map: [
        ( cc: 1,  type: \mixVol,     target: \alpha,                   min: 0.0,   max: 1.0 ),
        ( cc: 7,  type: \master,                                        min: 0.0,   max: 1.0 ),
        ( cc: 21, type: \layer,      target: \delta,   param: \f1,       min: 36,    max: 84 ),
        ( cc: 22, type: \mixSendRev, target: \theta,                     min: 0.0,   max: 1.0 ),
        ( cc: 23, type: \layer,      target: \epsilon, param: \freqHi,   min: 30.28, max: 90.28 ),
        ( cc: 24, type: \lfoRate,    target: 0,                         min: 0.005, max: 0.2 )
    ]
);


// ===== LOGIC — generic MIDI engine ===================================
if(MIDIClient.initialized.not) { MIDIClient.init };
MIDIIn.connectAll;

~ctrlByCC = ();
~cfg_ctrl.map.do { |line| ~ctrlByCC[line.cc] = line };

~ctrlScale = { |val, lo, hi| (val / 127).linlin(0, 1, lo, hi) };

MIDIdef.cc(\ung_cc, { |val, num, chan|
    var line = ~ctrlByCC[num];
    if(line.notNil and: { ~cfg_ctrl.channel.isNil or: { chan == ~cfg_ctrl.channel } }) {
        var v = ~ctrlScale.(val, line.min, line.max);
        switch(line.type,
            \mixVol,     { ~mixSet.(line.target, \vol, v) },
            \mixSendRev, { ~mixSet.(line.target, \sendRev, v) },
            \mixSendDly, { ~mixSet.(line.target, \sendDly, v) },
            \master,     { ~masterSet.(v) },
            // ~setParam, NOT Ndef.set: a direct n_set drops the koppelfeld node mapping
            \layer,      { ~setParam.(line.target.asSymbol, line.param, v) },
            \lfoRate,    {
                // ~lfoKeys exists only if 3_lfo is loaded — ignore silently
                if(~lfoKeys.notNil) {
                    var lfoKey = ~lfoKeys.detect { |k|
                        k.asString.beginsWith("lfo_" ++ line.target ++ "_") };
                    if(lfoKey.notNil) { Ndef(lfoKey).set(\rate, v) };
                };
            }
        );
    };
}).permanent_(true);

"5_control — MIDIdef(\\ung_cc) активен (CC-карта загружена).".postln;
)
