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

    /// The Config's `tmux-path`, or with none the login shell's tmux first, within 2 s, then the known paths; tmux 3.4
    /// or newer.
    static func lookUp(_ configured: String) throws(AttachFailure) -> (tmux: Tmux, version: String) {
        let path = try tmuxPath(configured, loginAnswer: { loginShellPath(of: "tmux") },
                                known: knownPaths(knownTmuxPaths), isExecutable: isExecutableFile)
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

    /// tmux with `args`, and `input` on its stdin when given.
    func run(_ args: [String], input: String? = nil) -> (status: Int32, out: String, err: String) {
        let out = Pipe(), err = Pipe(), stdin = Pipe()
        let p = makeProcess(path, base + args, input: input == nil ? FileHandle.nullDevice : stdin, output: out,
                            error: err)
        do { try p.run() } catch { return (-1, "", "\(error)") }
        if let input {
            // shortcut: written before the drains, so it fits the 64 KB pipe buffer; write on a thread if input grows.
            try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }
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

/// The Config's `tmux-path` as it is when set, else the login shell's answer, then the known paths. `missing` carries
/// the set path, or nil when the lookup found none.
nonisolated func tmuxPath(_ configured: String, loginAnswer: () -> String?, known: [String],
                          isExecutable: (String) -> Bool) throws(AttachFailure) -> String {
    if !configured.isEmpty {
        guard isExecutable(configured) else { throw .missing(path: configured) }
        return configured
    }
    guard let found = pickExecutable(loginAnswer: loginAnswer(), known: known, isExecutable: isExecutable)
    else { throw .missing(path: nil) }
    return found
}

/// A step of the attach that failed; each one shows its card.
nonisolated enum AttachFailure: Error {
    case missing(path: String?)
    case tooOld(path: String, version: String)
    case server(String)
    case client(String)

    var log: String {
        switch self {
        case let .missing(path): path.map { "missing \($0)" } ?? "missing"
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
