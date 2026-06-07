// =====================================================================
// App/1_app.scd
// UNGRUND · APP — оркестратор: бутстрап, загрузка слоёв, запуск, очистка
//
// ЕДИНАЯ ТОЧКА ВХОДА. Выполнить весь файл (Cmd-A, Shift-Return):
//   1. boot сервера;
//   2. установка базовой директории (thisProcess.nowExecutingPath);
//   3. аллокация шин (~busDry, ~busFxSend, ~busFxReturn);
//   4. загрузка остальных файлов в ПОРЯДКЕ ЗАВИСИМОСТЕЙ:
//        synths/*  -> 6_effects -> 2_mixer -> 3_lfo -> 5_control -> 4_sequencer
//      (синты и эффекты определяются ДО того, как микшер их маршрутизирует;
//       lfo/control — после микшера; секвенсор — последним);
//   5. s.sync между асинхронными батчами;
//   6. запуск демонстрационного таймлайна.
//
// ОСТАНОВКА:  Cmd-.  безопасен (оставляет чистый сервер при перезапуске
//   Ndef'ов с fadeTime). Полная очистка — абзац «CLEANUP» внизу файла
//   (или ~appCleanup.()).
//
// КАЖДЫЙ файл идемпотентен при перезагрузке: Ndef/Tdef/MIDIdef-ключи
//   ЗАМЕНЯЮТСЯ, не стакаются — любой слой можно итерировать отдельно,
//   просто перевыполнив его файл.
// =====================================================================


// ===== CONFIG — edit here ============================================
(
~cfg_app = (
    autostart:   true,     // запускать ли таймлайн секвенсора после загрузки
    sortSynths:  true      // грузить synths/*.scd в алфавитном порядке
);
)


// ===== LOGIC — boot, load, wire, start ===============================
(
~appDir = thisProcess.nowExecutingPath.dirname;   // база = папка App/

// --- master cleanup (идемпотентно) ----------------------------------
~appCleanup = { |verbose = true|
    Tdef.all.do(_.clear);
    Pdef.all.do(_.clear);
    MIDIdef.all.do(_.free);
    Ndef.all.do(_.clear);
    if(~busDry.notNil)      { ~busDry.free;      ~busDry = nil };
    if(~busFxSend.notNil)   { ~busFxSend.free;   ~busFxSend = nil };
    if(~busFxReturn.notNil) { ~busFxReturn.free; ~busFxReturn = nil };
    s.freeAll;
    if(verbose) { "UNGRUND app — очистка выполнена.".postln };
};

s.waitForBoot({

    // --- 0. чистый старт ---
    ~appCleanup.value(false);

    // --- 1. шины (никаких магических индексов) ---
    ~busDry      = Bus.audio(s, 2);   // сухой сум слоёв -> мастер
    ~busFxSend   = Bus.audio(s, 2);   // посыл слоёв -> эффекты (§K)
    ~busFxReturn = Bus.audio(s, 2);   // возврат эффектов -> мастер (§K)
    s.sync;

    // --- 2. синт-слои: глоб App/synths/*.scd ---
    ~synthFiles = (~appDir +/+ "synths" +/+ "*.scd").pathMatch;
    if(~cfg_app.sortSynths) { ~synthFiles = ~synthFiles.sort };
    if(~synthFiles.isEmpty) {
        "UNGRUND app — НЕ найдено ни одного синт-слоя в synths/".warn;
    };
    ~synthFiles.do { |path|
        ("  load synth: " ++ path.basename).postln;
        path.load;
    };
    s.sync;

    // --- 3. эффекты (читают ~busFxSend, пишут ~busFxReturn) ---
    (~appDir +/+ "6_effects.scd").load;
    s.sync;

    // --- 4. микшер (маршрутизирует слои + мастер) ---
    (~appDir +/+ "2_mixer.scd").load;
    s.sync;

    // --- 5. lfo (автоматизация — после микшера) ---
    (~appDir +/+ "3_lfo.scd").load;
    s.sync;

    // --- 6. control (MIDI — после микшера/lfo) ---
    (~appDir +/+ "5_control.scd").load;
    s.sync;

    // --- 7. секвенсор (последним) ---
    (~appDir +/+ "4_sequencer.scd").load;
    s.sync;

    "UNGRUND app — все слои загружены и смаршрутизированы.".postln;

    // --- 8. старт ---
    if(~cfg_app.autostart) {
        ~seqStart.value;
        "UNGRUND app — таймлайн запущен (~seqStop для остановки).".postln;
    } {
        "UNGRUND app — autostart выключен; запустите ~seqStart.value.".postln;
    };
});
)


// =====================================================================
// CLEANUP — выполнить этот абзац отдельно для полного сброса.
// (Cmd-. останавливает звук; этот блок освобождает шины/Ndef/Tdef/MIDIdef.)
// =====================================================================

(
~appCleanup.value(true);
)
