// =====================================================================
// tests/test_monade.scd
// UNGRUND — изолированный тест функции `monade`  (звуковой класс 1 из 8)
//
// ТЕМБР: связка из 10 пружин длиной ~10 м, колеблющихся в масле.
// Слышны соприкосновения пружин; среда (масло) демпфирует и затемняет;
// левая сторона приглушена — дальний конец связки, глубже в среде.
//
// ТОНЫ В НОТАХ:
// 10 пружин — независимые тоны n1…n10, заданные В НОТАХ (MIDI-ноты,
// A4 = 69 = 440 Гц). Рядом с каждым слайдером — имя ноты с центами
// (напр. F#2, C#3 -12¢). Слайдер непрерывный: целое значение = чистая
// нота, дробное = микротон (для биений ставьте два тона близко).
// Внутри SynthDef нота переводится в Гц (.midicps); пружины резонируют
// на полученной частоте. Значения n1…n10 по умолчанию — СОГЛАСОВАННАЯ
// связка: настроена композитором вручную (2026-05-22).
//
// СТОЛКНОВЕНИЯ: низкая обертоновая составляющая убрана (сухой контакт
// HPF 2.8 кГц); низкие пружины почти не возбуждаются ударами и громче
// в миксе — низкочастотные тоны держат фундамент.
//
// Синтез — физическое моделирование (НЕ запись, Аксиома II):
//   соприкосновения — Dust2; каждая пружина — allpass (дисперсия) +
//   CombC (резонанс на частоте тона); тело — непрерывный низкий шум;
//   масло — LPF + вязкий wobble + короче звон.
//
// СОХРАНЕНИЕ: кнопка "save" выводит блок всех 20 параметров (с именами
// нот) в post-окно и в файл tests/test_monade_params.txt.
//
// ВНИМАНИЕ: тембр радикально переопределяет класс monade за пределы
// reference_v2.md §C. Ноты равномерного строя (A440) — не 3-предельная
// решётка UNGRUND: чистый строй 94 Гц = F#2 +28¢ (вводится дробной
// нотой). «Связка пружин» — рабочий бриф синтеза (Аксиома VII).
//
// КАК ПОЛЬЗОВАТЬСЯ
//   1. Выделить весь файл (Cmd-A), выполнить (Shift-Return).
//   2. "play" — запуск, "release" — отпускание со спадом.
//   3. Слайдеры / числовые поля двигаются вживую во время звучания.
//   4. "random частоты"   — случайные значения 10 тонов-нот.
//      "random параметры" — случайные значения 10 параметров тембра.
//   5. "save"   — блок параметров в текст (post-окно + файл).
//   6. "запись аудио" — тумблер: финальный микс -> WAV-файл в tests/.
//   7. "паника" — полный сброс. Cmd-. безопасен. Закрытие окна = сброс.
//
// ПАРАМЕТРЫ (умолчания = согласованная связка)
//   n1…n10     тоны 10 пружин (MIDI-ноты)         12–96
//   amp        громкость                          0.0–1.0       0.883
//   atk / rel  атака / спад огибающей             0.5–30 / 60 s 1.81 / 5.68
//   density    частота соприкосновений            0.2–150 /s    8.65
//   contact    громкость сухих контактов          0–1           0.464
//   decay      время звона пружин                 0.2–8 s       3.74
//   disperse   дисперсия — металлический «зуммер» 0–1           0.605
//   oil        вязкость среды                     0–1           0.725
//   muffle     приглушение левой стороны          0–1           0.204
//   revSend    посыл в tape-reverb                0–1           0.06
// =====================================================================


// =====================================================================
// 0. Каталог параметров, директория файла, конвертация нот.
// =====================================================================

~mDir = thisProcess.nowExecutingPath !? { |p| p.dirname };

~paramOrder = [
    \n1, \n2, \n3, \n4, \n5, \n6, \n7, \n8, \n9, \n10,
    \amp, \atk, \rel, \density, \contact, \decay, \disperse, \oil, \muffle, \revSend
];

