// =====================================================================
// App/synths/zeta.scd
// UNGRUND · звуковой класс 6/8 — `zeta` (vinyl/tape surface noise)
//
// СТАТУС: РЕАЛЬНЫЙ СЛОЙ с панелью управления (по образцу alpha).
//   Премиса §C.6 (редизайн под Texture.wav): тихая «поверхность» —
//   шум изношенного винила / старой ленты. Два страта:
//     1) БЭД — непрерывный тихий окрашенный шум, mid-наклон, горб
//        энергии ~1.2 кГц (полоса ~200 Гц..7 кГц, мягкие склоны),
//        очень медленный «wow»-дрейф амплитуды/окраски, без чоппинга;
//     2) ТРЕСК — импульсные транзиенты с широким динамическим разбросом:
//        • мелкий «жарящийся» треск (плотный Dust ~40/с, крошечная
//          ЭКСПОНЕНЦИАЛЬНАЯ амплитуда, HF-наклон);
//        • редкие щелчки/поп (~2.5/с, экспон. амплитуда вплоть до пика,
//          широкополосные + низкое резонансное «тело»-thock на самых
//          громких). Крест-фактор высокий: тихий бэд ↔ громкие поп.
//   Потолок спектра жёсткий ~7 кГц — НЕ ярко, без воздуха выше 12 кГц.
//   Опц. саб-рокот <150 Гц («мотор/тонарм») держим ≥15 дБ под горбом.
//
//   У шума нет «нот», поэтому роль ЧАСТОТНЫХ СОСТАВЛЯЮЩИХ (group \freq)
//   играют края/центр полосы бэда (bedHpf/bedLpf/bedHumpFreq), HF-наклоны
//   треска (fineHpf/popHpf), частота тела поп (bodyFreq) и саб (subFreq).
//
// ОТСТРОЙКА В APP (механизм в 0_lib.scd):
//   ~openTuner.(\zeta)         — окно слайдеров по живому Ndef;
//   ~rndFreq.(\zeta)           — рандом частотных составляющих (\freq);
//   ~rndParams.(\zeta)         — рандом параметров текстуры (\tone);
//   ~savePreset.(\zeta,"имя")  — сохранить пресет в App/presets/zeta/;
//   ~loadPreset.(\zeta,"имя")  — загрузить пресет обратно.
//
// СПЕЦИФИКАЦИЯ ~spec_zeta — единый источник правды: из неё строятся
//   слайдеры, рандомайзеры и пресеты. Расширить управление = добавить
//   строку в ~spec_zeta.params И соответствующий аргумент в Ndef.
//
// ИНТЕРФЕЙС Ndef(\zeta):
//   — пишет стерео в свой выход (его читает 2_mixer.scd через Ndef-роутинг);
//   — посыл в эффекты выполняет МИКШЕР (через .send), а не сам слой;
//   — reverb send держать НИЗКИМ (сухая «поверхность», не зал).
//
// Итерировать этот слой = править ~spec_zeta и тело Ndef(\zeta).
// =====================================================================


