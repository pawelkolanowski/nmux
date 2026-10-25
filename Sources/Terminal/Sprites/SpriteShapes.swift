import CoreGraphics

// Block elements, U+2580 to U+259F; braille, U+2800 to U+28FF; the geometric shapes Ghostty draws, U+25E2 to U+25E5
// and U+25F8 to U+25FF; and Powerline, U+E0B0 to U+E0D4. Adapted from Ghostty's `src/font/sprite/draw/block.zig`,
// `braille.zig`, `geometric_shapes.zig` and `powerline.zig` at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

func drawBlock(_ cp: UInt32, _ c: inout Canvas, _ cell: Cell) {
    switch cp {
    case 0x2580: block(cell, &c, .upper, 1, 0.5)
    // ▁ to ▇: the lower eighths.
    case 0x2581...0x2587: block(cell, &c, .lower, 1, Double(cp - 0x2580) / 8)
    case 0x2588: fullBlockShade(cell, &c, Shade.on)
    // ▉ to ▏: the left eighths, seven down to one.
    case 0x2589...0x258F: block(cell, &c, .left, Double(0x2590 - cp) / 8, 1)
    case 0x2590: block(cell, &c, .right, 0.5, 1)
    case 0x2591: fullBlockShade(cell, &c, Shade.light)
    case 0x2592: fullBlockShade(cell, &c, Shade.medium)
    case 0x2593: fullBlockShade(cell, &c, Shade.dark)
    case 0x2594: block(cell, &c, .upper, 1, 0.125)
    case 0x2595: block(cell, &c, .right, 0.125, 1)
    case 0x2596...0x259F:
        // ▖ ▗ ▘ ▙ ▚ ▛ ▜ ▝ ▞ ▟ as the quadrants each fills: top left, top right, bottom left, bottom right.
        let quads = ["..#.", "...#", "#...", "#.##", "#..#", "###.", "##.#", ".#..", ".##.", ".###"][Int(cp - 0x2596)]
            .map { $0 == "#" }
        if quads[0] { fillFraction(cell, &c, 0, 0.5, 0, 0.5) }
        if quads[1] { fillFraction(cell, &c, 0.5, 1, 0, 0.5) }
        if quads[2] { fillFraction(cell, &c, 0, 0.5, 0.5, 1) }
        if quads[3] { fillFraction(cell, &c, 0.5, 1, 0.5, 1) }
    default: break
    }
}

/// A block `width` and `height` of the cell, aligned in it.
func block(_ cell: Cell, _ c: inout Canvas, _ alignment: Alignment, _ width: Double, _ height: Double,
           _ shade: UInt8 = Shade.on) {
    let w = Int((Double(cell.width) * width).rounded()), h = Int((Double(cell.height) * height).rounded())
    let x = switch alignment.horizontal {
    case .left: 0
    case .right: cell.width - w
    case .center: (cell.width - w) / 2
    }
    let y = switch alignment.vertical {
    case .top: 0
    case .bottom: cell.height - h
    case .middle: (cell.height - h) / 2
    }
    c.rect(x, y, w, h, shade)
}

func fullBlockShade(_ cell: Cell, _ c: inout Canvas, _ shade: UInt8) { c.box(0, 0, cell.width, cell.height, shade) }

/// Braille: dots in two columns of four, sized and spaced on whole pixels from what the drawing's size leaves over.
func drawBraille(_ cp: UInt32, _ c: inout Canvas, _ cell: Cell) {
    let (width, height) = (c.width, c.height)
    var w = min(width / 4, height / 8)
    var xSpacing = width / 4, ySpacing = height / 8
    var xMargin = xSpacing / 2, yMargin = ySpacing / 2
    var xLeft = width - 2 * xMargin - xSpacing - 2 * w
    var yLeft = height - 2 * yMargin - 3 * ySpacing - 4 * w
    // A dot of at least a pixel first, then margins, spacing, wider margins, and last a wider dot.
    if xLeft >= 2 && yLeft >= 4 && w == 0 { w += 1; xLeft -= 2; yLeft -= 4 }
    if xLeft >= 2 && xMargin == 0 { xMargin = 1; xLeft -= 2 }
    if yLeft >= 2 && yMargin == 0 { yMargin = 1; yLeft -= 2 }
    if xLeft >= 1 { xSpacing += 1; xLeft -= 1 }
    if yLeft >= 3 { ySpacing += 1; yLeft -= 3 }
    if xLeft >= 2 { xMargin += 1; xLeft -= 2 }
    if yLeft >= 2 { yMargin += 1; yLeft -= 2 }
    if xLeft >= 2 && yLeft >= 4 { w += 1 }
    let x = [xMargin, xMargin + w + xSpacing]
    let y = (0..<4).map { yMargin + $0 * (w + ySpacing) }
    // The codepoint's bits, low first, name the dots: the left column's top three, the right column's top three,
    // then the bottom left and the bottom right.
    let dots = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)]
    for (bit, (col, row)) in dots.enumerated() where cp >> bit & 1 != 0 {
        c.box(x[col], y[row], x[col] + w, y[row] + w)
    }
}