~params = (
    n1: 29.91, n2: 43.87, n3: 54.2, n4: 18.97, n5: 27.2,
    n6: 26.68, n7: 80.12, n8: 87.0, n9: 58.14, n10: 16.69,
    amp: 0.883, atk: 1.814, rel: 5.678, density: 8.65, contact: 0.464,
    decay: 3.74, disperse: 0.605, oil: 0.725, muffle: 0.204, revSend: 0.06
);

// MIDI-нота -> имя ноты (A4 = 69, MIDI 0 = C-1)
~noteName = { |midi|
    var names = #["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];
    var n = midi.round.asInteger;
    names[n % 12] ++ (n.div(12) - 1)
};

// MIDI-нота -> "имя +центы" для отображения у слайдера
~noteLabel = { |midi|
    var cents = ((midi - midi.round) * 100).round.asInteger;
    ~noteName.value(midi) ++ if(cents == 0, { "" }, {
        " " ++ if(cents > 0, { "+" }, { "" }) ++ cents ++ "¢"
    })
};


// =====================================================================
// 1. Сброс — идемпотентный демонтаж (освобождает синты, шины, группы).
// =====================================================================

~mReset = { |verbose = true|
    if(s.isRecording)  { s.stopRecording };
    if(~synth.notNil)  { ~synth.free;  ~synth = nil };
    if(~rev.notNil)    { ~rev.free;    ~rev = nil };
    if(~mst.notNil)    { ~mst.free;    ~mst = nil };
    if(~grpSrc.notNil) { ~grpSrc.freeAll; ~grpSrc.free; ~grpSrc = nil };
    if(~grpFx.notNil)  { ~grpFx.freeAll;  ~grpFx.free;  ~grpFx = nil };
    if(~busTest.notNil) { ~busTest.free; ~busTest = nil };
    if(~busFx.notNil)   { ~busFx.free;   ~busFx = nil };
    if(~busRev.notNil)  { ~busRev.free;  ~busRev = nil };
    if(verbose) { "test_monade — сброс выполнен.".postln };
};


// =====================================================================
// 2. Управление — статус, запуск, отпускание, random, запись, сохранение.
// =====================================================================

~mStatus = { |str|
    { if(~statusTxt.notNil) { ~statusTxt.string = "monade — " ++ str } }.defer;
};

~mPlay = {
    var node, args;
    if(~grpSrc.isNil) {
        "test_monade — сервер ещё не готов.".postln;
    } {
        if(~synth.notNil) { ~synth.set(\gate, 0) };
        args = (~paramOrder.collect { |k| [k, ~params[k]] }.flatten)
                ++ [\out, ~busTest.index, \fx_bus, ~busFx.index, \gate, 1];
        node = Synth(\monade, args, ~grpSrc);
        node.onFree({ if(~synth == node) { ~synth = nil; ~mStatus.value("свободно") } });
        ~synth = node;
        ~mStatus.value("звучит — атака " ++ ~params[\atk].round(0.1) ++ " s");
    };
};

~mRelease = {
    if(~synth.notNil) {
        ~synth.set(\gate, 0);
        ~mStatus.value("отпускание — спад " ++ ~params[\rel].round(0.1) ++ " s");
    } {
        ~mStatus.value("не звучит");
    };
};

// random — два независимых рандомайзера: тоны-ноты и параметры тембра.
~mRandomNotes = {
    if(~ez.notNil) {
        ~paramOrder.copyRange(0, 9).do { |key|
            var ez = ~ez[key];
            if(ez.notNil) { ez.valueAction_(ez.controlSpec.map(1.0.rand)) };
        };
        ~mStatus.value("random — случайные тоны (10 нот)");
    };
};

