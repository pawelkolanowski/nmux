import Foundation
import GhosttyVt
import QuartzCore

// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The pty that runs tmux's client, the reader thread that parses its output, and one libghostty-vt terminal behind one
/// lock, since libghostty-vt is not thread-safe. The callbacks follow Ghostty's `terminal.h`, and the device attributes
/// its `src/terminal/device_attributes.zig` and the grapheme cluster mode its `src/termio/Termio.zig`, at commit
/// 22f100c6.
public final class VTHost: @unchecked Sendable {
    /// What the host reports, fixed when it is made, so the reader thread never reads a callback another thread
    /// changes.
    struct Handlers: Sendable {
        /// On the reader thread after each parsed chunk, with its size in bytes.
        var output: @Sendable (Int) -> Void
        /// On the main thread once the client exited: its wait status and its last 4 KB of output.
        var exit: @MainActor @Sendable (Int32, String) -> Void
#if NMUX_SELFTEST
        /// On the reader thread, with the lock held, when a mode 2026 hold begins or ends.
        var hold: @Sendable (Bool) -> Void = { _ in }
#endif
    }

    private let handlers: Handlers

    /// The lock guards the terminal and every field below it that the callbacks touch.
    private let lock = NSLock()
    private let terminal: GhosttyTerminal
    private var size: GhosttySizeReportSize
    private var scheme = GHOSTTY_COLOR_SCHEME_LIGHT
    private var held = false
    private var heldSince = 0.0
    /// Replies `write_pty` queued while the terminal parsed, sent once the lock is released.
    private var replies: [UInt8] = []
    /// The write lock guards the pty: every write, the resize's ioctl and the close, after which fd is -1.
    private let writeLock = NSLock()
    private var fd: Int32
    private let pid: pid_t
    /// A write over 64 KB goes to the writer queue, and every write after it while one is queued, so they keep their
    /// order and a large paste never blocks the main thread. The queue lock guards the count, and is held across a
    /// write made at once, so a later large write never starts before it.
    private let writer = DispatchQueue(label: "nmux.vthost.writer")
    private let queueLock = NSLock()
    private var queued = 0
    /// The XTVERSION reply, alive as long as the host; an empty one leaves libghostty-vt's own, `libghostty`.
    private let xtversion: UnsafeMutableBufferPointer<UInt8>

    /// Starts `argv` on a new pty of `grid` cells of `cell`, with TMUX unset, as the pty's controlling terminal;
    /// `xtversion` is the terminal's answer to XTVERSION.
    init(argv: [String], grid: Grid, cell: Cell, handlers: Handlers, xtversion: String = "") throws(VTHostError) {
        self.handlers = handlers
        size = GhosttySizeReportSize(rows: UInt16(grid.rows), columns: UInt16(grid.cols),
                                     cell_width: UInt32(cell.width), cell_height: UInt32(cell.height))
        var made: GhosttyTerminal?
        guard ghostty_terminal_new(nil, &made, size.columns, size.rows) == GHOSTTY_SUCCESS, let made else {
            throw .terminal
        }
        do {
            (fd, pid) = try spawn(argv, size: winsize(size))
        } catch {
            ghostty_terminal_free(made)
            throw error
        }
        self.xtversion = .allocate(capacity: xtversion.utf8.count)
        _ = self.xtversion.initialize(from: xtversion.utf8)
        terminal = made
        ghostty_terminal_resize(terminal, size.columns, size.rows, size.cell_width, size.cell_height)
        configure()
    }

    /// Only a host never started ends here, since the reader holds it; closing the pty hangs up its client.
    deinit {
        if fd >= 0 { close(fd) }
        ghostty_terminal_free(terminal)
        xtversion.deallocate()
    }

    /// Starts reading the client's output.
    public func start() { Thread.detachNewThread { [self] in read() } }

