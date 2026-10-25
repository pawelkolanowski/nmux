import CoreText
import Foundation
import GhosttyVt

// The grid as the GPU draws it, rebuilt from libghostty-vt's render state one dirty row at a time: each cell's
// background, one glyph from the font, and the cursor. Adapted from Ghostty's `src/renderer/generic.zig`
// (`rebuildRow`, `addGlyph`, `addCursor`), `src/renderer/cursor.zig` (`style`) and `src/font/face/coretext.zig`
// (`renderGlyph`) at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// Ghostty's `CellText`, 32 bytes, laid out as `CellText` in Shaders.metal.
struct CellText {
    var glyphPos: SIMD2<UInt32>
    var glyphSize: SIMD2<UInt32>
    var bearings: SIMD2<Int16>
    var gridPos: SIMD2<UInt16>
    var color: SIMD4<UInt8>
    /// Which atlas; nmux has only the alpha one yet.
    var atlas: UInt8 = 0
    /// Ghostty's `bools`.
    var flags: UInt8 = 0
    static let isCursorGlyph: UInt8 = 2

    init(_ g: Glyph, at gridPos: SIMD2<UInt16>, color: SIMD4<UInt8>, flags: UInt8 = 0) {
        (glyphPos, glyphSize, bearings) = ([g.x, g.y], [g.width, g.height], [g.left, g.top])
        (self.gridPos, self.color, self.flags) = (gridPos, color, flags)
    }
}

/// A glyph's place in its atlas and its bearings: `left` from the cell's left edge, `top` from the cell's bottom up
/// to the glyph's top, in pixels. A glyph with no outline has no size and is never drawn.
struct Glyph {
    var x: UInt32 = 0, y: UInt32 = 0, width: UInt32 = 0, height: UInt32 = 0
    var left: Int16 = 0, top: Int16 = 0
}

enum CursorShape: String {
    case block, bar, underline, hollow
}

@MainActor
final class Cells {
    let font: Font
    private(set) var atlas = Atlas()
    private(set) var cols = 0, rows = 0
    /// One colour per cell, row-major; alpha 0 where the cell has the terminal's background.
    private(set) var bg: [SIMD4<UInt8>] = []
    /// Each row's glyphs.
    private(set) var text: [[CellText]] = []
    /// What each cell drew, which the self-test reads.
    private(set) var drawn: [Drawn] = []
    private(set) var cursor: CellText?
    private(set) var cursorShape: CursorShape?
    private(set) var cursorCell: SIMD2<Int>?
    private(set) var cursorWide = false
    private(set) var cursorColor = SIMD4<UInt8>(0, 0, 0, 255)
    /// Whether the terminal asks for a blinking cursor; the view runs the blink while it does.
    private(set) var cursorBlinking = false
    private(set) var background = SIMD4<UInt8>(255, 255, 255, 255)
    private(set) var foreground = SIMD4<UInt8>(0, 0, 0, 255)
    /// Set by the view; a change rebuilds only the cursor.
    var focused = true { didSet { if focused != oldValue { cursorChanged = true } } }
    var blinkVisible = true { didSet { if blinkVisible != oldValue { cursorChanged = true } } }
    private var cursorChanged = false
    /// The theme changed, and every row draws again.
    var restyled = false
    /// libghostty-vt marks nothing dirty when only the cursor's shape, blink or visibility changes, so the cursor
    /// as last built is compared with the render state's.
    private var builtCursor: BuiltCursor?
    private var glyphs: [GlyphKey: Glyph] = [:]
    private var cursorGlyphs: [CursorKey: Glyph] = [:]
    private var state: GhosttyRenderState?
    private var rowIterator: GhosttyRenderStateRowIterator?
    private var rowCells: GhosttyRenderStateRowCells?
    private var colors = GhosttyRenderStateColors()
    private var graphemes = [UInt32](repeating: 0, count: 16)

