#if NMUX_SELFTEST
import AppKit
import GhosttyVt

/// The self-test's view of the drawing: what the cells hold, the frames presented, one frame read back, and frames
/// that go on while the window is hidden. Only VTSelfTest calls it.
extension TerminalView {
    /// Frames presented so far.
    public var frames: UInt64 { renderer.frames }

    /// `face=<family> glyph=<id> fg=<rrggbb> bg=<rrggbb>` for the cell at x, y as last built; the face reads `none`
    /// for a cell with no text.
    public func describeCell(_ x: Int, _ y: Int) -> String? {
        cells.drawn(x, y).map { d in
            "face=\(d.face.map(family) ?? "none") glyph=\(d.glyph) fg=\(hex(d.fg)) bg=\(hex(d.bg))"
        }
    }

    public func hasGlyph(_ x: Int, _ y: Int) -> Bool { cells.drawn(x, y)?.face != nil }

    /// `<x>,<y> <shape> <rrggbb>`, or `none` when no cursor is drawn.
    public func describeCursor() -> String {
        guard let at = cells.cursorCell, let shape = cells.cursorShape else { return "none" }
        return "\(at.x),\(at.y) \(shape.rawValue) \(hex(cells.cursorColor))"
    }

    /// Lets `readBack` read the frames; set before the view gets its first drawable.
    public func keepFramesReadable() { renderer.layer.framebufferOnly = false }

    /// Draws one frame, reads its pixels back and hands `done` the verdict `bg <ok|bad> ink <x>,<y> <ok|bad> cursor
    /// <ok|bad>`.
    public func readBack(ink x: Int, _ y: Int, _ done: @escaping (String) -> Void) {
        renderer.readback = { [cells] frame in done(cells.verdict(frame, ink: x, y)) }
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
    /// differs from the cell's background; `cursor` the cursor cell's centre in the cursor's colour.
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
        return "bg \(ok(background)) ink \(x),\(y) \(ok(ink)) cursor \(ok(cursor))"
    }
}

private func hex(_ c: SIMD4<UInt8>) -> String { String(format: "%02x%02x%02x", c.x, c.y, c.z) }
#endif
