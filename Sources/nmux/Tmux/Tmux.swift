import AppKit
import Terminal

/// The tmux nmux found. Under the self-test every call reaches the seam's private server, with no config.
nonisolated struct Tmux {
    let path: String
#if NMUX_SELFTEST
    let base = ["-L", "nmux-test", "-f", "/dev/null"]
#else
    let base: [String] = []
#endif

    /// The login shell's tmux first, within 2 s, then the known paths; tmux 3.4 or newer.
    static func lookUp() throws(AttachFailure) -> (tmux: Tmux, version: String) {
        let found = pickExecutable(loginAnswer: loginShellPath(of: "tmux"), known: knownPaths(knownTmuxPaths),
                                   isExecutable: isExecutableFile)
        guard let path = found else { throw .missing }
        let tmux = Tmux(path: path)
        let version = tmuxVersion(tmux.run(["-V"]).out.trimmingCharacters(in: .whitespacesAndNewlines))
        guard tmuxIsNewEnough(version) else { throw .tooOld(path: path, version: version) }
        return (tmux, version)
    }

    /// The Session with the lowest `$ID`, or a new one, at the client's size, when the server has none. The new
    /// Session's window leaves room for the status line, so the client's attach never resizes it.
    func session(_ grid: Grid) throws(AttachFailure) -> SessionID {
        if let id = lowestSession(run(["list-sessions", "-F", "#{session_id}"]).out) { return id }
        let rows = grid.rows - statusRows(run(["start-server", ";", "show-options", "-gv", "status"]).out)
        let made = run(["new-session", "-d", "-x", "\(grid.cols)", "-y", "\(max(1, rows))", "-P", "-F",
                        "#{session_id}"])
        guard made.status == 0, let id = lowestSession(made.out) else {
            throw .server(made.err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return id
    }

    func run(_ args: [String]) -> (status: Int32, out: String, err: String) {
        let out = Pipe(), err = Pipe()
        let p = makeProcess(path, base + args, output: out, error: err)
        do { try p.run() } catch { return (-1, "", "\(error)") }
        // stderr drains on its own thread, so neither pipe fills up while nmux reads the other.
        nonisolated(unsafe) var e = Data()
        let drained = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            e = err.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        drained.wait()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }
}

/// A step of the attach that failed; each one shows its card.
nonisolated enum AttachFailure: Error {
    case missing
    case tooOld(path: String, version: String)
    case server(String)
    case client(String)

    var log: String {
        switch self {
        case .missing: "missing"
        case let .tooOld(path, version): "too-old \(path) \(version)"
        case let .server(detail): "server \(detail)"
        case let .client(detail): "client \(detail)"
        }
    }
}

/// The version `tmux -V` prints after `tmux `, as `3.7c` or `next-3.8`.
nonisolated func tmuxVersion(_ line: String) -> String {
    line.hasPrefix("tmux ") ? String(line.dropFirst(5)) : line
}

/// The major and minor of a tmux version; nil when it does not parse.
nonisolated func versionNumbers(_ version: String) -> (major: Int, minor: Int)? {
    var v = Substring(version)
    if v.hasPrefix("next-") { v = v.dropFirst(5) }
    let parts = v.split(separator: ".", maxSplits: 1)
    guard parts.count == 2, let major = Int(parts[0]), let minor = Int(parts[1].prefix(while: \.isNumber))
    else { return nil }
    return (major, minor)
}

/// nmux needs tmux 3.4 or newer; a version that does not parse counts as too old.
nonisolated func tmuxIsNewEnough(_ version: String) -> Bool {
    guard let v = versionNumbers(version) else { return false }
    return (v.major, v.minor) >= (3, 4)
}

/// The rows tmux's `status` option takes: `off` none, `on` one, a number that many.
nonisolated func statusRows(_ status: String) -> Int {
    let value = status.trimmingCharacters(in: .whitespacesAndNewlines)
    return value == "off" ? 0 : Int(value) ?? 1
}
