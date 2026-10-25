/// A Session's ID as tmux prints it, `$` and a number; a rename never changes it.
nonisolated struct SessionID: Hashable, CustomStringConvertible {
    let number: Int
    var description: String { "$\(number)" }
}

/// A Session as `list-sessions -F sessionFormat` gives it.
nonisolated struct SessionInfo: Equatable {
    let id: SessionID
    let name: String
}

nonisolated let sessionFormat = "#{session_id} #{session_name}"

/// The Sessions in `list-sessions -F sessionFormat` lines, ordered by the number after `$`, so a new one lands last and
/// `$10` comes after `$9`. A name may hold spaces.
nonisolated func parseSessions(_ lines: [String]) -> [SessionInfo] {
    lines.compactMap { line in
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts[0].hasPrefix("$"), let number = Int(parts[0].dropFirst()) else { return nil }
        return SessionInfo(id: SessionID(number: number), name: parts.count > 1 ? String(parts[1]) : "")
    }.sorted { $0.id.number < $1.id.number }
}

/// The Session with the lowest `$ID` in `list-sessions -F '#{session_id}'` output, so `$10` comes after `$9`.
nonisolated func lowestSession(_ listOutput: String) -> SessionID? {
    listOutput.split(separator: "\n")
        .compactMap { line in line.hasPrefix("$") ? Int(line.dropFirst()).map(SessionID.init) : nil }
        .min { $0.number < $1.number }
}

/// What a new list changed against the old one, by `$ID`. The new list itself is the new order.
nonisolated struct SessionChanges: Equatable {
    var added: [SessionInfo] = []
    var renamed: [SessionInfo] = []
    var removed: [SessionID] = []
}

nonisolated func sessionChanges(from old: [SessionInfo], to new: [SessionInfo]) -> SessionChanges {
    let before = Dictionary(old.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    let after = Set(new.map(\.id))
    return SessionChanges(added: new.filter { before[$0.id] == nil },
                          renamed: new.filter { s in before[s.id].map { $0 != s.name } ?? false },
                          removed: old.map(\.id).filter { !after.contains($0) })
}

/// `%client-session-changed <client> <$id> <name>`: the client's name, its tty for a terminal client, and the Session
/// it now shows. Nil for any other line.
nonisolated func clientSessionChanged(_ line: String) -> (client: String, info: SessionInfo)? {
    let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
    guard parts.count >= 3, parts[0] == "%client-session-changed", parts[2].hasPrefix("$"),
          let number = Int(parts[2].dropFirst()) else { return nil }
    return (String(parts[1]), SessionInfo(id: SessionID(number: number), name: parts.count > 3 ? String(parts[3]) : ""))
}
