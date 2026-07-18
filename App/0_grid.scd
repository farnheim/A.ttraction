// App/0_grid.scd — UNGRUND · GRID: генератор структурных сеток по канону
// docs/architecture/structure-grid/README.md (правила 1–6).
// Чистая логика, сервер не нужен. Грузится шагом 0a в 1_app.scd, сразу за
// 0_lib.scd — окно микшера (шаг 4) читает ~gridGenerate.
// API: ~gridGenerate.(complexity, seed) ->
//      ( text:, field:, nodes:, rows:, cols:, seed:, complexity:, graph: )
//      или nil при отказе; ~gridRender.(grid) -> строка поля.
//      nodes ОСТАЁТСЯ числом (его читает статус микшера); список узлов и рёбер
//      (индексами) — только внутри graph: для деривации 9_konstruktion.scd.
// Алфавит символов: docs/architecture/structure-grid/char.md.

(
// ===== CONFIG — edit here ============================================
// Между парой [a, b] интерполирует слайдер сложности 0..1.
// Поле фиксировано 16×16 (user override 2026-07-18): компактные, плотные,
// ветвисто-сходящиеся графы — mergeProb поднят ради замыканий (циклов census).
~cfg_grid = (
    nodes:      [7, 20],        // число Ф при сложности 0 -> 1
    branchProb: [0.35, 0.90],   // вероятность ветвления Ф (правило 4)
    mergeProb:  [0.45, 0.95],   // вероятность схождения двух ветвей в один Ф
    maxOut:     3,              // максимум исходящих связей из узла
    // Потолок ширины фронта. Растеризатор разводит связи только сегментами и
    // углами (тройники/кресты канон резервирует), и фронт шире 5 на плоскости
    // без пересечений почти не разводится. Без потолка такие графы всё равно
    // отбраковывались бы — но молча, смещая выборку в сторону узких.
    maxFront:   [3, 5],         // ширина фронта при сложности 0 -> 1
    cols:       [16, 16],       // ширина поля  (канонный минимум, фикс.)
    rows:       [16, 16],       // высота поля  (канонный минимум, фикс.)
    // Шаг рангов по строкам НЕ фиксирован: он выводится из числа рангов графа
    // так, чтобы граф занял поле по высоте (rowGap = (rows-2) div (tiers-1),
    // зажат в [rowGapMin, rowGapMax]). Фиксированный шаг молча отбраковывал по
    // высоте целые классы графов — стволовые, — и ретрай подменял их широкими:
    // выборка смещалась. rowGap-1 = число полос для горизонтальных перекладин,
    // поэтому широкий низкий граф получает много полос и разводится.
    rowGapMin:  2,              // правило 3: между рангами хотя бы одна связь
    rowGapMax:  8,              // потолок шага (длиннее связи не растягиваем)
    colGap:     3,              // шаг узлов по колонкам   (>= 3: боковые выходы)
    relax:      4,              // сглаживающих проходов раскладки (короче связи)
    // 16×16 разводится тяжело (полос мало): 20-Ф графы при c=1 проходят 100%
    // замера только с таким запасом ретраев; 22 Ф давали 70% — потолок поля
    rasterTries: 24,            // попыток развести ОДИН граф (перебор полос)
    graphTries: 120             // попыток вырастить новый граф до отказа
);


// ===== LOGIC — граф, раскладка, растеризация =========================
// алфавит канона: Ф свободны, связи — только прямые сегменты и углы
// (тройники, кресты и переходные символы канон резервирует)
~gridFillChars = ["░", "▒", "▓", "█", "▄"];
~gridLineChars = (
    weak: (
        vert: "│", horiz: "─",
        upRight: "└", upLeft: "┘", downRight: "┌", downLeft: "┐"
    ),
    strong: (
        vert: "║", horiz: "═",
        upRight: "╚", upLeft: "╝", downRight: "╔", downLeft: "╗"
    )
);

~gridLerp = { |pair, t| pair[0] + ((pair[1] - pair[0]) * t) };

// (a..b) в SC при a > b идёт ВНИЗ и возвращает непустой ряд — на вырожденных
// сегментах связи это рисовало бы лишние ячейки поверх соседних
~gridSpan = { |a, b| if(a > b) { [] } { (a .. b) } };

~gridMedian = { |vals|
    var s = vals.asArray.sort;
    var m = s.size div: 2;
    if(s.size.odd) { s[m] } { (s[m - 1] + s[m]) / 2 };
};

~gridRender = { |grid|
    grid[\field].collect { |row|
        var s = row.join("");
        var i = s.size - 1;
        while { i >= 0 and: { s[i] == $  } } { i = i - 1 };
        if(i < 0) { "" } { s.copyRange(0, i) };
    }.join("\n");
};

// ----- граф по рангам (этап 1) + сила связи (этап 2) -----------------
~gridGrow = { |target, branchProb, mergeProb, maxFront|
    var nodes = List[];
    var edges = List[];
    var mkNode, addEdge, frontier, tier, root;

    mkNode = { |t|
        var n = (tier: t, ins: List[], outs: List[], col: 0, ch: ~gridFillChars.choose);
        nodes.add(n); n;
    };
    addEdge = { |a, b|
        var e = (src: a, dst: b, strong: true, exitSide: \down, entrySide: \up);
        edges.add(e); a.outs.add(e); b.ins.add(e); e;
    };

    root = mkNode.(0);
    frontier = [root];
    tier = 0;

    while { nodes.size < target and: { frontier.size > 0 } } {
        var slots = List[];
        var kids = List[];
        var i = 0;
        var budget = target - nodes.size;
        var room = maxFront;
        var ods = Array.fill(frontier.size, 0);
        // порядок РОЗЫГРЫША od случаен, порядок слотов — фронтовой: иначе
        // остаток room доставался бы всегда левым Ф и структура кренилась влево
        (0 .. frontier.size - 1).scramble.do { |ix|
            var n = frontier[ix];
            // суммарная степень Ф <= 4: у ячейки ровно четыре соседа, каждая
            // связь занимает ровно один из них (ветвление в Ф — правило 4)
            var cap = ~cfg_grid.maxOut.min(4 - n.ins.size).min(budget).min(room);
            // бюджет/фронт исчерпан -> od = 0: Ф остаётся листовым (правило 5),
            // иначе фронт растёт по экспоненте и никакое поле его не вмещает.
            // Корень не ветвится: правило 2 даёт ему ровно ОДНУ первую связь, а
            // правило 6 требует непустого ствола до первого ветвящегося Ф.
            // rrand(2, cap) при cap = 1 вернул бы 2 (rrand симметричен по
            // порядку аргументов) — ветвимся только когда cap это позволяет.
            var od = if(cap < 1) { 0 } {
                if(n !== root and: { cap >= 2 } and: { branchProb.coin }) {
                    rrand(2, cap)
                } { 1 };
            };
            ods[ix] = od;
            budget = budget - od;
            room = room - od;
        };
        frontier.do { |n, ix| ods[ix].do { slots.add(n) } };
        while { i < slots.size } {
            var kid = mkNode.(tier + 1);
            addEdge.(slots[i], kid);
            if(
                (i + 1 < slots.size)
                and: { slots[i + 1] !== slots[i] }
                and: { mergeProb.coin }
            ) {
                addEdge.(slots[i + 1], kid);
                i = i + 2;
            } {
                i = i + 1;
            };
            kids.add(kid);
        };
        frontier = kids.asArray;
        tier = tier + 1;
    };

    // правило 6: схождение приоритетнее ветвления; узлы идут в порядке рангов,
    // поэтому сила входящей связи уже известна
    nodes.do { |n|
        var strong = case
            { n.ins.size >= 2 } { true }
            { n.outs.size >= 2 } { false }
            { n.ins.size == 0 } { true }
            { true } { n.ins[0].strong };
        n.outs.do { |e| e.strong = strong };
    };

    ( nodes: nodes.asArray, edges: edges.asArray, tiers: tier + 1 )
};

// ----- раскладка (этап 3) --------------------------------------------
// Ряд разводится с шагом colGap и ставится на СРЕДНЮЮ желаемую колонку, а не
// по центру поля: центрирование каждого ранга отдельно уводит Ф от родителей,
// и связям остаются длинные горизонтальные перекладины, которым не хватает
// двух свободных строк зазора — растеризация захлёбывается коллизиями
// Порядок узлов в ряду НЕ сортируется по желаемой колонке: узлы рождаются
// слева направо (слоты идут по порядку фронта), и этот порядок — плоское
// вложение графа. Пересортировка меняет вложение, ветви начинают пересекаться,
// а пересечение требует ┼/╬, которых канон не даёт => сплошной отказ
~gridPlaceTier = { |arr, desired, cols|
    var lo, hi, shift;
    arr.do { |n, i|
        var c = desired[i];
        if(i > 0) { c = c.max(arr[i - 1].col + ~cfg_grid.colGap) };
        n.col = c;
    };
    shift = (desired.mean - arr.collect { |n| n.col }.mean).round.asInteger;
    arr.do { |n| n.col = n.col + shift };
    lo = arr.first.col;
    if(lo < 1) { arr.do { |n| n.col = n.col + (1 - lo) } };
    hi = arr.last.col;
    if(hi > (cols - 2)) { arr.do { |n| n.col = n.col - (hi - (cols - 2)) } };
    arr;
};

~gridLayout = { |graph, cols|
    var byTier = Array.fill(graph[\tiers], { List[] });
    var top = graph[\tiers] - 1;
    var downSweep, upSweep;
    graph[\nodes].do { |n| byTier[n.tier].add(n) };
    byTier = byTier.collect(_.asArray);
    byTier[0][0].col = (cols / 2).floor.asInteger;

    downSweep = {
        ~gridSpan.(1, top).do { |t|
            byTier[t] = ~gridPlaceTier.(
                byTier[t],
                byTier[t].collect { |n|
                    ~gridMedian.(n.ins.collect { |e| e.src.col }).round.asInteger
                },
                cols
            );
        };
    };
    upSweep = {
        ~gridSpan.(0, top - 1).reverse.do { |t|
            byTier[t] = ~gridPlaceTier.(
                byTier[t],
                byTier[t].collect { |n|
                    if(n.outs.isEmpty) { n.col } {
                        ~gridMedian.(n.outs.collect { |e| e.dst.col }).round.asInteger
                    };
                },
                cols
            );
        };
    };

    downSweep.value;
    ~cfg_grid.relax.do { upSweep.value; downSweep.value };
    byTier;
};

// ----- стороны Ф: каждая связь занимает ровно одного соседа ----------
// входящая никогда не берёт \down, исходящая никогда не берёт \up —
// иначе связь шла бы против направления развития (сверху вниз)
~gridSides = { |graph|
    var ok = true;
    var pick = { |cands, used|
        var side = cands.detect { |s| used[s].isNil };
        if(side.isNil) { ok = false } { used[side] = true };
        side ? \down;
    };
    var order = { |dc, alt|
        var sides = if(dc < 0) { [\left, \right] } { if(dc > 0) { [\right, \left] } { [\left, \right] } };
        sides ++ [alt];
    };
    graph[\nodes].do { |n|
        var used = ();
        var insA  = n.ins.asArray.sort  { |a, b| (a.src.col - n.col).abs < (b.src.col - n.col).abs };
        var outsA = n.outs.asArray.sort { |a, b| (a.dst.col - n.col).abs < (b.dst.col - n.col).abs };
        insA.do { |e, i|
            var dc = e.src.col - n.col;
            var cands = if(i == 0) { [\up] ++ order.(dc, \up) } { order.(dc, \up) };
            e.entrySide = pick.(cands, used);
        };
        outsA.do { |e, i|
            var dc = e.dst.col - n.col;
            var cands = if(i == 0) { [\down] ++ order.(dc, \down) } { order.(dc, \down) };
            e.exitSide = pick.(cands, used);
        };
    };
    ok;
};

// ----- растеризация (этап 4) + проверки (этап 5) ---------------------
// Граф приходит готовым: раскладка и проверки детерминированы, случаен только
// выбор полосы под перекладину. Поэтому неудачную разводку перебираем НА ТОМ ЖЕ
// графе (rasterTries) и только потом отдаём его назад — иначе отбраковка по
// коллизии выбивает целые классы графов (широкие низкие) и смещает выборку.
~gridAttempt = { |graph, cols, rows|
    var field;
    var ok = true;
    var rowGap, rowOf, cells, place, edgesByReach, routed, pass;

    // шаг рангов под конкретный граф: стволовой сжимается до rowGapMin и влезает
    // по высоте, низкий растягивается до rowGapMax и получает полосы под
    // перекладины. Так отбраковка по высоте не выбивает стволовые графы.
    rowGap = if(graph[\tiers] > 1) {
        ((rows - 2) div: (graph[\tiers] - 1)).clip(~cfg_grid.rowGapMin, ~cfg_grid.rowGapMax)
    } { ~cfg_grid.rowGapMax };

    rowOf = { |n| 1 + (n.tier * rowGap) };

    // недостижимо при канонных nodes/rows, но CONFIG правится руками:
    // высокий target на низком поле не влезает даже при rowGapMin
    if(1 + ((graph[\tiers] - 1) * rowGap) > (rows - 1)) { ok = false };

    if(ok) { ~gridLayout.(graph, cols) };
    if(ok) {
        graph[\nodes].do { |n|
            if(n.col < 1 or: { n.col > (cols - 2) }) { ok = false };
        };
    };

    // правило 3: расстояние Чебышёва между любыми двумя Ф >= 2
    if(ok) {
        graph[\nodes].do { |a, i|
            graph[\nodes].do { |b, j|
                if(i < j) {
                    var d = (rowOf.(a) - rowOf.(b)).abs.max((a.col - b.col).abs);
                    if(d < 2) { ok = false };
                };
            };
        };
    };

    if(ok) { ok = ~gridSides.(graph) };

    cells = { |e, j|
        var n1 = e.src, n2 = e.dst;
        var r1 = rowOf.(n1), r2 = rowOf.(n2);
        var g = if(e.strong) { ~gridLineChars.strong } { ~gridLineChars.weak };
        var out = List[];
        var x, y;
        case
            { e.exitSide == \left }  { x = n1.col - 1; out.add([r1, x, g.downRight]) }
            { e.exitSide == \right } { x = n1.col + 1; out.add([r1, x, g.downLeft]) }
            { true }                 { x = n1.col };
        case
            { e.entrySide == \left }  { y = n2.col - 1; out.add([r2, y, g.upRight]) }
            { e.entrySide == \right } { y = n2.col + 1; out.add([r2, y, g.upLeft]) }
            { true }                  { y = n2.col };
        if(x == y) {
            ~gridSpan.(r1 + 1, r2 - 1).do { |r| out.add([r, x, g.vert]) };
        } {
            ~gridSpan.(r1 + 1, j - 1).do { |r| out.add([r, x, g.vert]) };
            out.add([j, x, if(y > x) { g.upRight } { g.upLeft }]);
            ~gridSpan.(x.min(y) + 1, x.max(y) - 1).do { |c| out.add([j, c, g.horiz]) };
            out.add([j, y, if(y > x) { g.downLeft } { g.downRight }]);
            ~gridSpan.(j + 1, r2 - 1).do { |r| out.add([r, y, g.vert]) };
        };
        out;
    };

    // коллизия = пересечение связей, которое потребовало бы ┼/╬ — канон их не
    // даёт, поэтому пишем только целиком свободный маршрут
    place = { |list|
        var free = list.every { |t|
            (t[0] >= 0) and: { t[0] < rows } and: { t[1] >= 0 } and: { t[1] < cols }
                and: { field[t[0]][t[1]] == " " };
        };
        if(free) { list.do { |t| field[t[0]][t[1]] = t[2] } };
        free;
    };

    edgesByReach = graph[\edges].sort { |a, b|
        (a.src.col - a.dst.col).abs > (b.src.col - b.dst.col).abs
    };

    pass = {
        var fine = true;
        field = Array.fill(rows, { Array.fill(cols, " ") });
        // routeLen валиден только из УСПЕШНОГО прохода: каждый pass сбрасывает
        // поле, и без сброса неудачный проход оставил бы длину чужой полосы
        graph[\edges].do { |e| e[\routeLen] = nil };
        graph[\nodes].do { |n| if(place.([[rowOf.(n), n.col, n.ch]]).not) { fine = false } };
        edgesByReach.do { |e|
            if(fine) {
                var lanes = ~gridSpan.(rowOf.(e.src) + 1, rowOf.(e.dst) - 1).scramble;
                var done = false;
                lanes.do { |j|
                    var list;
                    if(done.not) {
                        list = cells.(e, j);
                        done = place.(list);
                        if(done) { e[\routeLen] = list.size };
                    };
                };
                if(done.not) { fine = false };
            };
        };
        fine;
    };

    if(ok) {
        var n = 0;
        routed = false;
        while { routed.not and: { n < ~cfg_grid.rasterTries } } {
            n = n + 1;
            routed = pass.value;
        };
        ok = routed;
    };

    if(ok) {
        var idx = IdentityDictionary[];
        graph[\nodes].do { |n, i| idx[n] = i };
        (
            field: field, nodes: graph[\nodes].size, rows: rows, cols: cols,
            graph: (
                tiers: graph[\tiers], rowGap: rowGap,
                nodes: graph[\nodes].collect { |n, i|
                    (
                        i: i, tier: n.tier, ch: n.ch,
                        indeg: n.ins.size, outdeg: n.outs.size,
                        // сила входа (правило 6): корень и точки схождения сильны
                        strongIn: (n.ins.size == 0)
                            or: { n.ins.size >= 2 }
                            or: { n.ins[0].strong }
                    )
                },
                edges: graph[\edges].collect { |e|
                    ( src: idx[e.src], dst: idx[e.dst],
                      strong: e.strong, routeLen: e[\routeLen] )
                }
            )
        )
    };
};

~gridGenerate = { |complexity = 0.5, seed|
    var t = complexity.clip(0, 1);
    var target = ~gridLerp.(~cfg_grid[\nodes], t).round.asInteger.max(2);
    var bp   = ~gridLerp.(~cfg_grid[\branchProb], t);
    var mp   = ~gridLerp.(~cfg_grid[\mergeProb], t);
    var cols = ~gridLerp.(~cfg_grid[\cols], t).round.asInteger;
    var rows = ~gridLerp.(~cfg_grid[\rows], t).round.asInteger;
    var mf = ~gridLerp.(~cfg_grid[\maxFront], t).round.asInteger.max(1);
    var got = nil, n = 0;
    // seed ставится ДО цикла ретраев: ретраи графов и перебор полос потребляют
    // один детерминированный поток -> (seed, complexity) воспроизводит рисунок
    // побитово; seed внутри цикла зациклил бы каждый graphTry на одном графе
    seed = seed ?? { Date.seed };
    thisThread.randSeed = seed;
    while { got.isNil and: { n < ~cfg_grid.graphTries } } {
        n = n + 1;
        got = ~gridAttempt.(~gridGrow.(target, bp, mp, mf), cols, rows);
    };
    got !? { got[\text] = ~gridRender.(got); got[\seed] = seed; got[\complexity] = t; got };
};

"0_grid — генератор структурных сеток (~gridGenerate / ~gridRender).".postln;
)