    /// A cell's face and glyph, nil and 0 for an invisible cell or one with no text.
    struct Drawn {
        var face: CTFont?
        var glyph: CGGlyph = 0
        var fg = SIMD4<UInt8>.zero, bg = SIMD4<UInt8>.zero
        var wide = false
    }

    private struct BuiltCursor: Equatable {
        var cell: SIMD2<Int>?
        var style: GhosttyRenderStateCursorVisualStyle
        var visible, blinking: Bool
        var background, foreground: SIMD4<UInt8>
    }

    private struct GlyphKey: Hashable {
        var face: ObjectIdentifier
        var glyph: CGGlyph
    }

    private struct CursorKey: Hashable {
        var shape: CursorShape
        var wide: Bool
    }

    init(font: Font) {
        self.font = font
        ghostty_render_state_new(nil, &state)
        ghostty_render_state_row_iterator_new(nil, &rowIterator)
        ghostty_render_state_row_cells_new(nil, &rowCells)
        colors.size = MemoryLayout<GhosttyRenderStateColors>.size
    }

    isolated deinit {
        ghostty_render_state_row_cells_free(rowCells)
        ghostty_render_state_row_iterator_free(rowIterator)
        ghostty_render_state_free(state)
    }

    var textCount: Int { (cursor == nil ? 0 : 1) + text.reduce(0) { $0 + $1.count } }

    /// Copies every glyph to `out`, which holds `textCount`: a block cursor first, so the text over it draws on top;
    /// any other cursor last, over the text.
    func writeText(_ out: UnsafeMutablePointer<CellText>) {
        var i = 0
        if let cursor, cursorShape == .block { out[0] = cursor; i = 1 }
        for row in text where !row.isEmpty {
            row.withUnsafeBufferPointer { (out + i).update(from: $0.baseAddress!, count: $0.count) }
            i += row.count
        }
        if let cursor, cursorShape != .block { out[i] = cursor }
    }

