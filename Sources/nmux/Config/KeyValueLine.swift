import Foundation

/// Ghostty's `whitespace`: a space and a tab, never a no-break space.
nonisolated let blanks = CharacterSet(charactersIn: " \t")

/// A line of Ghostty's `key = value` syntax split at its first separator, the key and the value trimmed of blanks and
/// the value read without the double quotes around it; nil for a line without the separator. The Config and the themes
/// share it, as Ghostty's `src/cli/args.zig` at commit 22f100c6 reads both.
nonisolated func splitKeyValue(_ line: String, at separator: Character) -> (key: String, value: String)? {
    guard let at = line.firstIndex(of: separator) else { return nil }
    var value = line[line.index(after: at)...].trimmingCharacters(in: blanks)
    if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
    return (line[..<at].trimmingCharacters(in: blanks), value)
}
