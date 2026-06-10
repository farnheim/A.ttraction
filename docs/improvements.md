# Аудит проекта — ошибки, несоответствия, улучшения

> Дата: 2026-06-10. Охват: `.claude/agents/*`, `App/*`, `docs/*`, конфигурация
> репозитория. Семантика `Ndef.all` сверена с исходниками класс-библиотеки
> SuperCollider (`JITLib/ProxySpace/NodeProxy.sc:1067`).
> Приоритеты: **P1** — реальный баг / потеря данных; **P2** — надёжность,
> рассинхрон код↔док; **P3** — гигиена, опциональные оптимизации.

---

## 1. Баги в коде App (P1) — ✅ исправлены 2026-06-10

> Все пять пунктов внесены в код. Проверки: компиляция всех файлов App в
> sclang 3.14.0; headless-тест (без сервера): идемпотентная перезагрузка
> 3_lfo не рвёт маппинги, удалённая строка → unmap+clear; TempoClock один
> на сессию; `~seqMute`/`~seqRaise` меняют runtime-громкость, не трогая
> `~cfg_mixer`; teardown клока в `~appCleanup` не падает.

### 1.1 `3_lfo.scd` — цикл очистки LFO-прокси никогда не срабатывает

`App/3_lfo.scd:51-53`:

```supercollider
Ndef.all.keys.do { |k|
    if(k.asString.beginsWith("lfo_")) { Ndef(k).clear };
};
```

`Ndef.all` — это словарь **имя сервера → ProxySpace** (см.
`NodeProxy.sc`: `*dictFor` кладёт `all.put(server.name, dict)`). Ключи —
`\localhost` и т.п., строка `"lfo_"` не встречается никогда, цикл — no-op.

**Следствие.** Заявленная идемпотентность файла не выполняется: при удалении
или перенумерации строки в `~cfg_lfo.lines` старый kr-прокси `lfo_…` остаётся
жить, а его `.map` на целевой параметр не снимается — параметр «залипает» под
старой автоматизацией до полного `~appCleanup`.

**Исправление.** Чистить по собственному реестру и снимать маппинг:

```supercollider
(~lfoLines ? []).do { |line| Ndef(line.target).unmap(line.param) };
(~lfoKeys  ? []).do { |k| Ndef(k).clear };
~lfoKeys  = [];
// ... создание строк ...
~lfoLines = ~cfg_lfo.lines.copy;   // запомнить для следующей перезагрузки
```

### 1.2 `4_sequencer.scd` — утечка TempoClock при каждой перезагрузке

`App/4_sequencer.scd:51`: `~seqClock = TempoClock.new(...).permanent_(true)` —
каждое перевыполнение файла создаёт **новый** перманентный клок, старый никем
не останавливается и переживает Cmd-. (на то и `permanent`). `~appCleanup`
(`App/1_app.scd:57-70`) клок тоже не освобождает.

**Исправление.**

```supercollider
~seqClock = ~seqClock ?? { TempoClock.new(~cfg_seq.tempo).permanent_(true) };
~seqClock.tempo = ~cfg_seq.tempo;
```

и в `~appCleanup`: `if(~seqClock.notNil) { ~seqClock.clear; ~seqClock.stop; ~seqClock = nil }`.

### 1.3 Секвенсор разрушает исходное сведение (`~cfg_mixer.levels`)

`~seqRaise`/`~seqMute` (`App/4_sequencer.scd:54-59`) идут через `~mixSet`,
а `~mixSet` (`App/2_mixer.scd:127-136`) **записывает значение в
`~cfg_mixer.levels`**. `~seqStop` глушит все слои → в конфиге микшера у всех
слоёв `vol = 0`. После этого `~mixUnsolo` «восстанавливает» нули — исходное
сведение потеряно до перевыполнения `2_mixer.scd`.

Это прямо противоречит `docs/architecture.md` §8: «возврат восстанавливает
уровни из `~cfg_mixer`, исходное сведение не теряется» — для solo это так
(`~mixSolo` сознательно пишет в Ndef напрямую), а для секвенсора — нет.

