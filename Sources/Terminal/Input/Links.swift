import Foundation
import UniformTypeIdentifiers

// Links: URL detection, the scheme branch of Ghostty's `src/config/url.zig`, and which targets open, from
// `macos/Sources/Helpers/UntrustedURL.swift`, at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// Ghostty's scheme URLs: no trailing `.` or `,`, and a `)` only with its `(`. Paths, its other two branches, need the
/// pane's directory, which tmux keeps.
/// limitation: scheme URLs only, upgrade when nmux knows a pane's directory.
private let urlPattern = try! NSRegularExpression(pattern:
    #"(?:https?://|mailto:|ftp://|file:|ssh:|git://|ssh://|tel:|magnet:|ipfs://|ipns://|gemini://|gopher://|news:)"#
    + #"(?:(?:\[[:0-9a-fA-F]+(?:[:0-9a-fA-F]*)+\](?::[0-9]+)?)|[\w\-.~:/?#@!$&*+,;=%]+(?:[\(\[]\w*[\)\]])?)+(?<![,.])"#)

/// The cells of the URL that covers cell `x`, from a row's cells as text, one string a cell, empty for the tail of a
/// wide one.
func urlCells(_ row: [String], at x: Int) -> Range<Int>? {
    var starts: [Int] = [], text = ""
    for cell in row {
        starts.append(text.utf16.count)
        text += cell
    }
    starts.append(text.utf16.count)
    for match in urlPattern.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)) {
        let first = starts.lastIndex { $0 <= match.range.location }!
        let end = starts.firstIndex { $0 >= match.range.location + match.range.length }!
        if (first..<end).contains(x) { return first..<end }
    }
    return nil
}

/// The URL to open for a target printed in the terminal, or nil when Ghostty would not open it as it is: http and https
/// with a host, mailto with an address, and a local file or directory that cannot run code.
/// limitation: Ghostty asks before a custom scheme; nmux opens none, upgrade when a card can ask.
func openable(_ target: String) -> URL? {
    guard !target.unicodeScalars.contains(where: unsafeScalar), let url = URL(string: target),
          let scheme = url.scheme?.lowercased() else { return nil }
    switch scheme {
    case "http", "https": return url.host?.isEmpty == false ? url : nil
    case "mailto": return URLComponents(url: url, resolvingAgainstBaseURL: false)?.path.isEmpty == false ? url : nil
    case "file": return openableFile(url)
    default: return nil
    }
}

private func openableFile(_ url: URL) -> URL? {
    guard url.isFileURL, url.query == nil, url.fragment == nil else { return nil }
    if let host = url.host, !host.isEmpty, host.caseInsensitiveCompare("localhost") != .orderedSame { return nil }
    let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
    guard let values = try? canonical.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isExecutableKey,
                                                               .isRegularFileKey]),
          values.isDirectory == true || values.isRegularFile == true,
          !unsafeExtensions.contains(canonical.pathExtension.lowercased()),
          !(values.contentType.map { t in
              [UTType.application, .executable, .script].contains { t.conforms(to: $0) }
          } ?? false),
          values.isDirectory == true || values.isExecutable != true else { return nil }
    return canonical
}

private let unsafeExtensions: Set<String> = ["action", "app", "applescript", "class", "command", "desktop", "inetloc",
                                             "jar", "mobileconfig", "mpkg", "pkg", "scpt", "terminal", "tool", "url",
                                             "webloc", "workflow"]

/// Controls, and the invisible or reordering marks that could hide part of a target.
private func unsafeScalar(_ s: Unicode.Scalar) -> Bool {
    switch s.value {
    case 0x00...0x1F, 0x7F...0x9F, 0x061C, 0x200B...0x200F, 0x202A...0x202E, 0x2066...0x2069, 0x2028...0x2029,
         0x2060, 0xFEFF: true
    default: false
    }
}
