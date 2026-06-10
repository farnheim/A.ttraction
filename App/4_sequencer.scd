// =====================================================================
// App/4_sequencer.scd
// UNGRUND · SEQUENCER — блок-форма во времени (Tdef на TempoClock)
//
// Логика воспроизведения. CONFIG = блочный таймлайн в стиле UNGRUND
// (archives/scheme.md): список блоков, у каждого время старта (s),
// активные слои и опциональные правки параметров. Логика = Tdef-
// планировщик на TempoClock (серверное время, НЕ SystemClock/Thread).
//
// Демонстрационный таймлайн ниже — компактный (~80 c) набросок в духе
// ungrund.0001 (schicht/substratumwalk/94 Hz): alpha-Grund держится,
// theta-глазурь входит, beta-события эпизодически, eta в конце.
// НЕ зациклен бесконечно — по последнему блоку вызывает ~seqStop.
//
// УПРАВЛЕНИЕ:  ~seqStart.()  — запустить таймлайн с t=0
//              ~seqStop.()   — остановить, погасить все слои
// Старт делает 1_app.scd в самом конце загрузки.
//
// Зависимости: микшер (~mixSet, ~mixerLayers), синт-слои. Загружать
//   последним (см. 1_app.scd).
// =====================================================================


// ===== CONFIG — edit here ============================================
(
~cfg_seq = (
    tempo: 1.0,    // ударов в секунду TempoClock (1 = время в секундах)

    // Блочный таймлайн. Каждый блок:
    //   t      — момент старта блока, s (от начала)
    //   active — слои, поднятые до своей рабочей громкости
    //   gone   — слои, опущенные в тишину (vol 0)
    //   set    — опциональные правки параметров слоёв: [\layer, \param, value]
    // Слои, не упомянутые в блоке, сохраняют прежнее состояние.
    timeline: [
        ( t: 0,   active: [\alpha],                 gone: [\beta, \gamma, \delta, \epsilon, \zeta, \theta],
          set: [[\alpha, \amp, 0.22]] ),
        ( t: 4,   active: [\theta],                 gone: [] ),                       // §0001: theta с t=4
        ( t: 20,  active: [\beta],                   gone: [] ),                       // beta-события
        ( t: 36,  active: [\delta],                  gone: [],
          set: [[\delta, \freq, 188]] ),                                              // 94×2 = F#3
        ( t: 52,  active: [\epsilon],               gone: [\delta] ),
        ( t: 68,  active: [],                         gone: [\epsilon, \beta, \theta] ),
        ( t: 72,  active: [\eta],                 gone: [\alpha] ),               // eta: цезура
        ( t: 80,  active: [],                         gone: [\eta], finish: true )  // конец таймлайна
    ]
);


// ===== LOGIC — Tdef scheduler ========================================
// ОДИН клок на сессию: повторное выполнение файла НЕ создаёт новый
// (permanent-клок переживает Cmd-., плодить их = утечка планировщиков).
// Освобождает клок только ~appCleanup (1_app.scd).
~seqClock = ~seqClock ?? { TempoClock.new(~cfg_seq.tempo).permanent_(true) };
~seqClock.tempo = ~cfg_seq.tempo;

// громкость слоя — НАПРЯМУЮ в Ndef-роутер, НЕ через ~mixSet: ~mixSet пишет
// значение в ~cfg_mixer.levels, и прогон секвенсора перетирал бы исходное
// сведение нулями (~mixUnsolo после этого «восстанавливал» бы нули).
// Как у ~mixSolo: runtime-громкость отдельно, CONFIG-сведение неприкосновенно.
~seqSetVol = { |layer, v|
    Ndef(("mix_" ++ layer).asSymbol).set(\vol, v);
    if(~mixerGuiSync.notNil) { ~mixerGuiSync.(layer, \vol, v) };
};
// поднять слой до рабочей громкости из таблицы микшера
~seqRaise = { |layer|
    var lv = ~cfg_mixer.levels[layer];
    if(lv.notNil) { ~seqSetVol.(layer, lv.vol) };
};
// опустить слой в тишину
~seqMute = { |layer| ~seqSetVol.(layer, 0) };

// применить один блок таймлайна
~seqApplyBlock = { |block|
    (block.active   ? []).do { |l| ~seqRaise.(l) };
    (block.gone     ? []).do { |l| ~seqMute.(l) };
    // block[\set] (НЕ block.set): .set — это метод Event, перекрывает ключ
    (block[\set]    ? []).do { |triple|
        Ndef(triple[0].asSymbol).set(triple[1], triple[2]);
    };
};

// состояние для окна визуализации (7_viz.scd): индекс текущего блока и
// момент старта таймлайна (для расчёта playhead). nil, пока не запущен.
~seqCurrentBlock = ~seqCurrentBlock ? nil;
~seqStartTime    = ~seqStartTime    ? nil;

Tdef(\ung_sequencer, {
    var line = ~cfg_seq.timeline;
    var prevT = 0;
    line.do { |block, i|
        var wait = (block.t - prevT).max(0);
        if(wait > 0) { wait.wait };
        prevT = block.t;
        ~seqCurrentBlock = i;                          // для виз-окна
        ("seq @ " ++ block.t ++ "s  block " ++ i).postln;
        ~seqApplyBlock.(block);
        if(block.finish == true) {
            "seq — таймлайн завершён.".postln;
            { ~seqStop.value }.defer(0.1);
        };
    };
}).clock_(~seqClock).quant_(0);

// --- старт / стоп ---------------------------------------------------
~seqStart = {
    // исходное состояние: все слои в тишину, затем блок t=0 поднимет нужные
    ~mixerLayers.do { |l| ~seqMute.(l) };
    ~seqCurrentBlock = nil;
    ~seqStartTime    = Main.elapsedTime;     // отметка для playhead виз-окна (wall-clock)
    Tdef(\ung_sequencer).stop;
    Tdef(\ung_sequencer).play(~seqClock);
    "seq — старт таймлайна.".postln;
};

~seqStop = {
    Tdef(\ung_sequencer).stop;
    ~mixerLayers.do { |l| ~seqMute.(l) };
    ~seqStartTime    = nil;
    ~seqCurrentBlock = nil;
    "seq — стоп, слои погашены.".postln;
};

"4_sequencer — готов (~seqStart / ~seqStop).".postln;
)
