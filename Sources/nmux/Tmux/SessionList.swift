/// A Session's ID as tmux prints it, `$` and a number; a rename never changes it.
nonisolated struct SessionID: Hashable, CustomStringConvertible {
    let number: Int
    var description: String { "$\(number)" }
}

/// The Session with the lowest `$ID` in `list-sessions -F '#{session_id}'` output, so `$10` comes after `$9`.
nonisolated func lowestSession(_ listOutput: String) -> SessionID? {
    listOutput.split(separator: "\n")
        .compactMap { line in line.hasPrefix("$") ? Int(line.dropFirst()).map(SessionID.init) : nil }
        .min { $0.number < $1.number }
}
