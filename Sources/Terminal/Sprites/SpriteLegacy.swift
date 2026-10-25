import CoreGraphics

// Symbols for Legacy Computing, U+1FB00 to U+1FBEF, and its supplement, U+1CC1B to U+1CEAF, as far as Ghostty draws
// them. Adapted from Ghostty's `src/font/sprite/draw/symbols_for_legacy_computing.zig`,
// `symbols_for_legacy_computing_supplement.zig` and `octants.txt` at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// 🬼 to 🭧 as Ghostty's hand-written table draws them: four rows of three, `#` where the shape covers that point.
private let smoothMosaics = [
    "...|...|#..|##.", "...|...|#..|###", "...|#..|#..|##.", "...|#..|##.|###", "#..|#..|##.|##.", ".##|###|###|###",
    "..#|###|###|###", ".##|.##|###|###", "..#|.##|###|###", ".##|.##|.##|###", "...|..#|###|###", "...|...|..#|.##",
    "...|...|..#|###", "...|..#|..#|.##", "...|..#|.##|###", "..#|..#|.##|.##", "##.|###|###|###", "#..|###|###|###",
    "##.|##.|###|###", "#..|##.|###|###", "##.|##.|##.|###", "...|#..|###|###", "###|###|###|.##", "###|###|###|..#",
    "###|###|.##|.##", "###|###|.##|..#", "###|.##|.##|.##", "##.|#..|...|...", "###|#..|...|...", "##.|#..|#..|...",
    "###|##.|#..|...", "##.|##.|#..|#..", "###|###|#..|...", "###|###|###|##.", "###|###|###|#..", "###|###|##.|##.",
    "###|###|##.|#..", "###|##.|##.|##.", ".##|..#|...|...", "###|..#|...|...", ".##|..#|..#|...", "###|.##|..#|...",
    ".##|.##|..#|..#", "###|###|..#|...",
]

