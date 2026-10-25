import Foundation
import Terminal

/// The colours in force for one appearance: the fallback, Terminal.app's Basic and xterm's 16 to 255, with the accent
/// the cards draw with, for the appearance it was resolved for.
nonisolated struct Theme: Equatable, Sendable {
    var background, foreground, cursorColor: RGB
    var palette: [RGB]
    var accent: RGB
    var dark: Bool

    init(dark: Bool) {
        (foreground, background) = fallbackDefaults(dark: dark)
        cursorColor = foreground
        palette = fallbackPalette
        accent = palette[5]
        self.dark = dark
    }

    var terminal: TerminalColors {
        TerminalColors(foreground: foreground, background: background, cursor: cursorColor, palette: palette,
                       dark: dark)
    }
}
