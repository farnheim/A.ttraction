// =====================================================================
// App/3_lfo.scd
// UNGRUND · LFO — центральный реестр всей автоматизации параметров
//
// Здесь в ОДНОМ месте перечислены все автоматизируемые параметры. Каждая
// строка автоматизации задаёт: целевой слой, целевой параметр, форму
// (sine/tri/noise/noise0), частоту, и диапазон [min, max]. Движок ниже
// создаёт по одному kr-Ndef (LFO) на строку и маршрутизирует его выход
// на целевой параметр через Ndef(target).set(param, Ndef(lfoKey).kr).
//
// Добавить автоматизацию = добавить строку в ~cfg_lfo.lines. Никакой
// логики править не нужно.
//
// Все формы — МЕДЛЕННЫЙ дрейф (UNGRUND: движение должно быть дрейфом, не
// периодом, который ловит ухо). Выход сглажен .lag в самих слоях.
//
// Зависимости: синт-слои (целевые Ndef уже определены). Загружать ПОСЛЕ
//   синтов и микшера, ДО секвенсора (см. 1_app.scd).
// =====================================================================


// ===== CONFIG — edit here ============================================
(
// Каждая строка: ( target: \layer, param: \name, shape: \sine|\tri|\noise|\noise0,
//                   rate: Hz, min: lo, max: hi )
// target может быть и микшером: \mix_<layer> param \vol, либо агрегатор
// посылов \fxsend param \send_<layer> (см. 2_mixer.scd).
~cfg_lfo = (
    lines: [
        // monade: очень медленное дыхание громкости (§C.1 «дышит»)
        ( target: \monade,   param: \amp,    shape: \noise,  rate: 0.03, min: 0.16, max: 0.24 ),

        // binde: медленный дрейф добротности (внутреннее биение, §C.4)
        ( target: \binde,    param: \rq,     shape: \sine,   rate: 0.05, min: 0.015, max: 0.03 ),

        // schliere: дрейф верхней точки развёртки гребёнки (§C.5)
        ( target: \schliere, param: \freqHi, shape: \noise,  rate: 0.012, min: 600, max: 1000 ),

        // firnis: медленный дрейф частоты AM (сцинтилляция, §C.8)
        ( target: \firnis,   param: \lfnRate, shape: \tri,   rate: 0.02, min: 0.08, max: 0.16 ),

        // микшер: медленное дыхание посыла firnis в реверб (глазурь дышит)
        // цель — агрегатор посылов \fxsend, его именованный control \send_firnis
        ( target: \fxsend, param: \send_firnis, shape: \sine, rate: 0.025, min: 0.45, max: 0.70 )
    ]
);
)


// ===== LOGIC — automation engine =====================================
(
// чистим прежние LFO-Ndef'ы (идемпотентность при перезагрузке файла)
Ndef.all.keys.do { |k|
    if(k.asString.beginsWith("lfo_")) { Ndef(k).clear };
};

~lfoKeys = [];   // реестр созданных ключей (для очистки/инспекции)

~cfg_lfo.lines.do { |line, i|
    var lfoKey = ("lfo_" ++ i ++ "_" ++ line.target ++ "_" ++ line.param).asSymbol;
    var shape  = line.shape;
    var lo = line.min, hi = line.max;

    // kr-прокси: одна медленная форма, отмасштабированная в [min, max]
    Ndef(lfoKey, { |rate = 0.05|
        var osc = switch(shape,
            \sine,   { SinOsc.kr(rate) },
            \tri,    { LFTri.kr(rate) },
            \noise,  { LFNoise2.kr(rate) },     // плавный дрейф
            \noise0, { LFNoise0.kr(rate) },     // ступенчатый
            { LFNoise2.kr(rate) }               // по умолчанию — дрейф
        );
        osc.range(lo, hi)
    });
    Ndef(lfoKey).set(\rate, line.rate);

    // маршрутизация LFO -> целевой параметр
    Ndef(line.target.asSymbol).set(line.param, Ndef(lfoKey).kr(1));

    ~lfoKeys = ~lfoKeys.add(lfoKey);
};

("3_lfo — активно строк автоматизации: " ++ ~lfoKeys.size).postln;
)
