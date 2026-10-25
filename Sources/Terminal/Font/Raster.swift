import CoreText
import Foundation

// A font's glyph rasterised for the atlas, which the tests draw the reference sheets with too. Adapted from Ghostty's
// `src/font/face/coretext.zig` (`renderGlyph`) and `src/font/SharedGrid.zig` (`renderGlyph`) at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// Ghostty's `renderGlyph`: the glyph at its subpixel place on the baseline, scaled and aligned by its constraint over
/// `cells` cells, then centred in a cell wider than the face unless it stretches, as a coverage mask whose first row is
/// the top. A colour glyph always takes the emoji constraint and rasterises in premultiplied BGRA, four bytes a pixel;
/// a bitmap one (sbix) lands on whole pixels, and neither stroke nor thickening reaches it. A synthetic bold strokes
/// the outline too, and grows by the stroke; thickening smooths the font and pads the mask by a pixel. Empty when the
/// glyph has no outline.
func rasterise(_ face: Face, _ id: CGGlyph, constraint: Constraint, cells: Int, cell: Cell, thicken: Bool) -> Sprite {
    var glyph = id
    var rect = CTFontGetBoundingRectsForGlyphs(face.font, .horizontal, &glyph, nil, 1)
    let color = face.color
    let constraint = color ? Constraint.emoji : constraint
    let sbix = color && CTFontCopyTable(face.font, CTFontTableTag(kCTFontTableSbix), []) != nil
    if let stroke = face.stroke, !sbix { rect = rect.insetBy(dx: -stroke / 2, dy: -stroke / 2) }
    // Smaller than a quarter pixel has no outline worth drawing.
    guard rect.width >= 0.25, rect.height >= 0.25 else { return Sprite() }
    var box = GlyphBox(x: Double(rect.minX), y: Double(rect.minY) + Double(cell.baseline), width: Double(rect.width),
                       height: Double(rect.height))
    box = constraint.constrain(box, cell: cell, width: cells)
    // A stretch already placed the glyph on the grid's cells.
    if constraint.size != .stretch {
        let dx = (Double(cell.width) - cell.faceWidth) / 2
        box.x += dx
        // A cell narrower than the face keeps only the fraction, for the same subpixel position.
        if dx < 0 { box.x -= dx.rounded(.towardZero) }
    }
    if sbix {
        let (w, h) = (Double(cell.width), Double(cell.height))
        box.width = w - (w - box.width - box.x).rounded() - box.x.rounded()
        box.height = h - (h - box.height - box.y).rounded() - box.y.rounded()
        (box.x, box.y) = (box.x.rounded(), box.y.rounded())
    }
    let (x, y) = (box.x, box.y)
    let pad = thicken && !sbix ? 1 : 0
    let pxX = Int(x.rounded(.down)) - pad, pxY = Int(y.rounded(.down)) - pad
    let fracX = x - x.rounded(.down), fracY = y - y.rounded(.down)
    let width = Int((box.width + fracX).rounded(.up)) + 2 * pad
    let height = Int((box.height + fracY).rounded(.up)) + 2 * pad
    var pixels = [UInt8](repeating: 0, count: width * height * (color ? 4 : 1))
    pixels.withUnsafeMutableBytes { buf in
        guard let ctx = color ? colorContext(buf, width: width, height: height)
            : coverageContext(buf, width: width, height: height) else { return }
        // White in either context's colour space: the mask's full coverage, or the bitmap's own colours.
        ctx.setAllowsFontSmoothing(true)
        ctx.setShouldSmoothFonts(thicken)
        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.setAllowsFontSubpixelQuantization(false)
        ctx.setShouldSubpixelQuantizeFonts(false)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        let white = CGColor(gray: 1, alpha: 1)
        ctx.setFillColor(white)
        ctx.setStrokeColor(white)
        if let stroke = face.stroke, !sbix {
            ctx.setTextDrawingMode(.fillStroke)
            ctx.setLineWidth(stroke)
        }
        ctx.translateBy(x: fracX + Double(pad), y: fracY + Double(pad))
        ctx.scaleBy(x: box.width / Double(rect.width), y: box.height / Double(rect.height))
        var origin = CGPoint(x: -rect.minX, y: -rect.minY)
        CTFontDrawGlyphs(face.font, &glyph, &origin, 1, ctx)
    }
    return Sprite(pixels: pixels, width: width, height: height, left: pxX, top: pxY + height)
}

/// Premultiplied BGRA in sRGB, the layer's colour space, where Ghostty takes Display P3 for its own layer.
func colorContext(_ buf: UnsafeMutableRawBufferPointer, width: Int, height: Int) -> CGContext? {
    CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
}
