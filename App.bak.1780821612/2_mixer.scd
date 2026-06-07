// =====================================================================
// App/2_mixer.scd
// UNGRUND · MIXER — уровни слоёв, посылы в эффекты, мастер
//
// Микшер — единственное место, где сводятся все 8 синт-слоёв. Для
// каждого слоя задаются:
//   vol  — громкость сухого сигнала в мастер;
//   send — доля сигнала, уходящая в ~busFxSend (вход эффектов, §K).
//
// СИГНАЛ-ФЛОУ:
//   Ndef(\<class>)  --vol-->  ~busDry  -----\
//                  \--send-->  ~busFxSend     >--> Ndef(\master) --> out 0
//   Ndef(\tape_reverb)/(\ping_delay) --> ~busFxReturn --/
//
// Реализация: на каждый слой создаётся Ndef(\mix_<class>) — роутер,
//   читающий сухой слой и пишущий (а) в ~busDry с громкостью vol,
//   (б) в ~busFxSend с долей send. Так каждый слой иттерируется
//   отдельно, а его уровни/посылы живут здесь, в CONFIG.
//
// Зависимости: синт-слои (Ndef(\monade) ...), эффекты (6_effects.scd),
//   шины ~busDry / ~busFxSend / ~busFxReturn (создаёт 1_app.scd).
// Итерировать сведение = править таблицу levels ниже.
// =====================================================================


// ===== CONFIG — edit here ============================================
(
// Таблица уровней, ключ = имя слоя. vol = громкость в мастер,
// send = посыл в эффекты (§K.1/K.2 рекомендуемые уровни как старт).
~cfg_mixer = (
    master:  0.9,                                    // мастер-уровень

    levels: (
        //            vol    send  (send из §K.1 tape reverb)
        monade:   ( vol: 0.85, send: 0.55 ),
        riss:     ( vol: 0.90, send: 0.30 ),
        flockung: ( vol: 0.80, send: 0.35 ),
        binde:    ( vol: 0.80, send: 0.45 ),
        schliere: ( vol: 0.85, send: 0.15 ),
        kratzer:  ( vol: 0.75, send: 0.15 ),
        zaesur:   ( vol: 0.00, send: 0.00 ),          // тишина — без уровня
        firnis:   ( vol: 0.70, send: 0.60 )
    )
);

// порядок слоёв = порядок обработки/итерации
~mixerLayers = [\monade, \riss, \flockung, \binde, \schliere, \kratzer, \zaesur, \firnis];
)


// ===== LOGIC — routers + master ======================================
(
// --- роутер на каждый слой: только сухой -> ~busDry -----------------
// (посылы в эффекты собирает один агрегатор ~busFxSend ниже — чтобы
//  send-шина имела РОВНО одного писателя через ReplaceOut и никогда не
//  накапливалась между блоками. Так порядок узлов не критичен.)
~mixerLayers.do { |layer|
    var routerKey = ("mix_" ++ layer).asSymbol;
    var lv = ~cfg_mixer.levels[layer];
    Ndef(routerKey, { |vol = 0|
        var src = Ndef(layer.asSymbol).ar(2);        // читаем сухой слой
        src * vol.lag(0.1)                            // сухой -> ~busDry
    });
    Ndef(routerKey).set(\vol, lv.vol);
    Ndef(routerKey).fadeTime = 1;
    Ndef(routerKey).play(out: ~busDry.index, numChannels: 2);
};

// --- агрегатор посылов: сумма всех слоёв × send -> ~busFxSend --------
// Единственный писатель send-шины. ReplaceOut => без накопления.
// send-доли хранятся как именованные controls \send_<layer>.
Ndef(\fxsend, {
    var sends = ~mixerLayers.collect { |layer|
        var amt = NamedControl.kr(("send_" ++ layer).asSymbol, 0);
        Ndef(layer.asSymbol).ar(2) * amt.lag(0.1);
    };
    ReplaceOut.ar(~busFxSend.index, Mix(sends));
});
~mixerLayers.do { |layer|
    Ndef(\fxsend).set(("send_" ++ layer).asSymbol, ~cfg_mixer.levels[layer].send);
};
Ndef(\fxsend).fadeTime = 1;
Ndef(\fxsend).play(out: ~busFxSend.index, numChannels: 2);

// --- мастер: сумма (сухой + возврат эффектов), LeakDC, Limiter ------
Ndef(\master, { |amp = 0.9|
    var dry, fx, sig;
    dry = In.ar(~busDry.index, 2);
    fx  = In.ar(~busFxReturn.index, 2);
    sig = dry + fx;
    sig = LeakDC.ar(sig);
    sig = Limiter.ar(sig, 0.95, 0.01);               // §K.4: limiter 0.95
    sig = sig * amp.lag(0.05);
    sig
});
Ndef(\master).set(\amp, ~cfg_mixer.master);
Ndef(\master).fadeTime = 1;
Ndef(\master).play(out: 0, numChannels: 2);          // в аппаратный выход

// --- удобный сеттер для живой правки / MIDI / sequencer -------------
// ~mixSet.(\monade, \vol, 0.5)  — громкость слоя в мастер
// ~mixSet.(\firnis, \send, 0.8) — посыл слоя в эффекты (агрегатор \fxsend)
~mixSet = { |layer, which = \vol, value|
    if(which == \send) {
        Ndef(\fxsend).set(("send_" ++ layer).asSymbol, value);
    } {
        Ndef(("mix_" ++ layer).asSymbol).set(\vol, value);
    };
    ~cfg_mixer.levels[layer][which] = value;
};
~masterSet = { |value| Ndef(\master).set(\amp, value); ~cfg_mixer.master = value; };

// --- solo / unsolo для отстройки одного слоя в полном тракте ---------
// ~mixSolo.(\monade)  — звучит только monade (через реверб + мастер);
//                       остальные слои глушатся (vol=0, send=0).
// ~mixUnsolo.value    — восстановить уровни/посылы всех слоёв из CONFIG.
// Уровни читаются из ~cfg_mixer (не перетираются нулями), поэтому возврат
// возвращает исходное сведение.
~mixSolo = { |layer|
    ~mixerLayers.do { |l|
        var on = (l == layer);
        var lv = ~cfg_mixer.levels[l];
        Ndef(("mix_" ++ l).asSymbol).set(\vol, on.if({ lv.vol }, 0));
        Ndef(\fxsend).set(("send_" ++ l).asSymbol, on.if({ lv.send }, 0));
    };
};
~mixUnsolo = {
    ~mixerLayers.do { |l|
        var lv = ~cfg_mixer.levels[l];
        Ndef(("mix_" ++ l).asSymbol).set(\vol, lv.vol);
        Ndef(\fxsend).set(("send_" ++ l).asSymbol, lv.send);
    };
};
)
