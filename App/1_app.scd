// =====================================================================
// App/1_app.scd
// UNGRUND · APP — оркестратор: бутстрап, загрузка слоёв, запуск, очистка
//
// ЕДИНАЯ ТОЧКА ВХОДА. Весь файл — ОДИН блок ( ... ). Выполнить целиком
// (Cmd-A, затем Shift-Return) — или поставить курсор внутрь блока и Cmd-Enter:
//   1. boot сервера;
//   2. установка базовой директории (thisProcess.nowExecutingPath);
//   3. аллокация шин (~busDry, ~busFxSend, ~busFxReturn);
//   4. загрузка остальных файлов в ПОРЯДКЕ ЗАВИСИМОСТЕЙ:
//        synths/*  -> 6_effects -> 2_mixer -> 3_lfo -> 5_control -> 4_sequencer
//      (синты и эффекты определяются ДО того, как микшер их маршрутизирует;
//       lfo/control — после микшера; секвенсор — последним). Каждый модуль,
//       кроме synths, грузится ТОЛЬКО если включён своим флагом в ~cfg_app;
//   5. s.sync между асинхронными батчами;
//   6. авто-загрузка пресета "default" каждого слоя (App/presets/<layer>/default.scd, если есть);
//   7. окно микшера (~openMixer) и опционально окно визуализации (~openViz).
//
// ФАЗА САУНД-ДИЗАЙНА (умолчания ниже): сервер бутится, все synths/*.scd
//   звучат на уровнях микшера, эффекты включены, открыто окно микшера —
//   БЕЗ секвенсора, БЕЗ LFO, БЕЗ MIDI. Включение любого из них — флип
//   одного флага в ~cfg_app.
//
// ОСТАНОВКА:  Cmd-.  безопасен (оставляет чистый сервер при перезапуске
//   Ndef'ов с fadeTime). Полная очистка (шины/Ndef/Tdef/MIDIdef/окна) —
//   выполнить `~appCleanup.value(true)` (раскомментировать блок CLEANUP
//   внизу файла и выполнить, либо набрать вызов в post-окне).
//
// КАЖДЫЙ файл идемпотентен при перезагрузке: Ndef/Tdef/MIDIdef-ключи
//   ЗАМЕНЯЮТСЯ, не стакаются — любой слой можно итерировать отдельно,
//   просто перевыполнив его файл.
// =====================================================================


