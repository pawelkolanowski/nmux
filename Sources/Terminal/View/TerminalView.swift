import AppKit

/// The view the terminal's state is drawn into, through nmux's Metal 4 renderer. It owns the VT host, takes its colours
/// and face from the app, and paces the frames: the display link runs while something changes and pauses when a frame
/// finds nothing to draw, so a quiet prompt draws no frames.
@MainActor
public final class TerminalView: NSView {
    public let host: VTHost
#if NMUX_SELFTEST
    public weak var observer: TerminalViewObserver?
#endif
    /// A backing scale the font was not made for: the app hands every view the font of that scale through `setFont`.
    public var onScale: (Double) -> Void = { _ in }
    /// A size that is not whole cells of the font: the app snaps the window to whole cells, and the view then fits the
    /// pty to what the snap left.
    public var onSnap: () -> Void = {}
    /// On the main thread once the client exited: its wait status and its last 4 KB of output.
    public var onExit: (Int32, String) -> Void = { _, _ in }
    /// A new scale replaces them, with a new font and an empty atlas.
    private(set) var cells: Cells
    /// The GPU state it shares with every terminal, and its own renderer.
    let context: RenderContext
    let renderer: MetalRenderer
    private(set) var link: CADisplayLink?
    private var keyObservers: [NSObjectProtocol] = []
    private let waker: Waker
    /// Wakes the paused frames once a hold no output ends has run its 1 s.
    private var holdEnd: Timer?
    /// Draws the next frame though the terminal did not change.
    var redraw = false
    /// Runs only while the terminal asks for a blinking cursor and the window is key.
    private var blink: Timer?
    /// A window snap waits for the next turn of the main loop.
    private var snapping = false
    /// The window's backing scale as last seen; only a change of it is reported, so the self-test's forced scale holds.
    private var backingScale: CGFloat?

    /// Starts `argv` as the terminal's client on a pty of `grid` cells; `font` is the one every terminal of the
    /// window's backing scale draws with. The client's output waits for `host.start()`.
    public init(argv: [String], grid: Grid, context: RenderContext, font: Font) throws {
        // The host's handlers reach the view through the relay, which the view fills before the host starts.
        let relay = Relay(), waker = Waker()
        var handlers = VTHost.Handlers(
            // Output resumes the paused frames; on the reader thread, so the hop to the main queue is coalesced.
            output: { n in
                waker.wake(n) { bytes in
                    relay.view?.resume()
#if NMUX_SELFTEST
                    relay.view?.observer?.output(bytes)
#endif
                }
            },
            exit: { status, output in relay.view?.onExit(status, output) })
#if NMUX_SELFTEST
        handlers.hold = { held in
            if held { onMain { relay.view?.observer?.holdStarted() } }
        }
#endif
        host = try VTHost(argv: argv, grid: grid, cell: font.cell, handlers: handlers)
        self.waker = waker
        cells = Cells(font: font)
        (self.context, renderer) = (context, try MetalRenderer(context))
        super.init(frame: .zero)
        layer = renderer.layer
        wantsLayer = true
        layerContentsRedrawPolicy = .never
#if NMUX_SELFTEST
        renderer.onLate = { [weak self] in self?.observer?.lateFrame() }
#endif
        relay.view = self
    }

    required init?(coder: NSCoder) { fatalError("TerminalView is never decoded") }