**Исправление.** Секвенсору ставить громкости как `~mixSolo` — напрямую
`Ndef(("mix_"++l).asSymbol).set(\vol, …)`, не мутируя конфиг; либо разделить
в микшере «runtime-значение» и «значение CONFIG» (например,
`~mixSet.(…, updateCfg: false)` для seq).

### 1.4 `2_mixer.scd` — двойной путь записи у `\fxsend`

`App/2_mixer.scd:88-99`: тело `Ndef(\fxsend)` пишет в шину само через
`ReplaceOut.ar(~busFxSend.index, …)`, и одновременно вызывается
`Ndef(\fxsend).play(out: ~busFxSend.index, numChannels: 2)`. Функция,
завершающаяся `ReplaceOut`, не имеет выходных каналов — монитор `.play`
в лучшем случае подмешивает в шину тишину, в худшем — путает шейп прокси.
Нужен ровно один путь: либо вернуть `Mix(sends)` из функции и оставить
`.play(out:)`, либо оставить `ReplaceOut` и убрать `.play`. Сейчас комментарий
обещает «РОВНО один писатель», а писателей по коду два.

### 1.5 `2_mixer.scd` — окно микшера без защит, которые уже есть у тюнера

В `0_lib.scd` оба бага задокументированы как реально пойманные и закрыты
(`App/0_lib.scd:239-249, 385-398`):

- закрытие старого окна — через `try { … }` (ссылка может указывать на уже
  разрушенный Qt-объект);
- `onClose` чистит реестры **только если** `~ungTuner[layer] === win`
  (иначе отложенный onClose старого окна затирает слоты нового).

`~ungBuildMixer` (`App/2_mixer.scd:193, 287-292`) не имеет ни того, ни
другого: `~mixerWin.close` без `try`, onClose без guard — при
close→reopen возможны обрыв сборки окна и обнуление `~mixerGuiSync`
свежего окна. Перенести оба паттерна из 0_lib.

---

## 2. Надёжность и рассинхрон код ↔ конвенции (P2)

### 2.1 Мёртвый CONFIG: правка не влияет на звук

Нарушение конвенции §6 architecture.md («поведение меняется правкой ВЕРХА
файла»):

| Файл | Параметр CONFIG | Факт |
|------|-----------------|------|
| `App/synths/theta.scd:19` | `~cfg_theta.freqs` | частоты захардкожены в теле Ndef (`#[12640, …]`, строка 29); правка CONFIG ничего не меняет |
| `App/synths/gamma.scd:17` | `~cfg_gamma.partials` | то же: `#[5, 7, 9, 11, 13]` в теле (строка 27) |

Либо передавать в Ndef (для массивов — `NamedControl.kr(\freqs, ~cfg_theta.freqs)`
с фикс. размером), либо строить тело Ndef с захватом значения из `~cfg_*` на
момент выполнения файла и убрать дубль из CONFIG.

### 2.2 Идемпотентность микшера неполна

При перевыполнении `2_mixer.scd` с изменившимся `~activeLayers`
(или `~cfg_app.layers`) старые роутеры `Ndef(\mix_<L>)` исчезнувших слоёв не
удаляются, а у `\fxsend` остаются стейл-контролы `send_<L>`. Малозаметно, но
по той же схеме, что 1.1: чистить по реестру предыдущего списка слоёв.

### 2.3 Диапазоны LFO рассчитаны под старые дефолты alpha

`App/3_lfo.scd:31`: `alpha.amp` дрейфует в `[0.16, 0.24]` — это диапазон
вокруг старого `amp = 0.22` (architecture, Прил. A). Сейчас дефолт spec —
`0.30` (`alpha.scd:52`), а автозагружаемый пресет `default` ставит
`amp = 0.9499` (`App/presets/alpha/default.scd`). Включение `enableLfo`
мгновенно уронит громкость слоя в 4 раза. Диапазоны строк LFO стоит привязать
к текущим пресетам (или задавать их относительно: `±20%` от текущего
значения).

### 2.4 `epsilon` — дрейф гребёнки выходит за заявленный диапазон

