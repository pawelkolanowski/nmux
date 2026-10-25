import AppKit
import Terminal

/// The app's lifecycle, the one Session's terminal and the action dispatch. The colours and the font live in the
/// appearance, and the prompts in `AppDelegate+Prompts.swift`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    /// The window's content view, which holds the terminal and the card.
    var content: NSView?
    /// The Session's terminal.
    var terminal: TerminalView?
    let appearance = Appearance()
#if NMUX_SELFTEST
    var vtSelfTest: VTSelfTest?
#endif
    var card: CardView?
    /// The font the terminal draws with, at the window's backing scale, and the one of each scale the window has had.
    var font: Font?
    var fonts: [Double: Font] = [:]
    /// The GPU state the terminal draws with, made from the shader library `make` puts in the app's Resources.
    var renderContext: RenderContext?
    var metallib = Bundle.main.url(forResource: "nmux", withExtension: "metallib")
    /// The brew the card's Install runs, and the output of its run.
    var brew: Brew?
    var brewOutput = Data()
    var brewPID: pid_t?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let (window, frame) = makeWindow()
        self.window = window
        content = window.contentView
        appearance.host = self
        // The colours and the font go in before the window shows, so its first frame never flashes another background.
        appearance.loadTheme()
        appearance.apply()
        let font = appearance.makeFont(scale: window.backingScaleFactor)
        (self.font, fonts) = (font, [font.scale: font])
        // The frame goes in before the window shows, so it never appears at another size first.
        window.setFrame(frame, display: false)
        window.makeKeyAndOrderFront(nil)
        // With Stage Manager on, the first order front may come out narrower.
        window.setFrame(frame, display: true)
        selfTestLog("visible \(rectLog(frame))")
        appearance.follow(window)
        attach(window)
    }

    /// The attach runs at the window snapped to whole cells of the font, so tmux never reflows the panes at launch. The
    /// lookup may wait 2 s on the login shell, so it and the Session run off the main thread.
    func attach(_ window: NSWindow) {
        guard let font, let content else { return }
        snap(window, font: font)
        let grid = font.grid(in: content.bounds.size)
        logFit(font, grid: grid)
#if NMUX_SELFTEST
        // A Latin letter, an ideograph SF Mono lacks, and a codepoint only LastResort has.
        for cp: UInt32 in [0x41, 0x4E2D, 0x10FFFD] {
            selfTestLog("face \(String(format: "U+%04X", cp)) "
                        + "\(font.face(for: cp).map { $0.sprite ? "sprite" : family($0.font) } ?? "none")")
        }
#endif
        DispatchQueue.global().async {
            do throws(AttachFailure) {
                let (tmux, version) = try Tmux.lookUp()
                selfTestLog("tmux \(tmux.path) \(version)")
                let id = try tmux.session(grid)
                onMain { self.start(tmux, session: id, grid: grid) }
            } catch {
                self.attachFailed(error)
            }
        }
    }

    func logFit(_ font: Font, grid: Grid) {
        guard let window, let content else { return }
        let cell = font.cell, size = content.bounds.size
        selfTestLog("cell \(cell.width)x\(cell.height) baseline \(cell.baseline) scale \(logNumber(font.scale))")
        selfTestLog("grid \(grid.cols)x\(grid.rows) content \(logNumber(size.width))x\(logNumber(size.height))")
        selfTestLog("window \(rectLog(window.frame))")
    }

    /// A backing scale the font was not made for: the terminal takes the font of that scale, the same one each time.
    func rescale(_ scale: Double) {
        guard let current = font, scale != current.scale else { return }
        let next = fonts[scale] ?? Font(current.primary, points: current.points, scale: scale, thicken: current.thicken)
        (font, fonts[scale]) = (next, next)
        terminal?.setFont(next)
    }

    func sharedContext() throws(RendererError) -> RenderContext {
        if let renderContext { return renderContext }
        guard let metallib else { throw .setup("nmux.metallib") }
        let context = try RenderContext(metallib: metallib)
        renderContext = context
        return context
    }

    /// nmux's own quit.
    func quit() { NSApp.terminate(nil) }

    @objc func menuPicked(_ item: NSMenuItem) {
        if let action = item.representedObject as? AppAction { perform(action) }
    }

    /// An app shortcut, from the menu.
    func perform(_ action: AppAction) {
        selfTestLog("shortcut \(action.name)")
        switch action {
        case .quit: quit()
        }
    }

    /// A quit during the install ends brew and whatever it started.
    func applicationWillTerminate(_ notification: Notification) {
        if let brewPID { kill(-brewPID, SIGTERM) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

extension AppDelegate {
    /// tmux 3.7c sends styled underlines and their colour only to a terminal whose XTVERSION it knows, and it knows
    /// neither libghostty nor Ghostty; WezTerm's set is the narrowest with them. Only the tmux client sees the reply,
    /// since tmux answers its panes' XTVERSION itself.
    static let xtversion =
        "WezTerm (nmux \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))"

    /// The Session's terminal, on a plain tmux client attached to it, at the window's grid. The client declares
    /// overline, which xterm-256color's terminfo lacks, or tmux drops SGR 53 before nmux sees it. The terminal goes
    /// under the card. The client ends with 0 on detach or when its Session dies, and nmux with
    /// it; any other end shows the client card with the client's last line.
    func start(_ tmux: Tmux, session id: SessionID, grid: Grid) {
        guard let font, let content else { return }
        let view: TerminalView
        do {
            view = try TerminalView(argv: [tmux.path] + tmux.base
                                        + ["-T", "overline", "attach-session", "-t", "\(id)"],
                                    grid: grid, context: sharedContext(), font: font,
                                    xtversion: Self.xtversion)
        } catch {
            return attachFailed(.client("\(error)"))
        }
        view.onExit = { [weak self] status, output in
            guard let self else { return }
            guard status != 0 else { return self.quit() }
            self.terminal?.removeFromSuperview()
            self.terminal = nil
            self.attachFailed(.client(lastLines(output, 1)))
        }
        appearance.dress(view)
        view.onScale = { [weak self] in self?.rescale($0) }
        view.onSnap = { [weak self, weak view] in
            if let self, let window = self.window, let view { snap(window, font: view.font) }
        }
#if NMUX_SELFTEST
        vtSelfTest = VTSelfTest(view, rescale: { self.rescale($0) }, appearance: { dark in
            self.appearance.loadTheme(dark: dark)
            self.appearance.apply()
        })
#endif
        view.frame = content.bounds
        view.autoresizingMask = [.width, .height]
        content.addSubview(view, positioned: .below, relativeTo: card)
        window?.makeFirstResponder(view)
        terminal = view
        view.host.start()
        selfTestLog("attached \(id)")
    }
}

extension AppDelegate: AppearanceHost {
    var terminals: [TerminalView] { terminal.map { [$0] } ?? [] }
}
