import Foundation
import Terminal

/// A theme file's colours, every one optional, as a theme sets colours only: what the file sets, before the fallback
/// fills the rest.
nonisolated struct ThemeColors: Equatable, Sendable {
    var background, foreground, cursorColor, cursorText, selectionBackground, selectionForeground: RGB?
    var palette: [Int: RGB] = [:]
}

/// Ghostty's theme format (`src/config/Config.zig` and `src/config/theme.zig` at 22f100c6, MIT), colours only: the
/// config syntax of `parseConfig`, the six colour keys and `palette = N=<colour>` for N from 0 to 255, a colour
/// `#rrggbb` or `rrggbb`, the last line of a key or index winning. Every other line and every bad value is skipped,
/// with no problem.
nonisolated func parseTheme(_ text: String) -> ThemeColors {
    var colors = ThemeColors()
    let keys: [String: WritableKeyPath<ThemeColors, RGB?>] = [
        "background": \.background, "foreground": \.foreground, "cursor-color": \.cursorColor,
        "cursor-text": \.cursorText,
        "selection-background": \.selectionBackground, "selection-foreground": \.selectionForeground,
    ]
    for raw in text.components(separatedBy: "\n") {
        guard case let (name, value)? = split(raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r")), "=")
        else { continue }
        if let path = keys[name] {
            if let rgb = color(value) { colors[keyPath: path] = rgb }
        } else if name == "palette", case let (index, hex)? = split(value, "="), let n = Int(index),
                  (0...255).contains(n), let rgb = color(hex) {
            colors.palette[n] = rgb
        }
    }
    return colors
}

/// A line split as `splitKeyValue` does; nil for a comment too.
nonisolated private func split(_ line: String, _ separator: Character) -> (String, String)? {
    line.hasPrefix("#") ? nil : splitKeyValue(line, at: separator)
}

nonisolated private func color(_ text: String) -> RGB? {
    let hex = text.hasPrefix("#") ? text.dropFirst() : Substring(text)
    guard hex.count == 6, hex.allSatisfy(\.isHexDigit), let value = UInt32(hex, radix: 16) else { return nil }
    return RGB(value)
}

/// `theme`'s text as the name or path for each appearance, as Ghostty's `Theme.parseCLI`: a value holding `,`, `:` or
/// `=` is a pair, split at commas, each part `light:<x>` or `dark:<x>` trimmed around the colon; anything else is one
/// theme for both. A side a pair leaves out is nil, the fallback, where Ghostty refuses the line, so the other side
/// still works.
nonisolated struct ThemeSpec: Equatable, Sendable {
    var light, dark: String?
    var pair = false

    init(_ text: String) {
        let text = text.trimmingCharacters(in: blanks)
        guard text.contains(where: { ",:=".contains($0) }) else {
            light = text.isEmpty ? nil : text
            dark = light
            return
        }
        pair = true
        for part in text.split(separator: ",") {
            guard case let (side, name)? = split(String(part).trimmingCharacters(in: blanks), ":"), !name.isEmpty
            else { continue }
            if side == "light" { light = name }
            if side == "dark" { dark = name }
        }
    }

    func name(dark: Bool) -> String? { dark ? self.dark : light }
}

/// The folders a name is looked up in, in order: the author's beside the Config, then the bundle's when there is one.
nonisolated func themeFolders(_ location: ConfigLocation, bundle: String?) -> [String] {
    [location.themes] + (bundle.map { [$0] } ?? [])
}

/// The first file a name finds, its path and its text: an absolute path is read as it is; a name with a `/`, or `.` or
/// `..`, finds nothing; else each folder in order, past a file `read` finds nothing in or that is not UTF-8.
nonisolated func lookUpTheme(_ name: String, folders: [String],
                             read: (String) -> Data?) -> (path: String, text: String)? {
    func text(_ path: String) -> String? { read(path).flatMap { String(data: $0, encoding: .utf8) } }
    if name.hasPrefix("/") { return text(name).map { (name, $0) } }
    guard !name.contains("/"), name != ".", name != ".." else { return nil }
    for folder in folders {
        let path = folder + "/" + name
        if let text = text(path) { return (path, text) }
    }
    return nil
}

/// The colours in force for one appearance: the theme laid over the fallback, Terminal.app's Basic and xterm's 16 to
/// 255, with the accent the Session bar and the cards draw with and the red for warnings, for the appearance it was
/// resolved for. The source is the theme's path, nil for the fallback.
nonisolated struct Theme: Equatable, Sendable {
    var background, foreground, cursorColor: RGB
    /// Nil where the text under a block cursor takes the background in force, which a program may change.
    var cursorText, selectionBackground, selectionForeground: RGB?
    var palette: [RGB]
    var accent, red: RGB
    var dark: Bool
    var source: String?

    init(_ colors: ThemeColors = ThemeColors(), dark: Bool, source: String? = nil) {
        let (fg, bg) = fallbackDefaults(dark: dark)
        foreground = colors.foreground ?? fg
        background = colors.background ?? bg
        cursorColor = colors.cursorColor ?? foreground
        cursorText = colors.cursorText
        selectionBackground = colors.selectionBackground
        selectionForeground = colors.selectionForeground
        palette = fallbackPalette.indices.map { colors.palette[$0] ?? fallbackPalette[$0] }
        // The cursor colour, or palette 5 when the theme leaves it out or it is the foreground's.
        accent = (colors.cursorColor == foreground ? nil : colors.cursorColor) ?? palette[5]
        red = colors.palette[1] ?? accent
        self.dark = dark
        self.source = source
    }

    var terminal: TerminalColors {
        TerminalColors(foreground: foreground, background: background, cursor: cursorColor, palette: palette,
                       cursorText: cursorText, selectionBackground: selectionBackground,
                       selectionForeground: selectionForeground, dark: dark)
    }
}

/// `theme`'s text resolved for an appearance; a side found nowhere is the fallback, silently.
nonisolated func resolveTheme(_ spec: ThemeSpec, dark: Bool, folders: [String], read: (String) -> Data?) -> Theme {
    guard let name = spec.name(dark: dark),
          case let (path, text)? = lookUpTheme(name, folders: folders, read: read) else {
        return Theme(dark: dark)
    }
    return Theme(parseTheme(text), dark: dark, source: path)
}
