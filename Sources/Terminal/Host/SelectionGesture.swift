import GhosttyVt

// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// libghostty-vt's selection gesture and its press, drag and release events, reused for every Shift+left gesture,
/// adapted from Ghostty's `example/c-vt-selection-gesture` and `mouseButtonCallback` in `src/Surface.zig` at commit
/// 22f100c6. Each call hands the gesture one event at a viewport cell and makes the selection it returns the
/// terminal's, which keeps it on its rows as output scrolls them.
final class SelectionGesture {
    private let host: VTHost
    private var gesture: GhosttySelectionGesture?
    private var press: GhosttySelectionGestureEvent?
    private var drag: GhosttySelectionGestureEvent?
    private var release: GhosttySelectionGestureEvent?

    init(_ host: VTHost) {
        self.host = host
        ghostty_selection_gesture_new(nil, &gesture)
        ghostty_selection_gesture_event_new(nil, &press, GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_PRESS)
        ghostty_selection_gesture_event_new(nil, &drag, GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DRAG)
        ghostty_selection_gesture_event_new(nil, &release, GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_RELEASE)
    }

    deinit {
        [press, drag, release].forEach(ghostty_selection_gesture_event_free)
        host.locked { ghostty_selection_gesture_free(gesture, $0) }
    }

    /// A press `at` `x`, `y` pixels from the surface's top left. Clicks within `interval` and one cell's width of the
    /// last count up to a word and a line; a single click clears the selection.
    func pressed(_ cell: SIMD2<Int>, x: Double, y: Double, nanos: UInt64, interval: UInt64, distance: Double) {
        var at = GhosttySurfacePosition(x: x, y: y), time = nanos, repeatInterval = interval, repeatDistance = distance
        ghostty_selection_gesture_event_set(press, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION, &at)
        ghostty_selection_gesture_event_set(press, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_TIME_NS, &time)
        ghostty_selection_gesture_event_set(press, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_INTERVAL_NS,
                                            &repeatInterval)
        ghostty_selection_gesture_event_set(press, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_DISTANCE, &repeatDistance)
        apply(press, cell, clearsOnNone: true)
    }

    /// A drag to a cell; the geometry tells the gesture which side of a cell the pointer is on.
    func dragged(_ cell: SIMD2<Int>, x: Double, y: Double, cols: Int, cellWidth: Int, height: Double) {
        var at = GhosttySurfacePosition(x: x, y: y)
        var geometry = GhosttySelectionGestureGeometry(columns: UInt32(cols), cell_width: UInt32(cellWidth),
                                                       padding_left: 0, screen_height: UInt32(max(height, 1)))
        ghostty_selection_gesture_event_set(drag, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION, &at)
        ghostty_selection_gesture_event_set(drag, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_GEOMETRY, &geometry)
        apply(drag, cell, clearsOnNone: false)
    }

    /// The release ends the gesture and selects nothing itself.
    func released(_ cell: SIMD2<Int>) { apply(release, cell, clearsOnNone: false) }

    /// Whether the terminal holds a selection.
    var hasSelection: Bool {
        host.locked { t in
            var sel = emptySelection()
            return ghostty_terminal_get(t, GHOSTTY_TERMINAL_DATA_SELECTION, &sel) == GHOSTTY_SUCCESS
        }
    }

    /// Selects every cell of the viewport.
    func selectAll() {
        host.locked { t in
            var sel = emptySelection()
            guard ghostty_terminal_select_all(t, &sel) == GHOSTTY_SUCCESS else { return }
            ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_SELECTION, &sel)
        }
    }

    /// Only a selection that stands is cleared, so a plain click on a screen with none redraws nothing.
    func clear() {
        guard hasSelection else { return }
        host.locked { _ = ghostty_terminal_set($0, GHOSTTY_TERMINAL_OPT_SELECTION, nil) }
    }

    /// The selection's plain text, soft wraps joined and trailing blanks trimmed; nil with no selection.
    func text() -> String? {
        host.locked { t in
            var options = GhosttyTerminalSelectionFormatOptions()
            options.size = MemoryLayout<GhosttyTerminalSelectionFormatOptions>.size
            (options.emit, options.unwrap, options.trim) = (GHOSTTY_FORMATTER_FORMAT_PLAIN, true, true)
            var out: UnsafeMutablePointer<UInt8>?, len = 0
            guard ghostty_terminal_selection_format_alloc(t, nil, options, &out, &len) == GHOSTTY_SUCCESS
            else { return nil }
            defer { ghostty_free(nil, out, len) }
            return out.map { String(decoding: UnsafeBufferPointer(start: $0, count: len), as: UTF8.self) } ?? ""
        }
    }

    /// The first and last cell of the viewport the terminal's selection holds, read from the terminal itself.
    func span(_ grid: Grid) -> (first: SIMD2<Int>, last: SIMD2<Int>)? {
        host.locked { t in
            var sel = emptySelection()
            guard ghostty_terminal_get(t, GHOSTTY_TERMINAL_DATA_SELECTION, &sel) == GHOSTTY_SUCCESS else { return nil }
            func held(_ i: Int) -> Bool {
                var point = GhosttyPoint(), contains = false
                point.tag = GHOSTTY_POINT_TAG_VIEWPORT
                point.value.coordinate = GhosttyPointCoordinate(x: UInt16(i % grid.cols), y: UInt32(i / grid.cols))
                return ghostty_terminal_selection_contains(t, &sel, point, &contains) == GHOSTTY_SUCCESS && contains
            }
            let cells = 0..<grid.cols * grid.rows
            guard let first = cells.first(where: held), let last = cells.last(where: held) else { return nil }
            return (SIMD2(first % grid.cols, first / grid.cols), SIMD2(last % grid.cols, last / grid.cols))
        }
    }

    private func apply(_ event: GhosttySelectionGestureEvent?, _ cell: SIMD2<Int>, clearsOnNone: Bool) {
        host.locked { t in
            var ref = GhosttyGridRef()
            ref.size = MemoryLayout<GhosttyGridRef>.size
            var point = GhosttyPoint()
            point.tag = GHOSTTY_POINT_TAG_VIEWPORT
            point.value.coordinate = GhosttyPointCoordinate(x: UInt16(cell.x), y: UInt32(cell.y))
            guard ghostty_terminal_grid_ref(t, point, &ref) == GHOSTTY_SUCCESS else { return }
            ghostty_selection_gesture_event_set(event, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &ref)
            var sel = emptySelection()
            switch ghostty_selection_gesture_event(gesture, t, event, &sel) {
            case GHOSTTY_SUCCESS: ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_SELECTION, &sel)
            // Only a single click clears, as Ghostty's: a double or triple one that finds nothing keeps what was there.
            case GHOSTTY_NO_VALUE where clearsOnNone:
                var clicks: UInt8 = 0
                ghostty_selection_gesture_get(gesture, t, GHOSTTY_SELECTION_GESTURE_DATA_CLICK_COUNT, &clicks)
                if clicks == 1 { ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_SELECTION, nil) }
            default: break
            }
        }
    }
}

private func emptySelection() -> GhosttySelection {
    var sel = GhosttySelection()
    sel.size = MemoryLayout<GhosttySelection>.size
    return sel
}
