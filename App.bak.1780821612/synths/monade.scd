// =====================================================================
// App/synths/monade.scd
// UNGRUND · звуковой класс 1/8 — `monade` (sustained sine / Grund)
//
// СТАТУС: РЕАЛЬНЫЙ СЛОЙ (портирован из Tests/test_monade.scd).
//   Физическая модель «связка из 10 пружин в масле», адаптированная из
//   GUI-теста в Ndef-слой. Тоны заданы в MIDI-нотах (.midicps внутри).
//   Согласованная связка по умолчанию (композитор, 2026-05-22).
//
// ИНТЕРФЕЙС Ndef(\monade):
//   — пишет стерео в свой выход (его читает 2_mixer.scd через Ndef-роутинг);
//   — посыл в эффекты выполняет МИКШЕР (через .send), а не сам слой.
//   — управляемые параметры (\set / LFO / MIDI): см. CONFIG ниже.
//
// Итерировать этот слой = править CONFIG ниже и тело Ndef(\monade).
// =====================================================================


// ===== CONFIG — edit here ============================================
(
~cfg_monade = (
    // 10 тонов пружин в MIDI-нотах (дробные = микротоны).
    notes:    [29.91, 43.87, 54.2, 18.97, 27.2, 26.68, 80.12, 87.0, 58.14, 16.69],
    amp:      0.22,     // §K.4 gain staging: было 0.4, снижено под реверб
    density:  8.65,     // частота соприкосновений пружин, /s
    contact:  0.464,    // громкость сухих контактов
    decay:    3.74,     // время звона пружин, s
    disperse: 0.605,    // дисперсия — металлический «зуммер»
    oil:      0.725,    // вязкость среды
    muffle:   0.204     // приглушение левой стороны (дальний конец)
);
)


// ===== LOGIC — synthesis =============================================
(
Ndef(\monade, { |amp = 0.22, density = 8.65, contact = 0.464,
                 decay = 3.74, disperse = 0.605, oil = 0.725, muffle = 0.204,
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

    sway = LFNoise2.kr(0.1).range(0.3, 1.0);

    dens     = (density.lag(0.2) * sway).clip(0.05, 400);
    contacts = Dust2.ar(dens);

    // сухой контакт — ЯРКИЙ: низкая обертоновая составляющая убрана
    ticks = Decay2.ar(contacts.abs, 0.0004, 0.006 + (oilL * 0.02));
    ticks = ticks * ((BrownNoise.ar * 0.7) + 0.5);
    ticks = HPF.ar(ticks, 2800);
    metal = Mix(Ringz.ar(contacts,
                [3100, 4700, 6300] * LFNoise0.kr(9).range(0.96, 1.04),
                0.03)) * 0.16;
    ticks = (ticks + metal) * contact.lag(0.2);

    // тело — непрерывный низкий шум: масса связки в движении
    body = BrownNoise.ar(0.07) * LFNoise2.kr(0.35).range(0.3, 1.0);

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
    bundle = Mix(springs) * (1 / nSprings) * 3.4;
    bundle = bundle + (ticks * 1.5);

    cutBase = (5400 - (oilL * 3800)).clip(300, 6000);
    bundle  = LPF.ar(bundle, cutBase);
    bundle  = (bundle * 1.2).tanh;
    bundle  = LeakDC.ar(bundle);             // §DSP: после нелинейности

    sigL = LPF.ar(bundle, (cutBase * (1 - (muffL * 0.82))).clip(180, 6000));
    sigL = DelayC.ar(sigL, 0.05, muffL * 0.02);
    sigL = sigL * (1 - (muffL * 0.4));
    sigR = bundle;

    sigL = sigL * amp.lag(0.05) * (0.78 + (sway * 0.22));
    sigR = sigR * amp.lag(0.05) * (0.78 + (sway * 0.22));

    [sigL, sigR]
});

// применить CONFIG (распаковка notes -> n1..n10)
Ndef(\monade).set(
    \amp, ~cfg_monade.amp, \density, ~cfg_monade.density,
    \contact, ~cfg_monade.contact, \decay, ~cfg_monade.decay,
    \disperse, ~cfg_monade.disperse, \oil, ~cfg_monade.oil,
    \muffle, ~cfg_monade.muffle,
    \n1, ~cfg_monade.notes[0], \n2, ~cfg_monade.notes[1],
    \n3, ~cfg_monade.notes[2], \n4, ~cfg_monade.notes[3],
    \n5, ~cfg_monade.notes[4], \n6, ~cfg_monade.notes[5],
    \n7, ~cfg_monade.notes[6], \n8, ~cfg_monade.notes[7],
    \n9, ~cfg_monade.notes[8], \n10, ~cfg_monade.notes[9]
);
Ndef(\monade).fadeTime = 6;   // §0001: atk/rel framing ~6 s
)