~mRandomParams = {
    if(~ez.notNil) {
        ~paramOrder.copyRange(10, 19).do { |key|
            var ez = ~ez[key];
            if(ez.notNil) { ez.valueAction_(ez.controlSpec.map(1.0.rand)) };
        };
        ~mStatus.value("random — случайные параметры тембра (10)");
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
            ~mDir +/+ ("test_monade_" ++ Date.getDate.stamp ++ ".wav")
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
    lines = ~paramOrder.collect { |k, i|
        var v = ~params[k].round(0.001);
        var s = (k.asString ++ ":").padRight(8) ++ v.asString;
        if(i < 10) {
            s = s.padRight(20) ++ "(" ++ ~noteLabel.value(~params[k])
                ++ ", " ++ ~params[k].midicps.round(0.1) ++ " Hz)";
        };
        s;
    };
    text = "// ===== test_monade — параметры · " ++ Date.getDate.stamp ++ " =====\n"
         ++ lines.join("\n")
         ++ "\n// =====================================================";
    text.postln;
    if(~mDir.notNil) {
        path = ~mDir +/+ "test_monade_params.txt";
        File.use(path, "w", { |f| f.write(text) });
        ~mStatus.value("параметры сохранены -> " ++ path.basename);
    } {
        ~mStatus.value("параметры выведены в post-окно");
    };
};


// =====================================================================
// 3. Конструкторы слайдеров + окно (две колонки: тоны-ноты | тембр).
// =====================================================================

// Слайдер тона: значение — MIDI-нота; справа StaticText с именем ноты.
~mNoteSlider = { |y, key, label, spec|
    var ez, txt;
    ez = EZSlider(~win, Rect(20, y, 332, 24), label, spec, { |e|
        ~params[key] = e.value;
        if(~noteTxt[key].notNil) { ~noteTxt[key].string = ~noteLabel.value(e.value) };
        if(~synth.notNil) { ~synth.set(key, e.value) };
    }, ~params[key]);
    ez.labelView.stringColor_(Color.white);
    ez.round_(0.01);
    ~ez[key] = ez;
    txt = StaticText(~win, Rect(360, y, 106, 24))
        .stringColor_(Color.gray(0.88))
        .font_(Font("Menlo", 11, true))
        .string_(~noteLabel.value(~params[key]));
    ~noteTxt[key] = txt;
};

// Слайдер тембра: подпись белым, значение пишется в ~params.
~mSlider = { |x, y, key, label, spec|
    var ez;
    ez = EZSlider(~win, Rect(x, y, 420, 24), label, spec, { |e|
        ~params[key] = e.value;
        if(~synth.notNil) { ~synth.set(key, e.value) };
    }, ~params[key]);
    ez.labelView.stringColor_(Color.white);
    ~ez[key] = ez;
};

~mBuildWindow = {
    if(~win.notNil) { ~win.close };
    ~ez = ();
    ~noteTxt = ();
    ~win = Window("UNGRUND — test_monade  (1/8 · Grund █) — связка пружин в масле",
                  Rect(80, 60, 920, 478))
        .background_(Color.gray(0.12));

    StaticText(~win, Rect(20, 12, 880, 22))
        .string_("monade — связка из 10 пружин (~10 м) в масле · тоны в нотах")
        .stringColor_(Color.gray(0.92))
        .font_(Font("Menlo", 13, true));

    ~statusTxt = StaticText(~win, Rect(20, 36, 880, 20))
        .string_("monade — готово, нажмите play")
        .stringColor_(Color.gray(0.70))
        .font_(Font("Menlo", 11));

    StaticText(~win, Rect(20, 58, 880, 16))
        .string_("n1–n10 — MIDI-ноты (дробные = микротон) · справа имя ноты · save -> блок в текст")
        .stringColor_(Color.gray(0.45))
        .font_(Font("Menlo", 9));

    StaticText(~win, Rect(20, 80, 446, 16))
        .string_("ТОНЫ ПРУЖИН (ноты) — настраиваются вручную")
        .stringColor_(Color.gray(0.62))
        .font_(Font("Menlo", 10, true));

    StaticText(~win, Rect(480, 80, 420, 16))
        .string_("ТЕМБР И СРЕДА")
        .stringColor_(Color.gray(0.62))
        .font_(Font("Menlo", 10, true));

    // ----- левая колонка: 10 тонов-нот --------------------------------
    [29.91, 43.87, 54.2, 18.97, 27.2, 26.68, 80.12, 87.0, 58.14, 16.69].do { |dflt, i|
        ~mNoteSlider.value(100 + (i * 27), ("n" ++ (i + 1)).asSymbol,
            "n" ++ (i + 1), ControlSpec(12, 96, \lin, 0, dflt));
    };

    // ----- правая колонка: 10 параметров тембра -----------------------
    ~mSlider.value(480, 100, \amp,      "amp",      ControlSpec(0.0, 1.0, \lin, 0, 0.883));
    ~mSlider.value(480, 127, \atk,      "atk  s",   ControlSpec(0.5, 30, \exp, 0, 1.814, " s"));
    ~mSlider.value(480, 154, \rel,      "rel  s",   ControlSpec(0.5, 60, \exp, 0, 5.678, " s"));
    ~mSlider.value(480, 181, \density,  "density",  ControlSpec(0.2, 150, \exp, 0, 8.65, " /s"));
    ~mSlider.value(480, 208, \contact,  "contact",  ControlSpec(0.0, 1.0, \lin, 0, 0.464));
    ~mSlider.value(480, 235, \decay,    "decay  s", ControlSpec(0.2, 8.0, \exp, 0, 3.74, " s"));
    ~mSlider.value(480, 262, \disperse, "disperse", ControlSpec(0.0, 1.0, \lin, 0, 0.605));
    ~mSlider.value(480, 289, \oil,      "oil",      ControlSpec(0.0, 1.0, \lin, 0, 0.725));
    ~mSlider.value(480, 316, \muffle,   "muffle",   ControlSpec(0.0, 1.0, \lin, 0, 0.204));
    ~mSlider.value(480, 343, \revSend,  "revSend",  ControlSpec(0.0, 1.0, \lin, 0, 0.06));

    // ----- кнопки -----------------------------------------------------
    Button(~win, Rect(20, 384, 104, 42))
        .states_([["play", Color.gray(0.95), Color.gray(0.25)]])
        .font_(Font("Menlo", 14, true))
        .action_({ ~mPlay.value });

    Button(~win, Rect(132, 384, 104, 42))
        .states_([["release", Color.gray(0.95), Color.gray(0.25)]])
        .font_(Font("Menlo", 14, true))
        .action_({ ~mRelease.value });

    Button(~win, Rect(244, 384, 196, 42))
        .states_([["random — частоты", Color.white, Color(0.18, 0.34, 0.44)]])
        .font_(Font("Menlo", 12, true))
        .action_({ ~mRandomNotes.value });

    Button(~win, Rect(448, 384, 196, 42))
        .states_([["random — параметры", Color.white, Color(0.40, 0.30, 0.18)]])
        .font_(Font("Menlo", 12, true))
        .action_({ ~mRandomParams.value });

    Button(~win, Rect(652, 384, 248, 42))
        .states_([["save — параметры в текст", Color.white, Color(0.20, 0.40, 0.24)]])
        .font_(Font("Menlo", 12, true))
        .action_({ ~mSave.value });

    ~recBtn = Button(~win, Rect(20, 436, 300, 28))
        .states_([
            ["● запись аудио",      Color.white,      Color(0.50, 0.13, 0.13)],
            ["■ остановить запись", Color.gray(0.08), Color(0.95, 0.78, 0.25)]
        ])
        .font_(Font("Menlo", 11, true))
        .action_({ |b| if(b.value == 1) { ~mRecStart.value } { ~mRecStop.value } });

    Button(~win, Rect(328, 436, 572, 28))
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

    // ----- 4.1 SynthDef функции — связка из 10 пружин -----------------
    // n1..n10 — MIDI-ноты пружин; внутри переводятся в Гц (.midicps).
    SynthDef(\monade, { |out = 0, fx_bus = 18,
                        n1 = 29.91, n2 = 43.87, n3 = 54.2, n4 = 18.97, n5 = 27.2,
                        n6 = 26.68, n7 = 80.12, n8 = 87.0, n9 = 58.14, n10 = 16.69,
                        amp = 0.883, atk = 1.814, rel = 5.678,
                        density = 8.65, contact = 0.464,
                        decay = 3.74, disperse = 0.605, oil = 0.725, muffle = 0.204,
                        revSend = 0.06, gate = 1|
        var env, decayL, oilL, dispL, muffL,
            sway, dens, contacts, ticks, metal, body, notes,
            springs, bundle, cutBase, sigL, sigR;
        var nSprings = 10;

        env = EnvGen.kr(Env.asr(atk, 1, rel, curve: -4), gate, doneAction: 2);

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
            // низкие пружины почти не возбуждаются ударами, громче в миксе
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
        bundle  = LeakDC.ar(bundle);

        sigL = LPF.ar(bundle, (cutBase * (1 - (muffL * 0.82))).clip(180, 6000));
        sigL = DelayC.ar(sigL, 0.05, muffL * 0.02);
        sigL = sigL * (1 - (muffL * 0.4));
        sigR = bundle;

        sigL = sigL * env * amp.lag(0.05) * (0.78 + (sway * 0.22));
        sigR = sigR * env * amp.lag(0.05) * (0.78 + (sway * 0.22));

        Out.ar(out,    [sigL, sigR]);
        Out.ar(fx_bus, [sigL, sigR] * revSend.lag(0.1));
    }).add;

    // ----- 4.2 tape_reverb (из ungrund_0009, без изменений) -----------
    SynthDef(\tape_reverb_t, { |in = 18, out = 20, wet = 0.85|
        var sig, ratesL, ratesR, diffL, diffR, combL, combR, rolloff, procL, procR;
        sig    = In.ar(in, 2);
        sig    = DelayC.ar(sig, 0.05, 0.012);
        ratesL = [0.17, 0.24, 0.19, 0.31];
        ratesR = [0.21, 0.16, 0.28, 0.23];
        diffL  = sig[0];
        diffR  = sig[1];
        ratesL.do { |r| diffL = AllpassC.ar(diffL, 0.08, LFNoise2.kr(r).range(0.010, 0.070), 1.2) };
        ratesR.do { |r| diffR = AllpassC.ar(diffR, 0.08, LFNoise2.kr(r).range(0.010, 0.070), 1.2) };
        combL   = CombC.ar(diffL, 0.5, 0.087 + LFNoise2.kr(0.21).range(-0.002, 0.002), 2.5);
        combR   = CombC.ar(diffR, 0.5, 0.113 + LFNoise2.kr(0.17).range(-0.002, 0.002), 2.8);
        rolloff = 3500 + LFNoise2.kr(0.09).range(-300, 300);
        procL   = LPF.ar(combL, rolloff);
        procR   = LPF.ar(combR, rolloff);
        Out.ar(out, [procL, procR] * wet);
    }).add;

    // ----- 4.3 мастер: сумма (сухой + реверб), LeakDC, Limiter --------
    SynthDef(\ung_master_t, { |in_dry = 16, in_fx = 20, out = 0, master_amp = 1.0|
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
    ~rev = Synth.tail(~grpFx, \tape_reverb_t, [
        \in, ~busFx.index, \out, ~busRev.index, \wet, 1.0
    ]);
    ~mst = Synth.tail(~grpFx, \ung_master_t, [
        \in_dry, ~busTest.index, \in_fx, ~busRev.index,
        \out, 0, \master_amp, 1.0
    ]);

    "test_monade — synthdefs и маршрутизация готовы.".postln;

    // ----- 4.6 окно управления ----------------------------------------
    { ~mBuildWindow.value }.defer;
});


// =====================================================================
// 5. Жёсткий сброс — выполнить этот абзац отдельно при необходимости.
// =====================================================================

(
    Routine.run({ s.bind { ~mReset.value(true) } });
)
