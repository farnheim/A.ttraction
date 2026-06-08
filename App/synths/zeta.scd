// =====================================================================
// App/synths/zeta.scd
// UNGRUND · звуковой класс 6/8 — `zeta` (dry granulated noise burst)
//
// СТАТУС: РЕАЛЬНЫЙ СЛОЙ с панелью управления (по образцу alpha).
//   Премиса §C.6: высокочастотное мягкое облако шумовых зёрен (зерно
//   2–40 мс, плотность ~40–80 /s), HPF выше ~5 кГц, плотность зёрен мягко
//   модулируется LFNoise2 — текстура без механического чоппинга. Мягкий
//   высокочастотный шорох, не жёсткое царапанье. Яркость хрупкая.
//
//   У шума нет «нот», поэтому роль ЧАСТОТНЫХ СОСТАВЛЯЮЩИХ (group \freq)
//   играют края фильтра (hpf/lpf) и расстроенный резонансный банк r1..r5,
//   подкрашивающий облако. resAmt=низкий по умолчанию => чистый шум
//   (верность премисе); подняв resAmt, получаем тюнингованный шиммер.
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
//   — §C.6: reverb send держать НИЗКИМ (хрупкая яркость).
//
// Итерировать этот слой = править ~spec_zeta и тело Ndef(\zeta).
// =====================================================================