func drawLegacy(_ cp: UInt32, _ c: inout Canvas, _ cell: Cell) {
    switch cp {
    case 0x1FB00...0x1FB3B:
        // Sextants: the codepoint counts the patterns, skipping the ones other blocks already have.
        let idx = cp - 0x1FB00, bits = idx + idx / 0x14 + 1
        let thirds: [(Double, Double)] = [(0, 1.0 / 3), (1.0 / 3, 2.0 / 3), (2.0 / 3, 1)]
        for (bit, (row, half)) in [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (2, 1)].enumerated()
            where bits >> bit & 1 != 0 {
            fillFraction(cell, &c, Double(half) / 2, Double(half + 1) / 2, thirds[row].0, thirds[row].1)
        }
    case 0x1FB3C...0x1FB67: smoothMosaic(cell, &c, smoothMosaics[Int(cp - 0x1FB3C)])
    case 0x1FB68...0x1FB6B:
        // The cell less the triangle on that edge.
        edgeTriangle(cell, &c, [.left, .top, .right, .bottom][Int(cp - 0x1FB68)])
        c.invertWithinCell()
    case 0x1FB6C...0x1FB6F: edgeTriangle(cell, &c, [.left, .top, .right, .bottom][Int(cp - 0x1FB6C)])
    // Vertical then horizontal one eighth blocks, the second to the seventh.
    case 0x1FB70...0x1FB75:
        let n = Double(cp + 1 - 0x1FB70)
        fillFraction(cell, &c, n / 8, (n + 1) / 8, 0, 1)
    case 0x1FB76...0x1FB7B: horizontalEighth(cell, &c, Int(cp + 1 - 0x1FB76))
    case 0x1FB7C:
        block(cell, &c, .left, 0.125, 1)
        block(cell, &c, .lower, 1, 0.125)
    case 0x1FB7D:
        block(cell, &c, .left, 0.125, 1)
        block(cell, &c, .upper, 1, 0.125)
    case 0x1FB7E:
        block(cell, &c, .right, 0.125, 1)
        block(cell, &c, .upper, 1, 0.125)
    case 0x1FB7F:
        block(cell, &c, .right, 0.125, 1)
        block(cell, &c, .lower, 1, 0.125)
    case 0x1FB80:
        block(cell, &c, .upper, 1, 0.125)
        block(cell, &c, .lower, 1, 0.125)
    case 0x1FB81: for n in [0, 2, 4, 7] { horizontalEighth(cell, &c, n) }
    case 0x1FB82: block(cell, &c, .upper, 1, 0.25)
    case 0x1FB83: block(cell, &c, .upper, 1, 0.375)
    case 0x1FB84: block(cell, &c, .upper, 1, 0.625)
    case 0x1FB85: block(cell, &c, .upper, 1, 0.75)
    case 0x1FB86: block(cell, &c, .upper, 1, 0.875)
    case 0x1FB87: block(cell, &c, .right, 0.25, 1)
    case 0x1FB88: block(cell, &c, .right, 0.375, 1)
    case 0x1FB89: block(cell, &c, .right, 0.625, 1)
    case 0x1FB8A: block(cell, &c, .right, 0.75, 1)
    case 0x1FB8B: block(cell, &c, .right, 0.875, 1)
    case 0x1FB8C: block(cell, &c, .left, 0.5, 1, Shade.medium)
    case 0x1FB8D: block(cell, &c, .right, 0.5, 1, Shade.medium)
    case 0x1FB8E: block(cell, &c, .upper, 1, 0.5, Shade.medium)
    case 0x1FB8F: block(cell, &c, .lower, 1, 0.5, Shade.medium)
    case 0x1FB90: fullBlockShade(cell, &c, Shade.medium)
    case 0x1FB91:
        fullBlockShade(cell, &c, Shade.medium)
        block(cell, &c, .upper, 1, 0.5)
    case 0x1FB92:
        fullBlockShade(cell, &c, Shade.medium)
        block(cell, &c, .lower, 1, 0.5)
    // U+1FB93 is unassigned and draws nothing.
    case 0x1FB93: break
    case 0x1FB94:
        fullBlockShade(cell, &c, Shade.medium)
        block(cell, &c, .right, 0.5, 1)
    case 0x1FB95: checkerboardFill(cell, &c, 0)
    case 0x1FB96: checkerboardFill(cell, &c, 1)
    case 0x1FB97:
        c.box(0, c.height / 4, c.width, 2 * c.height / 4)
        c.box(0, 3 * c.height / 4, c.width, c.height)
    case 0x1FB98: diagonalFill(cell, &c, down: true)
    case 0x1FB99: diagonalFill(cell, &c, down: false)
    case 0x1FB9A:
        edgeTriangle(cell, &c, .top)
        edgeTriangle(cell, &c, .bottom)
    case 0x1FB9B:
        edgeTriangle(cell, &c, .left)
        edgeTriangle(cell, &c, .right)
    case 0x1FB9C: cornerTriangleShade(cell, &c, .tl, Shade.medium)
    case 0x1FB9D: cornerTriangleShade(cell, &c, .tr, Shade.medium)
    case 0x1FB9E: cornerTriangleShade(cell, &c, .br, Shade.medium)
    case 0x1FB9F: cornerTriangleShade(cell, &c, .bl, Shade.medium)
    case 0x1FBA0...0x1FBAE:
        // 🮠 to 🮮 as the corners each joins: top left, top right, bottom left, bottom right.
        let corners = ["#...", ".#..", "..#.", "...#", "#.#.", ".#.#", "..##", "##..", "#..#", ".##.", ".###", "#.##",
                       "##.#", "###.", "####"][Int(cp - 0x1FBA0)]
        cornerDiagonalLines(cell, &c, corners)
    case 0x1FBAF: linesChar(cell, &c, Lines("hlhl"))
    case 0x1FBBD:
        lightDiagonalCross(cell, &c)
        c.invertWithinCell()
    case 0x1FBBE:
        cornerDiagonalLines(cell, &c, "...#")
        c.invertWithinCell()
    case 0x1FBBF:
        cornerDiagonalLines(cell, &c, "####")
        c.invertWithinCell()
    case 0x1FBCE: block(cell, &c, .left, 2.0 / 3, 1)
    case 0x1FBCF: block(cell, &c, .left, 1.0 / 3, 1)
    case 0x1FBD0...0x1FBDF:
        // Each a line, or two, between points of the cell's edges and centre.
        let lines: [[(Alignment, Alignment)]] = [
            [(.right, .lowerLeft)], [(.upperRight, .left)], [(.upperLeft, .right)], [(.left, .lowerRight)],
            [(.upperLeft, .lower)], [(.upper, .lowerRight)], [(.upperRight, .lower)], [(.upper, .lowerLeft)],
            [(.upperLeft, .center), (.center, .upperRight)], [(.upperRight, .center), (.center, .lowerRight)],
            [(.lowerLeft, .center), (.center, .lowerRight)], [(.upperLeft, .center), (.center, .lowerLeft)],
            [(.upperLeft, .lower), (.lower, .upperRight)], [(.upperRight, .left), (.left, .lowerRight)],
            [(.lowerLeft, .upper), (.upper, .lowerRight)], [(.upperLeft, .right), (.right, .lowerLeft)],
        ]
        for (from, to) in lines[Int(cp - 0x1FBD0)] { cellDiagonal(cell, &c, from, to) }
    case 0x1FBE0...0x1FBE3: circle(cell, &c, [.upper, .right, .lower, .left][Int(cp - 0x1FBE0)], filled: false)
    case 0x1FBE4: block(cell, &c, .upper, 0.5, 0.5)
    case 0x1FBE5: block(cell, &c, .lower, 0.5, 0.5)
    case 0x1FBE6: block(cell, &c, .left, 0.5, 0.5)
    case 0x1FBE7: block(cell, &c, .right, 0.5, 0.5)
    case 0x1FBE8...0x1FBEF:
        let at: [Alignment] = [.upper, .right, .lower, .left, .upperRight, .lowerLeft, .lowerRight, .upperLeft]
        circle(cell, &c, at[Int(cp - 0x1FBE8)], filled: true)
    default: break
    }
}

