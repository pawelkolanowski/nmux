import Foundation

/// The known places of tmux, after the login shell's answer: Homebrew on Apple silicon, Homebrew on
/// Intel, MacPorts, the system.
nonisolated let knownTmuxPaths = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/opt/local/bin/tmux",
                                  "/usr/bin/tmux"]
/// Homebrew's brew on Apple silicon, then on Intel.
nonisolated let knownBrewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

/// The first executable candidate: the login shell's answer, then the known paths.
nonisolated func pickExecutable(loginAnswer: String?, known: [String], isExecutable: (String) -> Bool) -> String? {
    ((loginAnswer.map { [$0] } ?? []) + known).first(where: isExecutable)
}

nonisolated func knownPaths(_ paths: [String]) -> [String] {
#if NMUX_SELFTEST
    if SelfTest.noKnownPaths { return [] }
#endif
    return paths
}

/// A process of the executable at `path`, started in the home folder, so a Session tmux creates starts there and not in
/// Finder's `/`; its input reads nothing unless given.
nonisolated func makeProcess(_ path: String, _ arguments: [String], input: Any = FileHandle.nullDevice,
                             output: Any, error: Any) -> Process {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = arguments
    p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    (p.standardInput, p.standardOutput, p.standardError) = (input, output, error)
    return p
}

nonisolated func isExecutableFile(_ path: String) -> Bool {
    var dir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && !dir.boolValue
        && FileManager.default.isExecutableFile(atPath: path)
}

/// What `$SHELL -l -c 'command -v <name>'` finds, or nil when the shell fails or takes over 2 s. The answer follows a
/// marker line, so a banner the profile prints never stands in for it.
nonisolated func loginShellPath(of name: String) -> String? {
    let out = Pipe()
    let p = makeProcess(ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
                        ["-l", "-c", "echo \(lookupMarker); command -v \(name)"],
                        output: out, error: FileHandle.nullDevice)
    let done = DispatchSemaphore(value: 0)
    p.terminationHandler = { _ in done.signal() }
    guard (try? p.run()) != nil else { return nil }
    // Process gives the shell a process group of its own, so the kill takes whatever the profile started too.
    guard done.wait(timeout: .now() + 2) == .success else {
        kill(-p.processIdentifier, SIGKILL)
        return nil
    }
    // A child the shell left behind may hold the pipe open, so the read takes only what is there.
    let fd = out.fileHandleForReading.fileDescriptor
    _ = fcntl(fd, F_SETFL, O_NONBLOCK)
    var buf = [UInt8](repeating: 0, count: 4096)
    let n = read(fd, &buf, buf.count)
    try? out.fileHandleForReading.close()
    guard p.terminationStatus == 0, n > 0 else { return nil }
    return lookupAnswer(String(decoding: buf[..<n], as: UTF8.self))
}

/// The line the lookup prints before its answer.
nonisolated let lookupMarker = "nmux-lookup"

/// The line after the marker in the login shell's output; nil when none follows it.
nonisolated func lookupAnswer(_ output: String) -> String? {
    let lines = output.components(separatedBy: "\n")
    guard let marker = lines.lastIndex(of: lookupMarker), marker + 1 < lines.count else { return nil }
    let answer = lines[marker + 1]
    return answer.isEmpty ? nil : answer
}
