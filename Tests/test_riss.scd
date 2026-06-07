// =====================================================================
// tests/test_riss.scd
// UNGRUND — изолированный тест функции `riß`  (звуковой класс 2 из 8)
//
// ТЕМБР («Дисперсионный разлом» — переосмысление, согласовано с
// композитором 2026-05-22): РАЗЛОМ КАК ДИСПЕРСИОННЫЙ УДАР. Короткий
// яркий разрыв проходит сквозь каскад из 80 first-order allpass-секций
// (FOS). Групповая задержка каскада зависит от частоты: высокие
// составляющие выходят первыми, низкие — последними, и одиночный щелчок
// растягивается в нисходящий «лазерный» чирп раскола. Тело материала
// отзывается инармоническим звоном (Klank); суб-«вхлоп» даёт вес удара;
// «изломанность» добавляет сателлитные микротрещины и дрожь коэффициентов
// каскада; 2-й короткий путь — эхо трещины от дальнего края.
//
// СОБЫТИЙНЫЙ КЛАСС: riß — одноразовое событие. Тест-инструмент
// срабатывает по кнопке "выстрел" (один разлом). Огибающая НЕ имеет
// gate/release — синт сам освобождается (doneAction: 2) по завершении.
// Слайдеры задают параметры СЛЕДУЮЩЕГО выстрела.
//
// Синтез — физическое вычисление (НЕ запись, Аксиома II):
//   FOS — каскад first-order allpass (частотно-зависимая дисперсия);
//   Klank — инармонический звон тела; Dust — сателлитные микротрещины;
//   короткий реверб (хвост < 100 мс — §C.2 запрещает длиннее).
//
// ВНИМАНИЕ: дисперсионная модель — переосмысление класса riß за пределы
// reference_v2.md §C.2 (мягкое гранулярное облако). «Разлом» — рабочий
// бриф синтеза, согласован с композитором (Аксиома VII).
//
// ЗАПРЕЩЕНО КЛАССУ (reference_v2.md §C.2):
//   слышимый определённый тон · реверб-хвост длиннее 100 мс ·
//   ритмическое повторение (riß — событие, не пульс).
//
// СОХРАНЕНИЕ: кнопка "save" выводит блок всех 10 параметров в post-окно
// и в файл tests/test_riss_params.txt.
//
// КАК ПОЛЬЗОВАТЬСЯ
//   1. Выделить весь файл (Cmd-A), выполнить (Shift-Return).
//   2. "выстрел" — один разлом riß. Жмите повторно, чтобы услышать ещё.
//   3. Слайдеры задают параметры следующего выстрела (riß одноразов).
//   4. "random частоты" / "random параметры" — случайные значения.
//   5. "save"   — блок параметров в текст (post-окно + файл).
//   6. "запись аудио" — тумблер: финальный микс -> WAV-файл в tests/.
//   7. "паника" — полный сброс. Cmd-. безопасен. Закрытие окна = сброс.
//
// ПАРАМЕТРЫ (умолчания — рабочий бриф «разлом»)
//   body      резонанс тела материала          50–900 Hz     180
//   disperse  сила дисперсии (длина чирпа)      0–1           0.72
//   chirp     крутизна чирпа (градиент каскада) 0–1           0.5
//   fracture  «изломанность»: сателлиты + дрожь 0–1           0.35
//   crack     яркость / жёсткость разрыва       0–1           0.6
//   decay     время звона тела                  0.05–4 s      0.9
//   sub       уровень суб-«вхлопа»              0–1           0.5
//   echo      эхо трещины от дальнего края      0–1           0.3
//   amp       пиковая громкость                0–1           0.7
//   revSend   посыл в короткий реверб           0–1           0.25
// =====================================================================


// =====================================================================
// 0. Каталог параметров и директория файла.
// =====================================================================

~mDir = thisProcess.nowExecutingPath !? { |p| p.dirname };

~paramOrder = [
    \body, \disperse, \chirp, \fracture, \crack,
    \decay, \sub, \echo, \amp, \revSend
];

~params = (
    body: 180, disperse: 0.72, chirp: 0.5, fracture: 0.35, crack: 0.6,
    decay: 0.9, sub: 0.5, echo: 0.3, amp: 0.7, revSend: 0.25
);

