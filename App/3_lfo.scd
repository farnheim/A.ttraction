// =====================================================================
// App/3_lfo.scd
// UNGRUND · LFO — центральный реестр всей автоматизации параметров
//
// Здесь в ОДНОМ месте перечислены все автоматизируемые параметры. Каждая
// строка автоматизации задаёт: целевой слой, целевой параметр, форму
// (sine/tri/noise/noise0), частоту, и диапазон [min, max]. Движок ниже
// создаёт по одному kr-Ndef (LFO) на строку и маршрутизирует его выход
// на целевой параметр через Ndef(target).map(param, Ndef(lfoKey)).
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
        // alpha: очень медленное дыхание громкости (§C.1 «дышит»)
        ( target: \alpha,   param: \amp,    shape: \noise,  rate: 0.03, min: 0.16, max: 0.24 ),

        // delta: медленный дрейф добротности (внутреннее биение, §C.4)
        ( target: \delta,    param: \rq,     shape: \sine,   rate: 0.05, min: 0.015, max: 0.03 ),

        // epsilon: дрейф верхней точки развёртки гребёнки (§C.5)
        ( target: \epsilon, param: \freqHi, shape: \noise,  rate: 0.012, min: 600, max: 1000 ),

        // theta: медленный дрейф частоты AM (сцинтилляция, §C.8)
        ( target: \theta,   param: \lfnRate, shape: \tri,   rate: 0.02, min: 0.08, max: 0.16 ),

        // микшер: медленное дыхание посыла theta в реверб (глазурь дышит)
        // цель — агрегатор посылов \fxsend, его именованный control \send_theta
        ( target: \fxsend, param: \send_theta, shape: \sine, rate: 0.025, min: 0.45, max: 0.70 )
    ]
);


// ===== LOGIC — automation engine =====================================
// Идемпотентность при перезагрузке файла: чистим ПРОШЛЫЙ прогон по
// собственному реестру ~lfoActive (key/target/param на строку).
// ВАЖНО: Ndef.all — словарь «имя сервера -> ProxySpace», его ключи — имена
// СЕРВЕРОВ, а не ключи прокси; перебирать их в поисках "lfo_*" бесполезно.
// Строки, чей ключ есть и в новом конфиге, НЕ трогаем — их перезапишет
// Ndef ниже без разрыва маппинга (звук не прерывается). Снимаем только
// исчезнувшие/перенумерованные: unmap цели + clear kr-прокси (именно в
// этом порядке: clear до unmap оставил бы цель замапленной на чужую шину).
~lfoNewKeys = ~cfg_lfo.lines.collect { |line, i|
    ("lfo_" ++ i ++ "_" ++ line.target ++ "_" ++ line.param).asSymbol;
};
(~lfoActive ? []).do { |e|
    if(~lfoNewKeys.includes(e[\key]).not) {
        Ndef(e[\target]).unmap(e[\param]);
        Ndef(e[\key]).clear;
    };
};

~lfoKeys   = [];   // публичный реестр ключей (его читают 5_control и 7_viz)
~lfoActive = [];   // key/target/param текущего прогона (для очистки выше)

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

    // маршрутизация LFO -> целевой параметр.
    // .map (а НЕ .set): control-rate прокси маппится через control-шину;
    // .set принимает только скаляры -> "can't set a control to a UGen".
    Ndef(line.target.asSymbol).map(line.param, Ndef(lfoKey));

    ~lfoKeys   = ~lfoKeys.add(lfoKey);
    ~lfoActive = ~lfoActive.add((
        key: lfoKey, target: line.target.asSymbol, param: line.param.asSymbol
    ));
};

("3_lfo — активно строк автоматизации: " ++ ~lfoKeys.size).postln;
)
