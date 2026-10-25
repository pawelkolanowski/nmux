import CoreText
import Foundation
import GhosttyVt

// The grid as the GPU draws it, rebuilt from libghostty-vt's render state one dirty row at a time: each cell's
// background, the glyphs its row's runs shaped onto it, its decorations, and the cursor. Adapted from Ghostty's
// `src/renderer/generic.zig` (`rebuildRow`, `addGlyph`, `addUnderline`, `addOverline`, `addStrikethrough`,
// `addCursor`), `src/renderer/cursor.zig` (`style`), `src/renderer/cell.zig` (`isCovering`), `src/font/SharedGrid.zig`
// (`GlyphKey`), `src/font/shaper/coretext.zig` (`shape`) and the preedit of `generic.zig` (`rebuildCells`,
// `addPreeditCell`) at commit 22f100c6; the glyph's raster is `rasterise`'s.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// Ghostty's `CellText`, 32 bytes, laid out as `CellText` in Shaders.metal.
struct CellText {
    var glyphPos: SIMD2<UInt32>
    var glyphSize: SIMD2<UInt32>
    var bearings: SIMD2<Int16>
    var gridPos: SIMD2<UInt16>
    var color: SIMD4<UInt8>
    /// A `GlyphAtlas`, as the shader's `CellTextAtlas`.
    var atlas: UInt8
    /// Ghostty's `bools`.
    var flags: UInt8 = 0
    static let isCursorGlyph: UInt8 = 2

    init(_ g: Glyph, at gridPos: SIMD2<UInt16>, color: SIMD4<UInt8>, flags: UInt8 = 0) {
        (glyphPos, glyphSize, bearings, atlas) = ([g.x, g.y], [g.width, g.height], [g.left, g.top], g.atlas.rawValue)
        (self.gridPos, self.color, self.flags) = (gridPos, color, flags)
    }
}

/// A glyph's place in its atlas and its bearings: `left` from the cell's left edge, `top` from the cell's bottom up
/// to the glyph's top, in pixels. A glyph with no outline has no size and is never drawn.
struct Glyph {
    var x: UInt32 = 0, y: UInt32 = 0, width: UInt32 = 0, height: UInt32 = 0
    var left: Int16 = 0, top: Int16 = 0
    var atlas = GlyphAtlas.text
}

/// The alpha atlas or the colour one, named as the self-test logs it.
enum GlyphAtlas: UInt8 {
    case text, color
}

enum CursorShape: String {
    case block, bar, underline, hollow
}

@MainActor
final class Cells {
    let font: Font
    private(set) var atlas = Atlas()
    private(set) var colorAtlas = Atlas(depth: 4)
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
    /// The text input client's marked text, each codepoint with a width, set by the view; drawn from the cursor's cell
    /// on in place of the pane's cells there, which come back once it is gone.
    var preedit: [UInt32] = [] { didSet { if preedit != oldValue { preeditChanged = true } } }
    /// The cells of the link under the pointer while Cmd is held, underlined as Ghostty's hovered links are.
    var hoveredLink: LinkCells? {
        didSet { if hoveredLink != oldValue { linkRows += [oldValue?.row, hoveredLink?.row].compactMap { $0 } } }
    }
    private var linkRows: [Int] = []
    /// The theme's selection colours, set by the view; where one is missing a selected cell takes the default
    /// foreground as its background and the default background as its text, Ghostty's.
    var selectionBackground: SIMD4<UInt8>? { didSet { if selectionBackground != oldValue { restyled = true } } }
    var selectionForeground: SIMD4<UInt8>? { didSet { if selectionForeground != oldValue { restyled = true } } }
    /// The theme's text under a block cursor, set by the view; nil takes the background in force.
    var cursorText: SIMD4<UInt8>?
    /// The selection's colours or the theme changed, and every row draws again.
    var restyled = false
    /// Each row's selected columns as last built, nil where the row has none.
    private(set) var selection: [ClosedRange<Int>?] = []
    private var preeditChanged = false
    /// The row the marked text was last drawn on.
    private var preeditRow: Int?
    /// libghostty-vt marks nothing dirty when only the cursor's shape, blink or visibility changes, so the cursor
    /// as last built is compared with the render state's.
    private var builtCursor: BuiltCursor?
    private var glyphs: [GlyphKey: Glyph] = [:]
    private var cursorGlyphs: [CursorKey: Glyph] = [:]
    private var decorations: [DecorationKey: Glyph] = [:]
    private var sprites: [SpriteKey: Glyph] = [:]
    /// Every face a run was shaped in, by id, with its font for the shaper; a row's shaped glyphs by its identity,
    /// kept while the row's runs hash the same.
    private var faces: [(face: Face, shaping: CTFont)] = []
    private var faceIDs: [FaceKey: Int] = [:]
    private var shapedRows: [RowID: (hash: Int, glyphs: [Shaped])] = [:]
    /// Rows the last update that rebuilt any row had to shape, which the self-test reads.
    private(set) var shaped = 0
    private var runCells: [RunCell] = []
    private var state: GhosttyRenderState?
    private var rowIterator: GhosttyRenderStateRowIterator?
    private var rowCells: GhosttyRenderStateRowCells?
    private var colors = GhosttyRenderStateColors()
    private var graphemes = [UInt32](repeating: 0, count: 16)

