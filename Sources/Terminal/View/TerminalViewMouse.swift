import AppKit
import GhosttyVt

// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The view's mouse, adapted from Ghostty's mouse handlers in
/// `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` and `mouseButtonCallback`, `cursorPosCallback`,
/// `scrollCallback` and `linkAtPos` in `src/Surface.zig`, at commit 22f100c6. Every press, release, motion and wheel
/// line goes to the Session's PTY through libghostty-vt's mouse encoder, so tmux's mouse mode decides what it does.
/// Shift keeps the buttons for the window, where Shift+left selects. Held Cmd underlines the link under the pointer,
/// and Cmd+click opens it and never reaches tmux.
extension TerminalView {
    public override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        // Always active, so a window that is not key still reports motion, as Ghostty's does.
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect,
                                                 .activeAlways],
                                       owner: self))
        super.updateTrackingAreas()
    }

    public override func cursorUpdate(with event: NSEvent) { pointer.set() }

    public override func mouseDown(with event: NSEvent) {
        button(GHOSTTY_MOUSE_ACTION_PRESS, GHOSTTY_MOUSE_BUTTON_LEFT, event)
    }
    public override func mouseUp(with event: NSEvent) {
        button(GHOSTTY_MOUSE_ACTION_RELEASE, GHOSTTY_MOUSE_BUTTON_LEFT, event)
    }
    public override func rightMouseDown(with event: NSEvent) {
        button(GHOSTTY_MOUSE_ACTION_PRESS, GHOSTTY_MOUSE_BUTTON_RIGHT, event)
    }
    public override func rightMouseUp(with event: NSEvent) {
        button(GHOSTTY_MOUSE_ACTION_RELEASE, GHOSTTY_MOUSE_BUTTON_RIGHT, event)
    }
    /// Only the middle button among the others; Ghostty's back and forward buttons are not tmux's.
    public override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { button(GHOSTTY_MOUSE_ACTION_PRESS, GHOSTTY_MOUSE_BUTTON_MIDDLE, event) }
    }
    public override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { button(GHOSTTY_MOUSE_ACTION_RELEASE, GHOSTTY_MOUSE_BUTTON_MIDDLE, event) }
    }

    public override func mouseMoved(with event: NSEvent) { moved(event) }
    public override func mouseDragged(with event: NSEvent) { moved(event) }
    public override func rightMouseDragged(with event: NSEvent) { moved(event) }
    public override func otherMouseDragged(with event: NSEvent) { moved(event) }

    /// Out of the view no link is under the pointer; a drag keeps reporting through its drag events.
    public override func mouseExited(with event: NSEvent) {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        showHoveredLink(nil)
    }

    /// A precise delta counts twice, Ghostty's feel, against the cell in pixels; each line is one wheel press at the
    /// pointer, which a real wheel event carries and the self-test's leaves where the last move put it.
    /// limitation: no horizontal wheel, upgrade when a program in a pane needs it.
    public override func scrollWheel(with event: NSEvent) {
        if event.window != nil { pointerAt = convert(event.locationInWindow, from: nil) }
        let precise = event.hasPreciseScrollingDeltas
        let lines = wheel.lines(event.scrollingDeltaY * (precise ? 2 : 1), precise: precise,
                                cell: Double(font.cell.height))
        for _ in 0..<abs(lines) {
            report(GHOSTTY_MOUSE_ACTION_PRESS, lines > 0 ? GHOSTTY_MOUSE_BUTTON_FOUR : GHOSTTY_MOUSE_BUTTON_FIVE,
                   event.modifierFlags)
        }
    }

    /// The pointer an OSC 22 shape asks for, as Ghostty maps them; the pointing hand over a link.
    public var pointer: NSCursor {
        if cells.hoveredLink != nil { return .pointingHand }
        return switch mouseShape {
        case GHOSTTY_MOUSE_SHAPE_DEFAULT: .arrow
        case GHOSTTY_MOUSE_SHAPE_GRAB: .openHand
        case GHOSTTY_MOUSE_SHAPE_GRABBING: .closedHand
        case GHOSTTY_MOUSE_SHAPE_POINTER: .pointingHand
        case GHOSTTY_MOUSE_SHAPE_W_RESIZE: .columnResize(directions: .left)
        case GHOSTTY_MOUSE_SHAPE_E_RESIZE: .columnResize(directions: .right)
        case GHOSTTY_MOUSE_SHAPE_N_RESIZE: .rowResize(directions: .up)
        case GHOSTTY_MOUSE_SHAPE_S_RESIZE: .rowResize(directions: .down)
        case GHOSTTY_MOUSE_SHAPE_NS_RESIZE: .rowResize
        case GHOSTTY_MOUSE_SHAPE_EW_RESIZE: .columnResize
        case GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT: .iBeamCursorForVerticalLayout
        case GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU: .contextualMenu
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: .crosshair
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED: .operationNotAllowed
        default: .iBeam
        }
    }

    /// The shape the program last asked for through OSC 22; a change shows at once while the pointer is over the view.
    func syncPointerShape() {
        let shape = host.locked { t in
            var shape = GHOSTTY_MOUSE_SHAPE_TEXT
            ghostty_terminal_get(t, GHOSTTY_TERMINAL_DATA_MOUSE_SHAPE, &shape)
            return shape
        }
        guard shape != mouseShape else { return }
        mouseShape = shape
        pointerChanged()
    }

    /// Held Cmd finds the link under the pointer; for `flagsChanged`, where the event has no position of its own.
    func modsChanged(_ flags: NSEvent.ModifierFlags) {
        guard let window else { return }
        refreshLink(flags, at: cell(at: convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }

    private func button(_ action: GhosttyMouseAction, _ button: GhosttyMouseButton, _ event: NSEvent) {
        let at = convert(event.locationInWindow, from: nil)
        pointerAt = at
        // A Cmd+click is the link's for its whole gesture: it opens the link under it when it lets go in the cell it
        // pressed, and anywhere else it does nothing.
        if button == GHOSTTY_MOUSE_BUTTON_LEFT {
            if action == GHOSTTY_MOUSE_ACTION_PRESS, linkMods(event.modifierFlags) {
                linkPress = cell(at: at)
                return
            }
            if action == GHOSTTY_MOUSE_ACTION_RELEASE, let pressed = linkPress {
                linkPress = nil
                if pressed == cell(at: at), let (target, _) = hyperlink(at: pressed), let url = openable(target) {
                    open(url)
                }
                return
            }
        }
        if action == GHOSTTY_MOUSE_ACTION_PRESS {
            buttons.insert(button.rawValue)
        } else {
            buttons.remove(button.rawValue)
        }
        if button == GHOSTTY_MOUSE_BUTTON_LEFT { select(action, event) }
        // Shift keeps the buttons for the window's own selection.
        guard !event.modifierFlags.contains(.shift) else { return }
        report(action, button, event.modifierFlags)
    }

    private func moved(_ event: NSEvent) {
        let at = convert(event.locationInWindow, from: nil)
        pointerAt = at
        refreshLink(event.modifierFlags, at: cell(at: at))
        // A drag with Shift is the window's, and a Cmd+click's drag the link's; plain motion with Shift still goes.
        if selecting, event.modifierFlags.contains(.shift), buttons.contains(GHOSTTY_MOUSE_BUTTON_LEFT.rawValue) {
            let px = pixels(at)
            selectionGesture.dragged(gridCell(at), x: px.x, y: px.y, cols: grid.cols, cellWidth: font.cell.width,
                              height: bounds.height * font.scale)
            resume()
        }
        guard linkPress == nil, !(event.modifierFlags.contains(.shift) && !buttons.isEmpty) else { return }
        // The first button held, in Ghostty's order: left, right, middle.
        report(GHOSTTY_MOUSE_ACTION_MOTION, buttons.min().map { GhosttyMouseButton(rawValue: $0) }, event.modifierFlags)
    }

    /// A Shift+left press starts a selection gesture and a plain one drops the selection; the gesture's release ends
    /// it, with or without Shift, and copies under `copy-on-select`. The pointer counts clamped to the grid, as
    /// Ghostty's `posToViewport`.
    private func select(_ action: GhosttyMouseAction, _ event: NSEvent) {
        let at = convert(event.locationInWindow, from: nil), px = pixels(at)
        defer { resume() }
        if action == GHOSTTY_MOUSE_ACTION_PRESS {
            selecting = event.modifierFlags.contains(.shift)
            guard selecting else { return selectionGesture.clear() }
            selectionGesture.pressed(gridCell(at), x: px.x, y: px.y, nanos: UInt64(max(event.timestamp, 0) * 1e9),
                              interval: UInt64(NSEvent.doubleClickInterval * 1e9), distance: Double(font.cell.width))
        } else if selecting {
            selecting = false
            selectionGesture.released(gridCell(at))
            if copyOnSelect { copySelection() }
        }
    }

    /// The cell under a point of the view, clamped to the grid.
    private func gridCell(_ p: NSPoint) -> SIMD2<Int> {
        let grid = grid, at = pixels(p)
        return SIMD2(min(max(Int(at.x) / font.cell.width, 0), grid.cols - 1),
                     min(max(Int(at.y) / font.cell.height, 0), grid.rows - 1))
    }

    /// Sends the encoder's bytes for one event at the pointer, with Ghostty's binding mods: no sides, no Caps Lock.
    private func report(_ action: GhosttyMouseAction, _ button: GhosttyMouseButton?, _ flags: NSEvent.ModifierFlags) {
        let scale = font.scale, at = pixels(pointerAt)
        let bytes = mouse.encode(host, action: action, button: button,
                                 mods: ghosttyMods(flags.intersection([.shift, .control, .option, .command])),
                                 x: at.x, y: at.y, surface: (bounds.width * scale, bounds.height * scale),
                                 cell: font.cell, anyPressed: !buttons.isEmpty)
        guard !bytes.isEmpty else { return }
        host.send(bytes)
#if NMUX_SELFTEST
        observer?.mouse(mouseActionName(action), button.map(mouseButtonName) ?? "none", cell(at: pointerAt) ?? .zero,
                        bytes)
#endif
    }

    /// Cmd alone, as Ghostty's `linkAtPos` asks; Shift too while the terminal tracks the mouse, which never gets it.
    private func linkMods(_ flags: NSEvent.ModifierFlags) -> Bool {
        let mods = flags.intersection([.shift, .control, .option, .command])
        guard mods == [.command, .shift] else { return mods == .command }
        return host.locked { t in
            var tracking = false
            ghostty_terminal_get(t, GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING, &tracking)
            return tracking
        }
    }

    private func refreshLink(_ flags: NSEvent.ModifierFlags, at cell: SIMD2<Int>?) {
        showHoveredLink(linkMods(flags) ? cell.flatMap { hyperlink(at: $0)?.cells } : nil)
    }

    private func showHoveredLink(_ link: LinkCells?) {
        guard link != cells.hoveredLink else { return }
        cells.hoveredLink = link
        resume()
        pointerChanged()
    }

    /// Only while the pointer is over this window, not over another app's in front of it.
    private func pointerChanged() {
        guard let window, bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)),
              NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber
        else { return }
        pointer.set()
    }

    /// A point of the view in pixels from its top left, as the encoder and the grid count.
    private func pixels(_ p: NSPoint) -> (x: Double, y: Double) {
        (p.x * font.scale, (bounds.height - p.y) * font.scale)
    }

    /// The cell under a point of the view, none outside it.
    private func cell(at p: NSPoint) -> SIMD2<Int>? { bounds.contains(p) ? gridCell(p) : nil }

    /// Opens a link's target; under the self-test the observer takes it instead.
    private func open(_ url: URL) {
#if NMUX_SELFTEST
        if let observer { return observer.opened(url) }
#endif
        NSWorkspace.shared.open(url)
    }

    /// The link at a cell: its OSC 8 hyperlink, over the cells beside it that share it, else a URL in its row's text.
    /// limitation: a link ends at its row, upgrade when a wrapped URL must open whole.
    private func hyperlink(at cell: SIMD2<Int>) -> (target: String, cells: LinkCells)? {
        let cols = grid.cols
        return host.locked { t in
            func ref(_ x: Int) -> GhosttyGridRef? {
                var ref = GhosttyGridRef()
                ref.size = MemoryLayout<GhosttyGridRef>.size
                var point = GhosttyPoint()
                point.tag = GHOSTTY_POINT_TAG_VIEWPORT
                point.value.coordinate = GhosttyPointCoordinate(x: UInt16(x), y: UInt32(cell.y))
                return ghostty_terminal_grid_ref(t, point, &ref) == GHOSTTY_SUCCESS ? ref : nil
            }
            func uri(_ x: Int) -> String? {
                guard var ref = ref(x) else { return nil }
                var n = 0
                guard ghostty_grid_ref_hyperlink_uri(&ref, nil, 0, &n) == GHOSTTY_OUT_OF_SPACE, n > 0
                else { return nil }
                var buf = [UInt8](repeating: 0, count: n)
                guard ghostty_grid_ref_hyperlink_uri(&ref, &buf, n, &n) == GHOSTTY_SUCCESS else { return nil }
                return String(decoding: buf[..<n], as: UTF8.self)
            }
            // A cell's text: its cluster, a space when empty, nothing for the tail of a wide one.
            func text(_ x: Int) -> String {
                guard var ref = ref(x) else { return " " }
                var raw: GhosttyCell = 0, wide = GHOSTTY_CELL_WIDE_NARROW
                ghostty_grid_ref_cell(&ref, &raw)
                ghostty_cell_get(raw, GHOSTTY_CELL_DATA_WIDE, &wide)
                if wide == GHOSTTY_CELL_WIDE_SPACER_TAIL { return "" }
                var cps = [UInt32](repeating: 0, count: 16), n = 0
                guard ghostty_grid_ref_graphemes(&ref, &cps, cps.count, &n) == GHOSTTY_SUCCESS, n > 0
                else { return " " }
                return String(String.UnicodeScalarView(cps[..<n].compactMap(Unicode.Scalar.init)))
            }
            if let target = uri(cell.x) {
                var (start, end) = (cell.x, cell.x + 1)
                while start > 0, uri(start - 1) == target { start -= 1 }
                while end < cols, uri(end) == target { end += 1 }
                return (target, LinkCells(row: cell.y, cols: start..<end))
            }
            let row = (0..<cols).map(text)
            return urlCells(row, at: cell.x).map { (row[$0].joined(), LinkCells(row: cell.y, cols: $0)) }
        }
    }
}
