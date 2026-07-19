// App/0_grid.scd — UNGRUND · GRID: генератор сеток по канону
// docs/architecture/structure-grid/README.md (правила 1–9). Чистая логика.
// API: ~gridGenerate.(complexity, seed) -> ( text:, field:, nodes:, rows:,
//      cols:, seed:, complexity:, counts:, graph: ) или nil при отказе;
//      ~gridRender.(grid) -> строка поля.
// Алфавит: structure-grid/char.md; несущие WHY реализации:
// docs/features/grid-modulation/reference.md, Implementation notes.

(
// ===== CONFIG — edit here ============================================
// Между парой [a, b] интерполирует слайдер сложности 0..1; поле фиксировано
// 16×16 (override 2026-07-18).
~cfg_grid = (
    nodes:      [7, 20],        // число Ф при сложности 0 -> 1
    // нижние границы НУЛЕВЫЕ (правило 9): c = 0 обязан дать один голый ствол
    branchProb: [0.00, 0.90],   // вероятность ветвления Ф (правило 4)
    mergeProb:  [0.00, 0.95],   // вероятность схождения двух ветвей в один Ф
    maxOut:     3,              // максимум исходящих связей из узла
    maxFront:   [1, 5],         // фронт шире 5 не разводится — молчаливый отсев сместил бы выборку
    cols:       16,             // ширина поля  (канонный минимум, фикс.)
    rows:       16,             // высота поля  (канонный минимум, фикс.)
    // шаг рангов выводится из графа (rowGap = (rows-2) div (tiers-1), кламп) —
    // фиксированный шаг отбраковывал стволовые графы (Implementation notes)
    rowGapMin:  2,              // правило 3: между рангами хотя бы одна связь
    rowGapMax:  8,              // потолок шага (длиннее связи не растягиваем)
    colGap:     3,              // шаг узлов по колонкам   (>= 3: боковые выходы)
    relax:      4,              // сглаживающих проходов раскладки (короче связи)
    rasterTries: 24,            // попыток развести ОДИН граф; 16×16 требует запаса
    graphTries: 120             // попыток вырастить новый граф до отказа
);


// ===== LOGIC — граф, раскладка, растеризация =========================
// алфавит канона (ред. 2026-07-18): переходные углы — знак возврата (пр. 7),
// кресты — пересечения (пр. 8); ветвление/схождение только в Ф
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

// (a..b) при a > b в SC идёт ВНИЗ и непуст — вырожденный сегмент рисовал бы лишнее
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
        // розыгрыш od случаен, слоты — фронтовым порядком: без крена влево
        (0 .. frontier.size - 1).scramble.do { |ix|
            var n = frontier[ix];
            // суммарная степень Ф <= 4: у ячейки ровно четыре соседа (правило 4)
            var cap = ~cfg_grid.maxOut.min(4 - n.ins.size).min(budget).min(room);
            // od = 0 при исчерпании — лист (пр. 5); корень не ветвится (пр. 2, 6);
            // rrand(2, cap) при cap = 1 вернул бы 2 — ветвимся только при cap >= 2
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
// ряд ставится на СРЕДНЮЮ желаемую колонку (не в центр поля) и НЕ
// пересортировывается: порядок рождения = плоское вложение графа
// (Implementation notes)
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

// ----- стороны Ф: каждая связь занимает ровно одного соседа; входящая
// никогда не берёт \down, исходящая — \up (направление развития)
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
// неудачная разводка перебирается НА ТОМ ЖЕ графе (rasterTries) — отсев по
// коллизии сместил бы выборку; возвраты best-effort по закону предка,
// пересечения — вторым кругом полос в квоте правила 9 (поправка 2026-07-18)
~gridAttempt = { |graph, cols, rows, cx = 0.5|
    var field;
    var ok = true;
    var rowGap, rowOf, cells, place, edgesByReach, routed, pass;
    var nN = graph[\nodes].size;
    var retQuota   = (cx * nN / 4).floor.asInteger;
    var crossQuota = (cx * nN / 3).floor.asInteger;
    var crossCount = 0;
    var rets, ancestorsOf, freeH, retCells, retLanes;
    var isV = { |s| (s == "│") or: { s == "║" } };
    var isH = { |s| (s == "─") or: { s == "═" } };

    // шаг рангов под конкретный граф: стволовой сжимается, низкий растягивается
    // и получает полосы — отсев по высоте не выбивает стволовые
    rowGap = if(graph[\tiers] > 1) {
        ((rows - 2) div: (graph[\tiers] - 1)).clip(~cfg_grid.rowGapMin, ~cfg_grid.rowGapMax)
    } { ~cfg_grid.rowGapMax };

    rowOf = { |n| 1 + (n.tier * rowGap) };

    // недостижимо при канонном CONFIG — страхует ручную правку nodes/rows
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

    // --- возвраты (правило 7): выбор ПОСЛЕ раскладки и сторон; предки —
    // упорядоченными списками, не IdentitySet (детерминизм seed)
    rets = List[];
    if(ok) {
        graph[\nodes].do { |n|
            n[\sidesUsed] = n.ins.collect { |e| e.entrySide }
                ++ n.outs.collect { |e| e.exitSide };
            n[\retNeed] = 0;
        };
        ancestorsOf = IdentityDictionary[];
        graph[\nodes].do { |n|
            var lst = List[];
            n.ins.do { |e|
                if(lst.detect { |a| a === e.src }.isNil) { lst.add(e.src) };
                ancestorsOf[e.src].do { |a|
                    if(lst.detect { |x| x === a }.isNil) { lst.add(a) };
                };
            };
            ancestorsOf[n] = lst;
        };
        freeH = { |n|
            ([\left, \right].reject { |s| n[\sidesUsed].includes(s) }).size;
        };
        if(retQuota > 0) {
            var cands = List[];
            graph[\nodes].do { |n|
                ancestorsOf[n].do { |a| cands.add([n, a]) };
            };
            cands.asArray.scramble.do { |pair|
                var s = pair[0], d = pair[1];
                if((rets.size < retQuota)
                    and: { s[\retOut] != true } and: { d[\retIn] != true }
                    and: { freeH.(s) > s[\retNeed] } and: { freeH.(d) > d[\retNeed] }
                ) {
                    rets.add((
                        src: s, dst: d,
                        // возврат наследует силу ВХОДА src (правило 6)
                        strong: (s.ins.size >= 2)
                            or: { s.ins.size == 0 }
                            or: { s.ins[0].strong }
                    ));
                    s[\retOut] = true; d[\retIn] = true;
                    s[\retNeed] = s[\retNeed] + 1;
                    d[\retNeed] = d[\retNeed] + 1;
                };
            };
        };
    };

    // оси возврата разносильны (правило 7); смешанный угол = знак смены
    // направления чтения
    retCells = { |e, x|
        var src = e[\src], dst = e[\dst];
        var r1 = rowOf.(src), c1 = src.col;
        var r2 = rowOf.(dst), c2 = dst.col;
        var strong = e[\strong];
        var vert  = if(strong) { "║" } { "│" };
        var horiz = if(strong) { "─" } { "═" };
        var bot = if(x > c1) { if(strong) { "╜" } { "╛" } } { if(strong) { "╙" } { "╘" } };
        var top = if(x > c2) { if(strong) { "╖" } { "╕" } } { if(strong) { "╓" } { "╒" } };
        var out = List[];
        ~gridSpan.(c1.min(x) + 1, c1.max(x) - 1).do { |c| out.add([r1, c, horiz]) };
        out.add([r1, x, bot]);
        ~gridSpan.(r2 + 1, r1 - 1).do { |r| out.add([r, x, vert]) };
        out.add([r2, x, top]);
        ~gridSpan.(c2.min(x) + 1, c2.max(x) - 1).do { |c| out.add([r2, c, horiz]) };
        out;
    };

    // колонка x задаёт стороны обоих концов; x == col исключён (Implementation notes)
    retLanes = { |e|
        var src = e[\src], dst = e[\dst];
        var out = List[];
        (1 .. cols - 2).do { |x|
            var sSide, dSide;
            if((x != src.col) and: { x != dst.col }) {
                sSide = if(x > src.col) { \right } { \left };
                dSide = if(x > dst.col) { \right } { \left };
                if(
                    src[\sidesUsed].includes(sSide).not
                    and: { src[\retSides].includes(sSide).not }
                    and: { dst[\sidesUsed].includes(dSide).not }
                    and: { dst[\retSides].includes(dSide).not }
                ) {
                    out.add(( x: x, srcSide: sSide, dstSide: dSide ));
                };
            };
        };
        out.asArray.scramble;
    };

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

    // правило 8: пересечение — строго вертикаль сквозь горизонталь в квоте,
    // крест по силам осей; allowCross=false — плоский закон (и весь c=0)
    place = { |list, allowCross = false|
        var need = List[];
        var fine = true;
        var crossFor = { |vSym, hSym|
            if(vSym == "║") { if(hSym == "═") { "╬" } { "╫" } }
            { if(hSym == "═") { "╪" } { "┼" } };
        };
        list.do { |t|
            var cur;
            if(fine) {
                if((t[0] < 0) or: { t[0] >= rows } or: { t[1] < 0 } or: { t[1] >= cols }) {
                    fine = false;
                } {
                    cur = field[t[0]][t[1]];
                    case
                        { cur == " " } { }
                        { allowCross.not } { fine = false }
                        { isV.(t[2]) and: { isH.(cur) } } { need.add([t[0], t[1], crossFor.(t[2], cur)]) }
                        { isH.(t[2]) and: { isV.(cur) } } { need.add([t[0], t[1], crossFor.(cur, t[2])]) }
                        { true } { fine = false };
                };
            };
        };
        if(fine and: { (crossCount + need.size) > crossQuota }) { fine = false };
        if(fine) {
            list.do { |t| if(field[t[0]][t[1]] == " ") { field[t[0]][t[1]] = t[2] } };
            need.do { |t| field[t[0]][t[1]] = t[2] };
            crossCount = crossCount + need.size;
        };
        fine;
    };

    edgesByReach = graph[\edges].sort { |a, b|
        (a.src.col - a.dst.col).abs > (b.src.col - b.dst.col).abs
    };

    pass = {
        var fine = true;
        field = Array.fill(rows, { Array.fill(cols, " ") });
        crossCount = 0;
        // routeLen валиден только из УСПЕШНОГО прохода — сброс обязателен
        graph[\edges].do { |e| e[\routeLen] = nil };
        rets.do { |e| e[\routeLen] = nil; e[\placed] = false };
        graph[\nodes].do { |n| n[\retSides] = List[] };
        graph[\nodes].do { |n| if(place.([[rowOf.(n), n.col, n.ch]]).not) { fine = false } };
        edgesByReach.do { |e|
            if(fine) {
                var lanes = ~gridSpan.(rowOf.(e.src) + 1, rowOf.(e.dst) - 1).scramble;
                var done = false;
                // без пересечения предпочтительно: второй круг — когда плоско нельзя
                [false, true].do { |allow|
                    lanes.do { |j|
                        var list;
                        if(done.not) {
                            list = cells.(e, j);
                            done = place.(list, allow);
                            if(done) { e[\routeLen] = list.size };
                        };
                    };
                };
                if(done.not) { fine = false };
            };
        };
        // возвраты best-effort ПОСЛЕ остова: неуложившийся отбрасывается
        if(fine) {
            rets.do { |e|
                var lanes = retLanes.(e);
                var done = false;
                [false, true].do { |allow|
                    lanes.do { |lane|
                        var list;
                        if(done.not) {
                            list = retCells.(e, lane[\x]);
                            done = place.(list, allow);
                            if(done) {
                                e[\routeLen] = list.size;
                                e[\placed] = true;
                                e[\src][\retSides].add(lane[\srcSide]);
                                e[\dst][\retSides].add(lane[\dstSide]);
                            };
                        };
                    };
                };
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
        var placedRets = rets.select { |e| e[\placed] == true };
        var retInOf = IdentityDictionary[], retOutOf = IdentityDictionary[];
        var transitions = 0, crosses = 0;
        var retCorner = ["╒", "╓", "╘", "╙", "╕", "╖", "╛", "╜"];
        var crossSyms = ["┼", "╬", "╫", "╪"];
        graph[\nodes].do { |n, i| idx[n] = i };
        placedRets.do { |e|
            retOutOf[e[\src]] = (retOutOf[e[\src]] ? 0) + 1;
            retInOf[e[\dst]]  = (retInOf[e[\dst]] ? 0) + 1;
        };
        // счётчики ПО ГОТОВОМУ ПОЛЮ (правило 9); String-членство через == (контракт §6)
        field.do { |row| row.do { |s|
            if(retCorner.any { |x| x == s }) { transitions = transitions + 1 };
            if(crossSyms.any { |x| x == s }) { crosses = crosses + 1 };
        } };
        (
            field: field, nodes: graph[\nodes].size, rows: rows, cols: cols,
            counts: (
                branching: graph[\nodes].count { |n| n.outs.size >= 2 },
                transitions: transitions,
                crosses: crosses
            ),
            graph: (
                tiers: graph[\tiers], rowGap: rowGap,
                nodes: graph[\nodes].collect { |n, i|
                    (
                        i: i, tier: n.tier, ch: n.ch,
                        // степени двух родов: остов (indegS/outdegS) — Чтению 1,
                        // полный граф — Чтению 2
                        indegS: n.ins.size, outdegS: n.outs.size,
                        indeg: n.ins.size + (retInOf[n] ? 0),
                        outdeg: n.outs.size + (retOutOf[n] ? 0),
                        // сила входа ПО ОСТОВУ (правило 6)
                        strongIn: (n.ins.size == 0)
                            or: { n.ins.size >= 2 }
                            or: { n.ins[0].strong }
                    )
                },
                edges: graph[\edges].collect { |e|
                    ( src: idx[e.src], dst: idx[e.dst],
                      strong: e.strong, ret: false, routeLen: e[\routeLen] )
                } ++ placedRets.collect { |e|
                    ( src: idx[e[\src]], dst: idx[e[\dst]],
                      strong: e[\strong], ret: true, routeLen: e[\routeLen] )
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
    var cols = ~cfg_grid[\cols];
    var rows = ~cfg_grid[\rows];
    var mf = ~gridLerp.(~cfg_grid[\maxFront], t).round.asInteger.max(1);
    var got = nil, n = 0;
    // seed ДО цикла ретраев: один детерминированный поток => (seed, complexity)
    // воспроизводит рисунок побитово (dsp-spec Konstruktion)
    seed = seed ?? { Date.seed };
    thisThread.randSeed = seed;
    while { got.isNil and: { n < ~cfg_grid.graphTries } } {
        n = n + 1;
        got = ~gridAttempt.(~gridGrow.(target, bp, mp, mf), cols, rows, t);
    };
    got !? { got[\text] = ~gridRender.(got); got[\seed] = seed; got[\complexity] = t; got };
};

"0_grid — генератор структурных сеток (~gridGenerate / ~gridRender).".postln;
)
