import AppKit
import Terminal

/// The app's lifecycle, Closing nmux and the action dispatch. The Sessions live in the mirror, the Config and the Theme
/// in the appearance, and the prompts in `AppDelegate+Prompts.swift`.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    /// The window's content view, which holds the bar, the terminals and the card.
    var content: NSView?
    var bar: SessionBar?
    let keepAwake = KeepAwake()
    let mirror = SessionMirror()
    let appearance = Appearance(.current)
#if NMUX_SELFTEST
    var vtSelfTest: VTSelfTest?
#endif
    var card: CardView?
    /// The font every terminal draws with, at the window's backing scale, and the one of each scale the window has had,
    /// all of the Config's face; a new face starts the list again.
    var font: Font?
    var fonts: [Double: Font] = [:]
    /// The GPU state every terminal shares, made with the first from the shader library `make` puts in the app's
    /// Resources.
    var renderContext: RenderContext?
    var metallib = Bundle.main.url(forResource: "nmux", withExtension: "metallib")
    /// The grid the window held when nmux attached.
    var launchGrid = Grid(cols: 80, rows: 24)
    /// The New Session field while it is open.
    var draft: Draft?
    /// The Dock icon bounced for a bell, and nmux has not been active since.
    var bouncedSinceActive = false
    /// The brew the card's Install runs, and the output of its run.
    var brew: Brew?
    var brewOutput = Data()
    var brewPID: pid_t?
    /// The answer a clipboard card waits for.
    var clipboardAnswer: ((Bool) -> Void)?
    /// nmux quits itself, so the quit never asks.
    var leaving = false

    var sessions: [Session] { mirror.sessions }
    var terminal: TerminalView? { mirror.activeSession?.view }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let (window, frame) = makeWindow()
        window.delegate = self
        self.window = window
        content = window.contentView
        let bar = SessionBar(keepAwake: keepAwake, show: { self.show($0) }, close: { self.close($0) },
                             draft: { self.drafted($0) }, answer: { self.answer($0) })
        content?.addSubview(bar)
        self.bar = bar
        mirror.delegate = self
        appearance.host = self
        // The Config and the Theme go in before the window shows, so its first frame never flashes another background.
        loadConfig("launch")
        // The frame goes in before the window shows, so it never appears at another size first.
        window.setFrame(frame, display: false)
        window.makeKeyAndOrderFront(nil)
        // With Stage Manager on, the first order front may come out narrower; this set covers the bar.
        window.setFrame(frame, display: true)
        selfTestLog("visible \(rectLog(frame))")
        // limitation: each step of a live resize rebuilds every pill; lay out the old ones instead once that stutters.
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window,
                                               queue: .main) { _ in
            MainActor.assumeIsolated {
                self.updateBar()
                // The card's lines are cut to the window's width again.
                if self.configCardShows { self.showConfigProblems() }
            }
        }
        // AppKit drops the window's blur when it changes screens.
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: window,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { self.appearance.syncWindowBackground() }
        }
        updateBar()
        appearance.follow(window)
        attach(window)
    }

    /// Reads the Config at launch and on Reload Config; skipped lines show on their card after the apply, and a load
    /// that skips none closes the card a load before left open.
    func loadConfig(_ cause: String) {
        appearance.load(cause)
        if appearance.problems == nil, configCardShows { answered(false) }
        showConfigProblems()
    }

    /// The attach runs at the window snapped to whole cells of the font, so tmux never reflows the panes at launch. The
    /// lookup may wait 2 s on the login shell, so it and the Session run off the main thread.
    func attach(_ window: NSWindow) {
        guard let font, let content else { return }
        snap(window, font: font, top: SessionBar.height)
        let grid = font.grid(in: terminalFrame(content).size)
        logFit(font, grid: grid)
#if NMUX_SELFTEST
        // A Latin letter, an ideograph SF Mono lacks, and a codepoint only LastResort has.
        for cp: UInt32 in [0x41, 0x4E2D, 0x10FFFD] {
            selfTestLog("face \(String(format: "U+%04X", cp)) "
                        + "\(font.face(for: cp).map { $0.sprite ? "sprite" : family($0.font) } ?? "none")")
        }
#endif
        // The Config in force now; a later Reload Config leaves this attach alone.
        let config = appearance.config
        DispatchQueue.global().async {
            do throws(AttachFailure) {
                let (tmux, version) = try Tmux.lookUp(config.tmuxPath)
                selfTestLog("tmux \(tmux.path) \(version)")
                let id = try tmux.session(grid)
                // Whole, to tmux's own parser, so quotes and `;` mean what they mean in `~/.tmux.conf`.
                let command = tmux.run(["source-file", "-"], input: config.tmuxCommand)
                if command.status != 0 {
                    selfTestLog("options \(command.err.trimmingCharacters(in: .whitespacesAndNewlines))")
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
        let cell = font.cell, size = terminalFrame(content).size
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
        // An open field or prompt keeps the focus, so a Session made elsewhere drops nothing typed.
        if card == nil, draft == nil, mirror.asking == nil { window?.makeFirstResponder(session.view) }
        // The title names the Session for Mission Control, the Window menu and the Dock's menu; tmux's titles never
        // reach it.
        window?.title = "nmux: \(session.info.name)"
        selfTestLog("mirror " + sessions.map { "\($0.info.id):\($0.info.name)" }.joined(separator: " ")
                    + " active \(id)")
        selfTestLog("title \(window?.title ?? "")")
        updateBar()
        showConfigProblems()
    }

    /// The one update of the Session bar, for every change of the Sessions, each window resize and each Config reload;
    /// it logs the gap between the window's top and the shown terminal.
    func updateBar() {
        guard let bar else { return }
        bar.update(sessions, active: mirror.active, draft: draft)
        if let terminal, let content {
            selfTestLog("bar \(logNumber(content.bounds.height - terminal.frame.maxY))")
        }
    }

    /// The New Session field: Cmd+T and the plus open it, its Return creates the Session, and its Escape or lost focus
    /// drops it. A field that goes hands the focus back to the shown terminal.
    func drafted(_ event: DraftEvent) {
        // The focus handed back ends the field's editing, which cancels once more.
        if event == .cancel, draft == nil { return }
        let was = draft
        draft = nextDraft(draft, event)
        if was == nil, draft != nil { selfTestLog("field open") }
        if case .answer(.refused(let error)) = event, draft != nil { selfTestLog("field refused \(error)") }
        if was != nil, draft == nil {
            selfTestLog("field closed")
            window?.makeFirstResponder(terminal)
        }
        updateBar()
        if case .submit(let name) = event, draft != nil { mirror.create(name) { self.drafted(.answer($0)) } }
    }

    /// Cmd+W on the shown Session, or a click on a pill's close mark: that pill asks whether to kill the Session, and
    /// the bar takes the keys. The Session is not shown, and a close while any prompt is open does nothing.
    func close(_ id: SessionID) {
        guard mirror.asking == nil, card == nil, let session = mirror.session(id) else { return }
        drafted(.cancel)
        session.asking = true
        selfTestLog("ask session \(id)")
        updateBar()
        window?.makeFirstResponder(bar)
    }

    /// The prompt ends before anything else happens: a kill goes on, a cancel hands the keys back to the terminal.
    func answer(_ kill: Bool) {
        guard let session = mirror.asking else { return }
        session.asking = false
        selfTestLog("answer \(kill ? "kill" : "cancel")")
        window?.makeFirstResponder(terminal)
        if kill { mirror.kill(session) } else { updateBar() }
        showConfigProblems()
    }

    /// A BEL in a Session: one that is not shown takes the Bell mark, and while nmux is behind another app the Dock
    /// icon bounces once, until nmux was active again. nmux plays no sound and flashes nothing.
    func rang(_ session: Session) {
        let rule = bell(active: session === mirror.activeSession, front: NSApp.isActive,
                        bouncedSinceActive: bouncedSinceActive)
        if rule.mark, !session.bellMark {
            session.bellMark = true
            updateBar()
        }
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

    /// Cmd+Shift+W, Cmd+Q, the close button and the Dock's Quit ask on the closing card, the box unticked, its default
    /// Close; a close while any prompt is open does nothing, one over the Config's card takes its place, and one over a
    /// card that asks nothing quits at once.
    func closeNmux() {
        guard !leaving, mirror.asking == nil else { return }
        if configCardShows {
            card?.removeFromSuperview()
            card = nil
        }
        if cardOnlyReports { return quit() }
        guard card == nil else { return }
        drafted(.cancel)
        showCard(closingCard)
        selfTestLog("ask closing")
    }

    /// The closing card's answer. Unticked, nmux quits and touches no Session; ticked, it kills every Session it
    /// mirrors in their order and quits on the last answer, or as the control client ends with a server that ended
    /// first.
    func closeAnswered(all: Bool) {
        selfTestLog("answer close" + (all ? " all" : ""))
        answered(false)
        guard all, mirror.killAll(then: { self.quit() }) else { return quit() }
        leaving = true
    }

    /// nmux's own quit, which never asks.
    func quit() {
        leaving = true
        NSApp.terminate(nil)
    }

    /// The close button opens the card instead of closing the window.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeNmux()
        return false
    }

    /// A quit asks unless nmux quits itself or macOS shuts down, restarts or logs out, read from the quit Apple event's
    /// reason as Ghostty does; the Dock's Quit opens the card and goes no further.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let reason = NSAppleEventManager.shared()
            .currentAppleEvent?.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.typeCodeValue
        guard quitAsks(own: leaving, reason: reason), !cardOnlyReports else { return .terminateNow }
        closeNmux()
        return .terminateCancel
    }

    @objc func menuPicked(_ item: NSMenuItem) {
        if let action = item.representedObject as? AppAction { perform(action) }
    }

    /// An app shortcut, from the menu or the view.
    func perform(_ action: AppAction) {
        selfTestLog("shortcut \(action.name)")
        // A pill that asks, or the closing card, takes every key, its own shortcut among them; Reload Config applies
        // under it and leaves it open.
        if mirror.asking != nil || closingCardShows, action != .reloadConfig { return }
        // A card's keys wait for it, and the menu's Paste and Clear reach the terminal past its focus, and New
        // Session's field would take the focus from it.
        if card != nil, [.paste, .clear, .newSession].contains(action) { return }
        // While New Session's field has the focus, Copy, Paste and Select All edit its name, never the terminal.
        if bar?.drafting == true, let edit = [AppAction.copy: #selector(NSText.copy(_:)),
                                               .paste: #selector(NSText.paste(_:)),
                                               .selectAll: #selector(NSText.selectAll(_:))][action] {
            NSApp.sendAction(edit, to: nil, from: nil)
            return
        }
        switch action {
        case .quit, .closeNmux: closeNmux()
        case .clear: clear()
        case .copy: terminal?.copySelection()
        case .paste: paste()
        case .selectAll: terminal?.selectAll()
        case .newSession: drafted(.open)
        case .closeSession: if let active = mirror.active { close(active) }
        case .openConfig: openConfig()
        case .reloadConfig: loadConfig("reload")
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

    /// Opens the Config in the default text editor, as Ghostty's `open -t`, created empty with its folder when it is
    /// missing. The self-test opens no editor, and touches a Config only in an XDG_CONFIG_HOME of its own.
    func openConfig() {
#if NMUX_SELFTEST
        if !appearance.location.fromXDG { return }
#endif
        let url = URL(fileURLWithPath: appearance.location.config)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
#if NMUX_SELFTEST
        selfTestLog("open-config \(url.path)")
#else
        guard let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
#endif
    }

    /// A quit during the install ends brew and whatever it started; the control client goes with nmux, and the
    /// Keep-awake cup lets the Mac sleep again.
    func applicationWillTerminate(_ notification: Notification) {
        if let brewPID { kill(-brewPID, SIGTERM) }
        if keepAwake.hold != nil {
            keepAwake.release()
            selfTestLog("cup released")
        }
        mirror.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

extension AppDelegate: SessionMirrorDelegate {
    func cancelAsking() { answer(false) }

    /// tmux sends styled underlines and their colour only to a terminal whose XTVERSION it knows; 3.8 knows Ghostty,
    /// by the prefix `ghostty `, and libghostty-vt draws what Ghostty does. Only the tmux client sees the reply, since
    /// tmux answers its panes' XTVERSION itself.
    static let xtversion =
        "ghostty (nmux \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))"

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
            if let self, let window = self.window, let view { snap(window, font: view.font, top: SessionBar.height) }
        }
        view.shortcut = { event in
            guard let s = shortcut(event.characters(byApplyingModifiers: []), event.modifierFlags) else { return false }
            self.perform(s.action)
            return true
        }
        view.onBell = { [weak session] in if let session { self.rang(session) } }
#if NMUX_SELFTEST
        if let vtSelfTest { vtSelfTest.add(view) } else if let bar {
            vtSelfTest = VTSelfTest(view, bar: bar, create: { self.mirror.create($0) }, perform: { self.perform($0) },
                                     rescale: { self.rescale($0) }, card: { self.card }, appearance: { dark in
                                         self.appearance.loadTheme(dark: dark)
                                         self.appearance.apply("appearance")
                                     })
        }
#endif
        view.isHidden = true
        view.frame = terminalFrame(content)
        view.autoresizingMask = [.width, .height]
        content.addSubview(view, positioned: .below, relativeTo: card)
        view.host.start()
        selfTestLog("attached \(info.id)")
        return session
    }
}

extension AppDelegate: AppearanceHost {
    var terminals: [TerminalView] { sessions.map(\.view) }

    func pillWidthChanged(_ width: Double) {
        bar?.pillWidth = width
        updateBar()
    }

    func colourField() { bar?.field.colour() }

    /// At launch the attach fits the window to the new face.
    func faceChanged(_ font: Font) {
        (self.font, fonts) = (font, [font.scale: font])
        guard let window, let content, !sessions.isEmpty else { return }
        for session in sessions { session.view.setFont(font) }
        snap(window, font: font, top: SessionBar.height)
        logFit(font, grid: font.grid(in: terminalFrame(content).size))
    }
}