// слайдеры частотно-спектральной области (кнопка "random частоты")
~freqKeys  = [\body, \disperse, \chirp];
// остальные слайдеры (кнопка "random параметры")
~paramKeys = [\fracture, \crack, \decay, \sub, \echo, \amp, \revSend];


// =====================================================================
// 1. Сброс — идемпотентный демонтаж (освобождает синты, шины, группы).
// =====================================================================

~mReset = { |verbose = true|
    if(s.isRecording)  { s.stopRecording };
    if(~rev.notNil)    { ~rev.free;    ~rev = nil };
    if(~mst.notNil)    { ~mst.free;    ~mst = nil };
    if(~grpSrc.notNil) { ~grpSrc.freeAll; ~grpSrc.free; ~grpSrc = nil };
    if(~grpFx.notNil)  { ~grpFx.freeAll;  ~grpFx.free;  ~grpFx = nil };
    if(~busTest.notNil) { ~busTest.free; ~busTest = nil };
    if(~busFx.notNil)   { ~busFx.free;   ~busFx = nil };
    if(~busRev.notNil)  { ~busRev.free;  ~busRev = nil };
    if(verbose) { "test_riss — сброс выполнен.".postln };
};


// =====================================================================
// 2. Управление — статус, выстрел, random, запись, сохранение.
// =====================================================================

~mStatus = { |str|
    { if(~statusTxt.notNil) { ~statusTxt.string = "riß — " ++ str } }.defer;
};

// инфо-строка: время звона тела и оценка числа сателлитных трещин.
~mUpdateInfo = {
    { if(~infoTxt.notNil) {
        ~infoTxt.string = "звон ≈ " ++ ~params[\decay].round(0.01)
            ++ " s   ·   ~" ++ (~params[\fracture] * 13).round.asInteger
            ++ " сателлитов";
    } }.defer;
};

// выстрел — один разлом riß; синт сам освобождается (doneAction: 2).
~mShot = {
    var args;
    if(~grpSrc.isNil) {
        "test_riss — сервер ещё не готов.".postln;
    } {
        args = (~paramOrder.collect { |k| [k, ~params[k]] }.flatten)
                ++ [\out, ~busTest.index, \fx_bus, ~busFx.index];
        Synth(\riss, args, ~grpSrc);
        ~mStatus.value("выстрел — разлом · звон ≈ "
            ++ ~params[\decay].round(0.01) ++ " s");
    };
};

// random — два независимых рандомайзера: частотная область и параметры.
~mRandomFreq = {
    if(~ez.notNil) {
        ~freqKeys.do { |key|
            var ez = ~ez[key];
            if(ez.notNil) { ez.valueAction_(ez.controlSpec.map(1.0.rand)) };
        };
        ~mStatus.value("random — случайные частоты (body, disperse, chirp)");
    };
};

~mRandomParams = {
    if(~ez.notNil) {
        ~paramKeys.do { |key|
            var ez = ~ez[key];
            if(ez.notNil) { ez.valueAction_(ez.controlSpec.map(1.0.rand)) };
        };
        ~mStatus.value("random — случайные параметры (7)");
    };
};

// запись — тумблер: финальный микс (шина 0) пишется в WAV-файл tests/.
~mRecStart = {
    var path;
    if(s.isRecording) {
        ~mStatus.value("запись уже идёт");
    } {
        s.recHeaderFormat = "wav";
        s.recSampleFormat = "int24";
        path = if(~mDir.notNil) {
            ~mDir +/+ ("test_riss_" ++ Date.getDate.stamp ++ ".wav")
        };
        if(path.notNil) {
            s.record(path);
            ~mStatus.value("● запись -> " ++ path.basename);
        } {
            s.record;
            ~mStatus.value("● запись (каталог записей SuperCollider)");
        };
    };
};

~mRecStop = {
    if(s.isRecording) {
        s.stopRecording;
        ~mStatus.value("запись остановлена — файл сохранён");
    } {
        ~mStatus.value("запись не велась");
    };
};

