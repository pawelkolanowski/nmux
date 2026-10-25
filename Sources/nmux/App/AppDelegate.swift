import AppKit
import Terminal

/// The app's lifecycle and the action dispatch. The Sessions live in the mirror, the colours and the font
/// in the appearance, and the prompts in `AppDelegate+Prompts.swift`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    /// The window's content view, which holds the terminals and the card.
    var content: NSView?
    let mirror = SessionMirror()
    let appearance = Appearance()
#if NMUX_SELFTEST
    var vtSelfTest: VTSelfTest?
#endif
    var card: CardView?
    /// The font every terminal draws with, at the window's backing scale, and the one of each scale the window has had.
    var font: Font?
    var fonts: [Double: Font] = [:]
    /// The GPU state every terminal shares, made with the first from the shader library `make` puts in the app's
    /// Resources.
    var renderContext: RenderContext?
    var metallib = Bundle.main.url(forResource: "nmux", withExtension: "metallib")
    /// The grid the window held when nmux attached.
    var launchGrid = Grid(cols: 80, rows: 24)
    /// The Dock icon bounced for a bell, and nmux has not been active since.
    var bouncedSinceActive = false
    /// The brew the card's Install runs, and the output of its run.
    var brew: Brew?
    var brewOutput = Data()
    var brewPID: pid_t?
    /// The answer a clipboard card waits for.
    var clipboardAnswer: ((Bool) -> Void)?

    var sessions: [Session] { mirror.sessions }
    var terminal: TerminalView? { mirror.activeSession?.view }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let (window, frame) = makeWindow()
        self.window = window
        content = window.contentView
        mirror.delegate = self
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
                // The mouse and OSC 52 work with any tmux config.
                let options = tmux.run(["set", "-g", "mouse", "on", ";", "set", "-g", "set-clipboard", "on"])
                if options.status != 0 {
                    selfTestLog("options \(options.err.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                onMain {
                    self.launchGrid = grid
                    self.mirror.start(tmux, session: id)
                }
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

    /// A backing scale the font was not made for: every terminal takes the font of that scale, the same one each time.
    func rescale(_ scale: Double) {
        guard let current = font, scale != current.scale else { return }
        let next = fonts[scale] ?? Font(current.primary, points: current.points, scale: scale, thicken: current.thicken)
        (font, fonts[scale]) = (next, next)
        for session in sessions { session.view.setFont(next) }
    }

    func sharedContext() throws(RendererError) -> RenderContext {
        if let renderContext { return renderContext }
        guard let metallib else { throw .setup("nmux.metallib") }
        let context = try RenderContext(metallib: metallib)
        renderContext = context
        return context
    }

    /// Shows the Session and hides the one it leaves, in one turn of the run loop, so no blank frame shows between
    /// them.
    func show(_ id: SessionID) {
        guard let session = mirror.session(id) else { return }
        let left = mirror.activeSession
        mirror.activate(id)
        if session.bellMark {
            session.bellMark = false
            selfTestLog("bell \(id) none")
        }
        // limitation: a hidden Session keeps the last frame it presented, about 17 MB at 2x on a full screen, while one
        // never shown costs about 2 MB; free that frame once many visited Sessions weigh on the Mac.
        if left !== session {
            left?.view.isHidden = true
            session.view.isHidden = false
#if NMUX_SELFTEST
            vtSelfTest?.follow(session.view)
#endif
        }
        // An open card keeps the focus.
        if card == nil { window?.makeFirstResponder(session.view) }
        // The title names the Session for Mission Control, the Window menu and the Dock's menu; tmux's titles never
        // reach it.
        window?.title = "nmux: \(session.info.name)"
        selfTestLog("mirror " + sessions.map { "\($0.info.id):\($0.info.name)" }.joined(separator: " ")
                    + " active \(id)")
        selfTestLog("title \(window?.title ?? "")")
    }

    /// A BEL in a Session: one that is not shown takes the Bell mark, and while nmux is behind another app the Dock
    /// icon bounces once, until nmux was active again. nmux plays no sound and flashes nothing.
    func rang(_ session: Session) {
        let rule = bell(active: session === mirror.activeSession, front: NSApp.isActive,
                        bouncedSinceActive: bouncedSinceActive)
        if rule.mark { session.bellMark = true }
        selfTestLog("bell \(session.info.id) \(session.bellMark ? "mark" : "none")")
        if rule.attention {
            bouncedSinceActive = true
            NSApp.requestUserAttention(.informationalRequest)
            selfTestLog("attention")
        }
    }

    /// nmux in front again: the next bell behind another app bounces the Dock icon again.
    func applicationDidBecomeActive(_ notification: Notification) { bouncedSinceActive = false }

    /// The Session shortcuts: the Session a move lands on from the shown one is shown.
    func move(_ move: SessionMove) {
        guard let active = mirror.active, let i = sessions.firstIndex(where: { $0.info.id == active }) else { return }
        show(sessions[sessionIndex(move, active: i, count: sessions.count)].info.id)
    }

    /// nmux's own quit.
    func quit() { NSApp.terminate(nil) }

    @objc func menuPicked(_ item: NSMenuItem) {
        if let action = item.representedObject as? AppAction { perform(action) }
    }

    /// An app shortcut, from the menu or the view.
    func perform(_ action: AppAction) {
        selfTestLog("shortcut \(action.name)")
        // A card's keys wait for it, and the menu's Paste and Clear reach the terminal past its focus.
        if card != nil, [.paste, .clear].contains(action) { return }
        switch action {
        case .quit: quit()
        case .clear: clear()
        case .copy: terminal?.copySelection()
        case .paste: paste()
        case .selectAll: terminal?.selectAll()
        case .session(let n): move(.number(n))
        case .lastSession: move(.last)
        case .previousSession: move(.previous)
        case .nextSession: move(.next)
        }
    }

    /// Pastes into the active pane, after tmux says whether it turned bracketed paste on; a card that showed meanwhile
    /// keeps the keys, and the paste with them. The paste lands in the Session shown at Cmd+V, whose flag tmux gave.
    func paste() {
        guard let tmux = mirror.tmux, let session = mirror.active else { return }
        DispatchQueue.global().async {
            let flag = tmux.run(["display-message", "-p", "-t", "\(session)", "#{bracket_paste_flag}"]).out
            onMain {
                guard self.card == nil else { return }
                self.mirror.session(session)?.view.paste(paneBracketed: flag.hasPrefix("1"))
            }
        }
    }

    /// Clears the active pane's scrollback over the control client, in order with tmux's events, then Ctrl+L has the
    /// shell redraw its prompt on a clean screen.
    func clear() {
        guard let control = mirror.control, let session = mirror.active, let host = terminal?.host else { return }
        control.send("clear-history -t '\(session)'") { _, _ in host.send([0x0C]) }
    }

    /// A quit during the install ends brew and whatever it started; the control client goes with nmux.
    func applicationWillTerminate(_ notification: Notification) {
        if let brewPID { kill(-brewPID, SIGTERM) }
        mirror.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

extension AppDelegate: SessionMirrorDelegate {
    /// tmux 3.7c sends styled underlines and their colour only to a terminal whose XTVERSION it knows, and it knows
    /// neither libghostty nor Ghostty; WezTerm's set is the narrowest with them. Only the tmux client sees the reply,
    /// since tmux answers its panes' XTVERSION itself.
    static let xtversion =
        "WezTerm (nmux \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))"

    /// A Session's terminal, on a plain tmux client attached to it from the start, at the window's grid. The client
    /// declares overline and hyperlinks, which xterm-256color's terminfo lacks, or tmux drops SGR 53 and OSC 8 before
    /// nmux sees them. The terminal goes hidden under the card until the Session is shown.
    func makeSession(_ info: SessionInfo) -> Session? {
        guard let tmux = mirror.tmux, let font, let content else { return nil }
        let view: TerminalView
        do {
            view = try TerminalView(argv: [tmux.path] + tmux.base
                                        + ["-T", "overline,hyperlinks", "attach-session", "-t", "\(info.id)"],
                                    grid: terminal?.grid ?? launchGrid, context: sharedContext(), font: font,
                                    xtversion: Self.xtversion)
        } catch {
            attachFailed(.client("\(error)"))
            return nil
        }
        let session = Session(info, view)
        // A client that ended: the next list decides whether it attaches again or waits.
        view.onExit = { [weak self] _, _ in self?.mirror.relist() }
        view.onKeyDown = { [weak self, weak session] in
            guard let self, let session, session.waiting else { return false }
            self.mirror.attachAgain(session)
            return true
        }
        appearance.dress(view)
        view.askClipboard = { self.ask($0, $1) }
        view.onScale = { [weak self] in self?.rescale($0) }
        view.onSnap = { [weak self, weak view] in
            if let self, let window = self.window, let view { snap(window, font: view.font) }
        }
        view.shortcut = { event in
            guard let s = shortcut(event.characters(byApplyingModifiers: []), event.modifierFlags) else { return false }
            self.perform(s.action)
            return true
        }
        view.onBell = { [weak session] in if let session { self.rang(session) } }
#if NMUX_SELFTEST
        if let vtSelfTest { vtSelfTest.add(view) } else {
            vtSelfTest = VTSelfTest(view, create: { self.mirror.create($0) }, perform: { self.perform($0) },
                                     rescale: { self.rescale($0) }, appearance: { dark in
                                         self.appearance.loadTheme(dark: dark)
                                         self.appearance.apply()
                                     })
        }
#endif
        view.isHidden = true
        view.frame = content.bounds
        view.autoresizingMask = [.width, .height]
        content.addSubview(view, positioned: .below, relativeTo: card)
        view.host.start()
        selfTestLog("attached \(info.id)")
        return session
    }
}

extension AppDelegate: AppearanceHost {
    var terminals: [TerminalView] { sessions.map(\.view) }
}
