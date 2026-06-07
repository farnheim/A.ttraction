// =====================================================================
// App/5_control.scd
// UNGRUND · CONTROL — MIDI-управление (CC -> цель)
//
// CONFIG = таблица отображений CC -> цель. Каждая строка: номер CC,
// тип цели (\layer / \mixVol / \mixSend / \lfoRate / \master), имя
// слоя/параметра и диапазон [min, max], в который масштабируется
// значение CC (0–127). Логика = MIDIClient.init + MIDIIn.connectAll +
// один обобщённый MIDIdef, разбирающий конфиг.
//
// Добавить контроллер = добавить строку в ~cfg_ctrl.map.
//
// Перевычисляется ЧИСТО: один MIDIdef(\ung_cc) с фиксированным ключом
// (повторное выполнение заменяет, не стакает).
//
// Зависимости: микшер (~mixSet, ~masterSet), синт-слои, LFO (~lfoKeys).
//   Загружать после mixer/lfo (см. 1_app.scd).
// =====================================================================


// ===== CONFIG — edit here ============================================
(
// Каждая строка: ( cc: N, type: \layer|\mixVol|\mixSend|\lfoRate|\master,
//                   target: \layer (для \layer/\mixVol/\mixSend) или
//                           lfo-индекс (для \lfoRate),
//                   param: \name (только для type \layer),
//                   min: lo, max: hi )
~cfg_ctrl = (
    channel: nil,    // nil = любой MIDI-канал
    map: [
        // CC 1 (mod wheel) -> громкость monade
        ( cc: 1,  type: \mixVol,  target: \monade,            min: 0.0,  max: 1.0 ),
        // CC 7 -> мастер-уровень
        ( cc: 7,  type: \master,                              min: 0.0,  max: 1.0 ),
        // CC 21 -> частота binde (пример прямого параметра слоя)
        ( cc: 21, type: \layer,   target: \binde, param: \freq, min: 100, max: 2000 ),
        // CC 22 -> посыл firnis в реверб
        ( cc: 22, type: \mixSend, target: \firnis,            min: 0.0,  max: 1.0 ),
        // CC 23 -> частота развёртки schliere
        ( cc: 23, type: \layer,   target: \schliere, param: \freqHi, min: 300, max: 2000 ),
        // CC 24 -> частота первого LFO (lfo-индекс 0)
        ( cc: 24, type: \lfoRate, target: 0,                  min: 0.005, max: 0.2 )
    ]
);


// ===== LOGIC — generic MIDI engine ===================================
// инициализация MIDI один раз (повторно безопасно)
if(MIDIClient.initialized.not) { MIDIClient.init };
MIDIIn.connectAll;

// быстрый словарь cc -> строка конфига
~ctrlByCC = ();
~cfg_ctrl.map.do { |line| ~ctrlByCC[line.cc] = line };

// масштаб 0–127 -> [min, max] (линейно)
~ctrlScale = { |val, lo, hi| (val / 127).linlin(0, 1, lo, hi) };

// один обобщённый обработчик; фикс. ключ => перезапуск заменяет, не стакает
MIDIdef.cc(\ung_cc, { |val, num, chan|
    var line = ~ctrlByCC[num];
    if(line.notNil and: { ~cfg_ctrl.channel.isNil or: { chan == ~cfg_ctrl.channel } }) {
        var v = ~ctrlScale.(val, line.min, line.max);
        switch(line.type,
            \mixVol,  { ~mixSet.(line.target, \vol, v) },
            \mixSend, { ~mixSet.(line.target, \send, v) },
            \master,  { ~masterSet.(v) },
            \layer,   { Ndef(line.target.asSymbol).set(line.param, v) },
            \lfoRate, {
                // ~lfoKeys существует только если загружен 3_lfo (enableLfo).
                // Без LFO — тихо игнорируем (контроллер не должен падать).
                if(~lfoKeys.notNil) {
                    var lfoKey = ~lfoKeys.detect { |k|
                        k.asString.beginsWith("lfo_" ++ line.target ++ "_") };
                    if(lfoKey.notNil) { Ndef(lfoKey).set(\rate, v) };
                };
            }
        );
    };
}).permanent_(true);

"5_control — MIDIdef(\\ung_cc) активен (CC-карта загружена).".postln;
)
