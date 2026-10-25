import Foundation
import GhosttyVt

// The clipboard's parts that need no window: a paste through libghostty-vt's `ghostty_terminal_paste`, which brackets
// it under mode 2004, guarded by Ghostty's unsafe-paste rule, and the OSC 52 reply, adapted from Ghostty's
// `completeClipboardPaste` and `completeClipboardReadOSC52` in `src/Surface.zig` at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// `clipboard-write` and `clipboard-read`: what an OSC 52 write or read does.
public enum ClipboardAccess: String, Sendable {
    case allow, deny, ask
}

/// What the view asks the author before it goes on: an unsafe paste with its text, an OSC 52 read, an OSC 52 write with
/// its text.
public enum ClipboardAsk: Sendable {
    case paste(String), read, write(String)
}

enum PasteOutcome: Equatable, Sendable {
    case sent
    /// A line break, or the bracket end sequence, that could run a command: nothing went.
    case unsafe
    /// No text to paste, or libghostty-vt could not paste it.
    case empty
}

/// Pastes `text` into the terminal, whose write_pty callback takes the bytes; call with the terminal locked. tmux turns
/// bracketed paste on in its client whatever the pane asked, to tell a paste from typed keys, and drops the brackets
/// for a pane that never asked for them, so `paneBracketed`, the pane's own mode, decides whether a line break is safe;
/// the terminal's mode still frames the bytes and refuses the bracket end sequence.
func pasteText(_ terminal: GhosttyTerminal, _ text: String, paneBracketed: Bool, allowUnsafe: Bool) -> PasteOutcome {
    if !allowUnsafe, !paneBracketed, !ghostty_paste_is_safe(text, text.utf8.count) { return .unsafe }
    let read: GhosttyMimeReaderFn = { ud, _, writer in
        let bytes = ud!.assumingMemoryBound(to: UnsafeBufferPointer<UInt8>.self).pointee
        return bytes.isEmpty || writer.write?(writer.userdata, bytes.baseAddress, bytes.count) == true
    }
    var written = false
    let result = Array(text.utf8).withUnsafeBufferPointer { bytes in
        var bytes = bytes
        return Array("text/plain".utf8).withUnsafeBufferPointer { mime in
            var mimes = GhosttyString(ptr: mime.baseAddress, len: mime.count)
            return withUnsafePointer(to: &mimes) { mimes in
                withUnsafeMutablePointer(to: &bytes) { ud in
                    var paste = GhosttyPaste(size: MemoryLayout<GhosttyPaste>.size,
                                             location: GHOSTTY_CLIPBOARD_LOCATION_STANDARD,
                                             source: GHOSTTY_PASTE_SOURCE_CLIPBOARD, mimes: mimes, mimes_len: 1,
                                             reader: GhosttyMimeReader(read: read, userdata: ud),
                                             allow_unsafe: allowUnsafe)
                    return ghostty_terminal_paste(terminal, &paste, &written)
                }
            }
        }
    }
    if result == GHOSTTY_REJECTED { return .unsafe }
    return result == GHOSTTY_SUCCESS && written ? .sent : .empty
}

/// The OSC 52 reply that hands a program the standard clipboard's text, ended by ST as Ghostty ends it.
func osc52Reply(_ text: String) -> [UInt8] {
    Array("\u{1b}]52;c;\(Data(text.utf8).base64EncodedString())\u{1b}\\".utf8)
}

/// An OSC 52 request under its setting: `go` runs under allow and after a yes under ask, `refused` under deny and after
/// a no. `ask` shows the card and calls back with the answer.
@MainActor
func gate(_ access: ClipboardAccess, ask: (@escaping @MainActor (Bool) -> Void) -> Void,
          refused: @escaping @MainActor () -> Void, go: @escaping @MainActor () -> Void) {
    switch access {
    case .allow: go()
    case .deny: refused()
    case .ask: ask { $0 ? go() : refused() }
    }
}
