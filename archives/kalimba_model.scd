// =====================================================================
//  KALIMBA — сложная акустическая модель (синтетическая эмуляция)
//  Отдельный исполняемый инструмент с GUI.
//
//  Как запустить:
//    Открыть файл в SuperCollider IDE и выполнить весь блок ( Cmd/Ctrl + Enter,
//    поставив курсор внутри внешних скобок ).
//
//  Модель:
//    • Язычок = защемлённый металлический стержень (cantilever bar) —
//      модальный резонатор с НЕгармоническими обертонами
//      (отношения частот 1 : 6.267 : 17.55 : 34.39 : 56.84).
//    • Дека/корпус = банк деревянных мод-резонансов + фильтрация
//      «твёрдый ↔ мягкий».
//    • Внутренние резонансы, диффузия (allpass-сеть) и реверб с размером.
//    • Секвенсор играет натуральный минор (A aeolian).
//
//  Все параметры регулируются в реальном времени через окно GUI.
// =====================================================================

(
s.waitForBoot({
    fork {

        // ---------------------------------------------------------------
        //  ХРАНИЛИЩЕ ПАРАМЕТРОВ (живое, читается голосами и эффектами)
        // ---------------------------------------------------------------
        ~params = IdentityDictionary[
            // --- язычки (per-voice) ---
            \amp          -> 0.28,   // громкость щипка
            \tineMaterial -> 0.70,   // материал язычка: 0 мягкий метал -> 1 твёрдая сталь (звон/сустейн)
            \tineLength   -> 0.50,   // длина язычка: короткий(резкий) -> длинный(тёплый, дольше звучит)
            \bright       -> 0.55,   // яркость (баланс верхних обертонов)
            \inharm       -> 0.30,   // негармоничность (металлический «кланг»)
            \attackNoise  -> 0.35,   // шум ногтя/щипка в атаке
            \buzz         -> 0.12,   // характерный дребезг (mbira buzz)
            \decayScale   -> 1.00,   // общий множитель затухания

            // --- дека / корпус (FX) ---
            \boardHardness   -> 0.55, // материал деки: 0 мягкое дерево(глухо) -> 1 твёрдое(ярко, звонко)
            \resonanceLevel  -> 0.45, // уровень внутренних резонансов корпуса
            \bodySize        -> 0.50, // размер корпуса (ниже/выше моды)

            // --- пространство (FX) ---
            \diffusion   -> 0.40,    // диффузия (размытие, allpass-сеть)
            \roomSize    -> 0.55,    // размер реверберационного пространства
            \reverbTime  -> 3.20,    // время реверберации, сек
            \reverbMix   -> 0.32,    // доля реверба
            \damping     -> 0.50,    // затухание ВЧ в ревербе
            \drive       -> 0.08,    // лёгкое насыщение/сатурация
            \masterAmp   -> 0.90,    // общая громкость

            // --- секвенсор ---
            \bpm         -> 96,
            \density     -> 1.00,    // плотность нот (>1 = быстрее)
            \octave      -> 0,       // сдвиг октавы
            \chordChance -> 0.15     // вероятность аккорда
        ];

        // ---------------------------------------------------------------
        //  ГОЛОС: модель одного язычка (модальный синтез стержня)
        // ---------------------------------------------------------------
        SynthDef(\kalimbaTine, { |out=0, freq=440, amp=0.3, pan=0,
            tineMaterial=0.7, tineLength=0.5, bright=0.55, inharm=0.3,
            attackNoise=0.35, buzz=0.12, decayScale=1.0|

            var ratios, n, freqs, amps, rings, tilt, baseDecay, exc, sig, rattle;

            // Негармонические отношения мод защемлённого стержня (cantilever).
            ratios = [1, 6.267, 17.55, 34.39, 56.84];
            n = ratios.size;

            // Негармоничность слегка «растягивает» верхние моды (металлический кланг).
            freqs = freq * ratios * (1 + (inharm * [0, 0.008, 0.02, 0.04, 0.07]));

            // Спектральный наклон: яркость поднимает/убирает верхние обертоны.
            tilt = 1 + ((bright - 0.5) * 0.9 * Array.series(n, 0, 1));
            amps = ([1, 0.45, 0.28, 0.16, 0.09] * tilt).collect({ |a| a.max(0) });

            // Время звучания: материал металла + длина язычка + общий множитель.
            // Верхние моды затухают быстрее, чем основная.
            baseDecay = 2.4
                * tineMaterial.linexp(0, 1, 0.45, 1.7)
                * tineLength.linexp(0, 1, 0.50, 1.8)
                * decayScale;
            rings = baseDecay * [1, 0.6, 0.4, 0.25, 0.15];

            // Возбуждение: импульс удара + короткий шумовой щелчок ногтя.
            exc = (Impulse.ar(0) * 0.6)
                + (PinkNoise.ar(1)
                    * EnvGen.ar(Env.perc(0.0004, 0.004 + (attackNoise * 0.012)))
                    * attackNoise * 1.5);

            // Резонансный банк язычка.
            sig = DynKlank.ar(`[freqs, amps, rings], exc);

            // Дребезг (mbira buzz): волновой «fold» появляется на громких пиках.
            rattle = HPF.ar((sig * (1 + (buzz * 40))).fold2(0.18), 2600) * buzz * 0.6;
            sig = sig + rattle;

            sig = LeakDC.ar(sig);
            DetectSilence.ar(sig, 0.0004, 0.25, doneAction: 2);
            Out.ar(out, Pan2.ar(sig * amp, pan));
        }).add;

        // ---------------------------------------------------------------
        //  ЭФФЕКТЫ: дека/корпус + диффузия + реверб
        // ---------------------------------------------------------------
        SynthDef(\kalimbaFX, { |inBus, out=0,
            boardHardness=0.55, resonanceLevel=0.45, bodySize=0.5,
            diffusion=0.4, roomSize=0.55, reverbTime=3.2, reverbMix=0.32,
            damping=0.5, drive=0.08, masterAmp=0.9|

            var sig, mono, body, bFreqs, bAmps, bRings, sizeMul, cutoff, diff, wet;

            sig  = In.ar(inBus, 2);
            mono = sig.sum * 0.5;

            // Деревянные моды корпуса — «внутренние резонансы».
            // Размер корпуса смещает их вниз/вверх; твёрдость деки удлиняет звон.
            sizeMul = bodySize.linexp(0, 1, 1.6, 0.6);
            bFreqs  = [196, 287, 461, 698, 1140] * sizeMul;
            bAmps   = [1, 0.7, 0.5, 0.3, 0.18];
            bRings  = [0.32, 0.22, 0.16, 0.10, 0.06]
                        * boardHardness.linexp(0, 1, 0.5, 2.2);
            body = DynKlank.ar(`[bFreqs, bAmps, bRings], mono * 0.5);
            body = LeakDC.ar(body);
            sig  = sig + ((body ! 2) * resonanceLevel * 0.6);

            // Материал деки «твёрдый ↔ мягкий»: ФНЧ + добавка искры на твёрдой.
            cutoff = boardHardness.linexp(0, 1, 1400, 13000);
            sig = LPF.ar(sig, cutoff);
            sig = sig + (HPF.ar(sig, 3000) * boardHardness * 0.3);

            // Лёгкая сатурация дерева/металла.
            sig = (sig * (1 + (drive * 4))).tanh;

            // Диффузия: каскад allpass-фильтров, доля = diffusion.
            diff = sig;
            4.do {
                diff = AllpassC.ar(diff, 0.06, { rrand(0.012, 0.055) }.dup(2),
                    0.5 + (diffusion * 3));
            };
            sig = XFade2.ar(sig, diff, (diffusion * 2) - 1);

            // Реверберация с регулируемым размером пространства.
            wet = GVerb.ar(sig.sum * 0.4,
                roomsize:       roomSize.linlin(0, 1, 8, 120),
                revtime:        reverbTime,
                damping:        damping,
                inputbw:        0.5,
                spread:         15,
                drylevel:       0,
                earlyreflevel:  0.3,
                taillevel:      0.6,
                maxroomsize:    150);
            sig = (sig * (1 - (reverbMix * 0.6))) + (wet * reverbMix);

            sig = LeakDC.ar(sig) * masterAmp;
            Out.ar(out, Limiter.ar(sig, 0.95));
        }).add;

        s.sync;

        // ---------------------------------------------------------------
        //  АУДИО-ГРАФ
        // ---------------------------------------------------------------
        ~bus      = Bus.audio(s, 2);
        ~voiceGrp = Group.new(s);
        ~fx = Synth(\kalimbaFX, [
            \inBus, ~bus, \out, 0,
            \boardHardness, ~params[\boardHardness], \resonanceLevel, ~params[\resonanceLevel],
            \bodySize, ~params[\bodySize], \diffusion, ~params[\diffusion],
            \roomSize, ~params[\roomSize], \reverbTime, ~params[\reverbTime],
            \reverbMix, ~params[\reverbMix], \damping, ~params[\damping],
            \drive, ~params[\drive], \masterAmp, ~params[\masterAmp]
        ], ~voiceGrp, \addAfter);

        // ---------------------------------------------------------------
        //  ГАММА: натуральный минор (A aeolian), 3 октавы
        // ---------------------------------------------------------------
        ~root    = 57;                       // A3
        ~degrees = [0, 2, 3, 5, 7, 8, 10];   // натуральный минор
        ~pool    = ([0, 12, 24].collect({ |o| ~degrees + o + ~root })).flatten.sort;
        ~idx     = (~pool.size / 2).floor.asInteger;

        // ---------------------------------------------------------------
        //  ПАТТЕРН (читает живые параметры через Pfunc)
        // ---------------------------------------------------------------
        Pdef(\seq, Pbind(
            \instrument, \kalimbaTine,
            \out,   ~bus,
            \group, ~voiceGrp,
            \dur, Pfunc({
                var b = 60 / ~params[\bpm];
                [0.25, 0.5, 0.5, 0.75, 1].choose * b / ~params[\density];
            }),
            \midinote, Pfunc({
                var base, step;
                step = [-3, -2, -1, 1, 2, -1, 1, 3].choose;
                ~idx = (~idx + step).clip(0, ~pool.size - 1);
                base = ~pool[~idx] + (~params[\octave] * 12);
                if(~params[\chordChance].coin) {
                    [base,
                     ~pool[(~idx + 2).clip(0, ~pool.size - 1)] + (~params[\octave] * 12),
                     ~pool[(~idx + 4).clip(0, ~pool.size - 1)] + (~params[\octave] * 12)]
                } { base };
            }),
            \amp,          Pfunc({ ~params[\amp] * rrand(0.78, 1.0) }),
            \pan,          Pwhite(-0.4, 0.4),
            \tineMaterial, Pfunc({ ~params[\tineMaterial] }),
            \tineLength,   Pfunc({ ~params[\tineLength] }),
            \bright,       Pfunc({ ~params[\bright] }),
            \inharm,       Pfunc({ ~params[\inharm] }),
            \attackNoise,  Pfunc({ ~params[\attackNoise] }),
            \buzz,         Pfunc({ ~params[\buzz] }),
            \decayScale,   Pfunc({ ~params[\decayScale] })
        ));

        // ---------------------------------------------------------------
        //  GUI
        // ---------------------------------------------------------------
        {
            var w, mkSlider, header;
            ~sliders = IdentityDictionary.new;

            w = Window("KALIMBA — акустическая модель", Rect(120, 80, 560, 880))
                .background_(Color.grey(0.16));
            w.view.decorator = FlowLayout(w.view.bounds, 12 @ 12, 8 @ 5);

            header = { |t|
                StaticText(w, 510 @ 20).string_(t).align_(\center)
                    .font_(Font.monospace(12, bold: true))
                    .stringColor_(Color.white).background_(Color.grey(0.32));
            };

            // fx=true -> параметр сразу пишется в синт эффектов.
            mkSlider = { |label, key, spec, fx = false|
                var ez;
                ez = EZSlider(w, 510 @ 22, label, spec, { |e|
                    ~params[key] = e.value;
                    if(fx) { ~fx.set(key, e.value) };
                }, ~params[key], false, labelWidth: 175, numberWidth: 64);
                ez.setColors(
                    Color.grey(0.16), Color.white, Color.grey(0.4),
                    Color.grey(0.7), Color.black, Color.grey(0.25), Color.white);
                ~sliders[key] = ez;
                ez;
            };

            header.("— ЯЗЫЧКИ (металлические стержни) —");
            mkSlider.("Материал язычка",  \tineMaterial, ControlSpec(0, 1, \lin));
            mkSlider.("Длина язычка",      \tineLength,   ControlSpec(0, 1, \lin));
            mkSlider.("Яркость",           \bright,       ControlSpec(0, 1, \lin));
            mkSlider.("Негармоничность",   \inharm,       ControlSpec(0, 1, \lin));
            mkSlider.("Шум атаки (ноготь)",\attackNoise,  ControlSpec(0, 1, \lin));
            mkSlider.("Дребезг (buzz)",    \buzz,         ControlSpec(0, 1, \lin));
            mkSlider.("Затухание",         \decayScale,   ControlSpec(0.2, 3, \exp));
            mkSlider.("Громкость щипка",   \amp,          ControlSpec(0, 0.6, \lin));

            header.("— ДЕКА / КОРПУС —");
            mkSlider.("Материал деки (мягк↔тверд)", \boardHardness,  ControlSpec(0, 1, \lin), true);
            mkSlider.("Внутренние резонансы",       \resonanceLevel, ControlSpec(0, 1, \lin), true);
            mkSlider.("Размер корпуса",             \bodySize,       ControlSpec(0, 1, \lin), true);

            header.("— ПРОСТРАНСТВО (диффузия / реверб) —");
            mkSlider.("Диффузия",        \diffusion,  ControlSpec(0, 1, \lin),     true);
            mkSlider.("Размер реверба",  \roomSize,   ControlSpec(0, 1, \lin),     true);
            mkSlider.("Время реверба",   \reverbTime, ControlSpec(0.5, 12, \exp),  true);
            mkSlider.("Доля реверба",    \reverbMix,  ControlSpec(0, 1, \lin),     true);
            mkSlider.("Затухание ВЧ",    \damping,    ControlSpec(0, 1, \lin),     true);
            mkSlider.("Сатурация",       \drive,      ControlSpec(0, 1, \lin),     true);
            mkSlider.("Общая громкость", \masterAmp,  ControlSpec(0, 1.2, \lin),   true);

            header.("— СЕКВЕНСОР (A натуральный минор) —");
            mkSlider.("Темп (BPM)",         \bpm,         ControlSpec(40, 200, \lin, 1));
            mkSlider.("Плотность",          \density,     ControlSpec(0.25, 4, \exp));
            mkSlider.("Октава",             \octave,      ControlSpec(-2, 2, \lin, 1));
            mkSlider.("Вероятность аккорда",\chordChance, ControlSpec(0, 1, \lin));

            StaticText(w, 510 @ 8).string_("");

            Button(w, 120 @ 32)
                .states_([["▶ Играть", Color.white, Color.new(0.15, 0.5, 0.2)]])
                .font_(Font.monospace(13, bold: true))
                .action_({ Pdef(\seq).play(quant: 0) });

            Button(w, 120 @ 32)
                .states_([["■ Стоп", Color.white, Color.new(0.55, 0.15, 0.15)]])
                .font_(Font.monospace(13, bold: true))
                .action_({ Pdef(\seq).stop });

            Button(w, 120 @ 32)
                .states_([["✦ Щипок", Color.white, Color.new(0.2, 0.3, 0.55)]])
                .font_(Font.monospace(13, bold: true))
                .action_({
                    var nn = ~pool.choose + (~params[\octave] * 12);
                    Synth(\kalimbaTine, [
                        \out, ~bus, \freq, nn.midicps, \amp, ~params[\amp],
                        \pan, rrand(-0.3, 0.3),
                        \tineMaterial, ~params[\tineMaterial], \tineLength, ~params[\tineLength],
                        \bright, ~params[\bright], \inharm, ~params[\inharm],
                        \attackNoise, ~params[\attackNoise], \buzz, ~params[\buzz],
                        \decayScale, ~params[\decayScale]
                    ], ~voiceGrp);
                });

            Button(w, 120 @ 32)
                .states_([["⚄ Случайно", Color.white, Color.new(0.4, 0.3, 0.5)]])
                .font_(Font.monospace(13, bold: true))
                .action_({
                    [\tineMaterial, \tineLength, \bright, \inharm, \attackNoise, \buzz,
                     \boardHardness, \resonanceLevel, \bodySize, \diffusion].do { |k|
                        ~sliders[k].valueAction_(rrand(0.1, 0.9));
                    };
                });

            w.onClose = {
                Pdef(\seq).stop;
                ~fx.free;
                ~voiceGrp.free;
                ~bus.free;
            };

            w.front;
            "KALIMBA готова. Нажми ▶ Играть или ✦ Щипок.".postln;
        }.defer;

    };
});
)