`App/synths/epsilon.scd:36-38`: сумма `LFNoise2 + LFNoise2 * 0.5` имеет размах
±1.5, а `.range(lo, hi)` рассчитан на ±1 — фактический `sweepHz` экстраполирует
за `[freqLo, freqHi]` примерно на четверть диапазона (страхует только клип
`combTime`). Нормировать: `(a + (b * 0.5)) / 1.5` перед `.range`, либо
`.clip(-1, 1)`.

### 2.5 Мелкое

- `App/0_lib.scd:55` — `~ungDefault` нигде не используется (мёртвый код;
  либо удалить, либо применить в кнопке «сброс»).
- `App/7_viz.scd:107-114` — playhead считается по wall-clock
  (`Main.elapsedTime`), а Tdef идёт по `~seqClock`; при смене tempo на лету
  или нагрузке расходятся. Малая цена: брать `~seqClock.beats` от отметки
  старта.
- `App/1_app.scd:11` — в шапке порядок загрузки перечислен без `7_viz.scd`
  (architecture §5 его включает).
- `App/4_sequencer.scd` — `~seqApplyBlock` сетит параметры в `Ndef` напрямую,
  минуя `~setParam`: `~ungVals` и открытый тюнер не узнают о правке
  (слайдеры остаются на старых значениях). Использовать `~setParam`, когда
  у слоя есть spec.

---

## 3. Несоответствия документации (P2)

### 3.1 `.claude/CLAUDE.md` — незаполненный шаблон — ✅ заполнен 2026-06-10

Файл — болванка `[PROJECT NAME] … [e.g. Node.js 24, Express 4]`. Он
подгружается в каждую сессию Claude Code и сейчас не даёт ни одного факта о
проекте, только шум. Заполнить реальным содержанием: UNGRUND, SuperCollider
(sclang + scsynth, JITLib), карта `App/` (таблица §2-§3 architecture.md),
конвенции (один `( )`-блок на файл, CONFIG сверху, греческие имена слоёв,
`Tests/test_monade.scd` — locked), указатели на `docs/architecture.md`,
`docs/reference_v2.md`, пайплайны агентов.

### 3.2 `docs/architecture.md` отстал от редизайна zeta — ✅ переписан 2026-06-10

> Документ переписан целиком: Приложение B — новая vinyl/tape-зета
> (страты bed/sub/fine/pops, 26 параметров, группы spec); Приложение A —
> актуальные числа alpha (sprGain, bright, cutTop/cutOil, 27 параметров);
> §9 — новая премиса zeta с пометкой о вытеснении §C.6; §10 — актуальные
> клампы; §3 — `default.scd` (без подчёркивания) + карта `.claude/Tools/`;
> §4 — один писатель `\fxsend` (ReplaceOut, без `.play`), InFeedback в
> мастере и эффектах; §5 — 0_lib в цепочке загрузки; §8 — пункт про
> рендер-измерение; добавлен раздел «Связанные документы».

Память проекта: zeta редизайнен под vinyl/tape поверхность (2026-06-08), код
(`App/synths/zeta.scd`) и `docs/task.md` это отражают, architecture.md — нет:

- **Приложение B** целиком описывает старую zeta: «ВЧ-облако шумовых зёрен,
  HPF > 5 kHz, банк Ringz `r1..r5`, `resAmt`, 19 параметров, пресеты
  `pure_rustle`/`glass_shimmer`» — ничего из этого в коде больше нет
  (пресеты переехали в `archives/zeta/`). Переписать под bed/sub/fine/pops
  (26 параметров), сослаться на `docs/zeta_texture_reference.md`.
- §9, строка zeta — та же старая премиса «HPF > 5 kHz».
- §10 — «zeta: края `hpf`/`lpf` и частоты банка `r1..r5` клампятся…» —
  параметров `hpf/lpf/r1..r5` не существует.
- §3 — «`_default.scd` авто-грузится при autoPreset»: код грузит пресет с
  именем **`default`** (`1_app.scd:130`), файлы на диске — `default.scd`.
  Подчёркивания нет.
