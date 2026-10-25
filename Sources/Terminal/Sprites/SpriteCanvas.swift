import CoreGraphics

// The canvas every sprite draws on and the helpers the sprite files share. Adapted from Ghostty's
// `src/font/sprite/canvas.zig` (`Canvas`), `src/font/sprite/draw/common.zig` and `src/font/sprite/Face.zig`
// (`renderGlyph`) at commit 22f100c6, with CoreGraphics paths where Ghostty draws with z2d.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// A coverage canvas a quarter of the drawing wider and a quarter of the cell taller on every side, so a drawing may
/// leave its cell. Coordinates count from the cell's top-left, y down; `width` and `height` are the drawing's size,
/// the cell or both cells of a wide one.
struct Canvas {
    let width, height, padX, padY: Int
    private(set) var pixels: [UInt8]
    /// The rows and columns on each side the sprite leaves out, besides the empty ones it trims.
    var clip = (top: 0, left: 0, right: 0, bottom: 0)

    init(width: Int, height: Int) {
        (self.width, self.height, padX, padY) = (width, height, width / 4, height / 4)
        pixels = [UInt8](repeating: 0, count: (width + 2 * padX) * (height + 2 * padY))
    }

    var stride: Int { width + 2 * padX }
    var rows: Int { height + 2 * padY }

    /// Sets one pixel, as Ghostty's canvas writes its value rather than blending it; off the canvas does nothing.
    mutating func pixel(_ x: Int, _ y: Int, _ value: UInt8) {
        let cx = x + padX, cy = y + padY
        guard cx >= 0, cy >= 0, cx < stride, cy < rows else { return }
        pixels[cy * stride + cx] = value
    }

    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ shade: UInt8 = Shade.on) {
        guard w > 0, h > 0 else { return }
        for py in y..<y + h { for px in x..<x + w { pixel(px, py, shade) } }
    }

    /// The rectangle between two corners, in either order.
    mutating func box(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ shade: UInt8 = Shade.on) {
        rect(min(x0, x1), min(y0, y1), abs(x1 - x0), abs(y1 - y0), shade)
    }

    /// Draws with CoreGraphics in the cell's coordinates, filling and stroking in `shade` over what is there.
    mutating func draw(_ shade: UInt8 = Shade.on, _ body: (CGContext) -> Void) {
        let (w, h, px, py) = (stride, rows, padX, padY)
        pixels.withUnsafeMutableBytes { buf in
            guard let ctx = coverageContext(buf, width: w, height: h) else { return }
            ctx.translateBy(x: CGFloat(px), y: CGFloat(h - py))
            ctx.scaleBy(x: 1, y: -1)
            ctx.setFillColor(gray: 1, alpha: CGFloat(shade) / 255)
            ctx.setStrokeColor(gray: 1, alpha: CGFloat(shade) / 255)
            ctx.setLineCap(.butt)
            body(ctx)
        }
    }

    mutating func fill(_ path: CGPath, _ shade: UInt8 = Shade.on) {
        draw(shade) { ctx in ctx.addPath(path); ctx.fillPath() }
    }

    mutating func stroke(_ path: CGPath, width: Double, _ shade: UInt8 = Shade.on) {
        draw(shade) { ctx in ctx.setLineWidth(width); ctx.addPath(path); ctx.strokePath() }
    }

    /// Ghostty's inner stroke, the path offset inward by half the width and stroked, drawn as a stroke twice as wide
    /// inside the path; an open path counts as closed by a straight line.
    mutating func innerStroke(_ path: CGPath, width: Double) {
        draw { ctx in
            ctx.addPath(path)
            ctx.clip()
            ctx.setLineWidth(2 * width)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    mutating func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, thickness: Double) {
        stroke(polyline([(x0, y0), (x1, y1)]), width: thickness)
    }

    mutating func polygon(_ points: [(Double, Double)], _ shade: UInt8 = Shade.on) {
        let path = polyline(points)
        path.closeSubpath()
        fill(path, shade)
    }

    /// The canvas inverted and clipped to the cell, so what was drawn cuts its shape out of a full cell.
    mutating func invertWithinCell() {
        for i in pixels.indices { pixels[i] = 255 - pixels[i] }
        clipToCell()
    }

    mutating func flipHorizontal() {
        for y in 0..<rows { pixels[y * stride..<(y + 1) * stride].reverse() }
        (clip.left, clip.right) = (clip.right, clip.left)
    }

    /// Leaves out everything outside the cell.
    mutating func clipToCell() {
        clip = (padY, padX, padX, padY)
    }

    /// Ghostty's `writeAtlas`: the canvas inside its clip, trimmed of empty rows and columns, placed relative to the
    /// cell. An empty canvas gives an empty sprite.
    func sprite() -> Sprite {
        var (top, left, right, bottom) = clip
        func rowEmpty(_ y: Int) -> Bool { (left..<stride - right).allSatisfy { pixels[y * stride + $0] == 0 } }
        func columnEmpty(_ x: Int) -> Bool { (top..<rows - bottom).allSatisfy { pixels[$0 * stride + x] == 0 } }
        while top < rows - bottom && rowEmpty(top) { top += 1 }
        while bottom < rows - top && rowEmpty(rows - bottom - 1) { bottom += 1 }
        while left < stride - right && columnEmpty(left) { left += 1 }
        while right < stride - left && columnEmpty(stride - right - 1) { right += 1 }
        let w = stride - left - right, h = rows - top - bottom
        guard w > 0, h > 0 else { return Sprite() }
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            out.replaceSubrange(y * w..<(y + 1) * w,
                                with: pixels[(top + y) * stride + left..<(top + y) * stride + left + w])
        }
        return Sprite(pixels: out, width: w, height: h, left: left - padX, top: height + padY - top)
    }
}

