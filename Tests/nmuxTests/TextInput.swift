import AppKit
import Testing
@testable import nmux
@testable import Terminal

// Text input: what a key the text system took sends, from the marked text before and after and the texts inserted.
private func outcome(_ before: Bool, _ after: Bool, _ inserted: [String], _ chars: String? = "e",
                     replays: Bool = false) -> [Typed] {
    sends(markedBefore: before, markedAfter: after, inserted: inserted, characters: chars, text: chars,
          replays: replays)
}

struct TextInputTests {
    @Test("a dead key composes and sends nothing of its own") func aDeadKeyComposesAndSendsNothingOf() {
        #expect(outcome(false, true, []) == [.key(text: "e", composing: true)])
    }

    @Test("a dead key's letter commits the composed text") func aDeadKeysLetterCommitsTheComposedText() {
        #expect(outcome(true, false, ["é"]) == [.commit("é")])
    }

    @Test("a key with text and no composition goes with that text") func aKeyWithTextAndNoCompositionGoes() {
        #expect(outcome(false, false, ["ł"]) == [.key(text: "ł", composing: false)])
    }

    @Test("a key that inserted nothing and composed nothing goes bare")
    func aKeyThatInsertedNothingAndComposedNothing() {
        #expect(outcome(false, false, []) == [.key(text: "e", composing: false)])
    }

    @Test("Escape that cancels a composition is the IME's") func escapeThatCancelsACompositionIsTheImes() {
        #expect(outcome(true, false, [], "\u{1b}").isEmpty)
    }

    @Test("a lone control character inserted while composing is never sent")
    func aLoneControlCharacterInsertedWhileComposingIs() {
        #expect(outcome(true, false, ["\u{8}"]).isEmpty)
    }

    @Test("an inserted control character without composition goes as its key")
    func anInsertedControlCharacterWithoutCompositionGoesAs() {
        #expect(outcome(false, false, ["\u{3}"]) == [.key(text: nil, composing: false)])
    }

    @Test("an arrow that commits goes again bare") func anArrowThatCommitsGoesAgainBare() {
        #expect(outcome(true, false, ["日本"], replays: true) == [.commit("日本"), .key(text: nil, composing: false)])
    }

    @Test("Down, Right and Up replay after a commit, a plain Left does not") func downRightAndUpReplayAfterACommit() {
        #expect([0x7D, 0x7C, 0x7E].allSatisfy { replaysAfterCommit($0, arrows) })
        #expect(!replaysAfterCommit(0x7B, arrows))
        #expect(replaysAfterCommit(0x7B, arrows.union(.shift)))
        #expect(!replaysAfterCommit(0x24, []))
    }

    @Test("only the key itself takes its release") func onlyTheKeyItselfTakesItsRelease() {
        #expect(Typed.key(text: nil, composing: false).sendsKey)
        #expect(!Typed.key(text: "e", composing: true).sendsKey)
        #expect(!Typed.commit("é").sendsKey)
    }

    @Test("marked text starts at the cursor when it fits") func markedTextStartsAtTheCursorWhenIt() {
        #expect(preeditPlace([1, 2], cursor: 3, cols: 10) == (3, 0))
    }

    @Test("marked text at the row's end moves left") func markedTextAtTheRowsEndMovesLeft() {
        #expect(preeditPlace([2, 2], cursor: 8, cols: 10) == (6, 0))
    }

    @Test("marked text one codepoint past the room moves left by what does not fit")
    func markedTextOneCodepointPastTheRoomMoves() {
        #expect(preeditPlace([1, 1, 1, 1], cursor: 7, cols: 10) == (6, 0))
    }

    @Test("marked text further past the room drops its first codepoints, as Ghostty's range")
    func markedTextFurtherPastTheRoomDropsIts() {
        #expect(preeditPlace([1, 1, 1, 1, 1], cursor: 7, cols: 10) == (6, 1))
    }
}