// save — блок всех параметров в текст: вывод в post-окно + файл.
~mSave = {
    var lines, text, path;
    lines = ~paramOrder.collect { |k|
        (k.asString ++ ":").padRight(12) ++ ~params[k].round(0.0001).asString;
    };
    text = "// ===== test_riß — параметры · " ++ Date.getDate.stamp ++ " =====\n"
         ++ lines.join("\n")
         ++ "\n// звон ≈ " ++ ~params[\decay].round(0.01) ++ " s · дисперсия 80 секций"
         ++ "\n// =====================================================";
    text.postln;
    if(~mDir.notNil) {
        path = ~mDir +/+ "test_riss_params.txt";
        File.use(path, "w", { |f| f.write(text) });
        ~mStatus.value("параметры сохранены -> " ++ path.basename);
    } {
        ~mStatus.value("параметры выведены в post-окно");
    };
};


// =====================================================================
// 3. Конструктор слайдеров + окно (один столбец из 10 параметров).
// =====================================================================

// Слайдер параметра: значение пишется в ~params; синта-приёмника нет —
// riß одноразов, слайдеры задают параметры следующего выстрела.
~mSlider = { |y, key, label, spec, round = 0.001|
    var ez;
    ez = EZSlider(~win, Rect(20, y, 540, 24), label, spec, { |e|
        ~params[key] = e.value;
        ~mUpdateInfo.value;
    }, ~params[key]);
    ez.labelView.stringColor_(Color.white);
    ez.round_(round);
    ~ez[key] = ez;
};

~mBuildWindow = {
    if(~win.notNil) { ~win.close };
    ~ez = ();
    ~win = Window("UNGRUND — test_riß  (2/8 · Ereignis ▒) — дисперсионный разлом",
                  Rect(80, 60, 600, 478))
        .background_(Color.gray(0.12));

    StaticText(~win, Rect(20, 12, 560, 22))
        .string_("riß — дисперсионный разлом: чирп раскола сквозь каскад allpass")
        .stringColor_(Color.gray(0.92))
        .font_(Font("Menlo", 13, true));

    ~statusTxt = StaticText(~win, Rect(20, 36, 560, 20))
        .string_("riß — готово, нажмите «выстрел»")
        .stringColor_(Color.gray(0.70))
        .font_(Font("Menlo", 11));

    StaticText(~win, Rect(20, 58, 560, 16))
        .string_("событийный класс · «выстрел» = один разлом · слайдеры задают следующий")
        .stringColor_(Color.gray(0.45))
        .font_(Font("Menlo", 9));

    StaticText(~win, Rect(20, 80, 300, 16))
        .string_("ПАРАМЕТРЫ РАЗЛОМА — дисперсионная модель")
        .stringColor_(Color.gray(0.62))
        .font_(Font("Menlo", 10, true));

    ~infoTxt = StaticText(~win, Rect(320, 80, 260, 16))
        .align_(\right)
        .stringColor_(Color.gray(0.55))
        .font_(Font("Menlo", 10, true));

    // ----- 10 слайдеров параметров ------------------------------------
    ~mSlider.value(100, \body,     "body  Hz",  ControlSpec(50, 900, \exp, 0, 180, " Hz"), 1);
    ~mSlider.value(127, \disperse, "disperse",  ControlSpec(0, 1, \lin, 0, 0.72), 0.01);
    ~mSlider.value(154, \chirp,    "chirp",     ControlSpec(0, 1, \lin, 0, 0.5), 0.01);
    ~mSlider.value(181, \fracture, "fracture",  ControlSpec(0, 1, \lin, 0, 0.35), 0.01);
    ~mSlider.value(208, \crack,    "crack",     ControlSpec(0, 1, \lin, 0, 0.6), 0.01);
    ~mSlider.value(235, \decay,    "decay  s",  ControlSpec(0.05, 4.0, \exp, 0, 0.9, " s"), 0.01);
    ~mSlider.value(262, \sub,      "sub",       ControlSpec(0, 1, \lin, 0, 0.5), 0.01);
    ~mSlider.value(289, \echo,     "echo",      ControlSpec(0, 1, \lin, 0, 0.3), 0.01);
    ~mSlider.value(316, \amp,      "amp",       ControlSpec(0, 1, \lin, 0, 0.7), 0.001);
    ~mSlider.value(343, \revSend,  "revSend",   ControlSpec(0, 1, \lin, 0, 0.25), 0.01);

    ~mUpdateInfo.value;

    // ----- кнопки -----------------------------------------------------
    Button(~win, Rect(20, 384, 150, 42))
        .states_([["выстрел", Color.white, Color(0.52, 0.20, 0.12)]])
        .font_(Font("Menlo", 14, true))
        .action_({ ~mShot.value });

    Button(~win, Rect(178, 384, 140, 42))
        .states_([["random частоты", Color.white, Color(0.18, 0.34, 0.44)]])
        .font_(Font("Menlo", 12, true))
        .action_({ ~mRandomFreq.value });

    Button(~win, Rect(326, 384, 140, 42))
        .states_([["random параметры", Color.white, Color(0.40, 0.30, 0.18)]])
        .font_(Font("Menlo", 12, true))
        .action_({ ~mRandomParams.value });

    Button(~win, Rect(474, 384, 106, 42))
        .states_([["save", Color.white, Color(0.20, 0.40, 0.24)]])
        .font_(Font("Menlo", 14, true))
        .action_({ ~mSave.value });

    ~recBtn = Button(~win, Rect(20, 436, 270, 28))
        .states_([
            ["● запись аудио",      Color.white,      Color(0.50, 0.13, 0.13)],
            ["■ остановить запись", Color.gray(0.08), Color(0.95, 0.78, 0.25)]
        ])
        .font_(Font("Menlo", 11, true))
        .action_({ |b| if(b.value == 1) { ~mRecStart.value } { ~mRecStop.value } });

    Button(~win, Rect(298, 436, 282, 28))
        .states_([["паника / полный сброс", Color.gray(0.95), Color(0.5, 0.13, 0.13)]])
        .font_(Font("Menlo", 11, true))
        .action_({
            ~mReset.value(true);
            if(~recBtn.notNil) { ~recBtn.value_(0) };
            ~mStatus.value("сброшено");
        });

    ~win.onClose_({ ~mReset.value(false) });
    ~win.front;
};


