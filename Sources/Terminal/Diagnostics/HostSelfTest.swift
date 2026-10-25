#if NMUX_SELFTEST
import Foundation
import GhosttyVt

/// The self-test's view of the VT host: the screen's text and the default background.
extension VTHost {
    /// The active screen as plain text, its trailing blanks trimmed.
    public func screenText() -> String { locked(plainText) }

    /// The default background as `#rrggbb`.
    public func defaultBackground() -> String { locked(backgroundHex) }

    /// Whether a mode 2026 hold keeps the frame, as the view asks before each one.
    public var isHolding: Bool { holding() }
}

/// The version of libghostty-vt nmux was built with, `major.minor.patch`.
public var libghosttyVersion: String {
    [GHOSTTY_BUILD_INFO_VERSION_MAJOR, GHOSTTY_BUILD_INFO_VERSION_MINOR, GHOSTTY_BUILD_INFO_VERSION_PATCH].map { info in
        var part = 0
        ghostty_build_info(info, &part)
        return String(part)
    }.joined(separator: ".")
}

private func backgroundHex(_ terminal: GhosttyTerminal) -> String {
    var bg = GhosttyColorRgb()
    ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_COLOR_BACKGROUND_DEFAULT, &bg)
    return String(format: "#%02x%02x%02x", bg.r, bg.g, bg.b)
}

private func plainText(_ terminal: GhosttyTerminal) -> String {
    var options = GhosttyFormatterTerminalOptions()
    options.size = MemoryLayout<GhosttyFormatterTerminalOptions>.size
    options.emit = GHOSTTY_FORMATTER_FORMAT_PLAIN
    options.trim = true
    var formatter: GhosttyFormatter?
    guard ghostty_formatter_terminal_new(nil, &formatter, terminal, options) == GHOSTTY_SUCCESS else { return "" }
    defer { ghostty_formatter_free(formatter) }
    var out: UnsafeMutablePointer<UInt8>?, len = 0
    guard ghostty_formatter_format_alloc(formatter, nil, &out, &len) == GHOSTTY_SUCCESS, let out else { return "" }
    defer { ghostty_free(nil, out, len) }
    return String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
}

#endif