private func horizontalEighth(_ cell: Cell, _ c: inout Canvas, _ n: Int) {
    fillFraction(cell, &c, 0, 1, Double(n) / 8, Double(n + 1) / 8)
}

/// The shape through the points the pattern covers, in order round the cell from the top left: down the left edge,
/// along the bottom, up the right and back along the top. A point between two covered corners on the same edge adds
/// nothing.
private func smoothMosaic(_ cell: Cell, _ c: inout Canvas, _ pattern: String) {
    let rows = pattern.split(separator: "|").map { $0.map { $0 == "#" } }
    let (w, h) = (Double(cell.width), Double(cell.height))
    let upper = h / 3, lower = 2 * h / 3, center = w / 2
    // Each point with the pattern's place that covers it and the neighbours that make it redundant.
    let points: [(on: Bool, x: Double, y: Double)] = [
        (rows[0][0], 0, 0),
        (rows[1][0] && !(rows[0][0] && rows[2][0]), 0, upper),
        (rows[2][0] && !(rows[1][0] && rows[3][0]), 0, lower),
        (rows[3][0], 0, h),
        (rows[3][1] && !(rows[3][0] && rows[3][2]), center, h),
        (rows[3][2], w, h),
        (rows[2][2] && !(rows[3][2] && rows[1][2]), w, lower),
        (rows[1][2] && !(rows[2][2] && rows[0][2]), w, upper),
        (rows[0][2], w, 0),
        (rows[0][1] && !(rows[0][2] && rows[0][0]), center, 0),
    ]
    c.polygon(points.filter(\.on).map { ($0.x, $0.y) })
}

/// The triangle from the cell's centre to the edge.
private func edgeTriangle(_ cell: Cell, _ c: inout Canvas, _ edge: Edge) {
    let (w, h) = (Double(cell.width), Double(cell.height))
    let middle = (h / 2).rounded(), center = (w / 2).rounded()
    let ends: [(Double, Double)] = switch edge {
    case .top: [(w, 0), (0, 0)]
    case .left: [(0, 0), (0, h)]
    case .bottom: [(0, h), (w, h)]
    case .right: [(w, h), (w, 0)]
    }
    c.polygon([(center, middle)] + ends)
}