    /// The theme's colours: the terminal's defaults and palette under the host's lock; every row draws again.
    public func setColors(_ colors: TerminalColors) {
        host.setColors(colors)
        cells.restyled = true
        resume()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Out of its window the view draws nothing, and its link, timers and observers would keep it alive or waking.
        guard let window else {
            link?.invalidate()
            link = nil
            blink?.invalidate()
            blink = nil
            holdEnd?.invalidate()
            holdEnd = nil
            keyObservers.forEach(NotificationCenter.default.removeObserver)
            keyObservers = []
            return
        }
        guard link == nil else { return }
        renderer.layer.contentsScale = font.scale
        // The window may have changed screens since the font was measured.
        backingChanged(window)
        let link = displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
        keyObservers = [(NSWindow.didBecomeKeyNotification, true),
                        (NSWindow.didResignKeyNotification, false)].map { name, focused in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setFocused(focused) }
            }
        }
        setFocused(window.isKeyWindow)
        sized()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        sized()
    }

    public var font: Font { cells.font }

    /// The grid the view holds, in whole cells of the font.
    public var grid: Grid { font.grid(in: bounds.size) }

    /// The drawable follows the view's size in pixels and the terminal and the pty its grid. Inside a live resize the
    /// frame is drawn at once, to present with the window's transaction; otherwise the display link draws it, and a
    /// size that is not whole cells snaps the window on the next turn, once AppKit has laid out its views, and the pty
    /// takes the grid after the snap, so tmux reflows once.
    private func sized() {
        renderer.layer.drawableSize = CGSize(width: bounds.width * font.scale, height: bounds.height * font.scale)
        redraw = true
        // Out of a window the view has no size of its own yet.
        guard window != nil else { return }
        if inLiveResize {
            fitHost()
            step()
        } else {
            resume()
            if !snapLater() { fitHost() }
        }
    }

    private func fitHost() {
        let grid = grid
        guard host.resize(grid, cell: font.cell) else { return }
#if NMUX_SELFTEST
        observer?.resized(self, grid: grid)
#endif
    }

    /// Snaps the window to whole cells on the next turn, when its size is not, then fits the pty to what the snap left;
    /// false when the size is whole cells already.
    private func snapLater() -> Bool {
        guard window != nil, bounds.size != font.contentSize(grid) else { return false }
        guard !snapping else { return true }
        snapping = true
        onMain { [weak self] in
            guard let self else { return }
            self.snapping = false
            if self.window != nil { self.onSnap() }
            self.fitHost()
        }
        return true
    }

    public override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        renderer.layer.presentsWithTransaction = true
    }

    public override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        renderer.layer.presentsWithTransaction = false
        sized()
        // AppKit may still report the live resize here, so the last size is snapped by hand.
        _ = snapLater()
    }

    /// Also called for a change of colour space alone, which keeps the scale.
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window { backingChanged(window) }
    }

    private func backingChanged(_ window: NSWindow) {
        guard window.backingScaleFactor != backingScale else { return }
        backingScale = window.backingScaleFactor
        if window.backingScaleFactor != font.scale { onScale(window.backingScaleFactor) }
    }

    /// A new face, size or scale: the cell measured again and an empty atlas; the window then snaps to
    /// whole cells of the new cell, and the terminal and the pty take its grid.
    public func setFont(_ font: Font) {
        let next = Cells(font: font)
        (next.focused, next.blinkVisible) = (cells.focused, cells.blinkVisible)
        cells = next
        renderer.dropAtlas()
        renderer.layer.contentsScale = font.scale
#if NMUX_SELFTEST
        observer?.scaled(font.scale, cell: font.cell)
#endif
        sized()
    }

    /// An unfocused window draws a hollow cursor that never blinks. The self-test sets it by hand, since its window
    /// never becomes key.
    public func setFocused(_ focused: Bool) {
        cells.focused = focused
        syncBlink()
        resume()
    }

    func resume() { link?.isPaused = false }

    /// Draws when the terminal changed and pauses the frames when it did not. A mode 2026 hold keeps the cells last
    /// drawn and pauses too: output wakes the frames, and so does one timer past the hold's 1 s, by which time
    /// `holding` has ended it, so the end is drawn even when output stops.
    @objc func step() {
        if host.holding() {
            link?.isPaused = true
            if holdEnd == nil {
                holdEnd = Timer.scheduledTimer(withTimeInterval: 1.05, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.holdEnd = nil
                        self?.resume()
                    }
                }
            }
            return
        }
        guard cells.update(host) || redraw else {
            link?.isPaused = true
            return
        }
        // A frame the GPU could not encode is drawn again on the next tick.
        redraw = !renderer.draw(cells) { renderer.layer.nextDrawable() }
        syncBlink()
#if NMUX_SELFTEST
        observer?.framed()
#endif
    }

    /// Starts or stops the blink as the terminal and the focus ask; each toggle draws one frame. An unfocused window
    /// draws the hollow block, which Ghostty never blinks, so its blink would draw frames that change nothing.
    private func syncBlink() {
        let wanted = cells.cursorBlinking && cells.focused
        if wanted, blink == nil {
            let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.cells.blinkVisible.toggle()
                    self.resume()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            blink = timer
        } else if !wanted, let timer = blink {
            timer.invalidate()
            blink = nil
            cells.blinkVisible = true
        }
    }
}

/// The view the host's handlers reach: written once in the view's init and read only on the main thread.
private final class Relay: @unchecked Sendable {
    weak var view: TerminalView?
}

// Coalesces the reader thread's wakes into one hop to the main queue at a time, with the bytes parsed meanwhile.

private final class Waker: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = 0

    func wake(_ n: Int, _ body: @escaping @MainActor @Sendable (Int) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        bytes += n
        guard bytes == n else { return } // a hop is on its way
        onMain { [self] in
            lock.lock()
            let total = bytes
            bytes = 0
            lock.unlock()
            body(total)
        }
    }
}
