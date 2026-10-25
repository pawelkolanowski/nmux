import Foundation

/// A move among the Sessions, as the Session shortcuts send it: the n-th Session from 1, the last, the previous or the
/// next.
nonisolated enum SessionMove: Equatable {
    case number(Int), last, previous, next
}

/// The index a move lands on among `count` Sessions from the shown one: a number past the count is the last, and
/// previous and next wrap at the ends.
nonisolated func sessionIndex(_ move: SessionMove, active: Int, count: Int) -> Int {
    switch move {
    case .number(let n): min(max(n, 1), count) - 1
    case .last: count - 1
    case .previous: (active - 1 + count) % count
    case .next: (active + 1) % count
    }
}

/// The shown Session's index in the new list: the same Session while it lives, else the one now at its old index, else
/// the last. Nil when no Session is left.
nonisolated func activeIndex(old: [SessionID], new: [SessionID], active: SessionID) -> Int? {
    guard !new.isEmpty else { return nil }
    if let kept = new.firstIndex(of: active) { return kept }
    return min(old.firstIndex(of: active) ?? new.count, new.count - 1)
}

/// What a listed Session does once its client exits.
nonisolated enum ClientEnd: Equatable {
    /// Nothing: the client runs, or it waits for a key already.
    case none
    /// The client failed within a second of its start: tmux's error stays on screen and a key retries.
    case wait
    /// The client ended later, as a detach does, while its Session lives: it attaches again.
    case attach
}

nonisolated func clientEnd(exited: Bool, waiting: Bool, ranFor seconds: TimeInterval) -> ClientEnd {
    if !exited || waiting { return .none }
    return seconds < 1 ? .wait : .attach
}

/// `new-session -d [-s <name>] -P -F '#{session_id}'` for a name; an empty one leaves `-s` out, so tmux numbers the
/// Session. The name goes in single quotes, as a control client's command is parsed like a shell's, and a line break
/// becomes a space, or tmux would read two commands and send two answers.
nonisolated func createCommand(_ name: String) -> String {
    let line = String(name.map { $0.isNewline ? " " : $0 })
    let named = line.isEmpty ? "" : " -s '\(line.replacingOccurrences(of: "'", with: #"'\''"#))'"
    return "new-session -d\(named) -P -F '#{session_id}'"
}

/// What `create` hands back: the new Session, or tmux's refusal for the New Session field.
nonisolated enum Created: Equatable {
    case session(SessionID)
    case refused(String)
}

/// The answer to `createCommand` over the control client: its `$ID` line, or the error tmux wrote, trimmed.
nonisolated func created(ok: Bool, lines: [String]) -> Created {
    if ok, let id = lowestSession(lines.joined(separator: "\n")) { return .session(id) }
    let error = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return .refused(ok || error.isEmpty ? "tmux did not create the Session." : error)
}

/// What a bell does: a Session that is not shown takes the Bell mark, and while nmux is not the front app the Dock icon
/// bounces, unless it already bounced since nmux was last active.
nonisolated struct Bell: Equatable {
    var mark: Bool
    var attention: Bool
}

nonisolated func bell(active: Bool, front: Bool, bouncedSinceActive: Bool) -> Bell {
    Bell(mark: !active, attention: !front && !bouncedSinceActive)
}
