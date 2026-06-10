// =====================================================================
// App/synths/delta.scd
// UNGRUND · звуковой класс 4/8 — `delta` (formant-cluster wind / metal plates)
//
// СТАТУС: РЕАЛЬНЫЙ СЛОЙ (переписан из заглушки по docs/task.md, 2026-06-10).
//   Премиса §C.4 (`binde`), РАСШИРЕННАЯ: 5 независимых потоков ветра, каждый
//   возбуждает массивную металлическую пластину (Ringz-банк, «угол к потоку»),
//   поверх — формантный «человеческий» банк (3-формантный BPF на гласную) со
//   своим тоном и высотой от 3-limit решётки 94 Гц. Сохранены запреты §C.4:
//   нет глайда центральной высоты, модуляция идентичности полосы ≤ 0.25 Hz.
//   Премиса помечена как РАСШИРЕНИЕ §C.4 (см. docs/task.md supersede flag).
//
// ОТСТРОЙКА В APP (см. 0_lib.scd):
//   ~openTuner.(\delta)         — окно слайдеров по живому Ndef;
//   ~rndFreq.(\delta)           — рандом 5 тонов голосов (группа \freq);
//   ~rndParams.(\delta)         — рандом параметров среды/тембра (группа \tone);
//   ~savePreset.(\delta,"имя")  — сохранить пресет в App/presets/delta/;
//   ~loadPreset.(\delta,"имя")  — загрузить пресет обратно.
//
// СПЕЦИФИКАЦИЯ ~spec_delta — единый источник правды: из неё строятся
//   слайдеры, рандомайзеры и пресеты. Расширить управление = добавить строку
//   в ~spec_delta.params И соответствующий аргумент в Ndef.
//
// ИНТЕРФЕЙС Ndef(\delta):
//   — пишет стерео в свой выход (его читает 2_mixer.scd через Ndef-роутинг);
//   — посыл в эффекты выполняет МИКШЕР (через .send), а не сам слой.
//
// Итерировать этот слой = править ~spec_delta и тело Ndef(\delta).
// =====================================================================


// ===== CONFIG — edit here ============================================
(
// Спецификация параметров. group \freq — 5 фундаментальных тонов голосов
// (рандом «частоты»); group \tone — ветер/пластины/гласные/пространство
// (рандом «параметры»). spec задаёт диапазон, варп и ДЕФОЛТ (он же значение,
// применяемое при загрузке слоя). disp: \note — ТОЛЬКО на \freq-строках.
// Дефолты тонов на 3-limit решётке от 94 Гц: 141/188/282/376/564 Hz.
~spec_delta = (
    name: \delta,
    params: [
        // --- группа \freq: 5 фундаментальных тонов голосов (MIDI-ноты) ---
        ( key: \f1, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 48.71) ),  // 141 Hz ×3/2  — низкая квинта (грудной)
        ( key: \f2, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 53.71) ),  // 188 Hz ×2    — октава (низкий)
        ( key: \f3, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 60.72) ),  // 282 Hz ×3    — октава+квинта (средний)
        ( key: \f4, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 65.71) ),  // 376 Hz ×4    — две октавы (верхн.-средн.)
        ( key: \f5, group: \freq, disp: \note, spec: ControlSpec(36, 84, \lin, 0, 72.72) ),  // 564 Hz ×6    — две октавы+квинта (высокий)

        // --- группа \tone: ветер ---
        ( key: \amp,        group: \tone,              spec: ControlSpec(0.0, 0.5, \lin, 0, 0.18)  ),  // мастер-уровень слоя (§K.4)
        ( key: \windForce,  group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.6)   ),  // сила потока (общий уровень шума)
        ( key: \turbulence, group: \tone,              spec: ControlSpec(0.0, 0.9, \lin, 0, 0.45)  ),  // глубина медленных порывов (≤0.25 Hz)
        ( key: \gustRate,   group: \tone, unit: " Hz",  spec: ControlSpec(0.02, 0.25, \exp, 0, 0.08) ),  // базовая частота порывов (§C.4 ≤0.25)
        ( key: \flutter,    group: \tone,              spec: ControlSpec(0.0, 0.3, \lin, 0, 0.12)  ),  // мелкое дрожание воздуха (быстрое, мелкое)
        ( key: \edge,       group: \tone,              spec: ControlSpec(0.0, 0.6, \lin, 0, 0.18)  ),  // свист кромки (угол к потоку)
        ( key: \edgeRatio,  group: \tone,              spec: ControlSpec(3.0, 12.0, \exp, 0, 7.0)  ),  // высота свиста = fund × edgeRatio (база)

        // --- группа \tone: металлические пластины ---
        ( key: \metal,      group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.55)  ),  // доля резонанса пластины vs сырой ветер
        ( key: \plateQ,     group: \tone,              spec: ControlSpec(0.05, 3.0, \exp, 0, 0.9)  ),  // время звона пластины (масса/толщина)
        ( key: \plateBright,group: \tone,              spec: ControlSpec(0.3, 2.0, \lin, 0, 1.0)   ),  // яркость возбуждения (угол к потоку)
        ( key: \plateSpread,group: \tone,              spec: ControlSpec(0.0, 0.05, \lin, 0, 0.015)),  // расстройка длин звона между голосами

        // --- группа \tone: формантный «человеческий» фильтр ---
        ( key: \vowelMix,   group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.7)   ),  // выраженность гласной (хоровое качество §C.4)
        ( key: \vowelSel,   group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.5)   ),  // сдвиг набора гласных по голосам (a-e-i-o-u)
        ( key: \formRq,     group: \tone,              spec: ControlSpec(0.03, 0.3, \exp, 0, 0.09)  ),  // ширина формант (узко=ярче гласная)
        ( key: \formScale,  group: \tone,              spec: ControlSpec(0.6, 1.6, \lin, 0, 1.0)   ),  // привязка высоты форманты к фундаменту голоса
        ( key: \beatRate,   group: \tone, unit: " Hz",  spec: ControlSpec(0.05, 0.25, \exp, 0, 0.15) ),  // §C.4 биение формант (≤0.25 Hz)

        // --- группа \tone: уровни и пространство ---
        ( key: \voiceLevel, group: \tone,              spec: ControlSpec(0.0, 1.0, \lin, 0, 0.7)   ),  // общий уровень суммы голосов (до master amp)
        ( key: \panWidth,   group: \tone,              spec: ControlSpec(0.0, 0.3, \lin, 0, 0.22)  ),  // §F: pan ≤ ±0.3 для binde
        ( key: \panRate,    group: \tone, unit: " Hz",  spec: ControlSpec(0.01, 0.5, \exp, 0, 0.06) )   // §F: медленный дрейф панорамы
    ]
);