// ===== CONFIG — edit here ============================================
(
// Спецификация параметров. group \freq — частотные составляющие (рандом
// «частоты»); group \tone — текстура/среда (рандом «параметры»). spec
// задаёт диапазон, варп и ДЕФОЛТ (он же значение при загрузке слоя).
// disp: \hz — у шума нет «нот», но рядом со слайдером показываем
//   ближайшую ноту+центы (Гц -> .cpsmidi), как тоны alpha.
~spec_zeta = (
    name: \zeta,
    params: [
        // --- группа \freq: частотные составляющие текстуры ---
        ( key: \bedHpf,      group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(80,    600,   \exp, 0, 270)    ),  // низ полосы бэда
        ( key: \bedLpf,      group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(3000,  12000, \exp, 0, 11000)  ),  // потолок бэда (непрерывный HF-хисс ленты)
        ( key: \bedHumpFreq, group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(600,   2500,  \exp, 0, 1200)   ),  // центроид энергии ~1.2k
        ( key: \subFreq,     group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(40,    200,   \exp, 0, 120)    ),  // потолок саб-рокота
        ( key: \fineHpf,     group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(1500,  8000,  \exp, 0, 2000)   ),  // HF-наклон мелкого треска
        ( key: \popHpf,      group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(500,   6000,  \exp, 0, 1500)   ),  // HF-наклон щелчков
        ( key: \bodyFreq,    group: \freq, unit: " Hz", disp: \hz, spec: ControlSpec(80,    600,   \exp, 0, 180)    ),  // частота "thock"-тела поп

        // --- группа \tone: текстура, плотность, динамика, среда ---
        ( key: \amp,          group: \tone,             spec: ControlSpec(0.0,    0.5,   \lin, 0, 0.32)   ),  // мастер-уровень слоя
        ( key: \bedAmp,       group: \tone,             spec: ControlSpec(0.0,    1.0,   \lin, 0, 0.6)    ),  // уровень бэда (тихая «поверхность» под щелчками)
        ( key: \bedHumpRq,    group: \tone,             spec: ControlSpec(0.2,    1.5,   \lin, 0, 0.6)    ),  // ширина горба (rq)
        ( key: \bedHumpAmt,   group: \tone,             spec: ControlSpec(0.0,    1.0,   \lin, 0, 0.55)   ),  // выраженность горба (равная подмешка, не душит HF)
        ( key: \bedDriftRate, group: \tone, unit: " Hz", spec: ControlSpec(0.02,   2.0,   \exp, 0, 0.1)    ),  // скорость "wow"-дрейфа
        ( key: \bedDriftDepth,group: \tone,             spec: ControlSpec(0.0,    0.8,   \lin, 0, 0.25)   ),  // глубина дрейфа
        ( key: \subAmt,       group: \tone,             spec: ControlSpec(0.0,    0.3,   \lin, 0, 0.0)    ),  // саб-рокот (источник: 20–80 Гц — слабейшая полоса)
        ( key: \fineRate,     group: \tone, unit: " /s", spec: ControlSpec(5,      120,   \exp, 0, 45)     ),  // плотность мелкого треска
        ( key: \fineDecay,    group: \tone, unit: " s",  spec: ControlSpec(0.0003, 0.005, \exp, 0, 0.0015) ),  // распад тика
        ( key: \fineAmpMin,   group: \tone,             spec: ControlSpec(0.005,  0.3,   \exp, 0, 0.04)   ),  // нижний край эксп. распределения тиков
        ( key: \fineAmt,      group: \tone,             spec: ControlSpec(0.0,    1.0,   \lin, 0, 0.48)   ),  // уровень мелкого треска (HF-окрас)
        ( key: \popRate,      group: \tone, unit: " /s", spec: ControlSpec(0.2,    8.0,   \exp, 0, 2.4)    ),  // плотность поп
        ( key: \popDecay,     group: \tone, unit: " s",  spec: ControlSpec(0.002,  0.03,  \exp, 0, 0.006)  ),  // распад щелчка
        ( key: \popAmpMin,    group: \tone,             spec: ControlSpec(0.01,   0.5,   \exp, 0, 0.14)   ),  // нижний край эксп. распределения поп (стабильный крест)
        ( key: \popAmt,       group: \tone,             spec: ControlSpec(0.0,    1.0,   \lin, 0, 0.85)   ),  // уровень поп
        ( key: \bodyAmt,      group: \tone,             spec: ControlSpec(0.0,    1.0,   \lin, 0, 0.4)    ),  // выраженность "thock"-тела
        ( key: \bodyRing,     group: \tone, unit: " s",  spec: ControlSpec(0.005,  0.12,  \exp, 0, 0.04)   ),  // время звона тела
        ( key: \panWidth,     group: \tone,             spec: ControlSpec(0.0,    0.4,   \lin, 0, 0.3)    ),  // §F: pan ≤ ±0.4
        ( key: \panRate,      group: \tone, unit: " Hz", spec: ControlSpec(0.02,   2.0,   \exp, 0, 0.15)   )   // §F: медленная панорама
    ]
);


// ===== LOGIC — synthesis =============================================
// Пять под-блоков: бэд + саб + мелкий треск + поп, сумма в моно, Pan2,
// LeakDC, мастер-амплитуда, мягкий лимитер. Все импульсы живут ВНУТРИ
// персистентного графа Ndef (Dust2/Decay2) — никаких per-event Synth.
Ndef(\zeta, { |amp = 0.32,
    bedHpf = 270, bedLpf = 11000, bedHumpFreq = 1200, bedHumpRq = 0.6, bedHumpAmt = 0.55,
    bedAmp = 0.6, bedDriftRate = 0.1, bedDriftDepth = 0.25,
    subFreq = 120, subAmt = 0.0,
    fineHpf = 2000, fineRate = 45, fineDecay = 0.0015, fineAmpMin = 0.04, fineAmt = 0.48,
    popHpf = 1500, popRate = 2.4, popDecay = 0.006, popAmpMin = 0.14, popAmt = 0.85,
    bodyFreq = 180, bodyAmt = 0.4, bodyRing = 0.04,
    panWidth = 0.3, panRate = 0.15|

    var nyq, bed, bedFlat, bedHump, drift, sub;
    var fineTrig, fineLvl, fine, fineEnv;
    var popTrig, popLvl, click, body, bodyGain, pops;
    var sig, pan;

    nyq = SampleRate.ir * 0.45;

    // --- Block 1: бэд — непрерывный mid-наклонный окрашенный шум ----
    // PinkNoise (≈ -6 dB/oct склоны), полоса + широкий резонансный горб.
    bedFlat = PinkNoise.ar;
    bedFlat = HPF.ar(bedFlat, bedHpf.lag(0.2).clip(20, nyq));
    bedFlat = LPF.ar(bedFlat, bedLpf.lag(0.2).clip(1000, nyq));
    bedHump = Resonz.ar(bedFlat, bedHumpFreq.lag(0.2).clip(100, nyq), bedHumpRq.clip(0.2, 1.5));
    // XFade2: amt=0 -> чистая полоса, amt=1 -> явный (но не пиковый) горб
    bed = XFade2.ar(bedFlat, bedHump, (bedHumpAmt.lag(0.1).clip(0, 1) * 2) - 1);
    // медленный "wow"-дрейф амплитуды (гладкий LFNoise2, без чоппинга)
    drift = LFNoise2.kr(bedDriftRate.lag(0.2).clip(0.02, 2))
                .range(1 - bedDriftDepth.clip(0, 0.8), 1.0);
    bed = bed * drift * bedAmp.lag(0.1);

    // --- Block 2: саб-рокот — очень низкий, очень тихий ------------
    // «мотор/тонарм»-пол: BrownNoise через LPF, держим ≥15 дБ под горбом.
    sub = BrownNoise.ar;
    sub = LPF.ar(sub, subFreq.lag(0.2).clip(40, nyq));
    sub = sub * subAmt.lag(0.1);

    // --- Block 3: мелкий треск — «жарящаяся» текстура --------------
    // плотный Dust2, ЭКСПОНЕНЦИАЛЬНАЯ амплитуда (много мелких/мало крупных),
    // очень короткий распад, HF-наклон -> читается как тики, не удары.
    fineTrig = Dust2.ar(fineRate.lag(0.3).clip(0.2, 200));
    fineLvl  = TExpRand.ar(fineAmpMin.clip(0.005, 0.3), 1.0, fineTrig);
    fineEnv  = Decay2.ar(fineTrig * fineLvl, 0.0002, fineDecay.clip(0.0003, 0.005));
    fine     = fineEnv * WhiteNoise.ar;
    fine     = HPF.ar(fine, fineHpf.lag(0.2).clip(500, nyq));
    fine     = fine * fineAmt.lag(0.1);

    // --- Block 4: поп — редкие, экспон. до почти-пика, с «thock» ---
    popTrig  = Dust2.ar(popRate.lag(0.3).clip(0.2, 8));
    popLvl   = TExpRand.ar(popAmpMin.clip(0.01, 0.5), 1.0, popTrig);
    // тело щелчка: широкополосный, слегка HF-наклонён
    click    = Decay2.ar(popTrig * popLvl, 0.0003, popDecay.clip(0.002, 0.03)) * WhiteNoise.ar;
    click    = HPF.ar(click, popHpf.lag(0.2).clip(200, nyq));
    // резонансное «тело»-thock только на самых громких поп (gate popLvl^2)
    bodyGain = bodyAmt.lag(0.1).clip(0, 1) * popLvl.squared;
    body     = Ringz.ar(Decay.ar(popTrig * popLvl, 0.001),
                        bodyFreq.lag(0.2).clip(40, nyq),
                        bodyRing.clip(0.005, 0.12)) * bodyGain;
    pops     = (click + body) * popAmt.lag(0.1);

    // --- Block 5: сумма, панорама, кондиционирование ---------------
    sig = bed + sub + fine + pops;

    // §F: панорама в пределах ±0.4, медленно
    pan = LFNoise1.kr(panRate.lag(0.2).clip(0.02, 2)).range(panWidth.neg, panWidth.clip(0, 0.4));
    sig = Pan2.ar(sig, pan);

    sig = sig * amp.lag(0.05);
    sig = LeakDC.ar(sig);                 // после суммы + импульсного контента
    sig = Limiter.ar(sig, 0.95);          // страховка: редкое совпадение поп+тик
    sig
});

// ----- регистрация спецификации + применение дефолтов ---------------
// (самодостаточно: не зависит от 0_lib для применения; lib нужен лишь
//  для интерактивных рандома/пресетов/GUI после полной загрузки App.)
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\zeta] = ~spec_zeta;
~ungVals[\zeta]  = ();
~spec_zeta.params.do { |p|
    Ndef(\zeta).set(p.key, p.spec.default);
    ~ungVals[\zeta][p.key] = p.spec.default;
};
Ndef(\zeta).fadeTime = 0.5;   // непрерывная среда — мягкий fade

("synths/zeta — spec зарегистрирован ("
    ++ ~spec_zeta.params.size ++ " параметров); ~openTuner.(\\zeta)").postln;
)
