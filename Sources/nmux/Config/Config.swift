import Foundation
import Terminal

/// nmux's own small Config, not Ghostty's, since the terminal passes every key on: eleven keys in Ghostty's
/// `key = value` syntax, every one with its default. `font-family` keeps its text; the face falls back to SF Mono where
/// it is made. `theme` keeps its text for the lookup.
nonisolated struct Config: Equatable, Sendable {
    var theme = "Fuwafuwa Sakura"
    var fontFamily = "SF Mono"
    var fontSize = 14.0
    var fontThicken = false
    var optionAsAlt = OptionAsAlt.false
    var pillWidth = 136.0
    var backgroundOpacity = 1.0
    var backgroundBlur = 0
    var copyOnSelect = false
    var clipboardWrite = ClipboardAccess.allow
    var clipboardRead = ClipboardAccess.ask
}

/// A line nmux skipped: its number from 1, its trimmed text and why. A file that is not UTF-8 is one problem on line 0.
nonisolated struct ConfigProblem: Equatable, Sendable {
    let line: Int
    let text: String
    let reason: String
}

/// Where the Config and the author's themes live: `$XDG_CONFIG_HOME/nmux` when that is set and not empty, else
/// `~/.config/nmux`. nmux makes it once, at launch.
nonisolated struct ConfigLocation: Equatable {
    let folder: String
    /// Whether `XDG_CONFIG_HOME` named the folder.
    let fromXDG: Bool

    init(xdg: String?, home: String) {
        let xdg = xdg.flatMap { $0.isEmpty ? nil : $0 }
        (folder, fromXDG) = ((xdg ?? home + "/.config") + "/nmux", xdg != nil)
    }

    /// The environment's, at launch.
    static let current = ConfigLocation(xdg: ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
                                        home: FileManager.default.homeDirectoryForCurrentUser.path)

    var config: String { folder + "/config" }
    var themes: String { folder + "/themes" }
}

/// The file's bytes, nil when it is missing or cannot be read, as the settings in force and the lines skipped.
nonisolated func readConfig(_ data: Data?, exists: Bool = false) -> (Config, [ConfigProblem]) {
    guard let data else { return (Config(), exists ? [ConfigProblem(line: 0, text: "", reason: "cannot read")] : []) }
    guard let text = String(data: data, encoding: .utf8)
    else { return (Config(), [ConfigProblem(line: 0, text: "", reason: "not UTF-8")]) }
    return parseConfig(text)
}

/// Ghostty's syntax (`src/cli/args.zig` at 22f100c6, MIT): each line trimmed, a blank line or a `#` comment skipped,
/// the key and the value split at the first `=` and trimmed, a value in double quotes read without them, the last good
/// line of a key winning. An empty value sets the key back to its default. A line without `=` is a problem, where
/// Ghostty reads a bare key as a flag.
nonisolated func parseConfig(_ text: String) -> (Config, [ConfigProblem]) {
    var config = Config(), problems: [ConfigProblem] = []
    // By UTF-16 unit, so a CRLF splits at its LF as in Ghostty; a Character holds CRLF whole.
    for (i, raw) in text.components(separatedBy: "\n").enumerated() {
        let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
        if line.isEmpty || line.hasPrefix("#") { continue }
        func skip(_ reason: String) { problems.append(ConfigProblem(line: i + 1, text: line, reason: reason)) }
        guard let (name, value) = splitKeyValue(line, at: "=") else {
            skip("no '='")
            continue
        }
        guard let key = configKeys.first(where: { $0.name == name }) else {
            skip("unknown key")
            continue
        }
        if let reason = key.apply(&config, value) { skip(reason) }
    }
    return (config, problems)
}

/// Every key with its value in force, `key=value`, in the table's order, as the self-test logs them.
nonisolated func configLines(_ config: Config) -> [String] {
    configKeys.map { "\($0.name)=\($0.show(config))" }
}

nonisolated private struct ConfigKey: Sendable {
    let name: String
    /// Sets the value and returns nil, or returns the reason and leaves the config as it was.
    let apply: @Sendable (inout Config, String) -> String?
    let show: @Sendable (Config) -> String
}

nonisolated private func key<T>(_ name: String, _ path: WritableKeyPath<Config, T> & Sendable, _ reason: String,
                    show: @escaping @Sendable (T) -> String, parse: @escaping @Sendable (String) -> T?) -> ConfigKey {
    ConfigKey(name: name, apply: { config, value in
        guard !value.isEmpty else {
            config[keyPath: path] = Config()[keyPath: path]
            return nil
        }
        guard let parsed = parse(value) else { return reason }
        config[keyPath: path] = parsed
        return nil
    }, show: { show($0[keyPath: path]) })
}

/// Ghostty's `parseBool`.
nonisolated private func bool(_ value: String) -> Bool? {
    if ["1", "t", "T", "true"].contains(value) { return true }
    if ["0", "f", "F", "false"].contains(value) { return false }
    return nil
}

nonisolated private func number(_ value: String, _ range: ClosedRange<Double>) -> Double? {
    Double(value).flatMap { range.contains($0) ? $0 : nil }
}

nonisolated private func show(_ value: Double) -> String { String(format: "%g", value) }
nonisolated private func show(_ value: Bool) -> String { "\(value)" }

nonisolated private let trueOrFalse = "expects true or false"

// Where nmux differs from a plain range: `font-size` has no upper bound, `background-opacity` clamps any number, and
// `background-blur` takes a boolean or a radius.

nonisolated private let configKeys: [ConfigKey] = [
    key("theme", \.theme, "", show: { $0 }, parse: { $0 }),
    key("font-family", \.fontFamily, "", show: { $0 }, parse: { $0 }),
    key("font-size", \.fontSize, "expects a number above 0", show: show,
        parse: { Double($0).flatMap { $0 > 0 && $0.isFinite ? $0 : nil } }),
    key("font-thicken", \.fontThicken, trueOrFalse, show: show, parse: bool),
    key("option-as-alt", \.optionAsAlt, "expects one of false, true, left, right", show: \.rawValue,
        parse: OptionAsAlt.init),
    key("pill-width", \.pillWidth, "expects a number from 60 to 400", show: show, parse: { number($0, 60...400) }),
    // Clamped, as Ghostty does, so only a value that is not a number is a problem.
    key("background-opacity", \.backgroundOpacity, "expects a number", show: show,
        parse: { Double($0).flatMap { $0.isNaN ? nil : min(max($0, 0), 1) } }),
    key("background-blur", \.backgroundBlur, "expects true, false or a number from 0 to 100", show: { "\($0)" },
        parse: { value in
            bool(value).map { $0 ? 20 : 0 } ?? Int(value).flatMap { (0...100).contains($0) ? $0 : nil }
        }),
    key("copy-on-select", \.copyOnSelect, trueOrFalse, show: show, parse: bool),
    key("clipboard-write", \.clipboardWrite, "expects one of allow, deny, ask", show: \.rawValue,
        parse: ClipboardAccess.init),
    key("clipboard-read", \.clipboardRead, "expects one of allow, deny, ask", show: \.rawValue,
        parse: ClipboardAccess.init),
]
