import AppKit
import Terminal

/// The one window, at the visible size of the screen under the pointer, and the frame it takes: titled, its title bar
/// clear over the content. The green button zooms; nmux stays an ordinary window on the current Space.
func makeWindow() -> (NSWindow, frame: NSRect) {
    let screens = NSScreen.screens
#if NMUX_SELFTEST
    // The seam assumes a scale-2 screen, so the self-test opens on the sharpest one, wherever the pointer rests.
    let screen = screens.max { $0.backingScaleFactor < $1.backingScaleFactor } ?? NSScreen.main
#else
    let screen = launchScreen(frames: screens.map(\.frame), pointer: NSEvent.mouseLocation)
        .map { screens[$0] } ?? NSScreen.main
#endif
    let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    let window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.collectionBehavior = .fullScreenNone
    return (window, frame)
}

/// Shrinks the window to the largest grid of whole cells its content holds, its top-left kept, and from then on resizes
/// it by whole cells. Takes the size the content got, never the one asked for: Stage Manager may trim it.
func snap(_ window: NSWindow, font: Font) {
    guard let content = window.contentView?.bounds.size else { return }
    let grid = font.grid(in: content)
    var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: font.contentSize(grid)))
    frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
    window.contentResizeIncrements = NSSize(width: CGFloat(font.cell.width) / font.scale,
                                            height: CGFloat(font.cell.height) / font.scale)
    window.setFrame(frame, display: true)
}
