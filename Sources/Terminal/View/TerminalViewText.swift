import AppKit
import GhosttyVt

// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The view's text input client: dead keys, marked text, IMEs, dictation, the emoji picker and the accent popup.
/// Adapted from Ghostty's `NSTextInputClient` extension, `insertText`, `doCommand` and `ime_point` in
/// `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` and `src/Surface.zig` (`imePointScaled`) at commit
/// 22f100c6.
extension TerminalView: @preconcurrency NSTextInputClient {
    /// Inside a key the text waits for `keyDown`; outside one it is a commit.
    public func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil else { return }
        var chars = ""
        switch string {
        case let v as NSAttributedString: chars = v.string
        case let v as NSString:
            // The emoji picker may send a surrogate pair one half at a time; a trail without its lead is dropped, as
            // Terminal.app does.
            let unit = v.length == 1 ? v.character(at: 0) : nil
            if let unit, UTF16.isLeadSurrogate(unit) {
                leadSurrogate = unit
            } else if let unit, UTF16.isTrailSurrogate(unit) {
                chars = leadSurrogate.map { String(utf16CodeUnits: [$0, unit], count: 2) } ?? ""
                leadSurrogate = nil
            } else {
                chars = v as String
                leadSurrogate = nil
            }
        default: return
        }
        unmarkText()
        if inserted != nil { inserted!.append(chars); return }
        if !chars.isEmpty { commit(GHOSTTY_KEY_ACTION_PRESS, chars) }
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let v as NSAttributedString: markedText = v.string
        case let v as String: markedText = v
        default: return
        }
    }

    public func unmarkText() { markedText = "" }

    /// Marked text goes when the window loses key or the view its window; the text system forgets it too.
    func dropMarkedText() {
        guard !markedText.isEmpty else { return }
        inputContext?.discardMarkedText()
        markedText = ""
    }

    public func hasMarkedText() -> Bool { !markedText.isEmpty }

    public func markedRange() -> NSRange {
        markedText.isEmpty ? NSRange() : NSRange(location: 0, length: (markedText as NSString).length)
    }

    /// The selection's text, as Ghostty's, for Look Up and Services; whatever range is asked for, since macOS asks for
    /// ranges no terminal can map. No index is found.
    /// limitation: the range starts at 0, not at the selection's place in the screen's text as Ghostty's; upgrade when
    /// a system feature needs the place.
    public func selectedRange() -> NSRange {
        selectionGesture.text().map { NSRange(location: 0, length: ($0 as NSString).length) } ?? NSRange()
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    public func attributedSubstring(forProposedRange range: NSRange,
                                    actualRange: NSRangePointer?) -> NSAttributedString? {
        guard range.length > 0, let text = selectionGesture.text() else { return nil }
        return NSAttributedString(string: text,
                                  attributes: [.font: CTFontCreateCopyWithAttributes(font.primary, font.points,
                                                                                     nil, nil)])
    }

    public func characterIndex(for point: NSPoint) -> Int { 0 }

    /// Ghostty's IME point on screen: from the middle of the cursor's cell to the right, as wide as the marked text and
    /// never past the row's end, one cell high. An empty range has no width and starts after the cells it counts, so
    /// dictation's indicator sits at the cursor.
    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let cell = font.cell, scale = font.scale
        let (w, h) = (CGFloat(cell.width) / scale, CGFloat(cell.height) / scale)
        // The active screen's cursor, as Ghostty's; it does not follow a scrolled viewport either.
        let at = host.locked { t in
            var x: UInt16 = 0, y: UInt16 = 0
            ghostty_terminal_get(t, GHOSTTY_TERMINAL_DATA_CURSOR_X, &x)
            ghostty_terminal_get(t, GHOSTTY_TERMINAL_DATA_CURSOR_Y, &y)
            return (x: Int(x), y: Int(y))
        }
        var x = (CGFloat(at.x) + 0.5) * w
        let cols = cells.preedit.map(preeditWidth).reduce(0, +)
        var width = min(CGFloat(cols) * w, CGFloat(grid.cols - at.x - 1) * w)
        if range.length == 0, width > 0 {
            width = 0
            x += w * CGFloat(range.location + range.length)
        }
        let rect = NSRect(x: x, y: bounds.height - CGFloat(at.y + 1) * h, width: max(width, 0), height: h)
        guard let window else { return convert(rect, to: nil) }
        return window.convertToScreen(convert(rect, to: nil))
    }

    /// A command the text system found for a key, such as insertNewline: the key itself goes to the program, and doing
    /// nothing here keeps AppKit from beeping.
    public override func doCommand(by selector: Selector) {}
}
