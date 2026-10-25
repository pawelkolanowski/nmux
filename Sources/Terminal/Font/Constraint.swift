// How a glyph is scaled and aligned in its cells, and how many cells it may take. Adapted from Ghostty's
// `src/font/Glyph.zig` (`RenderOptions.Constraint`), `src/font/nerd_font_attributes.zig` (`getConstraint`),
// `src/renderer/cell.zig` (`isSymbol`, `constraintWidth`, `isGraphicsElement`),
// `src/build/uucode_config.zig` (`IsSymbolComponent`), `src/renderer/generic.zig` (`addGlyph`) and
// `src/font/SharedGrid.zig` (`renderGlyph`) at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// A glyph's sizing and alignment rules. The relative box places the glyph in its icon group, which the rules size and
/// align in its place; the paddings are fractions of the face.
struct Constraint: Equatable {
    enum Size {
        /// `fitCover1` scales down to fit, or up to cover one cell; `stretch` ignores the aspect ratio.
        case none, fit, cover, fitCover1, stretch
    }

    enum Align {
        /// `center1` centres in the first cell even over two.
        case none, start, end, center, center1
    }

    enum Height {
        case cell, icon
    }

    var size = Size.none
    var alignVertical = Align.none
    var alignHorizontal = Align.none
    var padTop = 0.0, padLeft = 0.0, padRight = 0.0, padBottom = 0.0
    var relativeWidth = 1.0, relativeHeight = 1.0, relativeX = 0.0, relativeY = 0.0
    /// The widest aspect ratio a stretch may reach.
    var maxXYRatio: Double?
    var maxConstraintWidth = 2
    var height = Height.cell

    static let none = Constraint()
    /// A symbol without a table entry, `addGlyph`'s.
    static let fit = Constraint(size: .fit)
    /// Every colour glyph, `SharedGrid.renderGlyph`'s.
    static let emoji = Constraint(size: .cover, alignVertical: .center, alignHorizontal: .center, padLeft: 0.025,
                                  padRight: 0.025)

    var doesAnything: Bool { size != .none || alignHorizontal != .none || alignVertical != .none }

    /// The face's numbers the rules read; a stretch reads the cell's instead.
    private struct Frame {
        var cellWidth: Int
        var faceWidth, faceHeight, faceY, iconHeight, iconHeightSingle: Double
    }

    /// The box, from the cell's left edge and bottom, scaled and aligned within `width` cells.
    func constrain(_ glyph: GlyphBox, cell: Cell, width: Int) -> GlyphBox {
        guard doesAnything else { return glyph }
        var frame = Frame(cellWidth: cell.width, faceWidth: cell.faceWidth, faceHeight: cell.faceHeight,
                          faceY: cell.faceY, iconHeight: cell.iconHeight, iconHeightSingle: cell.iconHeightSingle)
        guard size == .stretch else { return constrainInner(glyph, frame, width) }
        // A stretched glyph aligns across cells, so it scales to the grid, and needs no negative padding.
        (frame.faceWidth, frame.faceHeight, frame.faceY) = (Double(cell.width), Double(cell.height), 0)
        var c = self
        (c.padTop, c.padLeft, c.padRight, c.padBottom) = (max(0, padTop), max(0, padLeft), max(0, padRight),
                                                          max(0, padBottom))
        return c.constrainInner(glyph, frame, width)
    }

    private func constrainInner(_ glyph: GlyphBox, _ m: Frame, _ width: Int) -> GlyphBox {
        // An extra wide face never stretches a glyph over two cells, as font_patcher.
        let cells = size == .stretch && m.faceWidth > 0.9 * m.faceHeight ? 1 : min(maxConstraintWidth, width)
        let groupWidth = glyph.width / relativeWidth, groupHeight = glyph.height / relativeHeight
        var group = GlyphBox(x: glyph.x - groupWidth * relativeX, y: glyph.y - groupHeight * relativeY,
                             width: groupWidth, height: groupHeight)
        // Scaled about the group's centre.
        let (wf, hf) = scaleFactors(group, m, cells)
        let centreX = group.x + group.width / 2, centreY = group.y + group.height / 2
        group.width *= wf
        group.height *= hf
        group.x = centreX - group.width / 2
        group.y = centreY - group.height / 2
        group.y = alignedY(group, m)
        group.x = alignedX(group, m, cells)
        return GlyphBox(x: group.x + group.width * relativeX, y: group.y + group.height * relativeY,
                        width: wf * glyph.width, height: hf * glyph.height)
    }