- Приложение A (alpha) — числа из старой версии: «Mix/10 · 3.4 + ticks·1.5»,
  «amp снижен 0.4 → 0.22». В коде `sprGain` (деф. 4.6), `ticks * 0.9`,
  дефолт `amp = 0.30` (`alpha.scd:144-145, 52`). Обновить или пометить
  «числа иллюстративные, источник правды — `~spec_alpha`».

### 3.3 `docs/reference_v2.md` — не помечено вытеснение §C.6 и внутренние ошибки

- §C.6 `kratzer` («сухой гранулированный burst 100–800 мс, HPF 3–12 kHz,
  никогда дольше 1 с») концептуально **противоречит** реализованному слою
  `zeta` (непрерывная поверхность винила, центроид ~1.2 kHz). Правило
  avant-composer требует помечать вытесненные секции
  `> superseded YYYY-MM-DD` — добавить пометку и абзац о редизайне со ссылкой
  на `docs/zeta_texture_reference.md`. Иначе словарь системы и словарь кода —
  два разных словаря.
- Шапка: «Оригинал сохранён в `docs/reference.md` без изменений» — файл
  теперь `archives/reference.md`.
- `ungrund.0003`: в «One sentence» — «**six** of the 32 cells are *zäsur*»,
  а в таблице и тексте ниже — **пять** (4, 12, 20, 27, 31). Привести к одному
  числу.
- Опечатки: §K.4 «`rissz.amp_min/max`» (должно быть `riß`); §K.5 Basinski
  «(2002, **2063**)» → 2002–2003.

### 3.4 `docs/task.md` (spec zeta) расходится с натюненным кодом

Спека писалась до render-measure-доводки; код ушёл от неё по дефолтам:
`bedLpf` 7000 → **11000** (спека прямо запрещала «bright», это осознанное
отступление по результатам измерений), `bedAmp` 0.12 → 0.6, `fineAmt`
0.18 → 0.48, `fineHpf` 3000 → 2000, `popAmt` 0.7 → 0.85, `popAmpMin`
0.05 → 0.14, `subAmt` 0.04 → 0.0 и др. Добавить в конец task.md короткий
раздел «Post-tuning deviations (2026-06-08)» с фактическими дефолтами и
причиной (подгонка по спектру Texture.wav; два остаточных зазора — mid-HF
level и crest variance — отложены), чтобы спека перестала выглядеть как
несоблюдённая.

### 3.5 Битые ссылки после переезда файлов в `archives/`

`docs/decomposition.md` (шапка и «Связанные документы») и `docs/char.md`
ссылаются на `docs/reference.md`, `docs/scheme.md`, `docs/rulus.md`,
`docs/research.md`, `docs/task_v2.md` — все эти файлы теперь в `archives/`.
Поправить пути (`../archives/…`). Дополнительно: разбор
`construction_0001.txt` в decomposition.md ссылается на блоки `A, B, H, I, M`,
но в самом файле меток нет — добавить буквенную разметку в файл или убрать
буквы из разбора.

---

## 4. Агенты `.claude/agents` (P2) — ✅ исправлено 2026-06-10

> Сделано: `docs/rulus.md` v2 восстановлен (карта файлов, два контракта `.scd`,
> Pipeline 3 «итерация слоя», acceptance-метрики, протокол отклонений);
> создан канонический `docs/layer_contract.md` (контракт слоя + footguns);
> созданы `.claude/Tools/parse_check.scd` и `.claude/Tools/render_measure.sh` +
> `.claude/Tools/render_layer.scd` (проверены сквозным рендером zeta);
> все четыре агента обновлены: актуальные пути, контракт слоя, self-check,
> doc-sync в Definition of Done, запрет на `Tests/test_monade.scd`;
> historian получил WebSearch/WebFetch и переведён на sonnet;
> `.claude/CLAUDE.md` заполнен. Детали ниже — исторический контекст.

Все четыре агента написаны под «до-App» эпоху проекта и ссылаются на файлы,
которых больше нет на своих местах:

| Ссылка в агентах | Факт |
|------------------|------|
| `docs/rulus.md` (все четыре, «pipelines source of truth») | файл в `archives/rulus.md` |
| `docs/reference.md` (composer, analyst, dev) | в `archives/`; актуальные референсы — пер-слойные (`docs/zeta_texture_reference.md`) |
| `docs/research.md` (historian, composer, analyst) | в `archives/` |
| `prototype.scd` (все четыре; у dev — дефолтный `entry`) | не существует; точка входа — `App/1_app.scd`, слои — `App/synths/<class>.scd` |
| `NEW-PROJECT.md` (historian, composer) | не существует |

Рекомендации:

1. **Вернуть `rulus.md` в `docs/` в обновлённой редакции** (или править пути
   во всех агентах на `archives/`, но лучше первое — это действующий
   контракт, а не архив). В обновлённой редакции зафиксировать реальную
   практику: референс пер-слойный (`docs/<layer>_…_reference.md`),
   `docs/task.md` перезаписывается на задачу, выход dev — `App/synths/<layer>.scd`.
2. **Контракт `*.scd` в rulus.md противоречит архитектуре App**: «boot the
   server … end with a cleanup block» — а `docs/task.md` §Lifecycle для слоёв
   прямо требует обратного («No `s.waitForBoot`… No explicit cleanup in this
   file»). Описать два контракта: standalone-скрипт (старый) и слой App
   (один `( )`-блок, CONFIG сверху, без boot, без cleanup, саморегистрация
   spec).
3. `supercollider-dev` про App знает (Required Reading §6, правило о греческих
   именах), а `supercollider-analyst` и `avant-composer` — нет. Добавить им
   `docs/architecture.md` в Required Reading и правило «один верхнеуровневый
   `( )`-блок» (анализатор должен флагать его нарушение — это реальный
   класс багов из-за `.load`).
4. У dev `entry` по умолчанию заменить с `prototype.scd` на
   `App/synths/<layer>.scd`; в Output Format обновить примеры («How to run» —
   через `App/1_app.scd`, не открытие одиночного файла).
5. Добавить агентам запрет на правку `Tests/test_monade.scd` (файл
   зафиксирован — locked).

---

## 5. Гигиена репозитория и конфигурации (P3)

- **`clients.csv` в корне репозитория** — клиентская база с реальными
  email-адресами (PII), к проекту отношения не имеет. Удалить из репо; если
  репозиторий когда-либо публиковался/будет публиковаться — вычистить и из
  истории git.
- `.claude/settings.json`:
  - `"language": "english"` — при русскоязычном пользователе и русской
    документации это заставляет ассистента отвечать по-английски; сменить на
    `"russian"`;
  - `"allow": ["Bash", "WebFetch", …]` — карт-бланш на любые shell-команды и
    произвольные сетевые запросы без подтверждения; сузить до типовых
    безопасных команд (`Bash(ls:*)`, `Bash(sclang:*)` и т.п.) по вкусу;
  - `"plansDirectory": "docs/plans"` — каталога нет; `spinnerVerbs`,
    `companyAnnouncements` — следы чужого шаблона; убрать или создать каталог.
- `archives/README.md` — это вообще README чужого шаблон-проекта (ссылки на
  несуществующие `.claude/rules/`, `docs/plans/`, `http/`). Если он лежит как
  «образец» — переименовать в `_template_readme.md`; у самого `archives/`
  README с описью содержимого нет, а пригодился бы (что и когда вытеснено).
- Бинарники в git: `Tests/test_monade_260522_202604.wav`,
  `archives/Texture_1.wav`, `archives/Texture_2.wav`, `.DS_Store`.
  `.DS_Store` — в `.gitignore`; wav-референсы — решить осознанно (оставить
  как референсы или вынести/git-lfs). Примечание: `docs/task.md` и
  `docs/zeta_texture_reference.md` ссылаются на `archives/Texture.wav` —
  файла с таким именем нет, есть `Texture_1.wav`/`Texture_2.wav`; уточнить,
  какой из них измерялся.

---

## 6. Опциональные оптимизации по концепции (P3)

