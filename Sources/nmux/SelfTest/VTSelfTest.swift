#if NMUX_SELFTEST
import AppKit
import Terminal

/// The self-test's view of the VT host and the drawing: it watches the terminal's view as its observer and logs what
/// it sees. Tests/seam/lib.sh describes every line it logs.
final class VTSelfTest: TerminalViewObserver {
    private let view: TerminalView
    /// Hands the terminal the font of that backing scale, as a move to another screen does.
    private let rescale: (Double) -> Void
    /// Resolves the theme for that appearance, nil for the window's own, and applies it, as a switch of the system's
    /// does.
    private let appearance: (Bool?) -> Void
    private var parsed = 0, outputs = 0, probed = false, watchingHold = false
    private var drawnFrames = 0, readBack = false
    private var lastFrame = CACurrentMediaTime(), longestGap = 0.0
    private let named: [(x: Int, y: Int)]
    private let usr1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    private let usr2 = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
    private var steps = 0

    init(_ view: TerminalView, rescale: @escaping (Double) -> Void, appearance: @escaping (Bool?) -> Void) {
        (self.view, self.rescale, self.appearance) = (view, rescale, appearance)
        named = (SelfTest.cells ?? "").split(separator: " ").compactMap { pair in
            let xy = pair.split(separator: ",").compactMap { Int($0) }
            return xy.count == 2 ? (xy[0], xy[1]) : nil
        }
        signal(SIGUSR1, SIG_IGN)
        usr1.setEventHandler { MainActor.assumeIsolated { self.framesAsked() } }
        usr1.resume()
        signal(SIGUSR2, SIG_IGN)
        usr2.setEventHandler { MainActor.assumeIsolated { self.resizeStep() } }
        usr2.resume()
        add(view)
    }

    /// Watches the view, before it gets its first drawable.
    private func add(_ view: TerminalView) {
        view.observer = self
        view.keepFramesReadable()
        view.stepWhileHidden()
        // The window never becomes key under the self-test, so the cursor would stay hollow; the view is in its
        // window by the next turn.
        onMain { view.setFocused(true) }
    }

    func resized(_ view: TerminalView, grid: Grid) { selfTestLog("resize \(grid.cols)x\(grid.rows)") }

    func scaled(_ scale: Double, cell: Cell) {
        selfTestLog("scale \(logNumber(scale)) cell \(cell.width)x\(cell.height)")
    }
    func lateFrame() { selfTestLog("late frame") }
    func holdStarted() { watchHold() }

    private func resizeStep() {
        guard let window = view.window else { return }
        steps += 1
        let grid = view.grid, font = view.font
        switch steps {
        case 1: window.setContentSize(font.contentSize(Grid(cols: grid.cols - 3, rows: grid.rows - 2)))
        case 2:
            var size = font.contentSize(grid)
            size.width += CGFloat(font.cell.width) / font.scale / 2
            window.setContentSize(size)
        case 3: rescale(1)
        case 4: rescale(2)
        default: return
        }
        readBack = false
        onMain(after: 0.5) {
            let size = self.view.bounds.size, grid = self.view.grid, cell = self.view.font.cell
            selfTestLog("content \(logNumber(size.width))x\(logNumber(size.height)) grid \(grid.cols)x\(grid.rows) "
                        + "cell \(cell.width)x\(cell.height) scale \(logNumber(self.view.font.scale))")
        }
    }

    /// The gap counts from the request on, so a quiet spell before it is not one.
    private func framesAsked() {
        selfTestLog("frame gap \(Int((max(longestGap, CACurrentMediaTime() - lastFrame) * 1000).rounded()))")
        selfTestLog("frames \(view.frames)")
        (lastFrame, longestGap) = (CACurrentMediaTime(), 0)
    }

    func framed() {
        let now = CACurrentMediaTime()
        (longestGap, lastFrame) = (max(longestGap, now - lastFrame), now)
        drawnFrames += 1
        let mark = drawnFrames
        onMain(after: 0.4) {
            guard mark == self.drawnFrames else { return }
            for (x, y) in self.named {
                if let cell = self.view.describeCell(x, y) { selfTestLog("cell \(x),\(y) \(cell)") }
            }
            selfTestLog("cursor \(self.view.describeCursor())")
            guard !self.readBack, let ink = self.named.first, self.view.hasGlyph(ink.x, ink.y) else { return }
            self.readBack = true
            self.view.readBack(ink: ink.x, ink.y) { selfTestLog("readback \($0)") }
        }
    }

    func output(_ bytes: Int) {
        parsed += bytes
        outputs += 1
        let mark = outputs
        onMain(after: 0.4) {
            guard mark == self.outputs else { return }
            selfTestLog("vt \(self.parsed) bytes parsed")
            if let path = SelfTest.screen {
                try? Data(self.view.host.screenText().utf8).write(to: URL(fileURLWithPath: path))
            }
            if !self.probed { self.probe() }
            self.probed = true
        }
    }

    /// The replies to primary device attributes and a cursor position report, the default background under a
    /// dark, a light and the window's own appearance, through the app's apply, then a hold no one ends.
    private func probe() {
        for query in ["\u{1b}[c", "\u{1b}[6n"] {
            selfTestLog("reply \(hex(view.host.probe(Array(query.utf8))))")
        }
        for (name, dark) in [("dark", true), ("light", false)] {
            appearance(dark)
            selfTestLog("background \(name) \(view.host.defaultBackground())")
        }
        appearance(nil)
        selfTestLog("background system \(view.host.defaultBackground())")
        selfTestLog("probe hold")
        _ = view.host.probe(Array("\u{1b}[?2026h".utf8))
    }

    private func watchHold() {
        guard !watchingHold else { return }
        watchingHold = true
        func poll() {
            guard view.host.isHolding else {
                watchingHold = false
                return selfTestLog("hold released")
            }
            onMain(after: 0.1) { poll() }
        }
        poll()
    }
}
#endif