    private func configure() {
        set(GHOSTTY_TERMINAL_OPT_USERDATA, Unmanaged.passUnretained(self).toOpaque())
        let writePty: GhosttyTerminalWritePtyFn = { _, ud, data, len in
            guard let data else { return }
            host(ud).replies.append(contentsOf: UnsafeBufferPointer(start: data, count: len))
        }
        let size: GhosttyTerminalSizeFn = { _, ud, out in
            out?.pointee = host(ud).size
            return true
        }
        let scheme: GhosttyTerminalColorSchemeFn = { _, ud, out in
            out?.pointee = host(ud).scheme
            return true
        }
        // Ghostty's own answers: a VT220 with ANSI colour (`ESC [ ? 62 ; 22 c`), and `ESC [ > 1 ; 0 ; 0 c`.
        let attributes: GhosttyTerminalDeviceAttributesFn = { _, _, out in
            guard let out else { return false }
            out.pointee.primary.conformance_level = 62
            out.pointee.primary.features.0 = 22
            out.pointee.primary.num_features = 1
            out.pointee.secondary = GhosttyDeviceAttributesSecondary(device_type: 1, firmware_version: 0,
                                                                     rom_cartridge: 0)
            out.pointee.tertiary.unit_id = 0
            return true
        }
        let hold: GhosttyTerminalRenderHoldFn = { _, ud, held in
            let h = host(ud)
            h.held = held
            h.heldSince = CACurrentMediaTime()
#if NMUX_SELFTEST
            h.handlers.hold(held)
#endif
        }
        let version: GhosttyTerminalXtversionFn = { _, ud in
            let v = host(ud).xtversion
            return GhosttyString(ptr: v.baseAddress, len: v.count)
        }
        set(GHOSTTY_TERMINAL_OPT_XTVERSION, unsafeBitCast(version, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_WRITE_PTY, unsafeBitCast(writePty, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_SIZE, unsafeBitCast(size, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_COLOR_SCHEME, unsafeBitCast(scheme, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_DEVICE_ATTRIBUTES, unsafeBitCast(attributes, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_RENDER_HOLD, unsafeBitCast(hold, to: UnsafeRawPointer.self))
        // tmux holds the history.
        var noScrollback = 0
        set(GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES, &noScrollback)
        // Ghostty's default `grapheme-width-method = unicode`: a joined, toned or flagged emoji is one cell's cluster.
        // limitation: a full reset (RIS) turns the mode off, upgrade to a default the reset keeps once a program sends
        // one.
        var clusters = GhosttyTerminalModeConfig(mode: ghostty_mode_new(2027, false), value: true)
        set(GHOSTTY_TERMINAL_OPT_MODE, &clusters)
        let (fg, bg) = fallbackDefaults(dark: false)
        setDefaults(TerminalColors(foreground: fg, background: bg, cursor: fg, palette: fallbackPalette, dark: false))
        Array("xterm-256color".utf8).withUnsafeBufferPointer { p in // the terminal copies the name
            var name = GhosttyString(ptr: p.baseAddress, len: p.count)
            set(GHOSTTY_TERMINAL_OPT_TERMINFO_NAME, &name)
        }
    }

    private func set(_ option: GhosttyTerminalOption, _ value: UnsafeRawPointer?) {
        ghostty_terminal_set(terminal, option, value)
    }

    /// The defaults and the palette; call with the lock held.
    private func setDefaults(_ colors: TerminalColors) {
        var fg = ghosttyColor(colors.foreground), bg = ghosttyColor(colors.background),
            cursor = ghosttyColor(colors.cursor)
        set(GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, &fg)
        set(GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, &bg)
        set(GHOSTTY_TERMINAL_OPT_COLOR_CURSOR, &cursor)
        var palette = colors.palette.map(ghosttyColor)
        set(GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, &palette)
    }

    /// The theme's colours, at creation and on a switch of the appearance: a query (OSC 10, 11, 4) gets
    /// them from now on, and a program that set mode 2031 gets the colour scheme report when the appearance changed.
    func setColors(_ colors: TerminalColors) {
        locked { t in
            setDefaults(colors)
            let new = colors.dark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
            guard new != scheme else { return }
            scheme = new
            guard modeSet(t, 2031) else { return }
            var buf = [CChar](repeating: 0, count: 16), n = 0
            if ghostty_color_scheme_report_encode(scheme, &buf, buf.count, &n) == GHOSTTY_SUCCESS {
                replies += buf[..<n].map { UInt8(bitPattern: $0) }
            }
        }
    }

    private func read() {
        var buf = [UInt8](repeating: 0, count: 64 * 1024), tail: [UInt8] = []
        while true {
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n < 0 && errno == EINTR { continue }
            // EOF, or EIO once the client exited; any other error ends the read too, since the pty is gone.
            if n <= 0 { break }
            buf.withUnsafeBufferPointer { b in locked { ghostty_terminal_vt_write($0, b.baseAddress, n) } }
            keepTail(&tail, buf[..<n])
            handlers.output(n)
        }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        writeLock.lock()
        close(fd)
        fd = -1
        writeLock.unlock()
        let output = String(decoding: tail, as: UTF8.self)
        onMain { [exit = handlers.exit, status] in exit(status, output) }
    }

    /// Writes `bytes` to the client, from any thread: at once, unless it is over 64 KB or a write waits on the writer
    /// queue.
    public func send(_ bytes: [UInt8]) {
        queueLock.lock()
        guard queued > 0 || bytes.count > 64 * 1024 else {
            write(bytes)
            return queueLock.unlock()
        }
        queued += 1
        queueLock.unlock()
        writer.async { [self] in
            // A chunk at a time, so a resize or a reply never waits on the whole write.
            // limitation: a resize still waits on the chunk in flight, which is long only while tmux stops reading;
            // upgrade when that wait shows in a live resize.
            for start in stride(from: 0, to: bytes.count, by: 64 * 1024) {
                if !write(bytes[start..<min(start + 64 * 1024, bytes.count)]) { break }
            }
            queueLock.lock()
            queued -= 1
            queueLock.unlock()
        }
    }

    /// False when the client is gone; the reader reports the exit.
    @discardableResult
    private func write(_ bytes: some Collection<UInt8>) -> Bool {
        writeLock.lock()
        defer { writeLock.unlock() }
        return bytes.withContiguousStorageIfAvailable { b in
            var off = 0
            while fd >= 0, off < b.count {
                let n = Darwin.write(fd, b.baseAddress! + off, b.count - off)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { return false }
                off += n
            }
            return fd >= 0
        } ?? false
    }

    /// Runs `body` with the terminal locked, then sends what its callbacks queued.
    func locked<T>(_ body: (GhosttyTerminal) -> T) -> T {
        lock.lock()
        let result = body(terminal)
        let out = replies
        replies.removeAll(keepingCapacity: true)
        lock.unlock()
        if !out.isEmpty { send(out) }
        return result
    }

    /// Whether a mode 2026 hold keeps the frame. A hold older than 1 s ends here, since libghostty-vt has no clock;
    /// setting the mode does not call the hold callback.
    func holding() -> Bool {
        locked { t in
            guard held, CACurrentMediaTime() - heldSince > 1 else { return held }
            var off = GhosttyTerminalModeConfig(mode: ghostty_mode_new(2026, false), value: false)
            ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_MODE, &off)
            held = false
            return false
        }
    }

    /// Resizes the terminal and the pty together, to `grid` of `cell`; the size they already have is skipped. True
    /// when the grid changed; a new cell alone only updates the pixels the pty reports.
    func resize(_ grid: Grid, cell: Cell) -> Bool {
        var gridChanged = false
        let ws: winsize? = locked { t in
            let next = GhosttySizeReportSize(rows: UInt16(grid.rows), columns: UInt16(grid.cols),
                                             cell_width: UInt32(cell.width), cell_height: UInt32(cell.height))
            guard (next.columns, next.rows, next.cell_width, next.cell_height)
                    != (size.columns, size.rows, size.cell_width, size.cell_height) else { return nil }
            gridChanged = (next.columns, next.rows) != (size.columns, size.rows)
            size = next
            ghostty_terminal_resize(t, size.columns, size.rows, size.cell_width, size.cell_height)
            return winsize(size)
        }
        guard var ws else { return false }
        writeLock.lock()
        if fd >= 0 { _ = ioctl(fd, TIOCSWINSZ, &ws) }
        writeLock.unlock()
        return gridChanged
    }

#if NMUX_SELFTEST
    /// Parses `bytes` as if the client wrote them and returns the replies instead of sending them: the
    /// self-test's view of how queries are answered.
    public func probe(_ bytes: [UInt8]) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        bytes.withUnsafeBufferPointer { ghostty_terminal_vt_write(terminal, $0.baseAddress, $0.count) }
        let out = replies
        replies.removeAll(keepingCapacity: true)
        return out
    }
#endif
}

/// Whether the DEC private mode is on; call with the lock held.
private func modeSet(_ terminal: GhosttyTerminal, _ mode: UInt16) -> Bool {
    var config = GhosttyTerminalModeConfig(mode: ghostty_mode_new(mode, false), value: false)
    return ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_MODE, &config) == GHOSTTY_SUCCESS && config.value
}

public enum VTHostError: Error, CustomStringConvertible {
    case terminal
    case forkpty(errno: Int32)

    public var description: String {
        switch self {
        case .terminal: "libghostty-vt cannot create a terminal"
        case .forkpty(let errno): "forkpty: \(String(cString: strerror(errno)))"
        }
    }
}

private func host(_ ud: UnsafeMutableRawPointer?) -> VTHost { Unmanaged<VTHost>.fromOpaque(ud!).takeUnretainedValue() }

private func ghosttyColor(_ c: RGB) -> GhosttyColorRgb { GhosttyColorRgb(r: c.r, g: c.g, b: c.b) }

/// Appends a read to the client's last output, kept at `limit` bytes; a read that fills it alone is taken as it is.
func keepTail(_ tail: inout [UInt8], _ read: ArraySlice<UInt8>, limit: Int = 4096) {
    if read.count >= limit { return tail = Array(read.suffix(limit)) }
    tail.append(contentsOf: read)
    if tail.count > limit { tail.removeFirst(tail.count - limit) }
}

/// The pty's size: the grid in cells, and in pixels of the cell.
private func winsize(_ s: GhosttySizeReportSize) -> winsize {
    winsize(ws_row: s.rows, ws_col: s.columns, ws_xpixel: UInt16(clamping: UInt32(s.columns) * s.cell_width),
            ws_ypixel: UInt16(clamping: UInt32(s.rows) * s.cell_height))
}

/// forkpty makes the pty the child's controlling terminal (setsid and TIOCSCTTY), which posix_spawn cannot; the
/// child only calls execve on what was built before the fork.
private func spawn(_ args: [String], size: winsize) throws(VTHostError) -> (Int32, pid_t) {
    var env = ProcessInfo.processInfo.environment
    env["TMUX"] = nil
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
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
