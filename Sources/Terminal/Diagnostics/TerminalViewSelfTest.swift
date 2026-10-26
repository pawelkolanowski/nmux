#if NMUX_SELFTEST
import AppKit
import GhosttyVt

/// The self-test's view of the drawing: what the cells hold, the frames presented, one frame read back, and frames
/// that go on while the window is hidden. Only VTSelfTest calls it.
extension TerminalView {
    /// Frames presented so far.
    public var frames: UInt64 { renderer.frames }

    /// `face=<family> glyph=<id> glyphs=<n> atlas=<text|color> fg=<rrggbb> bg=<rrggbb> style=<style> synthetic=<yes|no>
    /// deco=<list> span=<1|2> cluster=<hex,…>` for the cell at x, y as last built. The face is its run's, `none` for a
    /// cell with no text, `sprite` with the glyph `U+<hex>` for a codepoint nmux draws itself; the glyph is the first
    /// with an outline shaped onto the cell, 0 when none, `glyphs` counts them, and `atlas` names that glyph's atlas,
    /// `text` when none; `span` counts the cells that glyph was placed over. A faint foreground adds its alpha,
    /// `rrggbbaa`; the list names each decoration with its colour, `underline-curly:#ff0000,strike:#000000`, or reads
    /// `none`; the cluster reads `none` for a cell with no text.
    public func describeCell(_ x: Int, _ y: Int) -> String? {
        cells.drawn(x, y).map { d in
            let deco = d.decorations.isEmpty ? "none" : d.decorations.map { "\($0.kind.rawValue):#\(hex($0.color))" }
                .joined(separator: ",")
            let cluster = d.cluster.isEmpty ? "none" : d.cluster.map { String($0, radix: 16) }.joined(separator: ",")
            let face = d.sprite ? "sprite" : d.face.map(family) ?? "none"
            let glyph = d.sprite ? String(format: "U+%04X", d.glyph) : "\(d.glyph)"
            return "face=\(face) glyph=\(glyph) glyphs=\(d.glyphCount) atlas=\(d.atlas) "
                + "fg=\(hex(d.fg))\(d.fg.w == 255 ? "" : String(format: "%02x", d.fg.w)) "
                + "bg=\(hex(d.bg)) style=\(d.style.rawValue) synthetic=\(d.synthetic ? "yes" : "no") deco=\(deco) "
                + "span=\(d.span) cluster=\(cluster)"
        }
    }

    /// `<x0>,<y0>-<x1>,<y1>`, the terminal's selection's first and last cell in the viewport, or `none`.
    public func describeSelection() -> String {
        guard let (first, last) = selectionGesture.span(grid) else { return "none" }
        return "\(first.x),\(first.y)-\(last.x),\(last.y)"
    }

    /// The rows the last update that rebuilt any row had to shape.
    public var rowsShaped: Int { cells.shaped }

    public func hasGlyph(_ x: Int, _ y: Int) -> Bool { cells.drawn(x, y)?.face != nil }

    public func isUnderlined(_ x: Int, _ y: Int) -> Bool {
        cells.drawn(x, y)?.decorations.contains { $0.kind.isUnderline } ?? false
    }

    public func isDecorated(_ x: Int, _ y: Int) -> Bool { cells.drawn(x, y)?.decorations.isEmpty == false }

    /// `<x>,<y> <shape> <rrggbb>`, or `none` when no cursor is drawn.
    public func describeCursor() -> String {
        guard let at = cells.cursorCell, let shape = cells.cursorShape else { return "none" }
        return "\(at.x),\(at.y) \(shape.rawValue) \(hex(cells.cursorColor))"
    }

    /// Copy, Paste and OSC 52 on a pasteboard of the self-test's own, never the author's.
    public func use(_ pasteboard: NSPasteboard) { self.pasteboard = pasteboard }

    /// Lets `readBack` read the frames; set before the view gets its first drawable.
    public func keepFramesReadable() { renderer.layer.framebufferOnly = false }

    /// Draws one frame, reads its pixels back and hands `done` the verdict `bg <ok|bad> ink <x>,<y> <ok|bad> cursor
    /// <ok|bad>`, then ` color <ok|bad>` when the ink cell's glyph is a colour one, then ` selected <ok|bad>` when the
    /// ink cell is selected, then ` underline <x>,<y> <ok|bad> plain <x>,<y> <ok|bad>` when given an underlined and a
    /// plain cell.
    public func readBack(ink x: Int, _ y: Int,
                         underline: (underlined: (x: Int, y: Int), plain: (x: Int, y: Int))? = nil,
                         _ done: @escaping (String) -> Void) {
        renderer.readback = { [cells] frame in
            var verdict = cells.verdict(frame, ink: x, y)
            if let (underlined, plain) = underline {
                func ok(_ pass: Bool) -> String { pass ? "ok" : "bad" }
                verdict += " underline \(underlined.x),\(underlined.y)"
                    + " \(ok(cells.underlineInk(frame, underlined.x, underlined.y)))"
                    + " plain \(plain.x),\(plain.y) \(ok(!cells.underlineInk(frame, plain.x, plain.y)))"
            }
            done(verdict)
        }
        redraw = true
        resume()
    }

