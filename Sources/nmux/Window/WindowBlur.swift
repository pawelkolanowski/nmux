import AppKit

/// The private CoreGraphics calls Ghostty's macOS app blurs its window with (`src/apprt/embedded.zig` at commit
/// 22f100c6, MIT), looked up as C functions; a macOS without them blurs nothing.
private let CGSDefaultConnectionForThread = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                                  "CGSDefaultConnectionForThread")
    .map { unsafeBitCast($0, to: (@convention(c) () -> UnsafeMutableRawPointer?).self) }
private let CGSSetWindowBackgroundBlurRadius = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                                     "CGSSetWindowBackgroundBlurRadius")
    .map { unsafeBitCast($0, to: (@convention(c) (UnsafeMutableRawPointer?, Int, Int32) -> Int32).self) }

/// Blurs what shows through the window's background by `radius`, 0 for none.
func blur(_ window: NSWindow, radius: Int) {
    guard let connection = CGSDefaultConnectionForThread, let blur = CGSSetWindowBackgroundBlurRadius else { return }
    _ = blur(connection(), window.windowNumber, Int32(radius))
}