    /// Takes the terminal's changes and rebuilds what is dirty. False when nothing changed. Nothing may read the
    /// state before `end_update`, which runs outside the host's lock.
    func update(_ host: VTHost) -> Bool {
        _ = host.locked { ghostty_render_state_begin_update(state, $0) }
        ghostty_render_state_end_update(state)

        var dirty = GHOSTTY_RENDER_STATE_DIRTY_FALSE
        ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_DIRTY, &dirty)
        var cur = GhosttyRenderStateCursor()
        cur.size = MemoryLayout<GhosttyRenderStateCursor>.size
        ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_CURSOR, &cur)
        ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_COLORS, &colors)
        let built = BuiltCursor(cell: cur.viewport_has_value ? SIMD2(Int(cur.viewport_x), Int(cur.viewport_y)) : nil,
                                style: cur.visual_style, visible: cur.visible, blinking: cur.blinking,
                                background: rgba(colors.background), foreground: rgba(colors.foreground))
        guard dirty != GHOSTTY_RENDER_STATE_DIRTY_FALSE || cursorChanged || built != builtCursor || restyled
        else { return false }
        // The default colours reach every cell that has none of its own.
        var full = dirty == GHOSTTY_RENDER_STATE_DIRTY_FULL || restyled
            || built.background != builtCursor?.background || built.foreground != builtCursor?.foreground
        restyled = false
        (cursorChanged, builtCursor) = (false, built)
        (background, foreground) = (built.background, built.foreground)

        var c: UInt16 = 0, r: UInt16 = 0
        ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_COLS, &c)
        ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_ROWS, &r)
        if Int(c) != cols || Int(r) != rows {
            (cols, rows) = (Int(c), Int(r))
            bg = [SIMD4<UInt8>](repeating: .zero, count: cols * rows)
            drawn = [Drawn](repeating: Drawn(), count: cols * rows)
            text = [[CellText]](repeating: [], count: rows)
            full = true
        }
        if full || dirty != GHOSTTY_RENDER_STATE_DIRTY_FALSE {
            ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &rowIterator)
            var y = 0
            while y < rows && ghostty_render_state_row_iterator_next(rowIterator) {
                defer { y += 1 }
                var rowDirty = false
                ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY, &rowDirty)
                guard full || rowDirty else { continue }
                ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &rowCells)
                rebuildRow(y)
            }
        }
        buildCursor(cur)
        ghostty_render_state_clean(state)
        return true
    }

    /// Each cell's background and glyph: inverse swaps the foreground and the background, and an invisible cell draws
    /// only its background, as xterm.
    private func rebuildRow(_ y: Int) {
        text[y].removeAll(keepingCapacity: true)
        var x = 0
        while x < cols && ghostty_render_state_row_cells_next(rowCells) {
            defer { x += 1 }
            var raw: GhosttyCell = 0, wide = GHOSTTY_CELL_WIDE_NARROW
            ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &raw)
            ghostty_cell_get(raw, GHOSTTY_CELL_DATA_WIDE, &wide)
            var style = GhosttyStyle()
            style.size = MemoryLayout<GhosttyStyle>.size
            var styled = false
            ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_HAS_STYLING, &styled)
            if styled {
                ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style)
            }
            var color = GhosttyColorRgb()
            let fg = ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR, &color)
                == GHOSTTY_SUCCESS ? rgba(color) : foreground
            let ownBg = ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR,
                                                           &color)
                == GHOSTTY_SUCCESS ? rgba(color) : nil
            let cellBg = style.inverse ? fg : ownBg
            let ink = style.inverse ? ownBg ?? background : fg
            bg[y * cols + x] = cellBg ?? .zero
            var d = Drawn(fg: ink, bg: cellBg ?? background, wide: wide == GHOSTTY_CELL_WIDE_WIDE)
            defer { drawn[y * cols + x] = d }

            var len: UInt32 = 0
            ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &len)
            guard len > 0, !style.invisible else { continue }
            if graphemes.count < len { graphemes = [UInt32](repeating: 0, count: Int(len)) }
            graphemes.withUnsafeMutableBufferPointer {
                _ = ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
                                                       $0.baseAddress)
            }
            // One glyph a cell: the grapheme's base codepoint.
            guard let face = font.face(for: graphemes[0]), let id = glyph(face, graphemes[0]) else { continue }
            (d.face, d.glyph) = (face, id)
            let g = atlasGlyph(face, id)
            if g.width > 0 { text[y].append(CellText(g, at: SIMD2(UInt16(x), UInt16(y)), color: ink)) }
        }
        for rest in x..<cols {
            bg[y * cols + rest] = .zero
            drawn[y * cols + rest] = Drawn(fg: foreground, bg: background)
        }
    }

    /// Ghostty's cursor style: none outside the viewport or while hidden, a hollow block while unfocused, none in a
    /// blink's off phase, else the shape the terminal asks for, over both cells of a wide character.
    private func buildCursor(_ cur: GhosttyRenderStateCursor) {
        (cursor, cursorShape, cursorCell, cursorWide) = (nil, nil, nil, false)
        // A hidden cursor never blinks: its blink would draw frames that show nothing.
        cursorBlinking = cur.blinking && cur.visible && cur.viewport_has_value
        guard cur.viewport_has_value, cur.visible else { return }
        let shape: CursorShape
        if !focused { shape = .hollow }
        else if cur.blinking && !blinkVisible { return }
        else {
            switch cur.visual_style {
            case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR: shape = .bar
            case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE: shape = .underline
            case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW: shape = .hollow
            default: shape = .block
            }
        }
        let x = Int(cur.viewport_x) - (cur.wide_tail ? 1 : 0), y = Int(cur.viewport_y)
        guard x >= 0, x < cols, y < rows else { return }
        let wide = cur.wide_tail || drawn[y * cols + x].wide
        cursorColor = rgba(colors.cursor_has_value ? colors.cursor : colors.foreground)
        cursor = CellText(cursorGlyph(shape, wide: wide), at: SIMD2(UInt16(x), UInt16(y)), color: cursorColor,
                          flags: CellText.isCursorGlyph)
        (cursorShape, cursorCell, cursorWide) = (shape, SIMD2(x, y), wide)
    }

    private func atlasGlyph(_ face: CTFont, _ id: CGGlyph) -> Glyph {
        let key = GlyphKey(face: ObjectIdentifier(face), glyph: id)
        if let g = glyphs[key] { return g }
        let g = render(face, id)
        glyphs[key] = g
        return g
    }

    /// Ghostty's `renderGlyph` without constraints, thickening or colour: the glyph's outline at its subpixel place on
    /// the baseline, centred in a cell wider than the face, as a coverage mask whose first row is the top.
    private func render(_ face: CTFont, _ id: CGGlyph) -> Glyph {
        var glyph = id
        let rect = CTFontGetBoundingRectsForGlyphs(face, .horizontal, &glyph, nil, 1)
        // Smaller than a quarter pixel has no outline worth drawing.
        guard rect.width >= 0.25, rect.height >= 0.25 else { return Glyph() }
        let cell = font.cell
        var x = Double(rect.minX)
        let y = Double(rect.minY) + Double(cell.baseline)
        let dx = (Double(cell.width) - cell.faceWidth) / 2
        x += dx
        // A cell narrower than the face keeps only the fraction, for the same subpixel position.
        if dx < 0 { x -= dx.rounded(.towardZero) }
        let pxX = Int(x.rounded(.down)), pxY = Int(y.rounded(.down))
        let fracX = x - x.rounded(.down), fracY = y - y.rounded(.down)
        let width = Int((Double(rect.width) + fracX).rounded(.up))
        let height = Int((Double(rect.height) + fracY).rounded(.up))
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpace(name: CGColorSpace.linearGray)!,
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return }
            ctx.setAllowsFontSmoothing(true)
            ctx.setShouldSmoothFonts(false)
            ctx.setAllowsFontSubpixelPositioning(true)
            ctx.setShouldSubpixelPositionFonts(true)
            ctx.setAllowsFontSubpixelQuantization(false)
            ctx.setShouldSubpixelQuantizeFonts(false)
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.translateBy(x: fracX, y: fracY)
            var origin = CGPoint(x: -rect.minX, y: -rect.minY)
            CTFontDrawGlyphs(face, &glyph, &origin, 1, ctx)
        }
        return place(pixels, width: width, height: height, left: pxX, top: pxY + height)
    }

    /// Ghostty's cursor sprites over the whole cell, or both cells of a wide character: a filled block, a block's
    /// outline, a bar at the left edge, or a line at the underline's place, `cursorThickness` thick.
    private func cursorGlyph(_ shape: CursorShape, wide: Bool) -> Glyph {
        let key = CursorKey(shape: shape, wide: wide)
        if let g = cursorGlyphs[key] { return g }
        let cell = font.cell, t = cell.cursorThickness
        let width = cell.width * (wide ? 2 : 1), height = cell.height
        let underline = min(max(cell.underlinePosition, 0), height - t)
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let on = switch shape {
                case .block: true
                case .hollow: x < t || y < t || x >= width - t || y >= height - t
                case .bar: x < t
                case .underline: y >= underline && y < underline + t
                }
                if on { pixels[y * width + x] = 255 }
            }
        }
        let g = place(pixels, width: width, height: height, left: 0, top: height)
        cursorGlyphs[key] = g
        return g
    }

    private func place(_ pixels: [UInt8], width: Int, height: Int, left: Int, top: Int) -> Glyph {
        let at = atlas.reserve(width: width, height: height)
        atlas.fill(x: at.x, y: at.y, width: width, height: height, rows: pixels)
        return Glyph(x: UInt32(at.x), y: UInt32(at.y), width: UInt32(width), height: UInt32(height),
                     left: Int16(clamping: left), top: Int16(clamping: top))
    }

    /// Called by the renderer once it uploaded what the atlas gained.
    func atlasUploaded() { atlas.uploaded() }
}

func rgba(_ c: GhosttyColorRgb) -> SIMD4<UInt8> { [c.r, c.g, c.b, 255] }
