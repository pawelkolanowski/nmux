import Foundation
import Testing
@testable import nmux
@testable import Terminal
import GhosttyVt

// The bytes a terminal's write_pty sent, which its userdata points at.
private final class Pasted { var bytes: [UInt8] = [] }

// The paste, into a fresh terminal whose write_pty keeps the bytes, with bracketed paste on or off in the terminal and
// in the pane behind tmux.
private func pasting(_ text: String, bracketed: Bool, pane: Bool? = nil,
                     allowUnsafe: Bool = false) -> (PasteOutcome, String) {
    let pasted = Pasted()
    var terminal: GhosttyTerminal?
    ghostty_terminal_new(nil, &terminal, 80, 24)
    defer { ghostty_terminal_free(terminal) }
    let keep: GhosttyTerminalWritePtyFn = { _, ud, data, len in
        Unmanaged<Pasted>.fromOpaque(ud!).takeUnretainedValue().bytes += UnsafeBufferPointer(start: data, count: len)
    }
    ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_USERDATA, Unmanaged.passUnretained(pasted).toOpaque())
    ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_WRITE_PTY, unsafeBitCast(keep, to: UnsafeRawPointer.self))
    let mode = Array((bracketed ? "\u{1b}[?2004h" : "\u{1b}[?2004l").utf8)
    ghostty_terminal_vt_write(terminal, mode, mode.count)
    let outcome = pasteText(terminal!, text, paneBracketed: pane ?? bracketed, allowUnsafe: allowUnsafe)
    return withExtendedLifetime(pasted) { (outcome, String(decoding: pasted.bytes, as: UTF8.self)) }
}
// The OSC 52 decision, against a card that answers `answer` and counts the times it showed.
@MainActor
private func gated(_ access: ClipboardAccess, answer: Bool) -> (went: Bool, refused: Bool, asked: Int) {
    var went = false, refused = false, asked = 0
    gate(access, ask: { asked += 1; $0(answer) }, refused: { refused = true }, go: { went = true })
    return (went, refused, asked)
}

@MainActor
struct ClipboardTests {
    @Test("a line without a break pastes as it is") func aLineWithoutABreakPastesAsIt() {
        #expect(pasting("one", bracketed: false) == (.sent, "one"))
    }

    @Test("a newline without bracketed paste is unsafe and sends nothing")
    func aNewlineWithoutBracketedPasteIsUnsafeAnd() {
        #expect(pasting("a\nb", bracketed: false) == (.unsafe, ""))
    }

    @Test("a carriage return without bracketed paste is unsafe too")
    func aCarriageReturnWithoutBracketedPasteIsUnsafe() {
        #expect(pasting("a\rb", bracketed: false) == (.unsafe, ""))
    }

    @Test("an unsafe paste allowed sends its newline as a carriage return")
    func anUnsafePasteAllowedSendsItsNewlineAs() {
        #expect(pasting("a\nb", bracketed: false, allowUnsafe: true) == (.sent, "a\rb"))
    }

    @Test("a newline in a bracketed paste is safe and goes wrapped") func aNewlineInABracketedPasteIsSafe() {
        #expect(pasting("a\nb", bracketed: true) == (.sent, "\u{1b}[200~a\nb\u{1b}[201~"))
    }

    @Test("a newline is unsafe when tmux's client is bracketed but the pane is not")
    func aNewlineIsUnsafeWhenTmuxsClientIs() {
        #expect(pasting("a\nb", bracketed: true, pane: false) == (.unsafe, ""))
    }

    @Test("a confirmed paste through tmux goes bracketed, for tmux to unwrap")
    func aConfirmedPasteThroughTmuxGoesBracketedFor() {
        #expect(pasting("a\nb", bracketed: true, pane: false, allowUnsafe: true)
            == (.sent, "\u{1b}[200~a\nb\u{1b}[201~"))
    }

    @Test("the bracket end sequence in a bracketed paste is unsafe") func theBracketEndSequenceInABracketedPaste() {
        #expect(pasting("a\u{1b}[201~b", bracketed: true) == (.unsafe, ""))
    }

    @Test("an empty text pastes nothing") func anEmptyTextPastesNothing() {
        #expect(pasting("", bracketed: false) == (.empty, ""))
    }

    @Test("allow goes on with no card") func allowGoesOnWithNoCard() {
        #expect(gated(.allow, answer: false) == (true, false, 0))
    }

    @Test("deny refuses with no card") func denyRefusesWithNoCard() {
        #expect(gated(.deny, answer: true) == (false, true, 0))
    }

    @Test("ask goes on after the card's yes") func askGoesOnAfterTheCardsYes() {
        #expect(gated(.ask, answer: true) == (true, false, 1))
    }

    @Test("ask refuses after the card's no") func askRefusesAfterTheCardsNo() {
        #expect(gated(.ask, answer: false) == (false, true, 1))
    }

    @Test("the write card's excerpt leaves out a final line break") func theWriteCardsExcerptLeavesOutAFinal() {
        #expect(writeCard("hi\n").excerpt == "hi")
    }

    @Test("the OSC 52 reply carries the text in base64, ended by ST") func theOsc52ReplyCarriesTheTextIn() {
        #expect(osc52Reply("hi") == Array("\u{1b}]52;c;aGk=\u{1b}\\".utf8))
    }

    @Test("the paste card counts the lines, a final line break not counting") func thePasteCardCountsTheLinesAFinal() {
        #expect(pasteCard("a\nb\n").title == "Paste 2 lines?")
        #expect(pasteCard("a\nb\n").excerpt == "a\nb")
        #expect(pasteCard("a\r\n").title == "Paste 1 line?")
    }

    @Test("the paste card keeps five lines and marks the rest") func thePasteCardKeepsFiveLinesAndMarks() {
        #expect(pasteCard((1...7).map(String.init).joined(separator: "\n")).excerpt == "1\n2\n3\n4\n5\n…")
    }

    @Test("the paste card cuts a long line") func thePasteCardCutsALongLine() {
        #expect(pasteCard(String(repeating: "x", count: 200) + "\n").excerpt
            == String(repeating: "x", count: 120) + "…")
    }

    @Test("Paste is the paste card's default and Cancel its dismissal") func pasteIsThePasteCardsDefaultAndCancel() {
        #expect(pasteCard("a\nb").defaultAction == .paste)
        #expect(pasteCard("a\nb").escape == .cancel)
    }

    @Test("the read card has Deny first, as its default and its dismissal") func theReadCardHasDenyFirstAsIts() {
        #expect(readCard.actions.first == .deny)
        #expect(readCard.defaultAction == .deny)
        #expect(readCard.escape == .deny)
    }

    @Test("the write card has Deny first and as its default") func theWriteCardHasDenyFirstAndAs() {
        #expect(writeCard("hi").actions.first == .deny)
        #expect(writeCard("hi").defaultAction == .deny)
    }

    @Test("a launch card keeps Restart as its default and Quit for Escape") func aLaunchCardKeepsRestartAsItsDefault() {
        #expect(quitRestart.last == .restart)
        #expect(CardState(kind: .server, title: "x", actions: quitRestart).escape == .quit)
    }
}