// ===== CONFIG — edit here ============================================
(
// Единая панель управления приложением. Флип одного флага меняет режим.
~cfg_app = (
    layers:          nil,     // nil = все synths/*.scd; либо [\alpha, \theta] — грузить только эти
    autoPreset:      true,    // авто-загрузка пресета "default" слоя, если есть App/presets/<layer>/default.scd
    enableEffects:   true,    // tape reverb + ping-pong delay (6_effects.scd)
    enableMixer:     true,    // маршрутизация слоёв + мастер (2_mixer.scd)
    enableMixerGui:  true,    // открыть окно микшера после загрузки
    enableLfo:       false,   // ВЫКЛ на фазе саунд-дизайна (3_lfo.scd)
    enableControl:   false,   // MIDI — ВЫКЛ по умолчанию (5_control.scd)
    enableSequencer: false,   // ВЫКЛ — блочный таймлайн (4_sequencer.scd)
    enableVizGui:    false,    // окно визуализации seq+LFO (имеет смысл только при enableLfo/Sequencer)
    autostart:       false,    // не запускать таймлайн (секвенсор) автоматически
    sortSynths:      true      // грузить synths/*.scd в алфавитном порядке
);


// ===== LOGIC — boot, load, wire, start ===============================
~appDir = thisProcess.nowExecutingPath.dirname;   // база = папка App/

// --- master cleanup (идемпотентно) ----------------------------------
~appCleanup = { |verbose = true|
    if(~ungCloseTuners.notNil) { ~ungCloseTuners.value };   // окна отстройки
    if(~vizClose.notNil)       { ~vizClose.value };         // окно визуализации
    if(~mixerWin.notNil)       { { ~mixerWin.close }.defer; ~mixerWin = nil };
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

    // --- 0a. общий инструментарий отстройки (specs/пресеты/рандом/GUI) ---
    //   грузится ПЕРВЫМ: synths/*.scd регистрируют свои spec в ~ungSpecs.
    (~appDir +/+ "0_lib.scd").load;

    // --- 0b. чистый старт ---
    ~appCleanup.value(false);

    // --- 1. шины (никаких магических индексов) ---
    ~busDry      = Bus.audio(s, 2);   // сухой сум слоёв -> мастер
    ~busFxSend   = Bus.audio(s, 2);   // посыл слоёв -> эффекты (§K)
    ~busFxReturn = Bus.audio(s, 2);   // возврат эффектов -> мастер (§K)
    s.sync;

    // --- 2. синт-слои: глоб App/synths/*.scd (опц. фильтр по ~cfg_app.layers) ---
    ~synthFiles = (~appDir +/+ "synths" +/+ "*.scd").pathMatch;
    if(~cfg_app.sortSynths) { ~synthFiles = ~synthFiles.sort };

    // фильтр выбора слоёв: если layers задан — грузим только перечисленные
    if(~cfg_app.layers.notNil) {
        var want = ~cfg_app.layers.collect(_.asSymbol);
        // предупредить о запрошенных слоях без файла
        var have = ~synthFiles.collect { |p| PathName(p).fileNameWithoutExtension.asSymbol };
        want.do { |l|
            if(have.includes(l).not) {
                ("UNGRUND app — запрошен слой без файла: " ++ l).warn;
            };
        };
        ~synthFiles = ~synthFiles.select { |p|
            want.includes(PathName(p).fileNameWithoutExtension.asSymbol);
        };
    };

    if(~synthFiles.isEmpty) {
        "UNGRUND app — НЕ найдено ни одного синт-слоя для загрузки.".warn;
    };

    // ~activeLayers — единственный источник правды о загруженных слоях.
    // Микшер и виз читают его. Ставим ДО загрузки микшера.
    ~activeLayers = ~synthFiles.collect { |p|
        PathName(p).fileNameWithoutExtension.asSymbol;
    };

    ~synthFiles.do { |path|
        ("  load synth: " ++ path.basename).postln;
        path.load;
    };
    s.sync;

    // --- 2b. авто-загрузка пресета "default" слоя (если файл существует) ---
    //   ~loadPreset работает без spec (просто ~setParam по ключам) — безопасно
    //   и для заглушек. Пропускаем молча, если пресета нет.
    if(~cfg_app.autoPreset) {
        ~activeLayers.do { |layer|
            // .any (value-сравнение), НЕ .includes: Array:includes сверяет по
            // ИДЕНТИЧНОСТИ (===), а два разных String с тем же содержимым не
            // идентичны — поэтому .includes("default") всегда давал false.
            if(~listPresets.(layer).any { |n| n == "default" }) {
                ~loadPreset.(layer, "default");
            };
        };
    };

    // --- 3. эффекты (читают ~busFxSend, пишут ~busFxReturn) ---
    if(~cfg_app.enableEffects) {
        (~appDir +/+ "6_effects.scd").load;
        s.sync;
    } {
        "UNGRUND app — эффекты ВЫКЛ (enableEffects=false).".postln;
    };

    // --- 4. микшер (маршрутизирует слои + мастер) ---
    if(~cfg_app.enableMixer) {
        (~appDir +/+ "2_mixer.scd").load;
        s.sync;
        // окно микшера — на AppClock
        if(~cfg_app.enableMixerGui and: { ~openMixer.notNil }) {
            { ~openMixer.value }.defer;
        };
    } {
        "UNGRUND app — микшер ВЫКЛ (enableMixer=false) — слои не маршрутизированы.".warn;
    };

    // --- 5. lfo (автоматизация — после микшера) ---
    if(~cfg_app.enableLfo) {
        (~appDir +/+ "3_lfo.scd").load;
        s.sync;
    } {
        "UNGRUND app — LFO ВЫКЛ (enableLfo=false).".postln;
    };

    // --- 6. control (MIDI — после микшера/lfo) ---
    if(~cfg_app.enableControl) {
        (~appDir +/+ "5_control.scd").load;
        s.sync;
    } {
        "UNGRUND app — MIDI ВЫКЛ (enableControl=false).".postln;
    };

    // --- 7. секвенсор (последним) ---
    if(~cfg_app.enableSequencer) {
        (~appDir +/+ "4_sequencer.scd").load;
        s.sync;
    } {
        "UNGRUND app — секвенсор ВЫКЛ (enableSequencer=false).".postln;
    };

    // --- 8. визуализация (seq + LFO) — самой последней, опционально ---
    if(~cfg_app.enableVizGui and: { ~cfg_app.enableLfo or: { ~cfg_app.enableSequencer } }) {
        (~appDir +/+ "7_viz.scd").load;
        s.sync;
        if(~openViz.notNil) { { ~openViz.value }.defer };
    };

    "UNGRUND app — все слои загружены и смаршрутизированы.".postln;

    // --- 9. старт таймлайна (только если секвенсор включён И autostart) ---
    if(~cfg_app.enableSequencer and: { ~cfg_app.autostart } and: { ~seqStart.notNil }) {
        ~seqStart.value;
        "UNGRUND app — таймлайн запущен (~seqStop для остановки).".postln;
    } {
        "UNGRUND app — таймлайн не запущен (саунд-дизайн). ~openMixer — окно микшера.".postln;
    };
});
)


// =====================================================================
// CLEANUP — выполнить этот абзац отдельно для полного сброса.
// (Cmd-. останавливает звук; этот блок освобождает шины/Ndef/Tdef/MIDIdef
//  и закрывает окна микшера/визуализации/отстройки.)
// =====================================================================

// (
// ~appCleanup.value(true);
// )