    private func scaleFactors(_ group: GlyphBox, _ m: Frame, _ cells: Int) -> (Double, Double) {
        guard size != .none else { return (1, 1) }
        let multiCell = cells > 1
        let targetWidth = (Double(cells) - (padLeft + padRight)) * m.faceWidth
        let iconHeight = multiCell ? m.iconHeight : m.iconHeightSingle
        let targetHeight = (1 - (padBottom + padTop)) * (height == .cell ? m.faceHeight : iconHeight)
        var wf = targetWidth / group.width, hf = targetHeight / group.height
        switch size {
        case .none, .stretch: break
        case .fit:
            hf = min(1, wf, hf)
            wf = hf
        case .cover:
            hf = min(wf, hf)
            wf = hf
        case .fitCover1:
            // Over two cells an icon keeps the size it has in one, never smaller.
            hf = min(wf, hf)
            if multiCell && hf > 1 { hf = max(1, scaleFactors(group, m, 1).1) }
            wf = hf
        }
        if let maxXYRatio, group.width * wf > group.height * hf * maxXYRatio {
            wf = group.height * hf * maxXYRatio / group.width
        }
        return (wf, hf)
    }

    /// The face's height offset by its place in the cell, which the baseline's rounding leaves uneven.
    private func alignedY(_ group: GlyphBox, _ m: Frame) -> Double {
        if size == .none && alignVertical == .none { return group.y }
        let startY = m.faceY + padBottom * m.faceHeight
        let endY = m.faceY + (m.faceHeight - group.height - padTop * m.faceHeight)
        let centreY = (startY + endY) / 2
        switch alignVertical {
        // Within the padded cell, else centred.
        case .none: return endY < startY ? centreY : max(startY, min(group.y, endY))
        case .start: return startY
        case .end: return endY
        case .center, .center1: return centreY
        }
    }

    /// Over several cells, from the first cell's left edge to the right edge of the last cell's face; centring the face
    /// in a wider cell comes after.
    private func alignedX(_ group: GlyphBox, _ m: Frame, _ cells: Int) -> Double {
        if size == .none && alignHorizontal == .none { return group.x }
        let fullFaceSpan = m.faceWidth + Double((cells - 1) * m.cellWidth)
        let startX = padLeft * m.faceWidth, padRightDX = padRight * m.faceWidth
        let endX = fullFaceSpan - group.width - padRightDX
        switch alignHorizontal {
        case .none: return max(startX, min(group.x, endX))
        case .start: return startX
        case .end: return max(startX, endX)
        case .center: return max(startX, (startX + endX) / 2)
        // Never left of the start, so a group wider than a cell aligns to it.
        case .center1: return max(startX, (startX + m.faceWidth - group.width - padRightDX) / 2)
        }
    }
}

/// The codepoint's Nerd Font constraint, nil when Ghostty's table has none: a binary search over the range triples.
func nerdFontConstraint(_ cp: UInt32) -> Constraint? {
    var lo = 0, hi = nerdFontRanges.count / 3
    while lo < hi {
        let mid = (lo + hi) / 2
        if nerdFontRanges[mid * 3 + 1] < cp { lo = mid + 1 } else { hi = mid }
    }
    guard lo < nerdFontRanges.count / 3, nerdFontRanges[lo * 3] <= cp else { return nil }
    return nerdFontConstraints[Int(nerdFontRanges[lo * 3 + 2])]
}

/// The constraint a text glyph on a cell whose first codepoint is `cp` takes: its Nerd Font entry, fit for another
/// symbol, else none.
func glyphConstraint(_ cp: UInt32) -> Constraint {
    nerdFontConstraint(cp) ?? (isSymbol(cp) ? .fit : .none)
}

/// Private use, or one of the blocks Arrows, Dingbats, Emoticons, Miscellaneous Symbols, Enclosed Alphanumerics and
/// its Supplement, Miscellaneous Symbols and Pictographs, Transport and Map Symbols.
func isSymbol(_ cp: UInt32) -> Bool {
    switch cp {
    case 0xE000...0xF8FF, 0xF0000...0xFFFFD, 0x100000...0x10FFFD: true
    case 0x2190...0x21FF, 0x2700...0x27BF, 0x1F600...0x1F64F, 0x2600...0x26FF, 0x2460...0x24FF, 0x1F100...0x1F1FF,
         0x1F300...0x1F5FF, 0x1F680...0x1F6FF: true
    default: false
    }
}

/// Box drawing, block elements, Legacy Computing and its supplement, and Powerline.
func isGraphicsElement(_ cp: UInt32) -> Bool {
    switch cp {
    case 0x2500...0x259F, 0x1FB00...0x1FBFF, 0x1CC00...0x1CEBF, 0xE0B0...0xE0D7: true
    default: false
    }
}

/// The cells the glyph on cell `x` may take: a wide cell's two; a symbol's two when the next cell is empty or a space,
/// unless it ends the row or follows a symbol that is no graphics element; else one. `codepoints` holds each cell's
/// first codepoint, 0 for none.
func constraintWidth(_ codepoints: [UInt32], at x: Int, wide: Bool) -> Int {
    if wide { return 2 }
    let cp = codepoints[x]
    guard isSymbol(cp), x < codepoints.count - 1 else { return 1 }
    if x > 0, isSymbol(codepoints[x - 1]), !isGraphicsElement(codepoints[x - 1]) { return 1 }
    return [0, 0x20, 0x2002].contains(codepoints[x + 1]) ? 2 : 1
}
