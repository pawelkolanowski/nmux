import Foundation
import Terminal

/// The colours in force for one appearance: the fallback, Terminal.app's Basic and xterm's 16 to 255, with the accent
/// the Session bar and the cards draw with and the red for warnings, for the appearance it was resolved for.
nonisolated struct Theme: Equatable, Sendable {
    var background, foreground, cursorColor: RGB
    /// Nil where the text under a block cursor takes the background in force, which a program may change.
    var cursorText, selectionBackground, selectionForeground: RGB?
    var palette: [RGB]
    var accent, red: RGB
    var dark: Bool

    init(dark: Bool) {
        (foreground, background) = fallbackDefaults(dark: dark)
        cursorColor = foreground
        palette = fallbackPalette
        accent = palette[5]
        red = accent
        self.dark = dark
    }

    var terminal: TerminalColors {
        TerminalColors(foreground: foreground, background: background, cursor: cursorColor, palette: palette,
                       cursorText: cursorText, selectionBackground: selectionBackground,
                       selectionForeground: selectionForeground, dark: dark)
    }
}
