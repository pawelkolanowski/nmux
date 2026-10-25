import AppKit

// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// Paste and OSC 52, adapted from Ghostty's `completeClipboardPaste`, `clipboardWrite` and `completeClipboardReadOSC52`
/// in `src/Surface.zig` at commit 22f100c6. A paste keeps the selection, as Ghostty's does; an unsafe one, a write
/// under `ask` and a read under `ask` wait for the author's answer on a card.
extension TerminalView {
    /// The pasteboard's text into the active pane, which turned bracketed paste on or not; a pasteboard without text,
    /// such as one holding an image, pastes nothing.
    public func paste(paneBracketed: Bool) {
        guard let text = pasteboard.string(forType: .string) else { return }
        paste(text, paneBracketed: paneBracketed, allowUnsafe: false)
    }

    /// A confirmed paste sends the text the card showed.
    private func paste(_ text: String, paneBracketed: Bool, allowUnsafe: Bool) {
        switch host.paste(text, paneBracketed: paneBracketed, allowUnsafe: allowUnsafe) {
        case .sent:
#if NMUX_SELFTEST
            observer?.pasted(text, bracketed: paneBracketed)
#endif
            break
        case .unsafe:
            askClipboard(.paste(text)) { [weak self] yes in
                if yes { self?.paste(text, paneBracketed: paneBracketed, allowUnsafe: true) }
            }
        case .empty: break
        }
    }

    func clipboardWritten(_ text: String) {
        gate(clipboardWrite, ask: { askClipboard(.write(text), $0) }, refused: {},
             go: { [weak self] in self?.writeClipboard(text) })
    }

    private func writeClipboard(_ text: String) {
        pasteboard.clearContents()
        if !text.isEmpty { pasteboard.setString(text, forType: .string) }
#if NMUX_SELFTEST
        observer?.clipboardWritten(text)
#endif
    }

    /// A denied read gets no reply at all; an allowed one gets the text, empty as it may be, since the program waits.
    func clipboardAsked() {
        gate(clipboardRead, ask: { askClipboard(.read, $0) }, refused: { [weak self] in self?.clipboardAnswered(nil) },
             go: { [weak self] in self?.replyClipboard() })
    }

    private func replyClipboard() {
        let text = pasteboard.string(forType: .string) ?? ""
        host.send(osc52Reply(text))
        clipboardAnswered(text)
    }

    private func clipboardAnswered(_ text: String?) {
#if NMUX_SELFTEST
        observer?.clipboardRead(text)
#endif
    }
}
