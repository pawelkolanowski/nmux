import AppKit
import GhosttyVt

// What a key the text system took sends, and where marked text stands, adapted from Ghostty's `keyDown`,
// `shouldReplayCommittedPreeditKey` and preedit range in `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`
// at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// One thing a key the text system took sends: committed text, or the key itself with its text.
enum Typed: Equatable, Sendable {
    case commit(String)
    case key(text: String?, composing: Bool)

    /// The key itself goes, not composing, so its release goes too.
    var sendsKey: Bool { if case .key(_, false) = self { true } else { false } }
}

/// What a key the text system took sends, from Ghostty's `keyDown`. Text inserted while marked text stood is a commit,
/// and an arrow that committed it goes again bare. Text inserted for a key without composition goes with that key. A
/// key that inserted nothing goes with its own text, composing when marked text stood before it or after. A lone
/// control character while composing is the IME's and goes nowhere.
func sends(markedBefore: Bool, markedAfter: Bool, inserted: [String], characters: String?, text: String?,
                  replays: Bool) -> [Typed] {
    let composing = markedBefore || markedAfter
    func imeOwns(_ t: String?) -> Bool {
        guard composing, let t, t.unicodeScalars.count == 1 else { return false }
        return t.unicodeScalars.first!.value < 0x20
    }
    let kept = inserted.filter { !imeOwns($0) }
    if markedBefore && !inserted.isEmpty {
        return kept.map(Typed.commit) + (replays ? [.key(text: nil, composing: false)] : [])
    }
    if !inserted.isEmpty { return kept.map { .key(text: eventText($0), composing: false) } }
    return imeOwns(characters) ? [] : [.key(text: text, composing: composing)]
}

/// Ghostty's `keyEventText`: none for empty text or text that starts with a control character, which the encoder makes
/// of the key itself.
func eventText(_ text: String) -> String? {
    guard let first = text.unicodeScalars.first, first.value >= 0x20, first.value != 0x7F else { return nil }
    return text
}

/// Ghostty's `shouldReplayCommittedPreeditKey`: Down, Right and Up after a commit still move; a plain Left does not,
/// since AppKit leaves the caret in place after a Korean IME commits.
func replaysAfterCommit(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> Bool {
    switch macKeys[keyCode] {
    case GHOSTTY_KEY_ARROW_DOWN?, GHOSTTY_KEY_ARROW_RIGHT?, GHOSTTY_KEY_ARROW_UP?: true
    case GHOSTTY_KEY_ARROW_LEFT?: !matchedModifiers(flags).isEmpty
    default: false
    }
}

/// Ghostty's preedit range: marked text of these cell widths starts at the cursor's column and moves left as far as the
/// row's end needs. Counted from its end, the codepoint that first passes the room right of the cursor is the first one
/// kept: those before it are dropped. The column it starts at and the codepoints dropped.
func preeditPlace(_ widths: [Int], cursor: Int, cols: Int) -> (start: Int, dropped: Int) {
    let room = cols - cursor
    var w = 0, dropped = 0
    for (i, width) in widths.enumerated().reversed() {
        w += width
        if w > room { dropped = i; break }
    }
    let end = w > 0 ? cursor + w - 1 : cursor
    return (max(cursor - max(end - (cols - 1), 0), 0), dropped)
}