// ===== LOGIC — synthesis =============================================
// 5 голосов: каждый = ветер (Stage A) → пластина-Ringz (Stage B) →
// формантный банк гласной (Stage C). Сумма → Splay → LeakDC → Limiter.
Ndef(\delta, { |amp = 0.18,
    f1 = 48.71, f2 = 53.71, f3 = 60.72, f4 = 65.71, f5 = 72.72,
    windForce = 0.6, turbulence = 0.45, gustRate = 0.08, flutter = 0.12,
    edge = 0.18, edgeRatio = 7.0,
    metal = 0.55, plateQ = 0.9, plateBright = 1.0, plateSpread = 0.015,
    vowelMix = 0.7, vowelSel = 0.5, formRq = 0.09, formScale = 1.0, beatRate = 0.15,
    voiceLevel = 0.7, panWidth = 0.22, panRate = 0.06|

    var nyq, funds, fundMid, nVoices = 5;
    var windForceL, turbL, gustRateL, flutterL, edgeL, edgeRatioL;
    var metalL, plateQL, plateBrightL, plateSpreadL;
    var vowelMixL, vowelSelL, formRqL, formScaleL, beatRateL;
    var voiceLevelL, panWidthL, panRateL;
    // инвариантные неангармонические шаблоны (idiophone-like, НЕ целочисленные)
    var plateRatios = #[1.0, 2.76, 5.40, 8.93, 13.34];
    var plateModAmps = #[0.55, 0.7, 0.6, 0.45, 0.3];
    // классические форманты гласных (3 нижних форманты, Hz): a e i o u
    var vowelTable = [
        [ 730, 1090, 2440 ],  // a
        [ 530, 1840, 2480 ],  // e
        [ 270, 2290, 3010 ],  // i
        [ 570,  840, 2410 ],  // o
        [ 300,  870, 2240 ]   // u
    ];
    var formGains = #[1.0, 0.95, 0.75];   // спад уровня по формантам (F2/F3 присутствуют)
    var voices, sig, fieldDrift;

    nyq = SampleRate.ir * 0.45;

    // --- лаги управляемых контролов ---
    windForceL   = windForce.lag(0.2).clip(0, 1);
    turbL        = turbulence.lag(0.2).clip(0, 0.9);
    gustRateL    = gustRate.clip(0.02, 0.25);
    flutterL     = flutter.lag(0.2).clip(0, 0.3);
    edgeL        = edge.lag(0.2).clip(0, 0.6);
    edgeRatioL   = edgeRatio.lag(0.2).clip(3, 12);
    metalL       = metal.lag(0.2).clip(0, 1);
    plateQL      = plateQ.lag(0.2).clip(0.05, 3.0);
    plateBrightL = plateBright.lag(0.2).clip(0.3, 2.0);
    plateSpreadL = plateSpread.lag(0.2).clip(0, 0.05);
    vowelMixL    = vowelMix.lag(0.2).clip(0, 1);
    vowelSelL    = vowelSel.lag(0.2).clip(0, 1);
    formRqL      = formRq.lag(0.2).clip(0.03, 0.3);
    formScaleL   = formScale.lag(0.2).clip(0.6, 1.6);
    beatRateL    = beatRate.clip(0.05, 0.25);
    voiceLevelL  = voiceLevel.lag(0.1).clip(0, 1);
    panWidthL    = panWidth.lag(0.2).clip(0, 0.3);
    panRateL     = panRate.clip(0.01, 0.5);

    // --- фундаменты голосов (MIDI → Hz, Nyquist-кламп после lag) ---
    funds   = [f1, f2, f3, f4, f5].collect { |n| n.lag(0.2).midicps.clip(40, nyq) };
    fundMid = funds[2];   // f3 как опорный регистр для масштаба формант

    voices = Array.fill(nVoices, { |i|
        var fund, wind, gust, flut, gustRi, edgeFreq, edgeWhistle;
        var plateFreqs, plateRings, plate, voiceSig;
        var vowelIdx, vowelLo, vowelHi, regScale, formant;
        var plateNorm;

        fund = funds[i];

        // ----- Stage A: поток ветра -----
        wind = PinkNoise.ar;
        // медленный порыв (≤0.25 Hz), несоизмеримая частота на голос
        gustRi = gustRateL * (0.7 + (i * 0.13));
        gust   = LFNoise2.kr(gustRi.clip(0.01, 0.25)).range(1 - turbL, 1.0);
        // мелкое быстрое дрожание воздуха (НЕ идентичность полосы, depth мал)
        flut   = LFNoise2.kr(2.5 + (i * 0.9)).range(1 - flutterL, 1.0);
        wind   = wind * windForceL * gust * flut;

        // свист кромки = угол к потоку: узкий Resonz на высокой гармонике
        edgeFreq    = (fund * edgeRatioL * (1 + (i * 0.08))).clip(40, nyq);
        edgeWhistle = Resonz.ar(PinkNoise.ar, edgeFreq, 0.03)
                        * gust * windForceL * edgeL * 6;
        wind = wind + edgeWhistle;

        // ----- Stage B: резонанс металлической пластины -----
        // неангармонический банк = «металл»; кламп ВСЕГО массива под Nyquist
        plateFreqs = (fund * plateRatios * (1 + ((i - 2) * plateBrightL * 0.04)))
                        .clip(40, nyq);
        // длины звона из plateQ, с расстройкой между голосами (углы)
        plateRings = plateQL * (1 + ((i - 2) * plateSpreadL))
                        * #[1.0, 0.85, 0.72, 0.6, 0.5];
        plateRings = plateRings.clip(0.02, 4.0);
        // Q-компенсация: нормировка по числу мод И по длине звона, чтобы
        // plateQ менял ТЕМБР, а не громкость
        plateNorm = (1 / plateRatios.size) / (1 + (plateQL * 0.7));
        plate = Mix(Ringz.ar(wind, plateFreqs, plateRings) * plateModAmps)
                    * plateNorm * 2.0;

        // смесь пластина vs сырой ветер
        voiceSig = XFade2.ar(wind * 0.9, plate, (metalL * 2) - 1);

        // ----- Stage C: формантный банк гласной -----
        // Базовая гласная голоса выбрана НА ЭТАПЕ СБОРКИ (голоса разнесены по
        // a-o-e-u-i: 0,3,1,4,2). vowelSel живо ИНТЕРПОЛИРУЕТ формантные частоты
        // от базовой гласной к следующей по кругу — плавный сдвиг набора без
        // индексации UGen'ом (он не может быть индексом массива).
        vowelIdx = #[0, 3, 1, 4, 2][i];          // build-time Integer
        vowelLo  = vowelTable.at(vowelIdx);
        vowelHi  = vowelTable.at((vowelIdx + 1) % 5);
        // регистровый масштаб: высокий голос → выше форманты (ребёнок/женщина)
        regScale = (fund / fundMid).clip(0.7, 1.6) * formScaleL;
        // 3 параллельных BPF + независимое медленное биение на каждую (§C.4).
        // Каждая форманта: linlin по vowelSel между Lo и Hi, потом регистр+кламп.
        formant = Mix(Array.fill(3, { |k|
            var ffLo  = vowelLo[k];
            var ffHi  = vowelHi[k];
            var ff    = (vowelSelL.linlin(0, 1, ffLo, ffHi) * regScale).clip(40, nyq);
            var beat  = LFNoise2.kr(beatRateL * (0.6 + (k * 0.3) + (i * 0.07)))
                        .range(0.4, 1.0);
            // форманты возбуждаются ШИРОКОПОЛОСНЫМ ветром (а не уже
            // подрезанным плато-голосом) — иначе в зоне гласной нет энергии.
            BPF.ar(voiceSig + (wind * 1.1), ff, formRqL) * formGains[k] * beat;
        }));
        // Q-компенсация форманта: нормировка по числу формант и по узости rq
        formant = formant * (1 / formGains.size) * (formRqL / 0.09).sqrt * 13.0;

        // смесь формантный голос vs неформантный (хоровое качество §C.4)
        voiceSig = XFade2.ar(voiceSig, formant, (vowelMixL * 2) - 1);

        // пер-голосный трим: высокие голоса чуть тише (баланс кластера)
        voiceSig * (1 - (i * 0.07));
    });

    // --- сумма голосов, пер-голосный трим 1/5, voiceLevel ---
    // Splay: 5-канальный массив → стерео; spread даёт ровный кластер.
    // Несоизмеримый медленный пан-дрейф на голос внутри ±panWidth.
    voices = voices.collect { |v, i|
        var pan = LFNoise1.kr(panRateL * (0.5 + (i * 0.21)))
                    .range(panWidthL.neg, panWidthL);
        Pan2.ar(v, pan);
    };
    // голоса частично декоррелированы → сумма растёт как ~√N, нормируем по √N,
    // чтобы число голосов не качало громкость, но и не «съедало» её делением на N
    sig = Mix(voices) * (1 / nVoices.sqrt) * voiceLevelL;

    // очень медленный дрейф всего поля внутри ±0.3 (§F)
    fieldDrift = LFNoise1.kr(0.03).range(-0.12, 0.12);
    sig = Balance2.ar(sig[0], sig[1], fieldDrift);

    // --- внутренний makeup-гейн ---
    // компенсирует каскад нормировок (plateNorm, 1/3 формант, √N голосов).
    // Сидит ПЕРЕД master amp, чтобы amp оставался уровнем слоя §K.4 (0.18).
    sig = sig * 3.3;

    // §C.4 регистр 100 Hz – 6 kHz: подрезаем sub ниже нижнего фундамента (141 Hz),
    // чтобы остаточный низ Ringz-банка не выходил за регистр binde. Три каскадных
    // HPF = ~36 dB/oct, держит полосу 20–80 Hz слабой.
    sig = HPF.ar(HPF.ar(HPF.ar(sig, 125), 125), 125);

    // --- master amp, кондиционирование, кирпич ---
    sig = sig * amp.lag(0.05);
    sig = LeakDC.ar(sig);                 // §DSP: после суммы + высокодобротный контент
    sig = Limiter.ar(sig, 0.95);          // §DSP: гарантия ±1.0 при рандоме высокого Q
    sig
});

// ----- регистрация спецификации + применение дефолтов ---------------
// (самодостаточно: не зависит от 0_lib для применения; lib нужен лишь для
//  интерактивных рандома/пресетов/GUI после полной загрузки App.)
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\delta] = ~spec_delta;
~ungVals[\delta]  = ();
~spec_delta.params.do { |p|
    Ndef(\delta).set(p.key, p.spec.default);
    ~ungVals[\delta][p.key] = p.spec.default;
};
Ndef(\delta).fadeTime = 4;   // §F sustained register: мягкий вход/выход 4 s

("synths/delta — spec зарегистрирован ("
    ++ ~spec_delta.params.size ++ " параметров); ~openTuner.(\\delta)").postln;
)
