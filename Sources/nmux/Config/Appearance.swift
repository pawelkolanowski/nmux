import AppKit
import Terminal

/// What an apply reaches: the window.
protocol AppearanceHost: AnyObject {
    var window: NSWindow? { get }
}

/// The Fallback look for the window's appearance, and the one apply that puts it on screen: at launch and on a switch
/// of the appearance. An open card stays.
final class Appearance {
    weak var host: AppearanceHost?
    /// The colours in force, for the appearance they were resolved for.
    private(set) var theme = Theme(dark: false)
    private var watch: NSKeyValueObservation?

    /// The Fallback look for the window's appearance.
    func loadTheme() {
        guard let window = host?.window else { return }
        theme = Theme(dark: isDark(window.effectiveAppearance))
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
        guard let window = host?.window else { return }
        ChromeTheme.current = ChromeTheme(theme)
        window.backgroundColor = nsColor(theme.background)
        // Every drawn view draws again, the card among them.
        func redraw(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(redraw)
        }
        window.contentView.map(redraw)
    }
}

func isDark(_ appearance: NSAppearance) -> Bool { appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
