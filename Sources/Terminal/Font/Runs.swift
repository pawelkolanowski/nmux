// A row's runs and the map from shaped glyphs back to cells, as plain values, adapted from Ghostty's
// `src/font/shaper/run.zig` (`RunIterator`) and `src/font/shaper/coretext.zig` (`shape`, `RunIteratorHook`) at commit
// 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// A cell as the run iterator sees it. `codepoints` is the cluster to shape, the base first, and empty for a cell with
/// no text, which shapes as a space. `style` and `face` are ids, equal exactly where Ghostty's comparable style (the
/// style without its background) and font index are.
struct RunCell: Hashable {
    var codepoints: Cluster = []
    var style = 0
    var face = 0
    var spacer = false
    var invisible = false
    /// libghostty-vt's empty cell, no text and no background of its own; a row's trailing ones are trimmed.
    var empty = true

    var grapheme: Bool { codepoints.count > 1 }
}

/// A cell's codepoints, the base first: the base inline and the rest in an array only a grapheme cluster fills, so a
/// rebuilt row allocates nothing for its plain cells.
struct Cluster: RandomAccessCollection, Hashable, ExpressibleByArrayLiteral {
    private var base: UInt32 = 0
    private var tail: [UInt32] = []
    let endIndex: Int
    var startIndex: Int { 0 }

    init(_ codepoints: some Collection<UInt32>) {
        base = codepoints.first ?? 0
        tail = Array(codepoints.dropFirst())
        endIndex = codepoints.count
    }

    init(arrayLiteral codepoints: UInt32...) { self.init(codepoints) }

    subscript(i: Int) -> UInt32 { i == 0 ? base : tail[i - 1] }
}

/// Ghostty's `RunIterator.next` over a whole row, each run as the cells it covers. A run breaks where the style or the
/// face changes, between `f` and `l` or `i`, between `s` and `t`, and on both sides of the cursor's cell unless that
/// cell is a grapheme. Invisible cells at a run's start are skipped, spacers ride along with the run, and trailing
/// empty cells are trimmed.
func runs(_ cells: [RunCell], cursor: Int?) -> [Range<Int>] {
    let end = (cells.lastIndex { !$0.empty } ?? -1) + 1
    var out: [Range<Int>] = []
    var i = 0
    while true {
        while i < end && cells[i].invisible { i += 1 }
        guard i < end else { return out }
        var j = i, face: Int?
        while j < end {
            let cell = cells[j]
            if cell.spacer { j += 1; continue }
            if j > i {
                let prev = cells[j - 1]
                if !prev.grapheme && !cell.grapheme, let p = prev.codepoints.first, let c = cell.codepoints.first,
                   p == 0x66 && (c == 0x6C || c == 0x69) || p == 0x73 && c == 0x74 { break }
                if cell.style != cells[i].style { break }
            }
            if !cell.grapheme, let cursor, i == cursor && j == i + 1 || i < cursor && j == cursor { break }
            if face == nil { face = cell.face } else if cell.face != face { break }
            j += 1
        }
        out.append(i..<j)
        i = j
    }
}

/// VS15 and VS16 pick a face and draw nothing.
func isPresentationSelector(_ cp: UInt32) -> Bool { cp == 0xFE0E || cp == 0xFE0F }

/// Whether a face draws a codepoint as text or as a colour emoji.
public enum Presentation: Sendable {
    case text, emoji
}

/// The presentation a cluster asks for, Ghostty's in `RunIterator.next`: VS15 or VS16 right after the base, else none.
func requestedPresentation(_ cluster: some Collection<UInt32>) -> Presentation? {
    switch cluster.dropFirst().first {
    case 0xFE0E: .text
    case 0xFE0F: .emoji
    default: nil
    }
}

/// Unicode's default presentation, its `Emoji_Presentation` property, which a codepoint with no request takes in a
/// fallback face.
func defaultPresentation(_ cp: UInt32) -> Presentation {
    Unicode.Scalar(cp)?.properties.isEmojiPresentation == true ? .emoji : .text
}

/// One run's text as CoreText takes it, in UTF-16, and Ghostty's codepoint map: for each unit, its codepoint and its
/// cell counted from the run's start. A surrogate pair's second unit maps to codepoint 0. Presentation selectors are
/// left out, as they pick a face and draw nothing.
struct RunText {
    var utf16: [UInt16] = []
    var map: [(codepoint: UInt32, cluster: Int)] = []
}

func runText(_ cells: ArraySlice<RunCell>) -> RunText {
    var text = RunText()
    for (cluster, cell) in zip(0..., cells) where !cell.spacer {
        for cp in cell.codepoints.isEmpty ? [0x20] : cell.codepoints where !isPresentationSelector(cp) {
            guard let scalar = Unicode.Scalar(cp) else { continue }
            let units = Array(String(Character(scalar)).utf16)
            text.utf16 += units
            text.map.append((cp, cluster))
            if units.count == 2 { text.map.append((0, cluster)) }
        }
    }
    return text
}

/// A glyph as CoreText laid it out: its index into the run's UTF-16, its position and its advance, in pixels.
struct LaidGlyph {
    var index: Int
    var x = 0.0, y = 0.0
    var advance = 0.0
}

/// Ghostty's map from glyphs to cells: a glyph opens a new cell only when its codepoint is the first of its cluster and
/// that cluster lies beyond every cluster seen, so a ligature stays on its first cell and a mark on its base. Each
/// glyph keeps its offset from that cell's start, rounded to the pixel, in the order CoreText laid the glyphs.
func cellsOf(_ glyphs: [LaidGlyph], map: [(codepoint: UInt32, cluster: Int)]) -> [(cell: Int, x: Int, y: Int)] {
    var runX = 0.0, runCluster = 0
    var cellX = 0.0, cellCluster = 0
    var out: [(cell: Int, x: Int, y: Int)] = []
    for g in glyphs {
        let cluster = map[g.index].cluster
        if cellCluster != cluster {
            // The nearest earlier unit that is not a surrogate's second half belongs to another cluster.
            let first = map[..<g.index].last { $0.codepoint != 0 }.map { $0.cluster != cluster } ?? true
            if first && cluster > runCluster { (cellCluster, cellX) = (cluster, runX) }
        }
        out.append((cellCluster, Int((g.x - cellX).rounded()), Int(g.y.rounded())))
        runX += g.advance
        runCluster = max(runCluster, cluster)
    }
    return out
}
