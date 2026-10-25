import AppKit
import Terminal

/// The one window, at the visible size of the screen under the pointer, and the frame it takes: titled, its title bar
/// clear over the content. The green button zooms; nmux stays an ordinary window on the current Space.
func makeWindow() -> (NSWindow, frame: NSRect) {
    let screens = NSScreen.screens
    let screen = launchScreen(frames: screens.map(\.frame), pointer: NSEvent.mouseLocation)
        .map { screens[$0] } ?? NSScreen.main
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

/// The grid the content holds in cells of SF Mono at 14 pt, the font nmux will draw in.
func launchGrid(_ window: NSWindow) -> Grid {
    let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let cell = CGSize(width: font.maximumAdvancement.width,
                      height: (font.ascender - font.descender + font.leading).rounded(.up))
    let size = window.contentRect(forFrameRect: window.frame).size
    return Grid(cols: max(1, Int(size.width / cell.width)), rows: max(1, Int(size.height / cell.height)))
}
