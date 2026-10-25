import AppKit

// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The selection's Edit menu actions and its colours, adapted from Ghostty's `copyToClipboard` and `selectAll` in
/// `src/Surface.zig` at commit 22f100c6. Copy and `copy-on-select` write the selection's plain text; no selection, or
/// one with no text, leaves the pasteboard as it was.
extension TerminalView {
    public func copySelection() {
        guard let text = selectionGesture.text(), !text.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#if NMUX_SELFTEST
        observer?.copied(text)
#endif
    }

    func dropSelection() {
        selectionGesture.clear()
        resume()
    }

    public func selectAll() {
        selectionGesture.selectAll()
        resume()
    }
}
