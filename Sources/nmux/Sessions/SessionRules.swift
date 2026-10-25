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
    /// Nothing: the client runs, it waits for a key already, or nmux is killing the Session.
    case none
    /// The client failed within a second of its start: tmux's error stays on screen and a key retries.
    case wait
    /// The client ended later, as a detach does, while its Session lives: it attaches again.
    case attach
}

nonisolated func clientEnd(exited: Bool, waiting: Bool, killing: Bool, ranFor seconds: TimeInterval) -> ClientEnd {
    if !exited || waiting || killing { return .none }
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

/// Whether nmux checks a move tmux made of a Session's client: a move to its own Session is nmux's own switch back, and
/// a Session being killed is left alone.
nonisolated func checksMove(own: SessionID, target: SessionID, killing: Bool) -> Bool {
    own != target && !killing
}

/// The reasons a quit Apple event carries for a shutdown, a restart and a logout, as Ghostty reads them (`why?`).
nonisolated let systemQuitReasons: Set<UInt32> = [0x7368_7574, 0x7265_7374, 0x726c_676f] // 'shut', 'rest', 'rlgo'

/// Whether a quit asks on the closing card: the Dock's Quit, a quit Apple event with no such reason, does; a shutdown,
/// restart or logout never does, nor do nmux's own quits (SIGTERM, an empty list, a server that is gone, a card's
/// answer).
nonisolated func quitAsks(own: Bool, reason: UInt32?) -> Bool {
    !own && !(reason.map(systemQuitReasons.contains) ?? false)
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

/// The New Session field while it is open: the name last submitted and tmux's refusal of it, if any.
nonisolated struct Draft: Equatable {
    var name = ""
    var error: String?
}

/// What happens to the draft: the field opens, its name is submitted, `create` answers, or the field goes.
nonisolated enum DraftEvent: Equatable {
    case open, submit(String), answer(Created), cancel
}

/// Open keeps a draft and its text, or starts an empty one; a submit drops the old refusal; a new `$ID` or a cancel
/// ends the draft, and a refusal keeps the submitted name with tmux's error. An answer after a cancel changes nothing.
nonisolated func nextDraft(_ draft: Draft?, _ event: DraftEvent) -> Draft? {
    switch event {
    case .open: draft ?? Draft()
    case .submit(let name): draft.map { _ in Draft(name: name) }
    case .answer(.refused(let error)): draft.map { Draft(name: $0.name, error: error) }
    case .answer(.session), .cancel: nil
    }
}
