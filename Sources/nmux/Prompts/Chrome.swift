import AppKit
import Carbon.HIToolbox
import Terminal

/// The chrome's colours: the theme's foreground, its background and the accent. Every drawn view reads the one current
/// value, which each apply replaces before it redraws them.
struct ChromeTheme {
    static var current = ChromeTheme(Theme(dark: false))
    let fg, bg, accent: NSColor

    init(_ theme: Theme) {
        fg = nsColor(theme.foreground)
        bg = nsColor(theme.background)
        accent = nsColor(theme.accent)
    }
}

func nsColor(_ c: RGB) -> NSColor {
    NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
}

/// The size a string takes in these attributes.
func textSize(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> NSSize {
    (text as NSString).size(withAttributes: attributes)
}

/// The keys a prompt answers: Return and the keypad's Enter take the default, and Escape dismisses.
enum KeyCode {
    static let `return` = UInt16(kVK_Return), enter = UInt16(kVK_ANSI_KeypadEnter), escape = UInt16(kVK_Escape)
}
