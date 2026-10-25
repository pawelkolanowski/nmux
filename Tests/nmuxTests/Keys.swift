import AppKit
import Testing
@testable import nmux
@testable import Terminal
import GhosttyVt

// Keys: the app shortcuts, the edit keys, the Option that is Alt, and the keycode table.
private let leftOption = NSEvent.ModifierFlags(
    rawValue: NSEvent.ModifierFlags.option.rawValue | UInt(NX_DEVICELALTKEYMASK))
private let rightOption = NSEvent.ModifierFlags(
    rawValue: NSEvent.ModifierFlags.option.rawValue | UInt(NX_DEVICERALTKEYMASK))
private func alt(_ setting: OptionAsAlt, _ flags: NSEvent.ModifierFlags) -> Bool {
    !translationFlags(flags, setting).contains(.option)
}
private let rightShift = NSEvent.ModifierFlags(
    rawValue: NSEvent.ModifierFlags.shift.rawValue | UInt(NX_DEVICERSHIFTKEYMASK))
private let leftShift = NSEvent.ModifierFlags(
    rawValue: NSEvent.ModifierFlags.shift.rawValue | UInt(NX_DEVICELSHIFTKEYMASK))

struct KeyTests {
    @Test("Cmd+T opens the New Session field") func cmdTOpensTheNewSessionField() {
        #expect(shortcut("t", .command)?.action == .newSession)
    }

    @Test("Cmd+Shift+W closes nmux and Cmd+W the Session") func cmdShiftWClosesNmuxAndCmdWTheSession() {
        #expect(shortcut("w", [.command, .shift])?.action == .closeNmux)
        #expect(shortcut("w", .command)?.action == .closeSession)
    }

    @Test("Cmd+Shift+[ and ] go to the previous and next Session") func cmdShiftAndGoToThePreviousAnd() {
        #expect(shortcut("[", [.command, .shift])?.action == .previousSession)
        #expect(shortcut("]", [.command, .shift])?.action == .nextSession)
    }

    @Test("Cmd+1 to Cmd+8 go to their Session", arguments: 1...8) func cmdNumberGoesToItsSession(number: Int) {
        #expect(shortcut("\(number)", .command)?.action == .session(number))
    }

    @Test("Cmd+9 goes to the last Session") func cmd9GoesToTheLastSession() {
        #expect(shortcut("9", .command)?.action == .lastSession)
    }