// ===== CONFIG — edit here ============================================
(
// Спецификация параметров. group \freq — частотные составляющие (рандом
// «частоты»); group \tone — текстура/среда (рандом «параметры»). spec
// задаёт диапазон, варп и ДЕФОЛТ (он же значение при загрузке слоя).
~spec_zeta = (
    name: \zeta,
    params: [
        // --- группа \freq: окно фильтра + резонансный банк облака ---
        ( key: \hpf, group: \freq, unit: " Hz", spec: ControlSpec(800,  14000, \exp, 0, 5000)  ),  // низ среза облака
        ( key: \lpf, group: \freq, unit: " Hz", spec: ControlSpec(4000, 20000, \exp, 0, 16000) ),  // потолок облака
        ( key: \r1,  group: \freq, unit: " Hz", spec: ControlSpec(2000, 16000, \exp, 0, 4200)  ),  // резонанс-шиммер 1
        ( key: \r2,  group: \freq, unit: " Hz", spec: ControlSpec(2000, 16000, \exp, 0, 6300)  ),  // резонанс-шиммер 2
        ( key: \r3,  group: \freq, unit: " Hz", spec: ControlSpec(2000, 16000, \exp, 0, 8400)  ),  // резонанс-шиммер 3
        ( key: \r4,  group: \freq, unit: " Hz", spec: ControlSpec(2000, 16000, \exp, 0, 10500) ),  // резонанс-шиммер 4
        ( key: \r5,  group: \freq, unit: " Hz", spec: ControlSpec(2000, 16000, \exp, 0, 12600) ),  // резонанс-шиммер 5

        // --- группа \tone: текстура и среда ---
        ( key: \amp,          group: \tone,             spec: ControlSpec(0.0,    0.5,  \lin, 0, 0.16)   ),
        ( key: \density,      group: \tone, unit: " /s", spec: ControlSpec(5,      160,  \exp, 0, 60)     ),  // плотность зёрен
        ( key: \grainDur,     group: \tone, unit: " s",  spec: ControlSpec(0.002,  0.04, \exp, 0, 0.012)  ),  // длительность зерна
        ( key: \grainAtk,     group: \tone, unit: " s",  spec: ControlSpec(0.0002, 0.01, \exp, 0, 0.0008) ),  // атака зерна (мягкость↔щелчок)
        ( key: \densModRate,  group: \tone, unit: " Hz", spec: ControlSpec(0.05,   12,   \exp, 0, 1.0)    ),  // частота дрейфа плотности
        ( key: \densModDepth, group: \tone,             spec: ControlSpec(0.0,    1.0,  \lin, 0, 0.5)    ),  // глубина дрейфа плотности
        ( key: \panWidth,     group: \tone,             spec: ControlSpec(0.0,    0.4,  \lin, 0, 0.4)    ),  // §F: pan ≤ ±0.4
        ( key: \panRate,      group: \tone, unit: " Hz", spec: ControlSpec(0.1,    16,   \exp, 0, 4.0)    ),  // частота панорамы
        ( key: \resAmt,       group: \tone,             spec: ControlSpec(0.0,    1.0,  \lin, 0, 0.2)    ),  // сухой шум ↔ тюнингованный шиммер
        ( key: \resRing,      group: \tone, unit: " s",  spec: ControlSpec(0.005,  0.08, \exp, 0, 0.02)   ),  // время звона резонансов
        ( key: \spread,       group: \tone,             spec: ControlSpec(0.0,    1.0,  \lin, 0, 0.4)    ),  // расстройка банка (ширина)
        ( key: \bite,         group: \tone,             spec: ControlSpec(0.0,    1.0,  \lin, 0, 0.25)   )   // жёсткость транзиента (царапина)
    ]
);


// ===== LOGIC — synthesis =============================================
Ndef(\zeta, { |amp = 0.16, density = 60, grainDur = 0.012, grainAtk = 0.0008,
                  densModRate = 1, densModDepth = 0.5,
                  panWidth = 0.4, panRate = 4,
                  resAmt = 0.2, resRing = 0.02, spread = 0.4, bite = 0.25,
                  hpf = 5000, lpf = 16000,
                  r1 = 4200, r2 = 6300, r3 = 8400, r4 = 10500, r5 = 12600|
    var densMod, trig, grainEnv, src, dry, bands, shimmer, biteSig, sig, pan;
    var nBands = 5;

    // плотность зёрен, мягко модулированная (без механического чоппинга)
    densMod = LFNoise2.kr(densModRate.clip(0.05, 12))
                .range(1 - densModDepth.clip(0, 1), 1.0);
    trig    = Dust.ar((density.lag(0.3) * densMod).clip(2, 200));

    // зерно = короткая шумовая вспышка с перкуссионной огибающей;
    // grainAtk правит мягкость атаки (малый = щелчок, больший = пуф)
    grainEnv = Decay2.ar(trig, grainAtk.clip(0.0002, 0.01), grainDur.clip(0.002, 0.04));
    src      = WhiteNoise.ar;
    dry      = grainEnv * src;

    // резонансный банк: расстроенный (spread) шиммер, подкрашивающий облако.
    // resAmt=0 -> чистый шум (верность премисе §C.6 по умолчанию).
    bands  = [r1, r2, r3, r4, r5].collect { |f, i|
        (f.lag(0.3) * LFNoise1.kr(0.2 + (i * 0.05))
            .range(1 - (spread * 0.03), 1 + (spread * 0.03))).clip(1000, 18000)
    };
    shimmer = Mix(Ringz.ar(dry, bands, resRing.clip(0.005, 0.08))) * (1 / nBands);
    sig     = (dry * (1 - (resAmt.lag(0.2) * 0.6))) + (shimmer * resAmt.lag(0.2));

    // bite — короткий жёсткий транзиент (даёт «kratz»-царапину, упр-мый)
    biteSig = Decay2.ar(trig, 0.0002, 0.002) * WhiteNoise.ar;
    biteSig = BPF.ar(biteSig, (lpf.lag(0.3) * 0.8).clip(2000, 16000), 0.6);
    sig     = sig + (biteSig * bite.clip(0, 1) * 0.6);

    // окно фильтра: хрупкая высокочастотная яркость
    sig = HPF.ar(sig, hpf.lag(0.3).clip(800, 16000));
    sig = LPF.ar(sig, lpf.lag(0.3).clip(3000, 20000));

    // §F: панорама в пределах ±0.4, медленно дышит
    pan = LFNoise1.kr(panRate.clip(0.1, 16)).range(panWidth.neg, panWidth);
    sig = Pan2.ar(sig, pan);

    sig = sig * amp.lag(0.05);
    sig = LeakDC.ar(sig);
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
Ndef(\zeta).fadeTime = 0.5;   // быстрая текстура — короткий fade

("synths/zeta — spec зарегистрирован ("
    ++ ~spec_zeta.params.size ++ " параметров); ~openTuner.(\\zeta)").postln;
)