1. **Вынести «хвост регистрации» слоя в 0_lib.** Блок
   `~ungSpecs[\x] = …; ~ungVals[\x] = (); params.do { set default }` дословно
   дублируется в `alpha.scd` и `zeta.scd` и будет скопирован ещё в 5 заглушек
   при доводке. Один helper в 0_lib:
   `~ungRegister = { |layer, spec, fadeTime| … }` — и доводка следующего слоя
   действительно сведётся к «написать его `~spec_<class>`», как и обещает
   architecture §9.
2. **Перевести заглушки на spec постепенно.** Сейчас у
   `beta/gamma/delta/epsilon/theta` кнопка tuner в микшере серая (нет spec).
   Даже минимальный `~spec_<class>` из 4–6 существующих параметров CONFIG
   сразу даёт тюнер, рандом и пресеты бесплатно — и устраняет двойную систему
   конфигурации (`~cfg_*` vs `~spec_*`).
3. **`~setParam` и LFO-маппинг.** `~setParam` пишет в Ndef даже когда параметр
   замаплен на LFO (set молча игнорируется сервером, GUI лишь помечает ⟳LFO).
   Честнее: при `~isMapped` либо не дёргать `.set`, либо предлагать снять
   маппинг (`Ndef(target).unmap(param)`) — иначе слайдер «крутится вхолостую».
4. **`eta` в маршрутизации.** Для слоя-тишины создаются роутер `mix_eta` и
   контрол `send_eta` — лишние узлы графа. Можно исключать `\eta` из
   `~mixerLayers` (тишину ведёт секвенсор, не микшер). Микрооптимизация,
   важнее как ясность концепции «тишина — регистр, а не сигнал».
5. **Единый clamp-хелпер.** `SampleRate.ir * 0.45` повторяется по слоям —
   мелкий хелпер/идиома в 0_lib (`~nyq = { SampleRate.ir * 0.45 }`) не нужен
   внутри SynthDef-графов, но как договорённость в architecture §10 стоит
   записать каноничную форму (post-lag clamp, как в task.md).

---

## Сводный порядок работ

| # | Что | Файлы | Приоритет |
|---|-----|-------|-----------|
| 1 | Очистка/unmap LFO по реестру | `3_lfo.scd` | P1 ✅ |
| 2 | TempoClock: переиспользование + очистка | `4_sequencer.scd`, `1_app.scd` | P1 ✅ |
| 3 | Секвенсор не мутирует `~cfg_mixer` | `4_sequencer.scd` (или `2_mixer.scd`) | P1 ✅ |
| 4 | Один путь записи `\fxsend` | `2_mixer.scd` | P1 ✅ |
| 5 | try/guard для окна микшера | `2_mixer.scd` | P1 ✅ |
| 6 | Мёртвый CONFIG theta/gamma | `synths/theta.scd`, `synths/gamma.scd` | P2 |
| 7 | Заполнить CLAUDE.md | `.claude/CLAUDE.md` | P2 ✅ |
| 8 | Обновить architecture.md (zeta, alpha, `_default`) | `docs/architecture.md` | P2 ✅ |
| 9 | Superseded-пометка §C.6 + правки reference_v2 | `docs/reference_v2.md` | P2 |
| 10 | Post-tuning-раздел в task.md | `docs/task.md` | P2 |
| 11 | Починить ссылки docs → archives | `docs/decomposition.md`, `docs/char.md` | P2 |
| 12 | Обновить 4 агента + вернуть rulus.md в docs/ (+ layer_contract.md, .claude/Tools/) | `.claude/agents/*`, `docs/rulus.md`, `docs/layer_contract.md`, `.claude/Tools/` | P2 ✅ |
| 13 | Удалить clients.csv, поправить settings.json | корень, `.claude/settings.json` | P3 |
| 14 | LFO-диапазоны под текущие пресеты; epsilon range; ~ungDefault; viz playhead | `3_lfo.scd`, `synths/epsilon.scd`, `0_lib.scd`, `7_viz.scd` | P3 |
| 15 | `~ungRegister`-хелпер + spec для заглушек | `0_lib.scd`, `synths/*` | P3 |
