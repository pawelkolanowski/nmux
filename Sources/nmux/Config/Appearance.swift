import AppKit
import Terminal

/// What an apply reaches: the window and the terminal.
protocol AppearanceHost: AnyObject {
    var window: NSWindow? { get }
    var terminals: [TerminalView] { get }
}

/// The Fallback look for the window's appearance and SF Mono, and the one apply that puts the colours on screen: at
/// launch before the first Session and on a switch of the appearance. Content, scroll and an open prompt stay.
final class Appearance {
    weak var host: AppearanceHost?
    /// The colours in force, for the appearance they were resolved for.
    private(set) var theme = Theme(dark: false)
    private var watch: NSKeyValueObservation?

    /// The Fallback look for the window's appearance, or the one given.
    func loadTheme(dark: Bool? = nil) {
        guard let window = host?.window else { return }
        theme = Theme(dark: dark ?? isDark(window.effectiveAppearance))
    }

    /// The Fallback look follows the system appearance live.
    func follow(_ window: NSWindow) {
        watch = window.observe(\.effectiveAppearance) { window, _ in
            MainActor.assumeIsolated {
                guard isDark(window.effectiveAppearance) != self.theme.dark else { return }
                self.loadTheme()
                self.apply()
            }
        }
    }

    func apply() {
        guard let host, let window = host.window else { return }
        for view in host.terminals { view.setColors(theme.terminal) }
        ChromeTheme.current = ChromeTheme(theme)
        window.backgroundColor = nsColor(theme.background)
        // Every drawn view draws again, the card among them.
        func redraw(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(redraw)
        }
        window.contentView.map(redraw)
    }

    /// A new Session's terminal starts in the colours in force.
    func dress(_ view: TerminalView) { view.setColors(theme.terminal) }

    /// SF Mono at 14 pt at the backing scale; SF Mono is the system's monospaced face, which CoreText does not find by
    /// name.
    func makeFont(scale: Double) -> Font {
        Font(NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), points: 14, scale: scale)
    }
}

func isDark(_ appearance: NSAppearance) -> Bool { appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
