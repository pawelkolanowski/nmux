import Foundation
import Terminal

#if NMUX_SELFTEST
/// The self-test build's seam, which the app seam checks through: `selftest: <event>` lines on stderr, and the
/// `NMUX_SELFTEST_*` variables that steer the build. `make test` builds it with `-DNMUX_SELFTEST`; the release build
/// has none of it. Tests/seam/lib.sh describes every variable.
nonisolated enum SelfTest {
    static func log(_ event: String) { FileHandle.standardError.write(Data("selftest: \(event)\n".utf8)) }
    /// The card action pressed on every card that offers it, a moment after it shows.
    static let press = variable("PRESS")
    /// A face file in the app's Resources/Fonts to draw in, in place of SF Mono.
    static let font = variable("FONT")
    /// Hides tmux's known paths, so the seam's login shell decides alone.
    static let noKnownPaths = variable("NO_KNOWN_PATHS") != nil
    /// The script of keys and commands, the cells logged on each settled frame, and where the screen's text goes.
    static let keys = variable("KEYS")
    static let cells = variable("CELLS")
    static let screen = variable("SCREEN")
    /// The input settings and the selection's colours, `<background> <foreground>` in hex; unset keeps the view's.
    static let optionAsAlt = variable("OPTION_AS_ALT").flatMap(OptionAsAlt.init)
    static let copyOnSelect = variable("COPY_ON_SELECT") == "true"
    static let clipboardWrite = variable("CLIPBOARD_WRITE").flatMap(ClipboardAccess.init)
    static let clipboardRead = variable("CLIPBOARD_READ").flatMap(ClipboardAccess.init)
    static let selectionColors: (RGB, RGB)? = {
        let hex = (variable("SELECTION_COLORS") ?? "").split(separator: " ").compactMap { UInt32($0, radix: 16) }
        return hex.count == 2 ? (RGB(hex[0]), RGB(hex[1])) : nil
    }()

    private static func variable(_ name: String) -> String? {
        ProcessInfo.processInfo.environment["NMUX_SELFTEST_\(name)"]
    }
}
#endif

/// Logs an event in the self-test build; the release build never formats it.
nonisolated func selfTestLog(_ event: @autoclosure () -> String) {
#if NMUX_SELFTEST
    SelfTest.log(event())
#endif
}

/// A whole number without its fraction, any other with it.
func logNumber(_ value: CGFloat) -> String { String(format: "%g", Double(value)) }

func rectLog(_ r: NSRect) -> String {
    [r.origin.x, r.origin.y, r.width, r.height].map { String(Int($0.rounded())) }.joined(separator: " ")
}

/// Bytes as two hex digits each.
func hex(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