func polyline(_ points: [(Double, Double)]) -> CGMutablePath {
    let path = CGMutablePath()
    path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
    return path
}

/// Coverage values; a canvas pixel is only ever one of them, none, or a path's antialiased edge.
enum Shade {
    static let light: UInt8 = 0x40, medium: UInt8 = 0x80, dark: UInt8 = 0xC0, on: UInt8 = 0xFF
}

/// A line's thickness from the base, Ghostty's `box_thickness`, which is the underline's.
enum Thickness {
    case superLight, light, heavy

    func px(_ base: Int) -> Int {
        switch self {
        case .superLight: max(base / 2, 1)
        case .light: base
        case .heavy: base * 2
        }
    }
}

extension Cell {
    /// A line's thickness in pixels.
    func line(_ thickness: Thickness) -> Int { thickness.px(underlineThickness) }
}

/// Where a line `thickness` thick starts, on whole pixels, to sit centred across `size`; box lines and everything that
/// joins them sit there.
func centred(_ size: Int, _ thickness: Int) -> Int { max(size - thickness, 0) / 2 }

/// The control point factor that approximates a circular arc with a cubic curve.
let arcFactor = (2.0.squareRoot() - 1) * 4 / 3

enum Corner { case tl, tr, bl, br }
enum Edge { case top, left, bottom, right }

/// Where a figure sits in its cell, Ghostty's `Alignment`.
struct Alignment {
    enum Horizontal { case left, right, center }
    enum Vertical { case top, bottom, middle }
    var horizontal = Horizontal.center, vertical = Vertical.middle

    static let upper = Alignment(vertical: .top), lower = Alignment(vertical: .bottom)
    static let left = Alignment(horizontal: .left), right = Alignment(horizontal: .right)
    static let center = Alignment()
    static let upperLeft = Alignment(horizontal: .left, vertical: .top)
    static let upperRight = Alignment(horizontal: .right, vertical: .top)
    static let lowerLeft = Alignment(horizontal: .left, vertical: .bottom)
    static let lowerRight = Alignment(horizontal: .right, vertical: .bottom)
}

/// Ghostty's `Fraction.min`: a fraction of `size` as the left or top edge of a block, rounded from the far end, so
/// the blocks on either side of a line meet at the same pixel.
func fractionMin(_ f: Double, _ size: Int) -> Int {
    let s = Double(size)
    return Int(s - ((1 - f) * s).rounded())
}

/// Ghostty's `Fraction.max`: a fraction of `size` as the right or bottom edge of a block.
func fractionMax(_ f: Double, _ size: Int) -> Int { Int((f * Double(size)).rounded()) }

/// The part of the cell between two vertical and two horizontal fractions.
func fillFraction(_ cell: Cell, _ c: inout Canvas, _ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) {
    c.box(fractionMin(x0, cell.width), fractionMin(y0, cell.height), fractionMax(x1, cell.width),
          fractionMax(y1, cell.height))
}

/// A vertical line with its left edge at `x`, from `y1` to `y2`.
func vline(_ c: inout Canvas, _ y1: Int, _ y2: Int, _ x: Int, _ thickness: Int) { c.box(x, y1, x + thickness, y2) }

/// A horizontal line with its top edge at `y`, from `x1` to `x2`.
func hline(_ c: inout Canvas, _ x1: Int, _ x2: Int, _ y: Int, _ thickness: Int) { c.box(x1, y, x2, y + thickness) }

func vlineMiddle(_ cell: Cell, _ c: inout Canvas, _ thickness: Thickness) {
    let t = cell.line(thickness)
    vline(&c, 0, cell.height, centred(cell.width, t), t)
}

func hlineMiddle(_ cell: Cell, _ c: inout Canvas, _ thickness: Thickness) {
    let t = cell.line(thickness)
    hline(&c, 0, cell.width, centred(cell.height, t), t)
}

/// A circle of radius `r` about x, y.
func circlePath(_ x: Double, _ y: Double, _ r: Double) -> CGMutablePath {
    let path = CGMutablePath()
    path.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    path.closeSubpath()
    return path
}
