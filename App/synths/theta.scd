// App/synths/theta.scd — UNGRUND class 8/8 `theta`, §C.8 `splitter` (2026-07-17):
// anschlag-каскад (5 микроимпульсов, 1.07 ms) + korn (1–3 моды решётки 94 Hz,
// закон размера T20 = min(40 ms, 45100/f)) + kante; истощение популяции §D.2:
// IOI_k = ioi0 * decel^k * versatz. NO random / noise / nonlinearity (Axiom III:
// период, не розыгрыш); слой сухой — §K.2 send 0.0 это ЗАПРЕТ, не вкус.
// Spec: plans/active/theta-splitter-population.md; reference + implementation
// notes: docs/features/theta/fragment-reference.md. ~spec_theta — source of truth.


// ===== CONFIG — edit here ============================================
(
// group \freq — только октавный индекс: высоты класса — фиксированная таблица
// ПО ПРЕМИССЕ. Колёса, 41 строка, закон размера, каскад и тримы — партитура,
// не CONFIG: правятся редактированием и перезапуском (прецедент gamma).
~spec_theta = (
    name: \theta,
    params: [
        // --- group \freq ---
        // без disp: октавный индекс — не частота; решётку держит round в LOGIC
        ( key: \fragOct, label: "октава мод",    group: \freq,             spec: ControlSpec(-1, 0, \lin, 1, 0)          ),

        // --- group \tone: the arrival law (NEVER lagged — they latch at the
        // population boundary, where Dgeom/Ddup re-poll their kr inputs) ---
        ( key: \ioi0, label: "IOI головы",       group: \tone, unit: " s", spec: ControlSpec(0.012, 0.120, \exp, 0, 0.018) ),  // head IOI; \exp — a time constant over 10:1
        ( key: \decel, label: "замедление",      group: \tone,             spec: ControlSpec(1.05, 1.40, \lin, 0, 1.22)  ),  // decel <= 1 is unreachable by construction
        ( key: \ioiMax, label: "потолок истощ.",     group: \tone, unit: " s", spec: ControlSpec(0.4, 1.5, \lin, 0, 0.60)    ),  // exhaustion floor -> kMax
        ( key: \popScale, label: "разм. популяции",   group: \tone,             spec: ControlSpec(0.5, 2.0, \lin, 0, 1.0)     ),  // scales wheel 6
        ( key: \gapScale, label: "пауза",   group: \tone,             spec: ControlSpec(0.3, 3.0, \lin, 0, 1.0)     ),  // scales wheel 7

        // --- group \tone: the contact + level ---
        ( key: \edgeWidth, label: "ширина контакта",  group: \tone,             spec: ControlSpec(0.2, 1.0, \lin, 0, 0.7)     ),  // scales wheel 2's rq; narrow = clean ping, wide = grain survives
        ( key: \edgeAmp, label: "уровень контакта",    group: \tone,             spec: ControlSpec(0.0, 1.0, \lin, 0, 0.45)    ),  // kante level vs the mode sum; 0.0 = a bell (a control, not a defect)
        ( key: \decayScale, label: "масшт. затух.", group: \tone,             spec: ControlSpec(0.3, 1.0, \lin, 0, 1.0)     ),  // can only SHORTEN the size law
        ( key: \spread, label: "разброс пан.",     group: \tone,             spec: ControlSpec(0.0, 1.0, \lin, 0, 0.8)     ),  // scales wheel 4; never moves one position
        ( key: \amp, label: "громкость",        group: \tone,             spec: ControlSpec(0.0, 0.30, \lin, 0, 0.09)   )   // §K.4; §F band −24…−10 dBFS peak
    ]
);


// ===== LOGIC — synthesis =============================================
// One persistent graph, весь планировщик — demand-rate внутри прокси (прецедент
// gamma): hot-swap идемпотентен. Scheduler -> odometer -> ONE global cascade ->
// round-robin по 14 голосам -> (korn + kante) -> pan -> LeakDC -> Limiter.
Ndef(\theta, { |fragOct = 0, ioi0 = 0.018, decel = 1.22, ioiMax = 0.60,
    popScale = 1.0, gapScale = 1.0, edgeWidth = 0.7, edgeAmp = 0.45,
    decayScale = 1.0, spread = 0.8, amp = 0.09|

    var nyq, fund = 94;
    // 12 доказуемо steal-free, 14 — запас под правку таблиц; украденный onset
    // проверяется счётом, не ухом — см. Implementation notes референса
    var nVoices = 14;

    // --- wheel 1: 41 fragment rows (ratios of 94 Hz, 2^i*3^j) ---
    // 13/17/11 строк по числу мод, попарно различны, low-ratio ряд немонотонен
    // (монотонный = свип = жест); unused slots REPEAT r0 => max(r0,r1,r2) —
    // всегда верхняя мода строки (центр kante BPF)
    var rowR0 = #[27, 16, 64, 12, 48, 24, 81, 18, 96, 36, 32, 54, 12, 72, 24,
        16, 81, 27, 54, 12, 48, 48, 64, 18, 24, 32, 36, 12, 64, 16, 72, 48, 18,
        16, 54, 32, 12, 64, 36, 18, 72];
    var rowR1 = #[27, 36, 81, 12, 54, 32, 81, 27, 96, 48, 32, 72, 16, 72, 27,
        16, 96, 32, 54, 18, 48, 81, 72, 24, 24, 96, 36, 27, 64, 24, 81, 64, 18,
        32, 96, 54, 24, 96, 54, 36, 96];
    var rowR2 = #[27, 16, 96, 12, 48, 64, 81, 18, 96, 96, 32, 54, 32, 72, 24,
        16, 81, 81, 54, 12, 48, 48, 64, 54, 24, 32, 36, 36, 64, 16, 72, 96, 18,
        48, 54, 32, 27, 64, 81, 18, 72];
    var rowN = #[1, 2, 3, 1, 2, 3, 1, 2, 1, 3, 1, 2, 3, 1, 2, 1, 2, 3, 1, 2, 1,
        2, 2, 3, 1, 2, 1, 3, 1, 2, 2, 3, 1, 3, 2, 2, 3, 2, 3, 2, 2];
    // wheel 2 — kante edge width, rq (17), 0.05–0.9, non-monotone
    var rqTable = #[0.33, 0.90, 0.12, 0.58, 0.05, 0.71, 0.24, 0.47, 0.83, 0.16,
        0.64, 0.09, 0.40, 0.77, 0.29, 0.54, 0.20];
    // wheel 3 — event level (31), −8…0 dB. (i*7) % 31 is a full-period
    // permutation (7 coprime to 31): non-monotone by construction, no
    // hand-tuned table to mistype. Mean ≈ −4.0 dB.
    var levelTable = (0..30).collect { |i| (-8 * ((i * 7) % 31) / 30).dbamp };
    // wheel 4 — pan (29), bounds exactly ±0.4 at spread 1.0 (§F), non-monotone
    var panTable = (0..28).collect { |i| (((i * 11) % 29) / 28 * 0.8) - 0.4 };
    // wheel 5 — versatz (11): отклонение закона прибытия. Среднее РОВНО 1.000
    // (иначе ломается аналитика истощения decel^{2N/3}); аудит: одиннадцать
    // 1.0 => чистое ritardando — анти-жестовое доказательство Axiom III
    var versatz = #[1.05, 0.60, 1.38, 0.72, 1.65, 0.55, 1.20, 0.82, 1.50, 0.68,
        0.85];
    // wheel 6 — population size N (7), 8–28; kMax=18 при дефолтах усечёт до
    // среднего 15.0 — корректно (популяция кончается на k=N ИЛИ IOI>ioiMax)
    var popTable = #[18, 26, 11, 22, 8, 28, 14];
    // wheel 7 — inter-population gap, s (23), 0.8–6.0, non-monotone; mean 3.022
    var gapTable = #[2.6, 5.1, 1.2, 3.8, 0.8, 4.4, 2.1, 6.0, 1.5, 3.2, 0.9, 4.9,
        2.4, 1.8, 5.6, 1.1, 3.5, 2.8, 4.1, 1.4, 5.3, 2.0, 3.0];

    // --- anschlag: закон прибытия класса в третьем масштабе. Onsets
    // 0/0.080/0.232/0.521/1.070 ms — из ВРЕМЁН, не из сэмплов (SR-инвариантность
    // в ms; не Buffer — это был бы сэмпл, Axiom II). См. Implementation notes.
    var cascC0 = 0.00008, cascCl = 1.9, cascAcc = 0.0;
    var cascTimes, cascLevels = #[1.0, 0.62, 0.85, 0.48, 0.71];
    // класс-константы, НИКОГДА не масштабируются fragOct (иначе скрытый второй
    // \freq); полосу 12–20 kHz проверять ТОЛЬКО FFT — band RMS инструмента
    // врёт на 2-полюсных скатах (ловушка 2026-07-17, см. Implementation notes)
    var cascHP = 400, cascLP = 9024, cascHPn = 2, cascLPn = 2;
    // НЕСУЩАЯ ширина: > пролёта каскада 1.07 ms и < мин. IOI 6.6 ms; понижение
    // пола ioi0 или минимума versatz ломает глобальный каскад МОЛЧА
    var cascGate = 0.0025;

    // --- dev-калибровки (не параметры), измерены 2026-07-17 при 44.1 k,
    // SR-зависимы — перекалибровывать на частоте рендера (Implementation notes)
    var t60Ref   = 0.045;  // норм. энергии мод: без неё размер управлял бы громкостью
                           // (~-3 dB/окт); из pitch-only T60, НИКОГДА из decayScale
    // закон ИЗМЕРЕН на каскаде (девиация D1 спеки: закон спеки инвертирован,
    // не применять — peak BPF-импульса растёт с ПОЛОСОЙ, narrower is QUIETER)
    var edgeRqExp = 0.85, edgeFExp = 0.4;
    var edgeRef  = 280;    // кладёт пик kante на пик korn при edgeAmp 1.0 =>
                           // дефолт 0.45 даёт контакт ~7 dB под модами
    var edgeTrim = 1.0;    // kante stratum vs mode sum при дефолте edgeAmp
    var makeup   = 0.58;   // peak -12 dBFS при amp 0.09; peak-метрика §F бьёт RMS

    var fragOctL, fragFund, edgeWidthL, edgeAmpL, decayScaleL, spreadL;
    var ioi0L, decelL, ioiMaxL, popScaleL, gapScaleL, kMax, nEffA, nEffB;
    var kStream, isFirst, geom, durs, tFrag, vals;
    var wR0, wR1, wR2, wN, wRq, wLevel, wPan;
    var imp, casc, vIdx, sig;

    nyq = SampleRate.ir * 0.45;

    // round ПОСЛЕ lag: ControlSpec:map игнорирует step => ~rndFreq может подать
    // -0.5 (вне решётки); round до lag не спасает (Implementation notes)
    fragOctL = fragOct.lag(0.2).round(1).clip(-1, 0);
    fragFund = fund * (2 ** fragOctL);

    edgeWidthL  = edgeWidth.lag(0.1).clip(0.2, 1.0);
    edgeAmpL    = edgeAmp.lag(0.1).clip(0, 1);
    decayScaleL = decayScale.lag(0.2).clip(0.3, 1.0);
    spreadL     = spread.lag(0.2).clip(0, 1);

    // --- block 1: the population scheduler (demand rate) ---
    // пять контролов плотности клампятся и НИКОГДА не лагаются: они читаются
    // раз в популяцию, на границе (Dgeom/Ddup re-poll при ресете Dseq) — lag
    // гнул бы закон в момент установления (спека, «density-control latching»)
    ioi0L     = ioi0.clip(0.012, 0.120);
    decelL    = decel.clip(1.05, 1.40);
    ioiMaxL   = ioiMax.clip(0.4, 1.5);
    popScaleL = popScale.clip(0.5, 2.0);
    gapScaleL = gapScale.clip(0.3, 3.0);

    // exit-тест замкнут на kr (по закону ДО versatz-отклонения): IOI_k > ioiMax
    // решается точно, никакого demand-ветвления
    kMax = ((ioiMaxL / ioi0L).log / decelL.log).floor + 1;

    // WHEEL 6 ШАГАЕТ РАЗ В ПОПУЛЯЦИЮ, не раз во фрагмент — девиация D2 спеки
    // (рецепт спеки измеренно замораживает размер популяции; RULED 2026-07-17).
    // Две НЕЗАВИСИМЫЕ копии: stream, названный дважды в одном demand-выражении,
    // тянется дважды; обе ресетятся на pull 0 => lockstep по построению.
    // kMax/popScale — kr-входы выражения с одним pull на популяцию: латч даром.
    nEffA = (Dseq(popTable, inf) * popScaleL).min(kMax).round(1).clip(2, 64);
    nEffB = (Dseq(popTable, inf) * popScaleL).min(kMax).round(1).clip(2, 64);

    // фазовый счётчик: флаг и геометрический закон ресетятся НА ОДНОМ pull и
    // читают ОДИН nEff (flag-конструкт спеки дрейфует — измерено 2026-07-17,
    // exhaustion ratio 0.81 при всех прочих метриках зелёных)
    kStream = Dseq([ Dseries(0, 1, nEffB) ], inf);
    // пауза — НЕ событие: едет на входном интервале первого фрагмента => ровно
    // nEff pulls на популяцию, одометр и «no terminal event» держатся структурно
    isFirst = kStream < 0.5;
    // САМАЯ ВАЖНАЯ СТРОКА СЛОЯ: ioi0 входит через СТАРТ Dgeom (`ioi0L * geom`
    // гнул бы закон на каждом pull — невидимо для parse, неслышимо на слух);
    // старт ioi0/decel из-за one-pull сдвига TDuty vs Demand.ar; НЕ «чинить»
    // через ControlDur.ir — рассинхронизирует узлы навсегда. Спека, footgun 2.
    geom = Dseq([ Dgeom(ioi0L / decelL, decelL, nEffA) ], inf);
    durs = (geom * Dseq(versatz, inf)) + (isFirst * Dseq(gapTable, inf) * gapScaleL);
    tFrag = TDuty.ar(durs);

    // --- block 2: the wheel odometer (demand rate) ---
    // колесо длины L ЕСТЬ Dseq(таблица, inf). PULL-ИНВАРИАНТ: каждый stream
    // тянется ровно раз на фрагмент ЭТИМ ОДНИМ Demand.ar; второй Demand / Dpoll
    // / viz-tap ломает одометр молча (все метрики уровней пройдут) — спека,
    // footgun 1. Поэтому mode-гейты ниже выводятся на ar (ar можно реюзать).
    vals = Demand.ar(tFrag, 0, [
        Dseq(rowR0, inf), Dseq(rowR1, inf), Dseq(rowR2, inf), Dseq(rowN, inf),
        Dseq(rqTable, inf), Dseq(levelTable, inf), Dseq(panTable, inf)
    ]);
    // именовать в точке pull: позиционный vals[i] — свой класс тихих отказов
    wR0 = vals[0]; wR1 = vals[1]; wR2 = vals[2]; wN = vals[3];
    wRq = vals[4]; wLevel = vals[5]; wPan = vals[6];

    // --- block 3: contact cascade — ГЛОБАЛЬНЫЙ, один на все голоса (каскады
    // доказуемо не перекрываются: min IOI 6.6 ms > пролёт 1.07 ms; голос берёт
    // свой через cascGate). DelayN, не DelayC: интерполяция размазала бы
    // односэмпловый фронт (Implementation notes).
    cascTimes = [0.0] ++ (0..3).collect { |i|
        cascAcc = cascAcc + (cascC0 * (cascCl ** i)); cascAcc
    };
    // выход TDuty — уже бэндлимитный дискретный импульс; алиасить в слое
    // нечему (нужна нелинейность/ресемплинг, карта запрещает обе)
    imp  = tFrag;
    casc = Mix(cascTimes.collect { |t, i|
        if(t <= 0) { imp * cascLevels[i] } { DelayN.ar(imp, 0.002, t) * cascLevels[i] }
    });
    cascHPn.do { casc = HPF.ar(casc, cascHP) };
    cascLPn.do { casc = LPF.ar(casc, cascLP) };

    // --- block 4: детерминированный round-robin (Stepper, не TIRand: random
    // UGen в этом слое аннулирует класс — §C.8)
    vIdx = Stepper.ar(tFrag, 0, 0, nVoices - 1, 1);

    sig = Mix.fill(nVoices, { |v|
        var trig, gate, excite, nMod, g1, g2, ratios, freqs, t20s, ringTs, eNorms;
        var modes, fTop, rqL, edgeNorm, kante, levelW, panW, voice;

        trig = tFrag * ((vIdx - v).abs < 0.5);
        gate   = Trig.ar(trig, cascGate);
        excite = casc * gate;

        // заморозка события: латчится СМАППЛЕННОЕ значение (Latch(ratio*fund),
        // не Latch(ratio)*fund) — fragOct в движении не перестроит звенящую моду
        nMod = Latch.ar(wN, trig);
        g1   = nMod > 1.5;
        g2   = nMod > 2.5;
        ratios = [wR0, wR1, wR2];
        // кламп не зацепляется по построению — страхует будущую правку таблиц
        freqs = ratios.collect { |r| Latch.ar(r * fragFund, trig).clip(20, nyq) };

        // korn: закон размера, decaytime Ringz — время −60 dB => T60 = 3*T20.
        // Кламп на ringT, НЕ на T20 (клип T20 разрешал бы нарушение 15 ms-пола
        // карты — Implementation notes)
        t20s   = freqs.collect { |f| (45.1 / f).min(0.040) };
        ringTs = t20s.collect { |t| (3 * t * decayScaleL).clip(0.015, 0.150) };
        eNorms = t20s.collect { |t| (t60Ref / (3 * t)).sqrt };
        // power-нормализация: 3-модовая строка не громче 1-модовой
        modes = Mix([
            Ringz.ar(excite, freqs[0], ringTs[0]) * eNorms[0],
            Ringz.ar(excite, freqs[1], ringTs[1]) * eNorms[1] * g1,
            Ringz.ar(excite, freqs[2], ringTs[2]) * eNorms[2] * g2
        ]) / nMod.max(1).sqrt;

        // kante: тот же каскад через один BPF на ВЕРХНЕЙ моде строки; narrow rq
        // = чистый ping, wide rq = зерно каскада доживает до фрагмента
        fTop     = freqs[0].max(freqs[1]).max(freqs[2]);
        rqL      = (Latch.ar(wRq, trig) * edgeWidthL).clip(0.01, 1.0);
        edgeNorm = edgeRef / ((rqL ** edgeRqExp) * (fTop ** edgeFExp));
        kante    = BPF.ar(excite, fTop, rqL) * edgeNorm
            * Decay2.ar(trig, 0.0002, 0.0025);

        levelW = Latch.ar(wLevel, trig);
        panW   = Latch.ar(wPan, trig);
        voice  = (modes + (kante * edgeAmpL * edgeTrim)) * levelW;
        // pan фиксирован на фрагмент, |pan| <= 0.4 при spread 1.0 (§F): spread
        // масштабирует всю таблицу, ни pan-LFO, ни дрейфа позиции нет
        Pan2.ar(voice, panW * spreadL);
    });

    // --- block 5: condition ---
    sig = sig * makeup * amp.lag(0.05);
    sig = LeakDC.ar(sig);
    // Limiter — единственная нелинейность и обязан молчать в каждом
    // СКОМПОНОВАННОМ состоянии; здесь только как страховка рандомайзера
    sig = Limiter.ar(sig, 0.95);
    sig
});

// register spec + apply defaults (self-sufficient: 0_lib only needed for
// interactive random/presets/GUI after the full App load)
~ungSpecs = ~ungSpecs ? ();
~ungVals  = ~ungVals  ? ();
~ungSpecs[\theta] = ~spec_theta;
~ungVals[\theta]  = ();
~spec_theta.params.do { |p|
    Ndef(\theta).set(p.key, p.spec.default);
    ~ungVals[\theta][p.key] = p.spec.default;
};
Ndef(\theta).fadeTime = 0.5;   // event class: cut, not faded

("synths/theta — spec зарегистрирован ("
    ++ ~spec_theta.params.size ++ " параметров); ~openTuner.(\\theta)").postln;
)
