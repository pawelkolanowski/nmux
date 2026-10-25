import CoreGraphics

// The sprite face: every codepoint Ghostty draws itself, and the decorations, drawn at the cell's metrics. Adapted
// from Ghostty's `src/font/sprite/Face.zig` (`ranges`, `hasCodepoint`, `renderGlyph`) and
// `src/font/sprite/draw/special.zig` at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The function that draws the codepoint, over exactly the ranges of Ghostty's sprite face.
private func spriteDraw(_ cp: UInt32) -> ((UInt32, inout Canvas, Cell) -> Void)? {
    switch cp {
    case 0x2500...0x257F: drawBox
    case 0x2580...0x259F: drawBlock
    case 0x25E2...0x25E5, 0x25F8...0x25FA, 0x25FF: drawGeometric
    case 0x2800...0x28FF: drawBraille
    case 0xE0B0...0xE0BF, 0xE0D2, 0xE0D4: drawPowerline
    case 0xF5D0...0xF60D: drawBranch
    case 0x1CC1B...0x1CC1E, 0x1CC21...0x1CC3F, 0x1CD00...0x1CDE5, 0x1CE00...0x1CE01, 0x1CE0B...0x1CE0C,
         0x1CE16...0x1CE19, 0x1CE51...0x1CEAF: drawLegacySupplement
    case 0x1FB00...0x1FBAF, 0x1FBBD...0x1FBBF, 0x1FBCE...0x1FBEF: drawLegacy
    default: nil
    }
}

/// Whether the sprite face draws the codepoint, which it does in every style and presentation.
func isSprite(_ cp: UInt32) -> Bool { spriteDraw(cp) != nil }

/// The codepoint's sprite over `span` cells, empty for one the sprite face lacks.
func charSprite(_ cp: UInt32, span: Int, cell: Cell) -> Sprite {
    guard let draw = spriteDraw(cp) else { return Sprite() }
    var canvas = Canvas(width: cell.width * span, height: cell.height)
    draw(cp, &canvas, cell)
    return canvas.sprite()
}

/// The name each decoration carries in the self-test's log.
enum Decoration: String {
    case underline
    case underlineDouble = "underline-double"
    case underlineCurly = "underline-curly"
    case underlineDotted = "underline-dotted"
    case underlineDashed = "underline-dashed"
    case strike
    case overline

    var isUnderline: Bool { ![.strike, .overline].contains(self) }
}

/// A coverage mask, or a colour glyph's BGRA, its first row the top, and its place: `left` from the cell's left edge,
/// `top` from the cell's bottom up to the mask's top. An empty sprite has no size.
struct Sprite {
    var pixels: [UInt8] = []
    var width = 0, height = 0
    var left = 0, top = 0
}

/// The decoration over `span` cells: the one-cell drawing repeated, so a curly or dashed line meets its neighbour's
/// as it meets itself.
func decorationSprite(_ decoration: Decoration, span: Int, cell: Cell) -> Sprite {
    var canvas = Canvas(width: cell.width * span, height: cell.height)
    let padY = canvas.padY
    canvas.draw { ctx in
        for i in 0..<span {
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(i * cell.width), y: 0)
            draw(decoration, ctx, cell: cell, padY: padY)
            ctx.restoreGState()
        }
    }
    return canvas.sprite()
}

/// A one-byte coverage mask over `buf`, its origin at the bottom-left, as glyphs and sprites rasterise into.
func coverageContext(_ buf: UnsafeMutableRawBufferPointer, width: Int, height: Int) -> CGContext? {
    CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
              space: CGColorSpace(name: CGColorSpace.linearGray)!, bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
}

private func draw(_ decoration: Decoration, _ ctx: CGContext, cell: Cell, padY: Int) {
    let width = cell.width, height = cell.height
    let position = cell.underlinePosition, thickness = cell.underlineThickness
    func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { ctx.fill(CGRect(x: x, y: y, width: w, height: h)) }
    switch decoration {
    case .underline:
        rect(0, min(position, height + padY - thickness), width, thickness)
    case .underlineDouble:
        let y = min(position, height + padY - 2 * thickness)
        rect(0, y - thickness, width, thickness)
        rect(0, y + thickness, width, thickness)
    case .underlineDotted:
        let w = Double(width), thick = Double(thickness)
        let radius = 0.5.squareRoot() * thick
        let y = min(Double(position) + 0.5 * thick, Double(height + padY) - radius.rounded(.up))
        let count = max(min((w / (4 * radius)).rounded(.up), (w / (3 * radius)).rounded(.down),
                            (w / (2 * radius + 1)).rounded(.down)), 1)
        var x = w / count / 2
        for _ in 0..<Int(count) {
            ctx.addArc(center: CGPoint(x: x, y: y), radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            ctx.closePath()
            x += w / count
        }
        ctx.fillPath()
    case .underlineDashed:
        let y = min(position, height + padY - thickness)
        let dash = width / 3 + 1
        for i in stride(from: 0, to: width / dash + 1, by: 2) { rect(i * dash, y, dash, thickness) }
    case .underlineCurly:
        let w = Double(width), lineWidth = Double(thickness)
        let amplitude = w / .pi
        let top = min(Double(position), Double(height + padY) - amplitude - lineWidth)
        let bottom = top + amplitude
        let r = 0.4, centre = 0.5 * w
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 0, y: bottom))
        ctx.addCurve(to: CGPoint(x: centre, y: top), control1: CGPoint(x: centre * r, y: bottom),
                     control2: CGPoint(x: centre - centre * r, y: top))
        ctx.addCurve(to: CGPoint(x: w, y: bottom), control1: CGPoint(x: centre + centre * r, y: top),
                     control2: CGPoint(x: w - centre * r, y: bottom))
        ctx.strokePath()
    case .strike:
        rect(0, cell.strikethroughPosition, width, cell.strikethroughThickness)
    case .overline:
        // Ghostty's overline sits at the cell's top, as thick as the underline.
        rect(0, 0, width, thickness)
    }
}