    @Test("Cmd+K, Cmd+C, Cmd+V, Cmd+A and Cmd+Q are the app's") func cmdKCmdCCmdVCmdA() {
        #expect(["k", "c", "v", "a", "q"].compactMap { shortcut($0, .command)?.action }
            == [.clear, .copy, .paste, .selectAll, .quit])
    }

    @Test("Cmd+=, Cmd+- and Cmd+0 are not bound") func cmdCmdAndCmd0AreNotBound() {
        #expect(["=", "-", "0"].allSatisfy { shortcut($0, .command) == nil })
    }

    @Test("a shortcut needs exactly its mods") func aShortcutNeedsExactlyItsMods() {
        #expect(shortcut("t", [.command, .option]) == nil)
        #expect(shortcut("t", []) == nil)
    }

    @Test("Caps Lock does not stop a shortcut") func capsLockDoesNotStopAShortcut() {
        #expect(shortcut("t", [.command, .capsLock])?.action == .newSession)
    }

    @Test("the shortcut names are the self-test's") func theShortcutNamesAreTheSelfTests() {
        #expect(shortcuts.map(\.action.name).joined(separator: " ") == "quit copy paste select-all clear new-session "
            + "close-session close-nmux previous-session next-session session-1 session-2 session-3 session-4 "
            + "session-5 session-6 session-7 session-8 last-session")
    }

    @Test("Cmd+Left, Cmd+Right and Cmd+Backspace send Ctrl+A, Ctrl+E and Ctrl+U")
    func cmdLeftCmdRightAndCmdBackspaceSend() {
        #expect(editKey(0x7B, arrows.union(.command)) == [0x01])
        #expect(editKey(0x7C, arrows.union(.command)) == [0x05])
        #expect(editKey(0x33, .command) == [0x15])
    }

    @Test("Option+Left and Option+Right send ESC b and ESC f") func optionLeftAndOptionRightSendEscB() {
        #expect(editKey(0x7B, arrows.union(.option)) == [0x1B, 0x62])
        #expect(editKey(0x7C, arrows.union(.option)) == [0x1B, 0x66])
    }

    @Test("an edit key takes only exactly its mods") func anEditKeyTakesOnlyExactlyItsMods() {
        #expect(editKey(0x7B, arrows.union([.command, .shift])) == nil)
        #expect(editKey(0x7B, arrows) == nil)
        #expect(editKey(0x33, .option) == nil)
    }

    @Test("option-as-alt false leaves both Options to type") func optionAsAltFalseLeavesBothOptionsTo() {
        #expect(!alt(.false, leftOption))
        #expect(!alt(.false, rightOption))
    }

    @Test("option-as-alt true makes both Options Alt") func optionAsAltTrueMakesBothOptionsAlt() {
        #expect(alt(.true, leftOption))
        #expect(alt(.true, rightOption))
    }

    @Test("option-as-alt left makes only the left Option Alt") func optionAsAltLeftMakesOnlyTheLeft() {
        #expect(alt(.left, leftOption))
        #expect(!alt(.left, rightOption))
    }

    @Test("option-as-alt right makes only the right Option Alt") func optionAsAltRightMakesOnlyTheRight() {
        #expect(!alt(.right, leftOption))
        #expect(alt(.right, rightOption))
    }

    @Test("an Option that is Alt keeps its device mask and the other flags") func anOptionThatIsAltKeepsItsDevice() {
        #expect(translationFlags(leftOption.union(.shift), .left)
            == NSEvent.ModifierFlags(rawValue: leftOption.rawValue & ~NSEvent.ModifierFlags.option.rawValue)
                .union(.shift))
    }

    @Test("the right Option is Alt with its side") func theRightOptionIsAltWithItsSide() {
        #expect(ghosttyMods(rightOption) == GhosttyMods(GHOSTTY_MODS_ALT | GHOSTTY_MODS_ALT_SIDE))
    }

    @Test("Control and Command are never consumed") func controlAndCommandAreNeverConsumed() {
        #expect(consumedMods([.control, .command, .capsLock, .shift])
            == GhosttyMods(GHOSTTY_MODS_SHIFT | GHOSTTY_MODS_CAPS_LOCK))
    }

    @Test("a right Shift's change presses it while its own side is held") func aRightShiftsChangePressesItWhileIts() {
        #expect(modifierPressed(GHOSTTY_KEY_SHIFT_RIGHT, rightShift) == true)
        #expect(modifierPressed(GHOSTTY_KEY_SHIFT_RIGHT, leftShift) == false)
    }

    @Test("a left Shift presses with Shift held and releases without") func aLeftShiftPressesWithShiftHeldAnd() {
        #expect(modifierPressed(GHOSTTY_KEY_SHIFT_LEFT, leftShift) == true)
        #expect(modifierPressed(GHOSTTY_KEY_SHIFT_LEFT, []) == false)
    }

    @Test("a key that is no modifier has no modifier change") func aKeyThatIsNoModifierHasNo() {
        #expect(modifierPressed(GHOSTTY_KEY_A, .shift) == nil)
    }

    @Test("a control character's text is its key without Control") func aControlCharactersTextIsItsKeyWithout() {
        #expect(keyText("\u{03}") { "c" } == "c")
    }

    @Test("Escape and Apple's function keys have no text") func escapeAndApplesFunctionKeysHaveNoText() {
        #expect(keyText("\u{1b}") { "\u{1b}" } == nil)
        #expect(keyText("\u{F700}") { nil } == nil)
    }

    @Test("a typed letter is its own text") func aTypedLetterIsItsOwnText() {
        #expect(keyText("ł") { nil } == "ł")
        #expect(keyText(nil) { nil } == nil)
    }

    @Test("the keycode table holds the 110 keys Ghostty maps, each once") func theKeycodeTableHoldsThe110KeysGhostty() {
        #expect(macKeys.count == 110)
        #expect(Set(macKeys.values.map(\.rawValue)).count == 110)
    }

    @Test("the keycode table maps A, Return, Escape, Backspace, Delete, Up, F1 and F12")
    func theKeycodeTableMapsAReturnEscapeBackspace() {
        #expect([0x00, 0x24, 0x35, 0x33, 0x75, 0x7E, 0x7A, 0x6F].map { macKeys[$0]! }
            == [GHOSTTY_KEY_A, GHOSTTY_KEY_ENTER, GHOSTTY_KEY_ESCAPE, GHOSTTY_KEY_BACKSPACE, GHOSTTY_KEY_DELETE,
                GHOSTTY_KEY_ARROW_UP, GHOSTTY_KEY_F1, GHOSTTY_KEY_F12])
    }
}
