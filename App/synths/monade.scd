// =====================================================================
// App/synths/monade.scd
// UNGRUND · звуковой класс 1/8 — `monade` (sustained sine / Grund)
//
// СТАТУС: РЕАЛЬНЫЙ СЛОЙ (портирован из Tests/test_monade.scd).
//   Физическая модель «связка из 10 пружин в масле», адаптированная из
//   GUI-теста в Ndef-слой. Тоны заданы в MIDI-нотах (.midicps внутри).
//   Согласованная связка по умолчанию (композитор, 2026-05-22).
//
// ОТСТРОЙКА В APP (вместо отдельного теста — см. 0_lib.scd):
//   ~openTuner.(\monade)         — окно слайдеров по живому Ndef;
//   ~rndFreq.(\monade)           — рандом 10 тонов (группа \freq);
//   ~rndParams.(\monade)         — рандом параметров тембра (группа \tone);
//   ~savePreset.(\monade,"имя")  — сохранить пресет в App/presets/monade/;
//   ~loadPreset.(\monade,"имя")  — загрузить пресет обратно.
//
// СПЕЦИФИКАЦИЯ ~spec_monade — единый источник правды: из неё строятся
//   слайдеры, рандомайзеры и пресеты. Расширить управление = добавить
//   строку в ~spec_monade.params И соответствующий аргумент в Ndef.
//
// ИНТЕРФЕЙС Ndef(\monade):
//   — пишет стерео в свой выход (его читает 2_mixer.scd через Ndef-роутинг);
//   — посыл в эффекты выполняет МИКШЕР (через .send), а не сам слой.
//   — управляемые параметры (\set / LFO / MIDI / tuner): см. CONFIG ниже.
//
// Итерировать этот слой = править ~spec_monade и тело Ndef(\monade).
// =====================================================================


// ===== CONFIG — edit here ============================================
(
// Спецификация параметров. group \freq — тоны (рандом «частоты»);
// group \tone — тембр/среда (рандом «параметры»). spec задаёт диапазон,
// варп и ДЕФОЛТ (он же значение, применяемое при загрузке слоя).
~spec_monade = (
    name: \monade,
    params: [
        // --- группа \freq: 10 тонов пружин (MIDI-ноты, дробные = микротон) ---
        ( key: \n1,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 29.91) ),
        ( key: \n2,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 43.87) ),
        ( key: \n3,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 54.2)  ),
        ( key: \n4,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 18.97) ),
        ( key: \n5,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 27.2)  ),
        ( key: \n6,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 26.68) ),
        ( key: \n7,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 80.12) ),
        ( key: \n8,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 87.0)  ),
        ( key: \n9,  group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 58.14) ),
        ( key: \n10, group: \freq, disp: \note, spec: ControlSpec(12, 96, \lin, 0, 16.69) ),

        // --- группа \tone: тембр и среда ---
        // базовые (как раньше)
        ( key: \amp,       group: \tone,             spec: ControlSpec(0.0, 1.0,  \lin, 0, 0.22)  ),
        ( key: \density,   group: \tone, unit: " /s", spec: ControlSpec(0.2, 150,  \exp, 0, 8.65)  ),
        ( key: \contact,   group: \tone,             spec: ControlSpec(0.0, 1.0,  \lin, 0, 0.464) ),
        ( key: \decay,     group: \tone, unit: " s",  spec: ControlSpec(0.2, 8.0,  \exp, 0, 3.74)  ),
        ( key: \disperse,  group: \tone,             spec: ControlSpec(0.0, 1.0,  \lin, 0, 0.605) ),
        ( key: \oil,       group: \tone,             spec: ControlSpec(0.0, 1.0,  \lin, 0, 0.725) ),
        ( key: \muffle,    group: \tone,             spec: ControlSpec(0.0, 1.0,  \lin, 0, 0.204) ),
        // новые — вынесены из «магических чисел» DSP (architecture §A)
        ( key: \bright,    group: \tone, unit: " Hz", spec: ControlSpec(1500, 6000, \exp, 0, 2800) ),  // HPF сухого контакта
        ( key: \metalAmt,  group: \tone,             spec: ControlSpec(0.0, 0.6,  \lin, 0, 0.16)  ),  // уровень метал-звона
        ( key: \bodyLevel, group: \tone,             spec: ControlSpec(0.0, 0.2,  \lin, 0, 0.07)  ),  // гул массы связки
        ( key: \drive,     group: \tone,             spec: ControlSpec(0.5, 4.0,  \exp, 0, 1.2)   ),  // пред-усиление tanh
        ( key: \sprGain,   group: \tone,             spec: ControlSpec(1.0, 6.0,  \lin, 0, 3.4)   ),  // усиление суммы пружин
        ( key: \swayRate,  group: \tone, unit: " Hz", spec: ControlSpec(0.02, 0.5, \exp, 0, 0.1)   ),  // частота «вдоха/выдоха»
        ( key: \cutTop,    group: \tone, unit: " Hz", spec: ControlSpec(2000, 8000, \exp, 0, 5400) ),  // верх среза LPF
        ( key: \cutOil,    group: \tone, unit: " Hz", spec: ControlSpec(0, 5000,   \lin, 0, 3800)  )   // глубина затемнения oil
    ]
);