    /// Draws one frame and hands `done` the first blank cell's centre as `<rrggbb> <aa>`, the colour with the alpha
    /// divided out, or `none` when every cell holds something.
    public func readBackground(_ done: @escaping (String) -> Void) {
        renderer.readback = { [cells] frame in
            let cell = cells.font.cell
            guard let i = cells.blank, let p = frame.bgra(i % cells.cols * cell.width + cell.width / 2,
                                                          i / cells.cols * cell.height + cell.height / 2)
            else { return done("none") }
            let rgb = [p.x, p.y, p.z].map { p.w == 0 ? 0 : min(255, (Int($0) * 255 + Int(p.w) / 2) / Int(p.w)) }
            done(String(format: "%02x%02x%02x %02x", rgb[0], rgb[1], rgb[2], p.w))
        }
        redraw = true
        resume()
    }

    /// The display link never ticks while the window is not visible, as behind a locked screen. The self-test then
    /// steps the same frames, paused alike, from a 60 Hz timer.
    public func stepWhileHidden() {
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let link = self.link, !link.isPaused,
                      self.window?.occlusionState.contains(.visible) == false else { return }
                self.step()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

extension Cells {
    func drawn(_ x: Int, _ y: Int) -> Drawn? {
        x >= 0 && y >= 0 && x < cols && y < rows ? drawn[y * cols + x] : nil
    }

    /// The first cell with no glyph, no background of its own and no cursor, and not the tail of a wide one.
    var blank: Int? {
        (0..<cols * rows).first { i in
            drawn[i].face == nil && bg[i].w == 0 && cursorCell != SIMD2(i % cols, i / cols)
                && !(i % cols > 0 && drawn[i - 1].wide)
        }
    }

    /// `bg` is a pixel outside every glyph, in the terminal's background; `ink` any pixel of the cell at x, y that
    /// differs from the cell's background; `cursor` the cursor cell's centre in the cursor's colour; `color`, for a
    /// colour glyph, any pixel of its cells that no blend of the foreground and the background gives; `selected`, for a
    /// selected cell, its top left pixel in the cell's background.
    func verdict(_ frame: Readback, ink x: Int, _ y: Int) -> String {
        let cell = font.cell
        func centre(_ cx: Int, _ cy: Int) -> SIMD4<UInt8>? {
            frame.bgra(cx * cell.width + cell.width / 2, cy * cell.height + cell.height / 2)
        }
        func ok(_ pass: Bool) -> String { pass ? "ok" : "bad" }
        let background = blank.map { centre($0 % cols, $0 / cols) == self.background } ?? false
        let ink = drawn(x, y).map { d in
            (0..<cell.height).contains { py in
                (0..<cell.width).contains { px in
                    frame.bgra(x * cell.width + px, y * cell.height + py).map { $0 != d.bg } ?? false
                }
            }
        } ?? false
        let cursor = cursorCell.map { centre($0.x, $0.y) == cursorColor } ?? false
        var verdict = "bg \(ok(background)) ink \(x),\(y) \(ok(ink)) cursor \(ok(cursor))"
        if let d = drawn(x, y), d.atlas == .color {
            let colored = (0..<cell.height).contains { py in
                (0..<cell.width * (d.wide ? 2 : 1)).contains { px in
                    frame.bgra(x * cell.width + px, y * cell.height + py).map { offBlend($0, d.fg, d.bg) } ?? false
                }
            }
            verdict += " color \(ok(colored))"
        }
        if selection[y]?.contains(x) == true, let d = drawn(x, y) {
            verdict += " selected \(ok(frame.bgra(x * cell.width, y * cell.height) == d.bg))"
        }
        return verdict
    }

    /// Whether the pixel lies off the line from `bg` to `fg`, by more than a tenth of the channel's range: measured
    /// along the channel where the two differ most.
    private func offBlend(_ p: SIMD4<UInt8>, _ fg: SIMD4<UInt8>, _ bg: SIMD4<UInt8>) -> Bool {
        func rgb(_ c: SIMD4<UInt8>) -> SIMD3<Double> { SIMD3(Double(c.x), Double(c.y), Double(c.z)) }
        let span = rgb(fg) - rgb(bg), off = rgb(p) - rgb(bg)
        let c = [0, 1, 2].max { abs(span[$0]) < abs(span[$1]) }!
        let t = span[c] == 0 ? 0 : off[c] / span[c]
        return [0, 1, 2].contains { abs(off[$0] - t * span[$0]) > 25.5 }
    }

    /// Whether any pixel of the underline's rows in the cell at x, y differs from the cell's background.
    func underlineInk(_ frame: Readback, _ x: Int, _ y: Int) -> Bool {
        let cell = font.cell
        guard let d = drawn(x, y) else { return false }
        let rows = cell.underlinePosition..<min(cell.underlinePosition + cell.underlineThickness, cell.height)
        return rows.contains { py in
            (0..<cell.width).contains { px in
                frame.bgra(x * cell.width + px, y * cell.height + py).map { $0 != d.bg } ?? false
            }
        }
    }
}

private func hex(_ c: SIMD4<UInt8>) -> String { String(format: "%02x%02x%02x", c.x, c.y, c.z) }
#endif