    /// A cell's face is its run's, nil for a spacer, an invisible cell or one with no text.
    struct Drawn {
        var face: CTFont?
        var sprite = false
        var cluster: Cluster = []
        var fg = SIMD4<UInt8>.zero, bg = SIMD4<UInt8>.zero
        var wide = false
        var style = FontStyle.regular
        var decorations: [(kind: Decoration, color: SIMD4<UInt8>)] = []
#if NMUX_SELFTEST
        /// Its glyph is the first glyph with an outline that its run shaped onto it, 0 when none, as on a ligature's
        /// covered cell; a sprite cell's glyph is its codepoint. Then that glyph's atlas, and the cells it was placed
        /// over: the constraint width for a font's glyph, else the grid width.
        var glyph: UInt32 = 0
        var glyphCount = 0
        var atlas = GlyphAtlas.text
        var span = 1
        var synthetic = false
#endif
    }

    private struct BuiltCursor: Equatable {
        var cell: SIMD2<Int>?
        var style: GhosttyRenderStateCursorVisualStyle
        var visible, blinking: Bool
        var background, foreground: SIMD4<UInt8>
    }

    /// A synthetic bold may share its CTFont with the regular face, so its stroke keeps their rasters apart; a glyph is
    /// placed over its constraint width, so that does. The constraint follows from the codepoint and stays out, as in
    /// Ghostty's `GlyphKey`.
    private struct GlyphKey: Hashable {
        var face: ObjectIdentifier
        var stroke: Double?
        var glyph: CGGlyph
        var width: Int
    }

    /// A face as runs tell faces apart: a synthetic bold shares its CTFont with the regular face but strokes it, and
    /// the sprite face shares the primary's.
    private struct FaceKey: Hashable {
        var font: ObjectIdentifier
        var stroke: Double?
        var sprite: Bool
    }

    /// libghostty-vt's row identity, its two words.
    private struct RowID: Hashable {
        var high, low: UInt64
    }

    /// A shaped glyph: the cell it draws from, in the face `face` names, offset from that cell in pixels. In the sprite
    /// face the glyph is the codepoint.
    private struct Shaped {
        var cell: Int
        var face: Int
        var glyph: UInt32
        var x, y: Int16
    }

    /// Ghostty's comparable style: everything that splits a run, which leaves the background out.
    private struct StyleKey: Hashable {
        var fg, underlineColor: StyleColor
        var bold, italic, faint, blink, inverse, invisible, strikethrough, overline: Bool
        var underline: Int32

        init(_ s: GhosttyStyle) {
            (fg, underlineColor) = (StyleColor(s.fg_color), StyleColor(s.underline_color))
            (bold, italic, faint, blink) = (s.bold, s.italic, s.faint, s.blink)
            (inverse, invisible, strikethrough, overline) = (s.inverse, s.invisible, s.strikethrough, s.overline)
            underline = s.underline
        }
    }

    /// A style's colour as SGR set it: none, a palette index or an RGB value.
    private enum StyleColor: Hashable {
        case none, palette(UInt8), rgb(UInt8, UInt8, UInt8)

