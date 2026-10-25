import AppKit
import Terminal

/// The app's lifecycle, the one Session's client and the action dispatch. The colours live in the appearance, and the
/// prompts in `AppDelegate+Prompts.swift`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    /// The window's content view, which holds the card.
    var content: NSView?
    /// The Session's tmux client.
    var client: PtyClient?
    let appearance = Appearance()
    var card: CardView?
    /// The brew the card's Install runs, and the output of its run.
    var brew: Brew?
    var brewOutput = Data()
    var brewPID: pid_t?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let (window, frame) = makeWindow()
        self.window = window
        content = window.contentView
        appearance.host = self
        // The colours go in before the window shows, so its first frame never flashes another background.
        appearance.loadTheme()
        appearance.apply()
        // The frame goes in before the window shows, so it never appears at another size first.
        window.setFrame(frame, display: false)
        window.makeKeyAndOrderFront(nil)
        // With Stage Manager on, the first order front may come out narrower.
        window.setFrame(frame, display: true)
        selfTestLog("visible \(rectLog(frame))")
        appearance.follow(window)
        attach(window)
    }

    /// The attach runs at the window's final size, so tmux never reflows the panes at launch. The lookup may wait 2 s
    /// on the login shell, so it and the Session run off the main thread.
    func attach(_ window: NSWindow) {
        let grid = launchGrid(window)
        selfTestLog("grid \(grid.cols)x\(grid.rows)")
        selfTestLog("window \(rectLog(window.frame))")
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
    /// A plain tmux client attached to the Session, on a pty at the window's grid. The client ends with 0 on detach or
    /// when its Session dies, and nmux with it; any other end shows the client card with the client's last line.
    func start(_ tmux: Tmux, session id: SessionID, grid: Grid) {
        do {
            client = try PtyClient(argv: [tmux.path] + tmux.base + ["attach-session", "-t", "\(id)"], grid: grid) {
                [weak self] status, output in
                guard let self else { return }
                guard status != 0 else { return self.quit() }
                self.client = nil
                self.attachFailed(.client(lastLines(output, 1)))
            }
        } catch {
            return attachFailed(.client("\(error)"))
        }
        selfTestLog("attached \(id)")
    }
}

extension AppDelegate: AppearanceHost {}
