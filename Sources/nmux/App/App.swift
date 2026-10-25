import AppKit
import Terminal

/// The entry: the process setup, then the app, which never returns.
@main
enum App {
    static func main() {
        // nmux and every client it starts reach the default server, never the one nmux was started from.
        unsetenv("TMUX")
        // A launch from the Dock or Finder has no locale, and tmux then draws every non-ASCII character as `_`; the
        // server nmux starts hands the same environment to every pane's shell.
        if let lang = utf8Lang(ProcessInfo.processInfo.environment, locale: .current, valid: localeExists) {
            setenv("LANG", lang, 1)
        }

#if NMUX_SELFTEST
        selfTestLog("libghostty-vt \(libghosttyVersion)")
#endif

        // A write to a closed pipe or pty fails with EPIPE instead of ending nmux.
        signal(SIGPIPE, SIG_IGN)

        // SIGTERM goes through NSApp.terminate, on the main queue, so the app ends as a quit would.
        signal(SIGTERM, SIG_IGN)
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler { MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.quit() } }
        sigterm.resume()

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.mainMenu = makeMainMenu(target: delegate)
        selfTestLog("launched")
        app.run()
    }
}

/// The `LANG` that makes tmux's client UTF-8 when none of `LC_ALL`, `LC_CTYPE` and `LANG` names UTF-8, as tmux reads
/// them: the locale's own `<language>_<region>.UTF-8` when it exists, else `en_US.UTF-8`. Nil keeps the user's choice.
nonisolated func utf8Lang(_ environment: [String: String], locale: Locale, valid: (String) -> Bool) -> String? {
    let names = ["LC_ALL", "LC_CTYPE", "LANG"].compactMap { environment[$0]?.uppercased() }
    if names.contains(where: { $0.contains("UTF-8") || $0.contains("UTF8") }) { return nil }
    if let language = locale.language.languageCode?.identifier, let region = locale.region?.identifier {
        let own = "\(language)_\(region).UTF-8"
        if valid(own) { return own }
    }
    return "en_US.UTF-8"
}

/// Whether the C library knows the locale, checked without changing nmux's own.
nonisolated func localeExists(_ name: String) -> Bool {
    guard let made = newlocale(LC_CTYPE_MASK, name, nil) else { return false }
    freelocale(made)
    return true
}