// =====================================================================
// 4. Загрузка сервера: SynthDefs -> шины/группы -> постоянные синты -> окно.
// =====================================================================

s.waitForBoot({
    ~mReset.value(false);

    // ----- 4.1 SynthDef функции — дисперсионный разлом ----------------
    SynthDef(\riss, { |out = 0, fx_bus = 18,
                      body = 180, disperse = 0.72, chirp = 0.5, fracture = 0.35,
                      crack = 0.6, decay = 0.9, sub = 0.5, echo = 0.3,
                      amp = 0.7, revSend = 0.25|
        var nMain = 80, nEcho = 22;
        var lifeEnv, pEnv, primary, satWin, satTrig, satBurst, exc;
        var cBase, disp, ringFreqs, ring, subFreq, subEnv, subW;
        var echoSig, echoDelay, crackPath, full;

        // --- лайфцикл узла: держим на время разлома, затем doneAction: 2
        lifeEnv = EnvGen.kr(
            Env([1, 1, 0], [decay.max(0.6) + 1.8, 0.08]),
            doneAction: 2);

        // --- возбуждение: первичный разрыв + сателлитные микротрещины --
        pEnv    = EnvGen.ar(Env.perc(0.0002, ExpRand(0.002, 0.006)));
        primary = (WhiteNoise.ar + Impulse.ar(0)) * pEnv;

        satWin   = EnvGen.kr(Env([1, 1, 0], [0.003, 0.06]));
        satTrig  = Dust.ar((fracture * 260).max(0));
        satBurst = Decay2.ar(satTrig, 0.0003, 0.0035) * WhiteNoise.ar * satWin;

        exc = primary + (satBurst * 0.55);
        exc = LPF.ar(exc, crack.linexp(0, 1, 900, 18000));

        // --- дисперсия: каскад first-order allpass (FOS) --------------
        // групповая задержка зависит от частоты -> нисходящий чирп.
        cBase = disperse.linlin(0, 1, 0.0, 0.965) * Rand(0.985, 1.015);
        disp  = exc ! 2;
        nMain.do { |i|
            var fr = i / (nMain - 1);
            var cg = cBase * (1 - (chirp * 0.55 * fr));
            var c  = (cg + ([Rand(fracture.neg, fracture),
                             Rand(fracture.neg, fracture)] * 0.06))
                        .clip(-0.985, 0.985);
            disp = FOS.ar(disp, c, 1.0, c.neg);
        };
        // дисперсия размазывает энергию во времени -> компенсация уровня
        disp = disp * disperse.linlin(0, 1, 1.5, 7.0);

        // --- тело материала: инармонический звон, возбуждённый разрывом
        ringFreqs = (body * [1, 2.71, 4.93, 7.12, 9.78]).clip(20, 18000);
        ring = Klank.ar(
            `[ringFreqs,
              [1, 0.6, 0.4, 0.26, 0.16],
              (decay * [1, 0.78, 0.6, 0.43, 0.28]).max(0.04)],
            exc);

        // --- суб-«вхлоп»: низкий удар в момент разрыва ----------------
        subFreq = body.linexp(50, 900, 36, 92);
        subEnv  = EnvGen.ar(Env.perc(0.004, 0.18 + (decay * 0.05), curve: -4));
        subW    = SinOsc.ar(subFreq) * subEnv;

        // --- 2-й путь: эхо трещины от дальнего края (короткая дисперсия)
        echoDelay = 0.04 + (echo * 0.09);
        echoSig   = DelayC.ar(Mix(disp) * 0.5, 0.25, echoDelay);
        nEcho.do { |i|
            var ce = ((cBase * 0.8) + Rand(-0.05, 0.05)).clip(-0.97, 0.97);
            echoSig = FOS.ar(echoSig, ce, 1.0, ce.neg);
        };
        echoSig = (echoSig * echo * 0.8) ! 2;

        // --- сборка ---------------------------------------------------
        crackPath = disp + echoSig + ((ring * 0.5) ! 2);
        crackPath = HPF.ar(crackPath, 90);
        full = crackPath + ((subW * sub) ! 2);
        full = (full * 1.5).tanh;
        full = LeakDC.ar(full);
        full = full * amp * lifeEnv * 0.5;

        Out.ar(out,    full);
        Out.ar(fx_bus, full * revSend.clip(0, 1));
    }).add;

    // ----- 4.2 короткий реверб — хвост < 100 мс (§C.2 запрещает длиннее)
    SynthDef(\riss_verb, { |in = 18, out = 20, wet = 1.0|
        var sig, w;
        sig = In.ar(in, 2);
        w = sig;
        // диффузия короткими allpass: decayTime 0.085 s -> хвост ~90 мс
        [0.0071, 0.0113, 0.0143, 0.0211].do { |dt|
            w = AllpassC.ar(w, 0.05, dt, 0.085);
        };
        w = LPF.ar(w, 6500);
        Out.ar(out, w * wet);
    }).add;

    // ----- 4.3 мастер: сумма (сухой + реверб), LeakDC, Limiter --------
    SynthDef(\ung_master_r, { |in_dry = 16, in_fx = 20, out = 0, master_amp = 1.0|
        var dry, fx, sig;
        dry = In.ar(in_dry, 2);
        fx  = In.ar(in_fx, 2);
        sig = dry + fx;
        sig = LeakDC.ar(sig);
        sig = Limiter.ar(sig, 0.95, 0.01);
        sig = sig * master_amp.lag(0.05);
        Out.ar(out, sig);
    }).add;

    s.sync;

    // ----- 4.4 шины и группы (источник -> эффекты) --------------------
    ~grpSrc  = Group.new(s, \addToHead);
    ~grpFx   = Group.after(~grpSrc);
    ~busTest = Bus.audio(s, 2);
    ~busFx   = Bus.audio(s, 2);
    ~busRev  = Bus.audio(s, 2);
    s.sync;

    // ----- 4.5 постоянные синты: реверб, затем мастер -----------------
    ~rev = Synth.tail(~grpFx, \riss_verb, [
        \in, ~busFx.index, \out, ~busRev.index, \wet, 1.0
    ]);
    ~mst = Synth.tail(~grpFx, \ung_master_r, [
        \in_dry, ~busTest.index, \in_fx, ~busRev.index,
        \out, 0, \master_amp, 1.0
    ]);

    "test_riss — synthdefs и маршрутизация готовы.".postln;

    // ----- 4.6 окно управления ----------------------------------------
    { ~mBuildWindow.value }.defer;
});


// =====================================================================
// 5. Жёсткий сброс — выполнить этот абзац отдельно при необходимости.
// =====================================================================

(
    Routine.run({ s.bind { ~mReset.value(true) } });
)