/// Lines from the middle of the top or bottom edge to the middle of a side, one per corner the pattern names: top
/// left, top right, bottom left, bottom right.
private func cornerDiagonalLines(_ cell: Cell, _ c: inout Canvas, _ corners: String) {
    let on = corners.map { $0 == "#" }
    let thick = Double(cell.line(.light))
    let (w, h) = (Double(cell.width), Double(cell.height))
    let cx = Double(cell.width / 2 + cell.width % 2), cy = Double(cell.height / 2 + cell.height % 2)
    if on[0] { c.line(cx, 0, 0, cy, thickness: thick) }
    if on[1] { c.line(cx, 0, w, cy, thickness: thick) }
    if on[2] { c.line(cx, h, 0, cy, thickness: thick) }
    if on[3] { c.line(cx, h, w, cy, thickness: thick) }
}

/// The point of the cell an alignment names.
private func point(_ cell: Cell, _ a: Alignment) -> (Double, Double) {
    let (w, h) = (Double(cell.width), Double(cell.height))
    let x: Double = switch a.horizontal { case .left: 0; case .right: w; case .center: w / 2 }
    let y: Double = switch a.vertical { case .top: 0; case .bottom: h; case .middle: h / 2 }
    return (x, y)
}

private func cellDiagonal(_ cell: Cell, _ c: inout Canvas, _ from: Alignment, _ to: Alignment) {
    let (p0, p1) = (point(cell, from), point(cell, to))
    c.line(p0.0, p0.1, p1.0, p1.1, thickness: Double(cell.line(.light)))
}

/// Parallel diagonal lines across the cell, top left to bottom right when `down`, clipped to the cell.
private func diagonalFill(_ cell: Cell, _ c: inout Canvas, down: Bool) {
    c.clipToCell()
    let t = cell.line(.light)
    // limitation: Ghostty divides by a count of 0 in a cell narrower than two lines; nmux draws one line there.
    let count = max(cell.width / (2 * t), 1)
    let (w, h) = (Double(cell.width), Double(cell.height))
    let stride = (w / Double(count)).rounded()
    for i in -count...count {
        let x = Double(i) * stride
        if down { c.line(x, 0, w + x, h, thickness: Double(t)) } else { c.line(w + x, 0, x, h, thickness: Double(t)) }
    }
}

private func checkerboardFill(_ cell: Cell, _ c: inout Canvas, _ parity: Int) {
    let xSize = 4, ySize = Int((4 * Double(cell.height) / Double(cell.width)).rounded())
    for x in 0..<xSize {
        let x0 = cell.width * x / xSize, x1 = cell.width * (x + 1) / xSize
        for y in 0..<ySize where (x + y) % 2 == parity {
            let y0 = cell.height * y / ySize, y1 = cell.height * (y + 1) / ySize
            c.rect(x0, y0, max(x1 - x0, 0), max(y1 - y0, 0))
        }
    }
}

/// A circle of half the cell's smaller side about the point, clipped to the cell; an outline sits inside the radius.
func circle(_ cell: Cell, _ c: inout Canvas, _ at: Alignment, filled: Bool) {
    c.clipToCell()
    let (x, y) = point(cell, at)
    let r = 0.5 * Double(min(cell.width, cell.height))
    let thick = Double(cell.line(.light))
    if filled { c.fill(circlePath(x, y, r)) } else { c.stroke(circlePath(x, y, r - thick / 2), width: thick) }
}

/// The octants 🯰 onward, each a mask of the eight it fills, bit 0 the top left and bit 7 the bottom right.
private let octants: [UInt8] = [
    0x04, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x0C, 0x0D, 0x0E, 0x10, 0x11, 0x12, 0x13, 0x15, 0x16, 0x17,
    0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27,
    0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38,
    0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A,
    0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x51, 0x52, 0x53, 0x54, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C, 0x5D,
    0x5E, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E,
    0x6F, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B, 0x7C, 0x7D, 0x7E,
    0x7F, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F,
    0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F,
    0xA1, 0xA2, 0xA3, 0xA4, 0xA6, 0xA7, 0xA8, 0xA9, 0xAB, 0xAC, 0xAD, 0xAE, 0xB0, 0xB1, 0xB2, 0xB3,
    0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC1, 0xC2, 0xC3, 0xC4,
    0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4,
    0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF, 0xE0, 0xE1, 0xE2, 0xE3, 0xE4,
    0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF, 0xF1, 0xF2, 0xF3, 0xF4, 0xF6,
    0xF7, 0xF8, 0xF9, 0xFB, 0xFD, 0xFE,
]