        init(_ c: GhosttyStyleColor) {
            switch c.tag {
            case GHOSTTY_STYLE_COLOR_PALETTE: self = .palette(c.value.palette)
            case GHOSTTY_STYLE_COLOR_RGB: self = .rgb(c.value.rgb.r, c.value.rgb.g, c.value.rgb.b)
            default: self = .none
            }
        }
    }

    private struct DecorationKey: Hashable {
        var decoration: Decoration
        var span: Int
    }

    private struct SpriteKey: Hashable {
        var codepoint: UInt32
        var span: Int
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
        guard dirty != GHOSTTY_RENDER_STATE_DIRTY_FALSE || cursorChanged || preeditChanged || !linkRows.isEmpty
                || built != builtCursor || restyled
        else { return false }
        // The default colours reach every cell that has none of its own, and selected cells.
        var full = dirty == GHOSTTY_RENDER_STATE_DIRTY_FULL || restyled
            || built.background != builtCursor?.background || built.foreground != builtCursor?.foreground
        restyled = false
        // Runs break around the cursor, so a cursor that moved reshapes the rows it left and entered.
        let moved = built.cell != builtCursor?.cell ? [builtCursor?.cell?.y, built.cell?.y].compactMap { $0 } : []
        // Marked text that changed redraws the row it left and the cursor's.
        // So does a link that came, went or moved.
        let marked = (preeditChanged ? [preeditRow, built.cell?.y].compactMap { $0 } : []) + linkRows
        (cursorChanged, preeditChanged, linkRows, builtCursor) = (false, false, [], built)
        (background, foreground) = (built.background, built.foreground)

