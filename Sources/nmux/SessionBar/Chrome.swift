import AppKit
import Carbon.HIToolbox
import Terminal

/// The chrome's colours: the theme's foreground, its background at `background-opacity`, the accent and the red. Every
/// drawn view reads the one current value, which each apply replaces before it redraws them.
struct ChromeTheme {
    static var current = ChromeTheme(Theme(dark: false), opacity: 1)
    let fg, bg, accent, danger: NSColor

    init(_ theme: Theme, opacity: Double) {
        fg = nsColor(theme.foreground)
        bg = nsColor(theme.background).withAlphaComponent(opacity)
        accent = nsColor(theme.accent)
        danger = nsColor(theme.red)
    }
}

func nsColor(_ c: RGB) -> NSColor {
    NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
}

/// The soft rounded wash a pill, the active mark and the spill share.
func wash(_ bounds: NSRect, inset: CGFloat = 2) -> NSBezierPath {
    NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: 4), xRadius: 6, yRadius: 6)
}

/// One line of text centred on the bar's middle, across `x` to `x + width`.
func drawLine(_ text: String, _ attributes: [NSAttributedString.Key: Any], x: CGFloat, width: CGFloat,
              in bounds: NSRect) {
    let height = textSize(text, attributes).height
    (text as NSString).draw(in: NSRect(x: x, y: (bounds.height - height) / 2, width: width, height: height),
                            withAttributes: attributes)
}

/// The size a string takes in these attributes.
func textSize(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> NSSize {
    (text as NSString).size(withAttributes: attributes)
}

/// An SF Symbol in one colour, centred on a point, 8 pt bold unless told otherwise.
func drawSymbol(_ name: String, _ color: NSColor, centre: NSPoint, size: CGFloat = 8, weight: NSFont.Weight = .bold) {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: [color]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    else { return }
    image.draw(in: NSRect(x: centre.x - image.size.width / 2, y: centre.y - image.size.height / 2,
                          width: image.size.width, height: image.size.height))
}

/// The keys a prompt answers: Return and the keypad's Enter take the default, Escape dismisses, Tab moves the focus and
/// Space presses what it is on.
enum KeyCode {
    static let `return` = UInt16(kVK_Return), enter = UInt16(kVK_ANSI_KeypadEnter), escape = UInt16(kVK_Escape)
    static let tab = UInt16(kVK_Tab), space = UInt16(kVK_Space)
}
