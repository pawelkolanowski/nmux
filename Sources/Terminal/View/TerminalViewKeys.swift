import AppKit
import Carbon
import GhosttyVt

// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The view's keys, adapted from Ghostty's `keyDown`, `keyUp`, `flagsChanged` and `keyAction` in
/// `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` at commit 22f100c6. An app shortcut answers first, an
/// edit key next, and every other key goes through the text system, then to the Session's PTY through libghostty-vt's
/// key encoder.
extension TerminalView {
    public override var acceptsFirstResponder: Bool { true }

    /// A synthetic Cmd key in the self-test skips `performKeyEquivalent` and lands here, as an unhandled real one does.
    /// A key a shortcut or an edit key took keeps its release from the encoder too, as Ghostty's consumed keys do.
    public override func keyDown(with event: NSEvent) {
        if shortcut(event) {
            taken.insert(event.keyCode)
            return
        }
        if onKeyDown() {
            taken.insert(event.keyCode)
            return
        }
        if let bytes = editKey(event.keyCode, event.modifierFlags) {
            taken.insert(event.keyCode)
            return send(event, bytes)
        }
        // An Option that is Alt reaches the layout without Option, so the text is the key's own. The event itself goes
        // to the text system when no Option went, as Ghostty reuses it: Korean input needs that one.
        let flags = translationFlags(event.modifierFlags, optionAsAlt)
        let translation = flags == event.modifierFlags ? event : NSEvent.keyEvent(
            with: event.type, location: event.locationInWindow, modifierFlags: flags, timestamp: event.timestamp,
            windowNumber: event.windowNumber, context: nil,
            characters: event.characters(byApplyingModifiers: flags) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "", isARepeat: event.isARepeat,
            keyCode: event.keyCode) ?? event
        let text = keyText(translation.characters) {
            translation.characters(byApplyingModifiers: flags.subtracting(.control))
        }
        let markedBefore = !markedText.isEmpty
        // A key that switches the keyboard layout is the input method's, never the program's.
        let layoutBefore = markedBefore ? nil : keyboardLayout()
        inserted = []
#if NMUX_SELFTEST
        if observer?.textSystem(translation) != true { interpretKeyEvents([translation]) }
#else
        interpretKeyEvents([translation])
#endif
        let texts = inserted ?? []
        inserted = nil
        if !markedBefore && layoutBefore != keyboardLayout() { return }
        let action = event.isARepeat ? GHOSTTY_KEY_ACTION_REPEAT : GHOSTTY_KEY_ACTION_PRESS
        let out = sends(markedBefore: markedBefore, markedAfter: !markedText.isEmpty, inserted: texts,
                        characters: event.characters, text: text, replays: replaysAfterCommit(event.keyCode, flags))
        // A key whose press only composed or committed keeps its release from the encoder too.
        if !out.contains(where: \.sendsKey) { taken.insert(event.keyCode) }
        for send in out {
            switch send {
            case .commit(let t): commit(action, t)
            case .key(let t, let composing):
                key(action, event, consumed: consumedMods(flags), text: t, composing: composing)
            }
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard taken.remove(event.keyCode) == nil else { return }
        key(GHOSTTY_KEY_ACTION_RELEASE, event, consumed: consumedMods(event.modifierFlags), text: nil)
    }

    /// A modifier's own press or release, for programs that read them; the side pressed decides which, as in Ghostty.
    public override func flagsChanged(with event: NSEvent) {
        modsChanged(event.modifierFlags)
        guard let key = macKeys[event.keyCode], let pressed = modifierPressed(key, event.modifierFlags) else { return }
        self.key(pressed ? GHOSTTY_KEY_ACTION_PRESS : GHOSTTY_KEY_ACTION_RELEASE, event,
                 consumed: consumedMods(event.modifierFlags), text: nil)
    }

    /// The encoder takes the terminal's modes before every key, then `option-as-alt` again, since the sync resets it.
    private func key(_ action: GhosttyKeyAction, _ event: NSEvent, consumed: GhosttyMods, text: String?,
                     composing: Bool = false) {
        // The codepoint with no modifiers at all; a modifier's own event has none.
        let unshifted = event.type == .flagsChanged
            ? 0 : event.characters(byApplyingModifiers: [])?.unicodeScalars.first?.value ?? 0
        let bytes = keys.encode(host, optionAsAlt: optionAsAlt, action: action,
                                key: macKeys[event.keyCode] ?? GHOSTTY_KEY_UNIDENTIFIED,
                                mods: ghosttyMods(event.modifierFlags), consumed: consumed, unshifted: unshifted,
                                text: text, composing: composing)
        // A press always reaches the log, so a key the encoder makes nothing of still shows it got there.
        guard action != GHOSTTY_KEY_ACTION_RELEASE || !bytes.isEmpty else { return }
        send(event, bytes)
    }

    /// Committed text goes as typed text, never as a paste: a key with no mods and keycode 0, which Ghostty's embedded
    /// runtime maps to the physical key it names, A on a Mac.
    func commit(_ action: GhosttyKeyAction, _ text: String) {
        let bytes = keys.encode(host, optionAsAlt: optionAsAlt, action: action,
                                key: macKeys[0] ?? GHOSTTY_KEY_UNIDENTIFIED, mods: 0, consumed: 0, unshifted: 0,
                                text: text)
        if !bytes.isEmpty {
            host.send(bytes)
            dropSelection()
        }
#if NMUX_SELFTEST
        observer?.committed(text)
#endif
    }

    /// A key pressed that sends bytes drops the selection, as Ghostty's `selection-clear-on-typing`, true by default; a
    /// release or a modifier's own event keeps it.
    private func send(_ event: NSEvent, _ bytes: [UInt8]) {
        if !bytes.isEmpty { host.send(bytes) }
        if !bytes.isEmpty, event.type == .keyDown { dropSelection() }
#if NMUX_SELFTEST
        observer?.key(event.keyCode, ghosttyMods(event.modifierFlags), bytes)
#endif
    }
}

/// The current keyboard layout's input source id, Ghostty's `KeyboardLayout.id`.
private func keyboardLayout() -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(id).takeUnretainedValue() as String
}