        var c: UInt16 = 0, r: UInt16 = 0
        ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_COLS, &c)
        ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_ROWS, &r)
        if Int(c) != cols || Int(r) != rows {
            (cols, rows) = (Int(c), Int(r))
            bg = [SIMD4<UInt8>](repeating: .zero, count: cols * rows)
            drawn = [Drawn](repeating: Drawn(), count: cols * rows)
            text = [[CellText]](repeating: [], count: rows)
            selection = [ClosedRange<Int>?](repeating: nil, count: rows)
            full = true
        }
        if full || dirty != GHOSTTY_RENDER_STATE_DIRTY_FALSE || !moved.isEmpty || !marked.isEmpty {
            ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &rowIterator)
            var y = 0, rebuilt = 0, shapedNow = 0
            var seen = Set<RowID>()
            while y < rows && ghostty_render_state_row_iterator_next(rowIterator) {
                defer { y += 1 }
                var id = GhosttyRenderStateRowId()
                ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_ID, &id)
                let key = RowID(high: id.bits.0, low: id.bits.1)
                seen.insert(key)
                var rowDirty = false
                ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY, &rowDirty)
                guard full || rowDirty || moved.contains(y) || marked.contains(y) else { continue }
                ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &rowCells)
                var sel = GhosttyRenderStateRowSelection()
                sel.size = MemoryLayout<GhosttyRenderStateRowSelection>.size
                selection[y] = ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_SELECTION, &sel)
                    == GHOSTTY_SUCCESS ? Int(sel.start_x)...Int(sel.end_x) : nil
                rebuilt += 1
                if rebuildRow(y, key, cursor: built.cell?.y == y ? built.cell?.x : nil) { shapedNow += 1 }
            }
            shapedRows = shapedRows.filter { seen.contains($0.key) }
            if rebuilt > 0 { shaped = shapedNow }
        }
        buildCursor(cur)
        ghostty_render_state_clean(state)
        return true
    }

    /// Each cell's background, glyphs and decorations: underline and overline under the glyphs, strikethrough over
    /// them. libghostty-vt leaves inverse, faint and the bold colour to the host: inverse swaps the foreground and the
    /// background, faint halves the foreground's alpha, Ghostty's `faint-opacity`, and bold keeps its colour, Ghostty's
    /// default `bold-color`. A full block covers its cell, so it takes the foreground as its background too, and under
    /// inverse the two cancel out, Ghostty's `isCovering`. A selected cell takes the selection's colours over all of
    /// that, a wide cell's tail with its head. An invisible cell draws only its background, as xterm. True when the
    /// row's runs had to be shaped again.
    private func rebuildRow(_ y: Int, _ key: RowID, cursor: Int?) -> Bool {
        text[y].removeAll(keepingCapacity: true)
        if preeditRow == y { preeditRow = nil }
        runCells.removeAll(keepingCapacity: true)
        var styles: [StyleKey: Int] = [:]
        var x = 0
        while x < cols && ghostty_render_state_row_cells_next(rowCells) {
            defer { x += 1 }
            var raw: GhosttyCell = 0, wide = GHOSTTY_CELL_WIDE_NARROW, tag = GHOSTTY_CELL_CONTENT_CODEPOINT
            ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &raw)
            ghostty_cell_get(raw, GHOSTTY_CELL_DATA_WIDE, &wide)
            ghostty_cell_get(raw, GHOSTTY_CELL_DATA_CONTENT_TAG, &tag)
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
            var len: UInt32 = 0
            ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &len)
            if len > 0 {
                if graphemes.count < len { graphemes = [UInt32](repeating: 0, count: Int(len)) }
                graphemes.withUnsafeMutableBufferPointer {
                    _ = ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
                                                           $0.baseAddress)
                }
            }
            let cluster = Cluster(graphemes[..<Int(len)])
            let selected = selection[y]?.contains(wide == GHOSTTY_CELL_WIDE_SPACER_TAIL ? x - 1 : x) == true
            let cellBg = selected ? selectionBackground ?? foreground
                : style.inverse != isCovering(cluster.first) ? fg : ownBg
            var ink = selected ? selectionForeground ?? background : style.inverse ? ownBg ?? background : fg
            if style.faint { ink.w = 128 }
            bg[y * cols + x] = cellBg ?? .zero
            // The style SGR asks for, until a face of another style draws the cell.
            var d = Drawn(cluster: cluster, fg: ink, bg: cellBg ?? background, wide: wide == GHOSTTY_CELL_WIDE_WIDE,
                          style: FontStyle(bold: style.bold, italic: style.italic))
            let styleKey = StyleKey(style)
            var cell = RunCell(style: styles[styleKey] ?? styles.count,
                               spacer: wide == GHOSTTY_CELL_WIDE_SPACER_TAIL || wide == GHOSTTY_CELL_WIDE_SPACER_HEAD,
                               invisible: style.invisible)
            styles[styleKey] = cell.style
            // A link takes a single underline, a double one where the cell's own is single.
            let single = Int32(GHOSTTY_SGR_UNDERLINE_SINGLE.rawValue)
            var sgr = style.underline
            if hoveredLink?.row == y, hoveredLink?.cols.contains(x) == true {
                sgr = sgr == single ? Int32(GHOSTTY_SGR_UNDERLINE_DOUBLE.rawValue) : single
            }
            if let underline = underlineDecoration(sgr) {
                var line = underlineColor(style.underline_color) ?? ink
                line.w = ink.w
                d.decorations.append((underline, line))
            }
            if style.overline { d.decorations.append((.overline, ink)) }
            if style.strikethrough { d.decorations.append((.strike, ink)) }

            // A cluster no face draws shapes as U+FFFD, else as a space, as Ghostty's run iterator does.
            let face: Face
            if d.cluster.isEmpty {
                face = font[style: d.style]
            } else if let whole = font.face(for: d.cluster, style: d.style) {
                (face, cell.codepoints) = (whole, d.cluster)
            } else if let replacement = font.face(for: 0xFFFD, style: d.style) {
                (face, cell.codepoints) = (replacement, [0xFFFD])
            } else {
                face = font[style: d.style]
            }
            cell.face = faceID(face)
            cell.empty = d.cluster.isEmpty && tag == GHOSTTY_CELL_CONTENT_CODEPOINT
            if !d.cluster.isEmpty && !cell.spacer && !cell.invisible {
                (d.face, d.sprite, d.style) = (face.font, face.sprite, face.style)
#if NMUX_SELFTEST
                d.synthetic = face.synthetic
                // A sprite that draws nothing still names its codepoint.
                if face.sprite { d.glyph = d.cluster[0] }
#endif
            }
            // A wide cell's tail is decorated with its head; a spacer head at the margin keeps its own.
            if cell.invisible || wide == GHOSTTY_CELL_WIDE_SPACER_TAIL { d.decorations = [] }
            runCells.append(cell)
            drawn[y * cols + x] = d
        }
        for rest in x..<cols {
            bg[y * cols + rest] = .zero
            drawn[y * cols + rest] = Drawn(fg: foreground, bg: background)
        }

        let (glyphs, reshaped) = shapedGlyphs(key, cursor: cursor, selection: selection[y])
        drawRow(y, glyphs)
        if let cursor, !preedit.isEmpty { addPreedit(y, cursor: cursor) }
        return reshaped
    }

    /// Ghostty's preedit: the pane's cells under the marked text draw nothing, and each codepoint draws in the regular
    /// face as text, in the default foreground, with a single underline under each of its cells.
    private func addPreedit(_ y: Int, cursor: Int) {
        let widths = preedit.map(preeditWidth)
        let (start, dropped) = preeditPlace(widths, cursor: cursor, cols: cols)
        let end = min(start + widths[dropped...].reduce(0, +), cols)
        text[y].removeAll { (start..<end).contains(Int($0.gridPos.x)) }
        for x in start..<end {
            bg[y * cols + x] = .zero
            drawn[y * cols + x] = Drawn(fg: foreground, bg: background)
        }
        let underline = decorationGlyph(.underline, span: 1)
        var x = start
        for (cp, width) in zip(preedit, widths).dropFirst(dropped) where x < cols {
            defer { x += width }
            let at = SIMD2(UInt16(x), UInt16(y))
            var d = Drawn(cluster: [cp], fg: foreground, bg: background, wide: width == 2,
                          decorations: [(.underline, foreground)])
#if NMUX_SELFTEST
            d.span = width
#endif
            for u in x..<min(x + width, cols) where underline.width > 0 {
                text[y].append(CellText(underline, at: SIMD2(UInt16(u), UInt16(y)), color: foreground))
            }
            if let face = font.face(for: cp, presentation: .text) {
                let id = face.sprite ? cp : glyph(face.font, cp).map(UInt32.init) ?? 0
                let g = face.sprite ? spriteGlyph(cp, span: width)
                    : id == 0 ? Glyph() : atlasGlyph(face, CGGlyph(id), constraint: glyphConstraint(cp), width: width)
                if g.width > 0 {
                    text[y].append(CellText(g, at: at, color: foreground))
                    (d.face, d.sprite) = (face.font, face.sprite)
#if NMUX_SELFTEST
                    (d.glyph, d.glyphCount, d.atlas) = (id, 1, g.atlas)
#endif
                }
            }
            drawn[y * cols + x] = d
        }
        preeditRow = y
    }

    /// The row's shaped glyphs, kept by the row's identity while its runs hash the same, as Ghostty keeps a run's
    /// shaping by its hash; true when they had to be shaped again.
    private func shapedGlyphs(_ key: RowID, cursor: Int?,
                              selection: ClosedRange<Int>?) -> (glyphs: [Shaped], reshaped: Bool) {
        var hasher = Hasher()
        hasher.combine(runCells)
        hasher.combine(cursor)
        hasher.combine(selection)
        let hash = hasher.finalize()
        if let kept = shapedRows[key], kept.hash == hash { return (kept.glyphs, false) }
        let glyphs = shapeRow(cursor: cursor, selection: selection)
        shapedRows[key] = (hash, glyphs)
        return (glyphs, true)
    }

    /// Each cell's underline and overline, the glyphs shaped onto it, then its strikethrough. A wide cell's tail is
    /// drawn with its head. A font's glyph takes the constraint of the cell's first codepoint over the cell's
    /// constraint width, as Ghostty's `addGlyph`; a sprite draws over the cell's grid width.
    private func drawRow(_ y: Int, _ glyphs: [Shaped]) {
        var g = 0
        let codepoints = (0..<cols).map { drawn[y * cols + $0].cluster.first ?? 0 }
        for x in runCells.indices {
            var d = drawn[y * cols + x]
            defer { drawn[y * cols + x] = d }
            let at = SIMD2(UInt16(x), UInt16(y)), span = d.wide ? 2 : 1
#if NMUX_SELFTEST
            d.span = span
#endif
            let constraint = glyphConstraint(codepoints[x]), width = constraintWidth(codepoints, at: x, wide: d.wide)
            for (kind, color) in d.decorations where kind != .strike {
                let sprite = decorationGlyph(kind, span: span)
                if sprite.width > 0 { text[y].append(CellText(sprite, at: at, color: color)) }
            }
            while g < glyphs.count && glyphs[g].cell < x { g += 1 }
            while g < glyphs.count && glyphs[g].cell == x {
                defer { g += 1 }
                let s = glyphs[g]
                let face = faces[s.face].face
                var atlased = face.sprite ? spriteGlyph(s.glyph, span: span)
                    : atlasGlyph(face, CGGlyph(s.glyph), constraint: constraint, width: width)
                guard atlased.width > 0, d.face != nil else { continue }
                atlased.left += s.x
                atlased.top += s.y
                text[y].append(CellText(atlased, at: at, color: d.fg))
#if NMUX_SELFTEST
                if d.glyphCount == 0 {
                    (d.glyph, d.atlas, d.span) = (s.glyph, atlased.atlas, face.sprite ? span : width)
                }
                d.glyphCount += 1
#endif
            }
            if let strike = d.decorations.first(where: { $0.kind == .strike }) {
                let sprite = decorationGlyph(.strike, span: span)
                if sprite.width > 0 { text[y].append(CellText(sprite, at: at, color: strike.color)) }
            }
        }
    }

    /// Each run of the row laid out in its face, its glyphs mapped back to the row's cells, in the cells' order.
    private func shapeRow(cursor: Int?, selection: ClosedRange<Int>?) -> [Shaped] {
        var out: [Shaped] = []
        for run in runs(runCells, cursor: cursor, selection: selection) {
            let text = runText(runCells[run])
            guard !text.utf16.isEmpty, let face = runCells[run].first(where: { !$0.spacer })?.face else { continue }
            // The sprite face is not shaped: each codepoint is its own glyph on its cell.
            if faces[face].face.sprite {
                for (cp, cell) in text.map where cp != 0 {
                    out.append(Shaped(cell: run.lowerBound + cell, face: face, glyph: cp, x: 0, y: 0))
                }
                continue
            }
            let laid = shape(text, in: faces[face].shaping)
            for (glyph, place) in zip(laid, cellsOf(laid.map(\.laid), map: text.map)) {
                out.append(Shaped(cell: run.lowerBound + place.cell, face: face, glyph: UInt32(glyph.glyph),
                                  x: Int16(clamping: place.x), y: Int16(clamping: place.y)))
            }
        }
        // CoreText may still lay a run out of order, as Ghostty sorts for; a stable sort keeps each cell's glyphs as
        // laid.
        guard zip(out, out.dropFirst()).contains(where: { $0.cell > $1.cell }) else { return out }
        return out.enumerated().sorted { ($0.element.cell, $0.offset) < ($1.element.cell, $1.offset) }.map(\.element)
    }

    /// The face's id, given the first time a run takes the face, with its font for the shaper.
    private func faceID(_ face: Face) -> Int {
        let key = FaceKey(font: ObjectIdentifier(face.font), stroke: face.stroke, sprite: face.sprite)
        if let id = faceIDs[key] { return id }
        faces.append((face, shapingFont(face.font)))
        faceIDs[key] = faces.count - 1
        return faces.count - 1
    }

    private func underlineDecoration(_ sgr: Int32) -> Decoration? {
        switch Int(sgr) {
        case Int(GHOSTTY_SGR_UNDERLINE_SINGLE.rawValue): .underline
        case Int(GHOSTTY_SGR_UNDERLINE_DOUBLE.rawValue): .underlineDouble
        case Int(GHOSTTY_SGR_UNDERLINE_CURLY.rawValue): .underlineCurly
        case Int(GHOSTTY_SGR_UNDERLINE_DOTTED.rawValue): .underlineDotted
        case Int(GHOSTTY_SGR_UNDERLINE_DASHED.rawValue): .underlineDashed
        default: nil
        }
    }

    /// SGR 58's colour, nil when the program set none.
    private func underlineColor(_ c: GhosttyStyleColor) -> SIMD4<UInt8>? {
        switch c.tag {
        case GHOSTTY_STYLE_COLOR_RGB: rgba(c.value.rgb)
        case GHOSTTY_STYLE_COLOR_PALETTE:
            withUnsafeBytes(of: colors.palette) {
                rgba($0.load(fromByteOffset: Int(c.value.palette) * 3, as: GhosttyColorRgb.self))
            }
        default: nil
        }
    }

    /// Ghostty's cursor style: none outside the viewport, while hidden or under marked text, a hollow block while
    /// unfocused, none in a blink's off phase, else the shape the terminal asks for, over both cells of a wide
    /// character.
    private func buildCursor(_ cur: GhosttyRenderStateCursor) {
        (cursor, cursorShape, cursorCell, cursorWide) = (nil, nil, nil, false)
        // A hidden cursor never blinks: its blink would draw frames that show nothing.
        cursorBlinking = cur.blinking && cur.visible && cur.viewport_has_value && preedit.isEmpty
        guard cur.viewport_has_value, cur.visible, preedit.isEmpty else { return }
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

    private func atlasGlyph(_ face: Face, _ id: CGGlyph, constraint: Constraint, width: Int) -> Glyph {
        let key = GlyphKey(face: ObjectIdentifier(face.font), stroke: face.stroke, glyph: id, width: width)
        if let g = glyphs[key] { return g }
        let raster = rasterise(face, id, constraint: constraint, cells: width, cell: font.cell, thicken: font.thicken)
        let g = raster.width > 0 ? place(raster.pixels, width: raster.width, height: raster.height, left: raster.left,
                                         top: raster.top, in: face.color ? .color : .text) : Glyph()
        glyphs[key] = g
        return g
    }

    /// Drawn once for each decoration and span, then reused from the atlas.
    private func decorationGlyph(_ decoration: Decoration, span: Int) -> Glyph {
        let key = DecorationKey(decoration: decoration, span: span)
        if let g = decorations[key] { return g }
        let s = decorationSprite(decoration, span: span, cell: font.cell)
        let g = s.width > 0 ? place(s.pixels, width: s.width, height: s.height, left: s.left, top: s.top) : Glyph()
        decorations[key] = g
        return g
    }

    /// Drawn once for each codepoint and span, then reused from the atlas; never thickened.
    private func spriteGlyph(_ codepoint: UInt32, span: Int) -> Glyph {
        let key = SpriteKey(codepoint: codepoint, span: span)
        if let g = sprites[key] { return g }
        let s = charSprite(codepoint, span: span, cell: font.cell)
        let g = s.width > 0 ? place(s.pixels, width: s.width, height: s.height, left: s.left, top: s.top) : Glyph()
        sprites[key] = g
        return g
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

    private func place(_ pixels: [UInt8], width: Int, height: Int, left: Int, top: Int,
                       in kind: GlyphAtlas = .text) -> Glyph {
        func put(_ atlas: inout Atlas) -> (x: Int, y: Int) {
            let at = atlas.reserve(width: width, height: height)
            atlas.fill(x: at.x, y: at.y, width: width, height: height, rows: pixels)
            return at
        }
        let at = kind == .color ? put(&colorAtlas) : put(&atlas)
        return Glyph(x: UInt32(at.x), y: UInt32(at.y), width: UInt32(width), height: UInt32(height),
                     left: Int16(clamping: left), top: Int16(clamping: top), atlas: kind)
    }

    /// Called by the renderer once it uploaded what the atlases gained.
    func atlasUploaded() {
        atlas.uploaded()
        colorAtlas.uploaded()
    }
}

/// A marked codepoint's cells, Ghostty's preedit width: two for a wide one, else one.
func preeditWidth(_ cp: UInt32) -> Int { ghostty_unicode_codepoint_width(cp) == 2 ? 2 : 1 }

func rgba(_ c: GhosttyColorRgb) -> SIMD4<UInt8> { [c.r, c.g, c.b, 255] }

/// Whether the codepoint's glyph covers its whole cell: only the full block, as in Ghostty.
private func isCovering(_ codepoint: UInt32?) -> Bool { codepoint == 0x2588 }

/// A link's cells: one row's run of columns.
struct LinkCells: Equatable {
    var row: Int
    var cols: Range<Int>
}
