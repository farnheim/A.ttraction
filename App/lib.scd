// App/lib.scd — NET machines: ports, buses, registry ~netMachine, base values; docs: docs/architecture/app/code-notes.md

(
var netMap, netUnmap, netAlloc;

~ungSpecs  = ~ungSpecs  ? ();
~ungVals   = ~ungVals   ? ();
~netBus    = ~netBus    ? ();
~netHooks  = ~netHooks  ? ();

~ungSpecOf = { |layer| ~ungSpecs[layer.asSymbol] };
~netLayers = {
    (~activeLayers ? ~ungSpecs.keys.asArray.sort).select { |l| ~ungSpecs[l].notNil }
};
// both sides list the same ports in the same order — only the last port (\out / \in) differs
~netPorts = { |spec, side|
    spec.params.collect(_.key) ++ (spec[\vars] ? []).collect(_.key) ++ [if(side == \src) { \out } { \in }]
};
~netAllPorts = { |side|
    ~netLayers.value.collect { |l| ~netPorts.(~ungSpecs[l], side).collect { |k| [l, k] } }.flatten(1)
};
~netTag = { |port| (port[0] ++ "." ++ port[1]).asSymbol };
// a machine outside ~netLayers has no row or column: its cells are out of the geometry, so must not sound
~netPortIndex = { |l, k, side|
    var sp = ~ungSpecs[l], b = ~netBus[l];
    if(sp.isNil or: { b.isNil } or: { ~netLayers.value.includes(l).not }) { nil } {
        ~netPorts.(sp, side).indexOf(k) !? { |i| b[if(side == \src) { \tap } { \mod }].index + i }
    }
};

// ControlSpec:map rounds and clips in the language and is not safe to hand a UGen
netMap = { |sp, u|
    if(sp.warp.isKindOf(ExponentialWarp)) {
        sp.minval * ((sp.maxval / sp.minval) ** u)
    } { sp.minval + (u * (sp.maxval - sp.minval)) }
};
netUnmap = { |sp, x|
    if(sp.warp.isKindOf(ExponentialWarp)) {
        (x / sp.minval).log / (sp.maxval / sp.minval).log
    } { (x - sp.minval) / (sp.maxval - sp.minval) }
};

netAlloc = { |name, n|
    var b = ~netBus[name];
    if(b.isNil or: { b[\n] != n }) {
        b !? { b[\tap].free; b[\mod].free };
        b = ( n: n, tap: Bus.audio(s, n), mod: Bus.audio(s, n) );
        ~netBus[name] = b;
    };
    b
};

// everything the closure needs is captured here: the Ndef builds the graph outside this environment
~netMachine = { |spec, body|
    var entries = { |pairs| pairs.clump(2).collect { |kv| (key: kv[0], spec: kv[1].asSpec) } };
    var name, level, srcKeys, dstKeys, n, bus, tapIdx, modIdx;
    var map = netMap, unmap = netUnmap;
    var specs = (), vspecs = ();
    spec = spec.copy.putAll((params: entries.(spec.params), vars: entries.(spec[\vars] ? [])));
    name = spec.name;
    level = spec[\level] ? 1;
    srcKeys = ~netPorts.(spec, \src);
    dstKeys = ~netPorts.(spec, \dst);
    n = srcKeys.size;
    bus = netAlloc.(name, n);
    tapIdx = bus[\tap].index;
    modIdx = bus[\mod].index;
    spec.params.do { |p| specs[p.key] = p.spec };
    spec[\vars].do { |v| vspecs[v.key] = v.spec };

    ~ungSpecs[name] = spec;
    ~ungVals[name]  = ~ungVals[name] ? ();
    spec.params.do { |p| ~setParam.(name, p.key, ~ungVals[name][p.key] ? p.spec.default) };
    Ndef(name).fadeTime = spec[\fade] ? 2;
    Ndef(name, {
        var mods = InFeedback.ar(modIdx, n);
        var taps = Array.fill(n, { List.new });
        var cache = ();
        var port = { |key|
            var i = dstKeys.indexOf(key);
            if(i.isNil) { Error("net: " ++ name ++ " has no port " ++ key).throw };
            i
        };
        var io = (
            nyq: SampleRate.ir * 0.45,
            par: { |self, key|
                var i, sp, u;
                if(cache[key].isNil) {
                    i  = port.(key);
                    sp = specs[key];
                    u  = (key.ar(unmap.(sp, sp.default).clip(0, 1)).lag(0.005) + mods[i]).clip(0, 1);
                    taps[i].add((u * 2) - 1);
                    cache[key] = map.(sp, u);
                };
                cache[key]
            },
            node: { |self, key, sig|
                var i = port.(key), sp = vspecs[key], u;
                u = (unmap.(sp, sig.clip(sp.minval, sp.maxval)) + mods[i]).clip(0, 1);
                u.asArray.do { |x| taps[i].add((x * 2) - 1) };
                map.(sp, u)
            },
            feed: { |self|
                if(cache[\in].isNil) { cache[\in] = LeakDC.ar(mods[port.(\in)]).clip2(1) };
                cache[\in]
            }
        );
        var sig = Sanitize.ar(Limiter.ar(LeakDC.ar(body.(io) * level), 0.95));
        taps[n - 1].add(sig.asArray.mean);
        Out.ar(tapIdx, Sanitize.ar(taps.collect { |l| if(l.isEmpty) { DC.ar(0) } { l.asArray.mean } }));
        sig
    });
    ("net · " ++ name ++ " · " ++ n ++ " sources · " ++ dstKeys.size ++ " destinations").postln;
    ~netRewire.value;
};

// ----- parameters (base values; modulation rides on top in the graph) -----
~netParam = { |layer, key|
    ~ungSpecOf.(layer) !? { |sp| sp.params.detect { |p| p.key == key } }
};
~setParam = { |layer, key, v|
    var p;
    layer = layer.asSymbol; key = key.asSymbol;
    p = ~netParam.(layer, key);
    if(p.notNil) {
        v = p.spec.constrain(v);
        Ndef(layer).set(key, p.spec.unmap(v));
        if(~ungVals[layer].isNil) { ~ungVals[layer] = () };
        ~ungVals[layer][key] = v;
        ~netHooks.do { |f| f.(layer, key, v) };
    };
    v
};
~netGet = { |layer, key|
    (~ungVals[layer] !? { |d| d[key] }) ?? { ~netParam.(layer, key) !? { |p| p.spec.default } }
};
~netDefaults = { |layer|
    ~ungSpecOf.(layer) !? { |sp| sp.params.do { |p| ~setParam.(layer, p.key, p.spec.default) } };
};
~netDiceBase = { |layer, amt = 1.0|
    ~ungSpecOf.(layer).params.do { |p|
        var u = p.spec.unmap(~netGet.(layer, p.key));
        ~setParam.(layer, p.key, p.spec.map(u.blend(1.0.rand, amt)));
    };
};


"lib — машины готовы (~netMachine, ~setParam, ~netAllPorts).".postln;
)
