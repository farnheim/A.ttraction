// App/5_control.scd — UNGRUND · CONTROL: MIDI CC -> target mapping table
// plus one generic MIDIdef(\ung_cc) (fixed key: re-running replaces, never
// stacks). Adding a controller = adding a line to ~cfg_ctrl.map.
// Load after mixer/lfo (docs/architecture/app/README.md).


// ===== CONFIG — edit here ============================================
(
// Each line: ( cc: N, type: \layer|\mixVol|\mixSend|\lfoRate|\master,
//              target: \layer (or lfo index for \lfoRate),
//              param: \name (only for type \layer), min: lo, max: hi )
~cfg_ctrl = (
    channel: nil,    // nil = any MIDI channel
    map: [
        ( cc: 1,  type: \mixVol,  target: \alpha,            min: 0.0,  max: 1.0 ),
        ( cc: 7,  type: \master,                              min: 0.0,  max: 1.0 ),
        ( cc: 21, type: \layer,   target: \delta, param: \freq, min: 100, max: 2000 ),
        ( cc: 22, type: \mixSend, target: \theta,            min: 0.0,  max: 1.0 ),
        ( cc: 23, type: \layer,   target: \epsilon, param: \freqHi, min: 300, max: 2000 ),
        ( cc: 24, type: \lfoRate, target: 0,                  min: 0.005, max: 0.2 )
    ]
);


// ===== LOGIC — generic MIDI engine ===================================
if(MIDIClient.initialized.not) { MIDIClient.init };
MIDIIn.connectAll;

// fast lookup cc -> config line
~ctrlByCC = ();
~cfg_ctrl.map.do { |line| ~ctrlByCC[line.cc] = line };

// scale 0–127 -> [min, max] (linear)
~ctrlScale = { |val, lo, hi| (val / 127).linlin(0, 1, lo, hi) };

MIDIdef.cc(\ung_cc, { |val, num, chan|
    var line = ~ctrlByCC[num];
    if(line.notNil and: { ~cfg_ctrl.channel.isNil or: { chan == ~cfg_ctrl.channel } }) {
        var v = ~ctrlScale.(val, line.min, line.max);
        switch(line.type,
            \mixVol,  { ~mixSet.(line.target, \vol, v) },
            \mixSend, { ~mixSet.(line.target, \send, v) },
            \master,  { ~masterSet.(v) },
            \layer,   { Ndef(line.target.asSymbol).set(line.param, v) },
            \lfoRate, {
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
