import Foundation

/// Homebrew's brew, found the way tmux is: the login shell's within 2 s, then the known paths.
nonisolated func findBrew() -> String? {
    pickExecutable(loginAnswer: loginShellPath(of: "brew"), known: knownPaths(knownBrewPaths),
                   isExecutable: isExecutableFile)
}

/// brew with the arguments Install runs it with, from its own folder first on the PATH.
nonisolated struct Brew {
    let path: String
    let arguments: [String]

    /// Returns brew's pid, which leads a process group of its own. Both of brew's streams reach onOutput in
    /// order, then onExit gets its status. The read stops once brew
    /// is gone and the pipe is empty, so a child brew leaves behind holding the pipe cannot hang the card.
    func run(onOutput: @escaping @Sendable (Data) -> Void,
             onExit: @escaping @Sendable (Int32) -> Void) throws -> pid_t {
        let out = Pipe()
        let p = makeProcess(path, arguments, output: out, error: out)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (path as NSString).deletingLastPathComponent + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env
        try p.run()
        let fd = out.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        Thread.detachNewThread {
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                var ready = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                _ = poll(&ready, 1, 100)
                let n = read(fd, &buf, buf.count)
                if n > 0 { onOutput(Data(buf[..<n])); continue }
                if n == 0 || !p.isRunning { break }
            }
            try? out.fileHandleForReading.close()
            p.waitUntilExit()
            onExit(p.terminationStatus)
        }
        return p.processIdentifier
    }
}
