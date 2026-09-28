// App/lines.scd — NET · the geometry of one column, in rows. A column is an
// array of entries (row:, len:, fixed:) sorted by row, on a rail of n rows;
// `len` is a signed line length in rows: + runs down, − runs up. A line stops
// at the frame and at the next entry and shares a gap with the line coming the
// other way; a row under a line takes no entry. `fixed` lengths are never
// moved, the others are being placed. No cells, no server, no chance: entries
// are the caller's scratch copies and may carry any payload.
// Reference: docs/features/matrix-ru.md.

// ===== CONFIG — edit here ============================================
(
// private to this file: the closures below keep them after the block ends
var eps, sorted, lower, gapsOf, roomOf, coveredIn, share;

~cfg_lines = (
    lineRows: 10
);


// ===== LOGIC =========================================================
eps = 1e-9;

sorted = { |col| col.sort { |x, y| x[\row] < y[\row] } };

lower = { |col, r|
    var lo = 0, hi = col.size, mid;
    while { lo < hi } {
        mid = (lo + hi) div: 2;
        if(col[mid][\row] < r) { lo = mid + 1 } { hi = mid };
    };
    lo
};

gapsOf = { |col, n|
    col.collect { |e, i| [
        e[\row] - (if(i > 0) { col[i - 1][\row] } { -1 }) - 1,
        (if(i + 1 < col.size) { col[i + 1][\row] } { n }) - e[\row] - 1
    ] }
};

roomOf = { |col, r, n|
    var i = lower.(col, r), j = i, a, b;
    while { (j < col.size) and: { col[j][\row] == r } } { j = j + 1 };
    a = if(i > 0) { col[i - 1] };
    b = if(j < col.size) { col[j] };
    [
        r - (a !? { a[\row] } ? -1) - 1 - (a !? { a[\len].max(0) } ? 0),
        (b !? { b[\row] } ? n) - r - 1 - (b !? { b[\len].neg.max(0) } ? 0)
    ].collect { |x| if(x < eps) { 0 } { x.min(~cfg_lines.lineRows) } }
};

coveredIn = { |col, r|
    col.any { |e|
        var k = (r - e[\row]) * e[\len].sign;
        (k > 0) and: { (k - 1) < (e[\len].abs - eps) }
    }
};

// each gap is touched once, so the order the lines come in does not matter
share = { |col, n|
    var gaps;
    col = sorted.(col);
    gaps = gapsOf.(col, n);
    col.do { |e, i|
        var g = (if(e[\len] > 0) { gaps[i][1] } { gaps[i][0] }).min(~cfg_lines.lineRows);
        if(e[\fixed].not and: { e[\len].abs > (g + eps) }) { e[\len] = e[\len].sign * g };
    };
    (col.size - 1).do { |i|
        var a = col[i], b = col[i + 1], g = gaps[i][1], la = a[\len], lb = b[\len].neg, f;
        if((la > 0) and: { lb > 0 } and: { (la + lb) > (g + eps) }) {
            case
            { a[\fixed] and: { b[\fixed].not } } { b[\len] = (g - la).max(0).neg }
            { b[\fixed] and: { a[\fixed].not } } { a[\len] = (g - lb).max(0) }
            { f = g / (la + lb); a[\len] = la * f; b[\len] = lb.neg * f };
        };
    };
    col
};


~linesRange = { |col, r, n|
    if(coveredIn.(col, r)) { [0, 0] } { roomOf.(col, r, n) * [-1, 1] }
};

// `least` in rows: a neighbour being placed with no more room than that
// could only ever get a line too short to exist
~linesAccept = { |col, entry, n, least = 0|
    var r = entry[\row], i = lower.(col, r), trial;
    if(((i < col.size) and: { col[i][\row] == r }) or: { coveredIn.(col, r) }) { col } {
        trial = col.copy.insert(i, entry);
        if([i - 1, i, i + 1].every { |j|
            var e = if((j >= 0) and: { j < trial.size }) { trial[j] };
            e.isNil or: { e[\fixed] } or: { roomOf.(trial, e[\row], n).sum > least }
        }) { trial } { col }
    }
};

// the rooms are taken before any new line exists, so the deal is order-free
~linesDeal = { |col, n, lenFn|
    var fresh = col.reject { |e| e[\fixed] };
    var rooms = fresh.collect { |e| roomOf.(col, e[\row], n) };
    fresh.do { |e, i| e[\len] = lenFn.(rooms[i][0], rooms[i][1]) };
    share.(col, n)
};

// the Matrix draws its lines in lineRows
~netChanged !? { |f| f.value };


"lines — геометрия столбца (~linesRange, ~linesAccept, ~linesDeal).".postln;
)
