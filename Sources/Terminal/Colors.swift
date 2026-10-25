// The fallback's colours, Terminal.app's Basic profile and xterm's colours 16 to 255, and the colours a terminal takes
// from the theme.

public struct RGB: Equatable, Sendable {
    public let r, g, b: UInt8

    public init(_ hex: UInt32) {
        r = UInt8(hex >> 16 & 0xff)
        g = UInt8(hex >> 8 & 0xff)
        b = UInt8(hex & 0xff)
    }

    public var hex: UInt32 { UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }
}

/// Black on white in light mode, white on black in dark mode; the cursor takes the foreground.
public func fallbackDefaults(dark: Bool) -> (foreground: RGB, background: RGB) {
    dark ? (RGB(0xffffff), RGB(0x000000)) : (RGB(0x000000), RGB(0xffffff))
}

/// Terminal.app's Basic colours 0 to 15, then xterm's 6×6×6 cube and grey ramp, never derived from the 16.
public let fallbackPalette: [RGB] = {
    let basic: [UInt32] = [0x000000, 0x990000, 0x00a600, 0x999900, 0x0000b2, 0xb200b2, 0x00a6b2, 0xbfbfbf,
                           0x666666, 0xe50000, 0x00d900, 0xe5e500, 0x0000ff, 0xe500e5, 0x00e5e5, 0xe5e5e5]
    let level = { (i: Int) in UInt32(i == 0 ? 0 : 55 + 40 * i) }
    let cube = (0..<216).map { i in level(i / 36) << 16 | level(i / 6 % 6) << 8 | level(i % 6) }
    let greys = (0..<24).map { i in UInt32(8 + 10 * i) * 0x010101 }
    return (basic + cube + greys).map(RGB.init)
}()

/// What a terminal draws in: its defaults, its 256 colours, the text under a block cursor and its selection's colours,
/// nil where the text takes the background in force or a selected cell inverts, and the appearance they were resolved
/// for, which the colour scheme report gives.
public struct TerminalColors: Equatable, Sendable {
    public var foreground, background, cursor: RGB
    public var palette: [RGB]
    public var cursorText, selectionBackground, selectionForeground: RGB?
    public var dark: Bool

    public init(foreground: RGB, background: RGB, cursor: RGB, palette: [RGB], cursorText: RGB? = nil,
                selectionBackground: RGB?, selectionForeground: RGB?, dark: Bool) {
        (self.foreground, self.background, self.cursor, self.palette) = (foreground, background, cursor, palette)
        (self.cursorText, self.selectionBackground) = (cursorText, selectionBackground)
        (self.selectionForeground, self.dark) = (selectionForeground, dark)
    }
}