// ===== LOGIC — synthesis =============================================
Ndef(\monade, { |amp = 0.22, density = 8.65, contact = 0.464,
                 decay = 3.74, disperse = 0.605, oil = 0.725, muffle = 0.204,
                 bright = 2800, metalAmt = 0.16, bodyLevel = 0.07, drive = 1.2,
                 sprGain = 3.4, swayRate = 0.1, cutTop = 5400, cutOil = 3800,
                 n1 = 29.91, n2 = 43.87, n3 = 54.2, n4 = 18.97, n5 = 27.2,
                 n6 = 26.68, n7 = 80.12, n8 = 87.0, n9 = 58.14, n10 = 16.69|
    var decayL, oilL, dispL, muffL,
        sway, dens, contacts, ticks, metal, body, notes,
        springs, bundle, cutBase, sigL, sigR;
    var nSprings = 10;

    decayL = decay.lag(0.3).clip(0.1, 10);
    oilL   = oil.lag(0.3).clip(0, 1);
    dispL  = disperse.lag(0.3).clip(0, 1);
    muffL  = muffle.lag(0.3).clip(0, 1);

    sway = LFNoise2.kr(swayRate.clip(0.005, 2)).range(0.3, 1.0);

    dens     = (density.lag(0.2) * sway).clip(0.05, 400);
    contacts = Dust2.ar(dens);

    // сухой контакт — ЯРКИЙ: низкая обертоновая составляющая убрана
    ticks = Decay2.ar(contacts.abs, 0.0004, 0.006 + (oilL * 0.02));
    ticks = ticks * ((BrownNoise.ar * 0.7) + 0.5);
    ticks = HPF.ar(ticks, bright.lag(0.2).clip(500, 10000));
    metal = Mix(Ringz.ar(contacts,
                [3100, 4700, 6300] * LFNoise0.kr(9).range(0.96, 1.04),
                0.03)) * metalAmt.lag(0.2);
    ticks = (ticks + metal) * contact.lag(0.2);

    // тело — непрерывный низкий шум: масса связки в движении
    body = BrownNoise.ar(bodyLevel.lag(0.2)) * LFNoise2.kr(0.35).range(0.3, 1.0);

    // --- связка из 10 пружин: каждая на своём тоне (нота -> Гц) ---
    notes = [n1, n2, n3, n4, n5, n6, n7, n8, n9, n10];
    springs = Array.fill(nSprings, { |i|
        var sf, sd, collGain, ringGain, voice;
        sf       = notes[i].lag(0.2).midicps.clip(20, 2400);
        sd       = decayL * (0.7 + (i * 0.55 / nSprings));
        collGain = sf.linlin(110, 430, 0.08, 0.8);
        ringGain = sf.linexp(45, 700, 1.5, 0.65);
        voice = ((body) + (contacts * collGain))
                    * LFNoise2.kr(0.3 + (i * 0.05)).range(0.4, 1.0)
                    * 0.05 / sd.max(0.3);
        3.do { |k|
            var dt = LFNoise2.kr(0.2 + (i * 0.04) + (k * 0.07))
                .range(0.003, 0.003 + (dispL * 0.021));
            voice = AllpassC.ar(voice, 0.03, dt, 0.03 + (dispL * 0.07));
        };
        voice = CombC.ar(
            voice, 0.12,
            ((1 / sf) * (1 + LFNoise2.kr(0.13 + (i * 0.03))
                .range(oilL.neg * 0.01, oilL * 0.01))).clip(0.0004, 0.115),
            sd * (1 - (oilL * 0.55))
        );
        voice * ringGain
    });
    bundle = Mix(springs) * (1 / nSprings) * sprGain.lag(0.2);
    bundle = bundle + (ticks * 1.5);

    cutBase = (cutTop.lag(0.3) - (oilL * cutOil.lag(0.3))).clip(300, 9000);
    bundle  = LPF.ar(bundle, cutBase);
    bundle  = (bundle * drive.lag(0.2)).tanh;
    bundle  = LeakDC.ar(bundle);             // §DSP: после нелинейности

    sigL = LPF.ar(bundle, (cutBase * (1 - (muffL * 0.82))).clip(180, 9000));
    sigL = DelayC.ar(sigL, 0.05, muffL * 0.02);
    sigL = sigL * (1 - (muffL * 0.4));
    sigR = bundle;

    sigL = sigL * amp.lag(0.05) * (0.78 + (sway * 0.22));
    sigR = sigR * amp.lag(0.05) * (0.78 + (sway * 0.22));

    [sigL, sigR]
});

// ----- регистрация спецификации + применение дефолтов ---------------
// (самодостаточно: не зависит от 0_lib для применения; lib нужен лишь
//  для интерактивных рандома/пресетов/GUI после полной загрузки App.)
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\monade] = ~spec_monade;
~ungVals[\monade]  = ();
~spec_monade.params.do { |p|
    Ndef(\monade).set(p.key, p.spec.default);
    ~ungVals[\monade][p.key] = p.spec.default;
};
Ndef(\monade).fadeTime = 6;   // §0001: atk/rel framing ~6 s

("synths/monade — spec зарегистрирован ("
    ++ ~spec_monade.params.size ++ " параметров); ~openTuner.(\\monade)").postln;
)
