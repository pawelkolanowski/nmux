import Foundation

/// The client's size in cells.
public struct Grid: Equatable, Sendable {
    public let cols: Int
    public let rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }
}

/// A program on a pty that is its controlling terminal, with TMUX unset. Nothing draws its output yet: a reader thread
/// keeps only its last 4 KB, so a client that fails can tell why.
public final class PtyClient: Sendable {
    private let fd: Int32
    private let pid: pid_t
    private let exit: @MainActor @Sendable (Int32, String) -> Void

    /// Starts `argv` on a new pty of `grid` cells. `exit` gets its wait status and its last 4 KB of output, on the main
    /// thread, once the client exited and the pty is drained.
    public init(argv: [String], grid: Grid,
                exit: @escaping @MainActor @Sendable (Int32, String) -> Void) throws(PtyError) {
        let size = winsize(ws_row: UInt16(clamping: grid.rows), ws_col: UInt16(clamping: grid.cols), ws_xpixel: 0,
                           ws_ypixel: 0)
        (fd, pid) = try spawn(argv, size: size)
        self.exit = exit
        Thread.detachNewThread { [self] in read() }
    }

    private func read() {
        var buf = [UInt8](repeating: 0, count: 64 * 1024), tail: [UInt8] = []
        while true {
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n < 0 && errno == EINTR { continue }
            // EOF, or EIO once the client exited; any other error ends the read too, since the pty is gone.
            if n <= 0 { break }
            tail = Array((tail + buf[..<n]).suffix(4096))
        }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        close(fd)
        let output = String(decoding: tail, as: UTF8.self)
        onMain { [exit, status] in exit(status, output) }
    }
}

public enum PtyError: Error, CustomStringConvertible {
    case forkpty(errno: Int32)

    public var description: String {
        switch self {
        case .forkpty(let errno): "forkpty: \(String(cString: strerror(errno)))"
        }
    }
}

/// forkpty makes the pty the child's controlling terminal (setsid and TIOCSCTTY), which posix_spawn cannot; the
/// child only calls execve on what was built before the fork.
private func spawn(_ args: [String], size: winsize) throws(PtyError) -> (Int32, pid_t) {
    var env = ProcessInfo.processInfo.environment
    env["TMUX"] = nil
    env["TERM"] = "xterm-256color"
    let argv = args.map { strdup($0) } + [nil]
    let envp = env.map { strdup("\($0)=\($1)") } + [nil]
    defer { (argv + envp).forEach { free($0) } }
    var ws = size, fd: Int32 = -1
    let pid = forkpty(&fd, nil, nil, &ws)
    if pid == 0 {
        execve(argv[0], argv, envp)
        _exit(127)
    }
    guard pid > 0 else { throw .forkpty(errno: errno) }
    // Every later client would inherit this pty, and keep it open after its own Session ends.
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    return (fd, pid)
}