/// The sixteenth blocks 𜺐 to 𜺯, each as the quarters it spans: left, right, top and bottom.
private let sixteenths: [[Double]] = [
    [0, 1, 0, 1], [1, 2, 0, 1], [2, 3, 0, 1], [3, 4, 0, 1], [0, 1, 1, 2], [1, 2, 1, 2], [2, 3, 1, 2], [3, 4, 1, 2],
    [0, 1, 2, 3], [1, 2, 2, 3], [2, 3, 2, 3], [3, 4, 2, 3], [0, 1, 3, 4], [1, 2, 3, 4], [2, 3, 3, 4], [3, 4, 3, 4],
    [2, 4, 3, 4], [1, 4, 3, 4], [0, 3, 3, 4], [0, 2, 3, 4], [0, 1, 2, 4], [0, 1, 1, 4], [0, 1, 0, 3], [0, 1, 0, 2],
    [0, 2, 0, 1], [0, 3, 0, 1], [1, 4, 0, 1], [2, 4, 0, 1], [3, 4, 0, 2], [3, 4, 0, 3], [3, 4, 1, 4], [3, 4, 2, 4],
]

func drawLegacySupplement(_ cp: UInt32, _ c: inout Canvas, _ cell: Cell) {
    let (w, h, t) = (c.width, c.height, cell.underlineThickness)
    switch cp {
    case 0x1CC1B:
        linesChar(cell, &c, Lines(".l.l"))
        c.box(w - t, 0, w, h / 2)
    case 0x1CC1C:
        linesChar(cell, &c, Lines(".l.l"))
        c.box(w - t, h / 2, w, h)
    case 0x1CC1D:
        c.box(0, 0, w, t)
        c.box(0, 0, t, h / 2)
    case 0x1CC1E:
        c.box(0, h - t, w, h)
        c.box(0, h / 2, t, h)
    case 0x1CC21...0x1CC2F:
        // Separated quadrants: top left, top right, bottom left, bottom right in the codepoint's low bits.
        let quad = cp - 0x1CC20
        let gap = max(1, w / 12)
        let midX = gap * 2 + w % 2, midY = gap * 2 + h % 2
        let bw = (w - gap * 2 - midX) / 2, bh = (h - gap * 2 - midY) / 2
        for (bit, (col, row)) in [(0, 0), (1, 0), (0, 1), (1, 1)].enumerated() where quad >> bit & 1 != 0 {
            let x = gap + col * (bw + midX), y = gap + row * (bh + midY)
            c.box(x, y, x + bw, y + bh)
        }
    case 0x1CC30...0x1CC3F:
        // Twelfth and quarter circles, as pieces of ellipses that touch the edges of their block of cells: the
        // cell's column and row in the block, the block's size in cells, and the corner the piece bends round.
        let pieces: [(Double, Double, Double, Double, Corner)] = [
            (0, 0, 2, 2, .tl), (1, 0, 2, 2, .tl), (2, 0, 2, 2, .tr), (3, 0, 2, 2, .tr),
            (0, 1, 2, 2, .tl), (0, 0, 1, 1, .tl), (1, 0, 1, 1, .tr), (3, 1, 2, 2, .tr),
            (0, 2, 2, 2, .bl), (0, 1, 1, 1, .bl), (1, 1, 1, 1, .br), (3, 2, 2, 2, .br),
            (0, 3, 2, 2, .bl), (1, 3, 2, 2, .bl), (2, 3, 2, 2, .br), (3, 3, 2, 2, .br),
        ]
        let p = pieces[Int(cp - 0x1CC30)]
        circlePiece(cell, &c, p.0, p.1, p.2, p.3, p.4)
    case 0x1CD00...0x1CDE5:
        let mask = octants[Int(cp - 0x1CD00)]
        for bit in 0..<8 where mask >> bit & 1 != 0 {
            let x = Double(bit % 2) / 2, y = Double(bit / 2) / 4
            fillFraction(cell, &c, x, x + 0.5, y, y + 0.25)
        }
    case 0x1CE00:
        circle(cell, &c, .left, filled: false)
        circle(cell, &c, .right, filled: false)
    case 0x1CE01:
        circle(cell, &c, .upper, filled: false)
        circle(cell, &c, .lower, filled: false)
    case 0x1CE0B:
        circlePiece(cell, &c, 0, 0, 1, 0.5, .tl)
        circlePiece(cell, &c, 0, 0, 1, 0.5, .bl)
    case 0x1CE0C:
        circlePiece(cell, &c, 1, 0, 1, 0.5, .tr)
        circlePiece(cell, &c, 1, 0, 1, 0.5, .br)
    case 0x1CE16...0x1CE19:
        linesChar(cell, &c, Lines("l.l."))
        switch cp {
        case 0x1CE16: c.box(w / 2, 0, w, t)
        case 0x1CE17: c.box(w / 2, h - t, w, h)
        case 0x1CE18: c.box(0, 0, w / 2, t)
        default: c.box(0, h - t, w / 2, h)
        }
    case 0x1CE51...0x1CE8F:
        // Separated sextants: top left, top right, middle left, middle right, bottom left, bottom right in the low
        // bits; the middle row takes the height left over.
        let sex = cp - 0x1CE50
        let gap = max(1, w / 12)
        let midX = gap * 2 + w % 2, midY = gap * 2 + (h % 3) / 2
        let bw = (w - gap * 2 - midX) / 2
        let bh = (h - gap * 2 - midY * 2) / 3
        let middle = h - gap * 2 - midY * 2 - bh * 2
        let tops = [gap, gap + bh + midY, gap + bh + midY + middle + midY], heights = [bh, middle, bh]
        for bit in 0..<6 where sex >> bit & 1 != 0 {
            let x = gap + bit % 2 * (bw + midX), row = bit / 2
            c.box(x, tops[row], x + bw, tops[row] + heights[row])
        }
    case 0x1CE90...0x1CEAF:
        let q = sixteenths[Int(cp - 0x1CE90)].map { $0 / 4 }
        fillFraction(cell, &c, q[0], q[1], q[2], q[3])
    default: break
    }
}

