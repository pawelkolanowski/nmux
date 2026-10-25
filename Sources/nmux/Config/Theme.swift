import Foundation
import Terminal

/// The colours in force for one appearance: the fallback, Terminal.app's Basic and xterm's 16 to 255, with the accent
/// the cards draw with, for the appearance it was resolved for.
nonisolated struct Theme: Equatable, Sendable {
    var background, foreground: RGB
    var palette: [RGB]
    var accent: RGB
    var dark: Bool

    init(dark: Bool) {
        (foreground, background) = fallbackDefaults(dark: dark)
        palette = fallbackPalette
        accent = palette[5]
        self.dark = dark
    }
}