func drawGeometric(_ cp: UInt32, _ c: inout Canvas, _ cell: Cell) {
    switch cp {
    case 0x25E2: cornerTriangleShade(cell, &c, .br, Shade.on)
    case 0x25E3: cornerTriangleShade(cell, &c, .bl, Shade.on)
    case 0x25E4: cornerTriangleShade(cell, &c, .tl, Shade.on)
    case 0x25E5: cornerTriangleShade(cell, &c, .tr, Shade.on)
    case 0x25F8: cornerTriangleOutline(cell, &c, .tl)
    case 0x25F9: cornerTriangleOutline(cell, &c, .tr)
    case 0x25FA: cornerTriangleOutline(cell, &c, .bl)
    case 0x25FF: cornerTriangleOutline(cell, &c, .br)
    default: break
    }
}

/// The cell's half on the side of `corner`, cut along the other diagonal.
private func cornerTriangle(_ cell: Cell, _ corner: Corner) -> CGMutablePath {
    let (w, h) = (Double(cell.width), Double(cell.height))
    let points: [(Double, Double)] = switch corner {
    case .tl: [(0, 0), (0, h), (w, 0)]
    case .tr: [(0, 0), (w, h), (w, 0)]
    case .bl: [(0, 0), (0, h), (w, h)]
    case .br: [(0, h), (w, h), (w, 0)]
    }
    let path = polyline(points)
    path.closeSubpath()
    return path
}

func cornerTriangleShade(_ cell: Cell, _ c: inout Canvas, _ corner: Corner, _ shade: UInt8) {
    c.fill(cornerTriangle(cell, corner), shade)
}

private func cornerTriangleOutline(_ cell: Cell, _ c: inout Canvas, _ corner: Corner) {
    c.innerStroke(cornerTriangle(cell, corner), width: Double(cell.line(.light)))
}

/// Powerline draws over the whole drawing, both cells of a wide one.
func drawPowerline(_ cp: UInt32, _ c: inout Canvas, _ cell: Cell) {
    let (w, h) = (Double(c.width), Double(c.height))
    switch cp {
    case 0xE0B0: c.polygon([(0, 0), (w, h / 2), (0, h)])
    case 0xE0B1:
        c.stroke(polyline([(0, 0), (w, h / 2), (0, h)]), width: Double(cell.line(.light)))
    case 0xE0B2: c.polygon([(w, 0), (0, h / 2), (w, h)])
    case 0xE0B3:
        drawPowerline(0xE0B1, &c, cell)
        c.flipHorizontal()
    case 0xE0B4: c.fill(halfCircle(w, h, stroked: false))
    case 0xE0B5: c.innerStroke(halfCircle(w, h, stroked: true), width: Double(cell.underlineThickness))
    case 0xE0B6:
        drawPowerline(0xE0B4, &c, cell)
        c.flipHorizontal()
    case 0xE0B7:
        drawPowerline(0xE0B5, &c, cell)
        c.flipHorizontal()
    case 0xE0B8: c.polygon([(0, 0), (w, h), (0, h)])
    case 0xE0B9, 0xE0BF: lightDiagonalUpperLeftToLowerRight(cell, &c)
    case 0xE0BA: c.polygon([(w, 0), (w, h), (0, h)])
    case 0xE0BB, 0xE0BD: lightDiagonalUpperRightToLowerLeft(cell, &c)
    case 0xE0BC: c.polygon([(0, 0), (w, 0), (0, h)])
    case 0xE0BE: c.polygon([(0, 0), (w, 0), (w, h)])
    case 0xE0D2:
        let t = Double(cell.underlineThickness)
        c.polygon([(0, 0), (w, 0), (w / 2, h / 2 - t / 2), (0, h / 2 - t / 2)])
        c.polygon([(0, h), (w, h), (w / 2, h / 2 + t / 2), (0, h / 2 + t / 2)])
    case 0xE0D4:
        drawPowerline(0xE0D2, &c, cell)
        c.flipHorizontal()
    default: break
    }
}

/// The right half of a circle of the drawing's height, or of its width when that is less, with straight sides between
/// the quarter arcs. The stroked outline starts and ends with a pixel of horizontal line, so its offset ends meet the
/// left edge square.
private func halfCircle(_ w: Double, _ h: Double, stroked: Bool) -> CGMutablePath {
        let r = min(w, h / 2), end = stroked ? 1.0 : 0
    let path = CGMutablePath()
    path.move(to: .zero)
    if stroked { path.addLine(to: CGPoint(x: 1, y: 0)) }
    path.addCurve(to: CGPoint(x: r, y: r), control1: CGPoint(x: r * arcFactor, y: 0),
                  control2: CGPoint(x: r, y: r - r * arcFactor))
    path.addLine(to: CGPoint(x: r, y: h - r))
    path.addCurve(to: CGPoint(x: end, y: h), control1: CGPoint(x: r, y: h - r + r * arcFactor),
                  control2: CGPoint(x: r * arcFactor, y: h))
    if stroked { path.addLine(to: CGPoint(x: 0, y: h)) } else { path.closeSubpath() }
    return path
}
