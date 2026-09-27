// App/tape.scd — TAPE: the master tape stage `kennlinie` (§K.6) between LeakDC
// and the Limiter of Ndef(\master). A port of the measured FerricTDS-type model
// as shipped in our VST3 "Spl Tape" v0.3 (Plugin/Source/TapeModel.cpp): program-
// dependent compressor, 2× oversampled track saturator with stereo crosstalk,
// COLOR (emphasis, flux, LF resonance, dispersion), W&F as one swept allpass.
// Model, findings, validation: docs/features/master/ferric-model/README.md.
// Loads before mixer.scd; re-executing this file rebuilds the master live.


// ===== CONFIG — edit here ============================================
(
// the knobs are the plugin's, all 0…1: hr = operating level (±12 dB drive,
// output-compensated), dyn = compression, rec = recovery, sat = saturation
// drive, lim = limiter curve blend, color = head/transformer colour, wf = W&F,
// trim = output ±6 dB. `? ()`: the knobs are STATE and survive a hot reload
~cfg_tape = ~cfg_tape ? (
    on: 1,
    hr: 0.5, color: 0.0, wf: 0.0, dyn: 0.0, rec: 0.0, sat: 0.0, lim: 0.0, trim: 0.5
);


// ===== LOGIC — the model =============================================
~tapeKeys = [\on, \hr, \color, \wf, \dyn, \rec, \sat, \lim, \trim];

// fitted constants of Spl Tape v0.3 — measurement results, not taste
~tapeModel = (
    satScale: 0.253, crosstalk: -0.31, makeupDb: 0.14, smoothTime: 0.02,
    comp: (
        sA: 0.35091274, kA: -7.6612718, wA: 3.6324319,
        sB: 6, kB: 13.166987, wB: 6.3361546, bandFc: 702.8828, bandQ: 6,
        ceilingDb: 14.38003,
        hpSlow: 49.312799, lpSlow: 6884.5703, hpFast: 188.3744, lpFast: 24000,
        fa0: 0.0001, kfa: 6, fr0: 0.089352233, kfr: -3.1621184,
        sa0: 0.035637878, ksa: 0.17098161, sr0: 0.032439148, ksr: 0.7839592,
        mix: 0.22646734, fastOffsetDb: -6.7472474, linkFast: 0.37862744, linkSlow: 1,
        g0: 0.0020780639, kg: -3.6066804
    ),
    sidechain: ( floorDb: 8.968, floorCurve: 0.918, poleHz: 140.23, poleCurve: 0.958 ),
    knee: ( t: 0.23209114, n: 3.8678291, k: 0.97274954 ),
    xfmr: (
        amount: 0.1827766, fluxHz: 21.66114, bandHz: 38.46943, bandQ: 0.3762099,
        dampDb: 0.4633671, dampLevel: 0.2496891, dampPower: 1.440644, energyTime: 0.007889419
    ),
    hfAllpass: [18486.08, 1.1605533],
    colorHf: (
        x: [0, 0.25, 0.5, 1],
        zero: [2113.5636, 2113.5636, 2411.1947, 2617.2247],
        gainDb: [0, 3.3811377, 6.2903346, 11.737604]
    ),
    colorLf: (
        x: [0, 0.24, 0.49, 0.74, 0.99],
        hpHz: [2.8671235, 2.4342377, 2.0518962, 1.7284048, 1.4555609],
        hpQ: [0.20000003, 0.20000003, 0.20000013, 0.2, 0.20000065],
        pkHz: [31.747244, 28.912318, 26.372943, 24.195281, 22.227713],
        pkDb: [1.7089905, 2.4816077, 3.2588726, 4.0265611, 4.7669983],
        pkQ: [0.41648597, 0.40757959, 0.39870077, 0.388875, 0.37772775],
        apAHz: [26.152252, 50.324664, 87.580034, 143.00774, 238.98454],
        apAQ: [0.60185811, 0.60078064, 0.6263882, 0.63917587, 0.6532474],
        apBHz: [24.4813, 52.194592, 91.730456, 155.40941, 267.49967],
        apBQ: [0.40675009, 0.41517856, 0.39763632, 0.38942853, 0.37923476]
    ),
    wf: ( rateScale: 0.993, rateCurve: 2.512, cornerAt48k: 1 / 3.425, logDepth: 0.31 ),
    halfTaps: 16, lag60: 6.907755
);
~tapeModel.latency = (2 * ~tapeModel.halfTaps) - 1;

~tapeHalfBand = {
    var hb = ~tapeModel.halfTaps;
    var g = hb.collect { |i|
        var k = (2 * i) + 1, n = 2 * hb;
        var w = 0.42 + (0.5 * cos(pi * k / n)) + (0.08 * cos(2pi * k / n));
        0.5 * sin(pi * k / 2) / (pi * k / 2) * w
    };
    g * (0.25 / g.sum)
}.value;

~tapeTable = { |xs, ys, x|
    IEnvGen.kr(Env(ys, xs.differentiate.drop(1)), x.clip(xs.first, xs.last) - xs.first)
};

~tapeOnePole = { |x, kind, fc, sr|
    var a = exp(-2pi * fc / sr);
    if(kind == \hp) { FOS.ar(x, a, a.neg, a) } { FOS.ar(x, 1 - a, 0, a) }
};

// RBJ biquads through BEQSuite, never SOS: SOS takes its coefficients as
// float32 inputs, which leaves a 25 Hz COLOR allpass only −71 dB clean against
// double precision (measured 2026-09-27); BEQSuite derives them in double, −152 dB
~tapeRbj = { |x, kind, f0, q, gainDb = 0|
    var rq = q.reciprocal;
    switch(kind,
        \hp, { BHiPass.ar(x, f0, rq) },
        \ap, { BAllPass.ar(x, f0, rq) },
        \pk, { BPeakEQ.ar(x, f0, rq, gainDb) },
        \bp, { var w0 = 2pi * f0 * SampleDur.ir; BBandPass.ar(x, f0, log((0.5 / q) + ((0.25 / q.squared) + 1).sqrt) * sin(w0) / (0.34657359 * w0)) }
    )
};

~tapeShelf = { |x, zeroHz, poleHz, sr, normalizeHf = true|
    var kz = tan(pi * zeroHz / sr), kp = tan(pi * poleHz / sr);
    var r = if(normalizeHf) { kp / kz } { 1 };
    FOS.ar(x, r * (1 + kz) / (1 + kp), r * (kz - 1) / (1 + kp), (1 - kp) / (1 + kp))
};

~tapeSoftplus = { |x| x.max(0) + log(1 + exp(x.abs.neg)) };

~tapeDetector = { |fastL, fastR, slowL, slowR, rec|
    var c = ~tapeModel.comp, l60 = ~tapeModel.lag60;
    var fa = c.fa0 * exp(c.kfa * rec) * l60, fr = c.fr0 * exp(c.kfr * rec) * l60;
    var sa = c.sa0 * exp(c.ksa * rec) * l60, sd = c.sr0 * exp(c.ksr * rec) * l60;
    var al = fastL.abs, ar = fastR.abs, mx = max(al, ar);
    var pl = slowL.squared, pr = slowR.squared, pm = 0.5 * (pl + pr);
    var fastIn = [al, ar].collect { |a| (c.linkFast * mx) + ((1 - c.linkFast) * a) };
    var slowIn = [pl, pr].collect { |p| (c.linkSlow * pm) + ((1 - c.linkSlow) * p) };
    [0, 1].collect { |i|
        var f = LagUD.ar(fastIn[i], fa, fr), s = LagUD.ar(slowIn[i], sa, sd);
        (c.mix * (f.max(1e-12).ampdb + c.fastOffsetDb))
            + ((1 - c.mix) * ((s.max(1e-20).ampdb * 0.5) + 3.0103))
    }
};

~tapeCompressor = { |l, r, drive, color, rec, sr|
    var c = ~tapeModel.comp, sc = ~tapeModel.sidechain;
    var cc = color.max(1e-4), pole = sc.poleHz * (cc ** sc.poleCurve);
    var zero = pole * (sc.floorDb.neg * (cc ** sc.floorCurve)).dbamp;
    var x = [l, r].collect { |v|
        var d = v * drive;
        Select.ar(color > 0, [d, ~tapeShelf.(d, zero, pole, sr, false)])
    };
    var slowSc = x.collect { |v| ~tapeOnePole.(~tapeOnePole.(v, \hp, c.hpSlow, sr), \lp, c.lpSlow, sr) };
    var fastSc = x.collect { |v| ~tapeOnePole.(~tapeOnePole.(v, \hp, c.hpFast, sr), \lp, c.lpFast, sr) };
    var bandSc = x.collect { |v| ~tapeRbj.(v, \bp, c.bandFc, c.bandQ) };
    var ea = ~tapeDetector.(fastSc[0], fastSc[1], slowSc[0], slowSc[1], rec);
    var eb = ~tapeDetector.(bandSc[0], bandSc[1], bandSc[0], bandSc[1], rec);
    var smooth = exp(-1 / (c.g0 * exp(c.kg * rec) * sr));
    [0, 1].collect { |i|
        var red = (c.sA * c.wA * ~tapeSoftplus.((ea[i] - c.kA) / c.wA))
            + (c.sB * c.wB * ~tapeSoftplus.((eb[i] - c.kB) / c.wB));
        OnePole.ar((c.ceilingDb * tanh(red / c.ceilingDb)).neg, smooth)
    }
};

~tapeKnee = { |u|
    var k = ~tapeModel.knee, a = u.abs, r = (a - k.t).max(0) / (1 - k.t);
    k.k * u.sign * (a.min(k.t) + ((1 - k.t) * r / ((1 + (r ** k.n)) ** (1 / k.n))))
};

// first-order ADAA of u/√(1+u²) with the difference quotient rationalised:
// (F(c) − F(p))/(c − p) = (c + p)/(√(1+c²) + √(1+p²)). No division by c − p,
// so no ill-conditioned branch — in float32 the plain quotient loses ~−76 dB
~tapeShape = { |cur, prev, lim|
    var soft = ((cur + prev) / ((1 + cur.squared).sqrt + (1 + prev.squared).sqrt))
        + (0.5 * (cur - prev));
    soft + (lim * (~tapeKnee.(cur) - soft))
};

// 2× polyphase island around the shaper, Blackman half-band
~tapeOversampled = { |x, lim|
    var hb = ~tapeModel.halfTaps, g = ~tapeHalfBand;
    var taps = { |v, n| var t = v; [v] ++ n.collect { t = Delay1.ar(t) } };
    var fir = { |l| hb.collect { |i| g[i] * (l[hb - 1 - i] + l[hb + i]) }.sum };
    var line = taps.(x, (2 * hb) - 1), even = line[hb], odd = 2 * fir.(line);
    var shapedEven = ~tapeShape.(even, Delay1.ar(odd), lim);
    (0.5 * taps.(shapedEven, hb - 1).last) + fir.(taps.(~tapeShape.(odd, even, lim), (2 * hb) - 1))
};

~tapeWfRate = { |wf| ~tapeModel.wf.rateScale * sinh(~tapeModel.wf.rateCurve * wf) };

// Phasor, not SinOsc: its phase accumulates in double; the wavetable SinOsc
// leaves 1e-4 of error in the W&F allpass coefficient (measured 2026-09-27)
~tapeWfCos = { |wf| (Phasor.ar(0, ~tapeWfRate.(wf) * SampleDur.ir) * 2pi).cos };

// sig: stereo; knobs: an Event of the ~tapeKeys (control UGens or numbers);
// wfCos: the W&F cosine from a shared clock, nil = the body runs its own
~tapeBody = { |sig, knobs, wfCos|
    var m = ~tapeModel, x = m.xfmr, lf = m.colorLf, sr = SampleRate.ir, beta = m.crosstalk;
    var kv = ~tapeKeys.collect { |k| var v = knobs[k]; if(v.isNumber) { DC.kr(v) } { v } };
    var smooth = { |v| Lag.kr(v, m.smoothTime * m.lag60) };
    var on, hr, color, wf, dyn, rec, sat, lim, trim;
    var h, compDrive, satDrive, headroom, outGain, colorOn, wfOn, lfIdx;
    var hfGain, fz, fp, corner, wfK, wfCoef, energyCoef;
    var in, gdb, pre, kx, tracks, wet, dry, lt;

    #on, hr, color, wf, dyn, rec, sat, lim, trim = kv;
    colorOn = smooth.(color > 0); wfOn = smooth.(wf > 0);
    on = smooth.(on); lim = smooth.(lim); color = smooth.(color);
    h = 24 * (0.5 - smooth.(hr));
    compDrive = (h + (36 * smooth.(dyn))).dbamp;
    satDrive  = (h + (24 * smooth.(sat))).dbamp;
    headroom  = h.dbamp;
    outGain   = (m.makeupDb + ((smooth.(trim) - 0.5) * 12)).dbamp;
    lfIdx     = (color - 0.01).max(0);
    lt = lf.collect { |ys, k| if(k != \x) { ~tapeTable.(lf.x, ys, lfIdx) } };

    hfGain = ~tapeTable.(m.colorHf.x, m.colorHf.gainDb, color);
    fz = ~tapeTable.(m.colorHf.x, m.colorHf.zero, color);
    fp = fz * hfGain.dbamp;

    corner = m.wf.cornerAt48k * 48000 / sr;
    wfK    = corner * exp(m.wf.logDepth.neg * (wfCos ?? { ~tapeWfCos.(wf) }));
    wfCoef = (wfK - 1) / (wfK + 1);
    energyCoef = exp(-1 / (x.energyTime * sr));

    in = sig.collect { |v|
        var disp = ~tapeRbj.(~tapeRbj.(v, \ap, lt.apAHz, lt.apAQ), \ap, lt.apBHz, lt.apBQ);
        v + (colorOn * (disp - v))
    };
    gdb = ~tapeCompressor.(in[0], in[1], compDrive, color, rec, sr);
    pre = [0, 1].collect { |i| ~tapeShelf.(in[i] * gdb[i].dbamp, fz, fp, sr) };

    // two tape tracks with crosstalk β: mono passes as one track, anti-phase
    // distorts most; the output matrix is the exact inverse of the input one
    kx = satDrive * m.satScale / (1 + beta);
    tracks = [0, 1].collect { |i| ~tapeOversampled.(kx * (pre[i] + (beta * pre[1 - i])), lim) };

    wet = [0, 1].collect { |i|
        var shaped = (tracks[i] - (beta * tracks[1 - i])) / (kx * (1 - beta.squared));
        var post = ~tapeShelf.(shaped, fp, fz, sr);
        var internal = post * headroom;
        var phi = ~tapeOnePole.(internal, \lp, x.fluxHz, sr);
        var wound = internal - (x.amount * phi * phi.abs);
        var band = ~tapeRbj.(wound, \bp, x.bandHz, x.bandQ);
        var r = OnePole.ar(band.squared, energyCoef).sqrt / x.dampLevel;
        var damping = (x.dampDb.neg * (r ** x.dampPower) / ((1 + r) ** (x.dampPower - 1))).dbamp;
        var colored = ~tapeRbj.(~tapeRbj.((wound + ((damping - 1) * band)) / headroom, \hp, lt.hpHz, lt.hpQ),
            \pk, lt.pkHz, lt.pkQ, lt.pkDb);
        var y = post + (colorOn * (colored - post));
        y = ~tapeRbj.(y, \ap, m.hfAllpass[0].min(sr * 0.45), m.hfAllpass[1]);
        // direct form I (y = c·x + x₁ − c·y₁) as the model defines it: FOS alone is
        // direct form II, which differs once c moves; every FOS input audio-rate,
        // or it falls back to per-block ramps
        y = y + (wfOn * (FOS.ar((wfCoef * y) + Delay1.ar(y), DC.ar(1), DC.ar(0), wfCoef.neg) - y));
        y * outGain
    };

    // the bypass runs through the same latency: switching is a crossfade, not a jump
    dry = DelayN.ar(sig, 0.01, (m.latency + 0.25) * SampleDur.ir);
    dry + (on * (wet - dry))
};


// ===== LOGIC — live state ============================================
// the knobs live on ONE control bus: every stage that reads it (Ndef(\master),
// render_master's no-limiter probe) hears the same settings by construction
~busTape = ~busTape ?? { Bus.control(s, ~tapeKeys.size) };

~tapeKnobs = {
    var v = In.kr(~busTape.index, ~tapeKeys.size);
    ().putPairs([~tapeKeys, v].flop.flatten)
};

// ONE W&F oscillator for every stage: two nodes started at different moments
// would each run their own phase, and render_master's probe would then differ
// from the master wherever wf > 0 (measured: guard median 0.056 dB). Built once
// — a hot reload keeps its phase instead of crossfading two oscillators. The
// NRT tools load this file with no server: their body runs its own oscillator
if(s.serverRunning and: { Ndef(\tapeClock).source.isNil }) {
    Ndef(\tapeClock, { ~tapeWfCos.(In.kr(~busTape.index + ~tapeKeys.indexOf(\wf))) });
};
~tapeStage = { |sig| ~tapeBody.(sig, ~tapeKnobs.value, Ndef(\tapeClock).ar(1)) };

~tapePush = { ~busTape.setn(~cfg_tape.atAll(~tapeKeys)) };

~tapeSet = { |key, value|
    var k = key.asSymbol, i = ~tapeKeys.indexOf(k);
    if(i.isNil) { ("tape — нет ручки " ++ key).warn } {
        ~cfg_tape[k] = value;
        ~busTape.setAt(i, value);
        ~tapeGuiSync.(k, value);
    };
};

~tapePush.value;

// hot reload: a master built before this file ran still carries the old body
// (the hook exists only while mixer.scd is loaded — ~appCleanup clears it)
~mixerRebuildMaster !? (_.value);


// ===== GUI — the tape block of the Ungrund window ===================
~tapeGuiRows = [
    [\hr, "headrm"], [\trim, "trim"], [\sat, "sat"], [\lim, "limit"],
    [\dyn, "dyn"], [\rec, "recov"], [\color, "color"], [\wf, "w&f"]
];
~tapeGuiHeight = 34 + (~tapeGuiRows.size * 28);
~tapeWid = ~tapeWid ? ();

~tapeGui = { |win, x, y|
    var fmt2 = { |v| ~uiFmt.(v, 2) };
    ~tapeWid = ();
    ~tapeWid[\on] = ~uiBtn.(win, Rect(x, y, 84, 24), ["tape off", "tape on"],
        { ~tapeSet.(\on, if(~cfg_tape[\on] > 0.5) { 0 } { 1 }) }, ~cfg_tape[\on] > 0.5);
    ~tapeGuiRows.do { |row, i|
        var key = row[0];
        ~tapeWid[key] = ~uiRulerRow.(win, x, y + 34 + (i * 28), 42, 190, row[1],
            ControlSpec(0, 1, \lin, 0, ~cfg_tape[key]), ~cfg_tape[key], { |v| ~tapeSet.(key, v) }, fmt2);
    };
};

~tapeGuiSync = { |key, value|
    if(key == \on) { ~uiBtnSet.(~tapeWid[\on], value > 0.5) } { ~tapeWid[key] !? { |r| ~uiRulerSet.(r, value) } };
};

"tape — kennlinie (§K.6): ~tapeSet.(\\sat, 0.3)".postln;
)