/// A quarter of an ellipse `w` by `h` cells, stroked half its line inside the block's edges, for the cell at `x`, `y`
/// of the block.
private func circlePiece(_ cell: Cell, _ c: inout Canvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                         _ corner: Corner) {
    let width = Double(c.width) * w, height = Double(c.height) * h
    let xp = Double(c.width) * x, yp = Double(c.height) * y
    c.clipToCell()
        let cw = arcFactor * width, ch = arcFactor * height
    let thick = Double(cell.underlineThickness), ht = thick / 2
    func p(_ px: Double, _ py: Double) -> CGPoint { CGPoint(x: px - xp, y: py - yp) }
    let path = CGMutablePath()
    switch corner {
    case .tl:
        path.move(to: p(width, ht))
        path.addCurve(to: p(ht, height), control1: p(width - cw, ht), control2: p(ht, height - ch))
    case .tr:
        path.move(to: p(width, ht))
        path.addCurve(to: p(width * 2 - ht, height), control1: p(width + cw, ht),
                      control2: p(width * 2 - ht, height - ch))
    case .bl:
        path.move(to: p(ht, height))
        path.addCurve(to: p(width, height * 2 - ht), control1: p(ht, height + ch),
                      control2: p(width - cw, height * 2 - ht))
    case .br:
        path.move(to: p(width * 2 - ht, height))
        path.addCurve(to: p(width, height * 2 - ht), control1: p(width * 2 - ht, height + ch),
                      control2: p(width + cw, height * 2 - ht))
    }
    c.stroke(path, width: thick)
}
