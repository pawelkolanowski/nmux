// The cell from a face's numbers, the fallback scale and the grid fit.
//
// `cellMetrics` is adapted from Ghostty's `src/font/Metrics.zig` (`calc`, `FaceMetrics`) and `fallbackScale` from
// `src/font/Collection.zig` (`scaleFactor`), at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The client's size in cells.
public struct Grid: Equatable, Sendable {
    public let cols: Int
    public let rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }
}

/// A face's numbers in pixels, relative to the baseline with +y up; descent is negative.
struct FaceMetrics {
    var pxPerEm: Double
    /// The advance of the widest printable ASCII glyph.
    var cellWidth: Double
    var ascent: Double
    var descent: Double
    var lineGap: Double
    /// The top of each stroke.
    var underlinePosition: Double?
    var underlineThickness: Double?
    var strikethroughPosition: Double?
    var strikethroughThickness: Double?
    var capHeight: Double?
    var exHeight: Double?

    var lineHeight: Double { ascent - descent + lineGap }

    /// A missing or non-positive metric takes Ghostty's estimate.
    var estimatedCapHeight: Double { positive(capHeight) ?? 0.75 * ascent }
    var estimatedExHeight: Double { positive(exHeight) ?? 0.75 * estimatedCapHeight }
    var estimatedUnderlineThickness: Double { positive(underlineThickness) ?? 0.15 * estimatedExHeight }
    var estimatedStrikethroughThickness: Double { positive(strikethroughThickness) ?? estimatedUnderlineThickness }
    var estimatedUnderlinePosition: Double { underlinePosition ?? -estimatedUnderlineThickness }
    var estimatedStrikethroughPosition: Double {
        strikethroughPosition ?? (estimatedExHeight + estimatedStrikethroughThickness) / 2
    }
}

private func positive(_ value: Double?) -> Double? { value.flatMap { $0 > 0 ? $0 : nil } }

/// The cell in whole pixels. The baseline counts from the cell's bottom; the positions from its top.
public struct Cell: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let baseline: Int
    let underlinePosition: Int
    let underlineThickness: Int
    let strikethroughPosition: Int
    let strikethroughThickness: Int
    /// Ghostty's default; the bar and underline cursors draw this thick.
    let cursorThickness: Int
    /// The face's own fractional size, and the offset of its bottom from the cell's, for glyph placement.
    let faceWidth: Double
    let faceHeight: Double
    let faceY: Double
}

/// Rounded, never ceiled, so the cell stays within half a pixel of the design.
func cellMetrics(_ face: FaceMetrics) -> Cell {
    let faceWidth = face.cellWidth, faceHeight = face.lineHeight
    let width = faceWidth.rounded(), height = faceHeight.rounded()
    // Half the line gap sits under the descent; the face is centred in the rounded height.
    let faceBaseline = face.lineGap / 2 - face.descent
    let baseline = (faceBaseline - (height - faceHeight) / 2).rounded()
    let topToBaseline = height - baseline
    return Cell(
        width: max(1, Int(width)),
        height: max(1, Int(height)),
        baseline: Int(baseline),
        underlinePosition: Int((topToBaseline - face.estimatedUnderlinePosition).rounded()),
        underlineThickness: max(1, Int(face.estimatedUnderlineThickness.rounded(.up))),
        strikethroughPosition: Int((topToBaseline - face.estimatedStrikethroughPosition).rounded()),
        strikethroughThickness: max(1, Int(face.estimatedStrikethroughThickness.rounded(.up))),
        cursorThickness: 1,
        faceWidth: max(1, faceWidth),
        faceHeight: max(1, faceHeight),
        faceY: baseline - faceBaseline)
}

/// The factor a fallback face's size takes to match the primary: the ratio of ex heights, else cap heights,
/// else line heights, whichever both faces have first, compared in ems; 1 when neither has a line height.
func fallbackScale(primary: FaceMetrics, face: FaceMetrics) -> Double {
    let pairs: [(Double?, Double?)] = [
        (primary.exHeight, face.exHeight),
        (primary.capHeight, face.capHeight),
        (primary.lineHeight, face.lineHeight),
    ]
    for (p, f) in pairs {
        if let p = positive(p), let f = positive(f) { return (p / primary.pxPerEm) / (f / face.pxPerEm) }
    }
    return 1
}

/// As many whole cells as the pixels hold, at least 1 × 1.
func gridFit(width: Int, height: Int, cell: Cell) -> Grid {
    Grid(cols: max(1, width / cell.width), rows: max(1, height / cell.height))
}
