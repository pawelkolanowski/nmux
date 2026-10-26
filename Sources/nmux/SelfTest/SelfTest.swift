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
    /// A face file in the app's Resources/Fonts to draw in, in place of the config's.
    static let font = variable("FONT")
    /// Hides tmux's known paths, so the seam's login shell decides alone.
    static let noKnownPaths = variable("NO_KNOWN_PATHS") != nil
    /// The script of keys and commands, the cells logged on each settled frame, and where the screen's text goes.
    static let keys = variable("KEYS")
    static let cells = variable("CELLS")
    static let screen = variable("SCREEN")

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

/// Bytes as two hex digits each, and a colour as six.
func hex(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
func hex(_ rgb: RGB) -> String { hex([rgb.r, rgb.g, rgb.b]) }
