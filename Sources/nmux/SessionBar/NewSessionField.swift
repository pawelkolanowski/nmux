import AppKit

/// The New Session field in the plus's place, a pill wide: the active pill's wash in the accent at 10% behind a
/// borderless text field, its name centred and semibold, red with tmux's error in a tip under it after a refusal.
/// Return submits, Escape cancels, and focus leaving it cancels too.
final class NewSessionField: NSView, NSTextFieldDelegate {
    private unowned let bar: SessionBar
    let text = NSTextField()
    private var refused: String?
    private var tip: Tip?

    init(bar: SessionBar) {
        self.bar = bar
        super.init(frame: .zero)
        isHidden = true
        text.isBordered = false
        text.drawsBackground = false
        text.focusRingType = .none
        text.font = .systemFont(ofSize: 12, weight: .semibold)
        text.alignment = .center
        text.usesSingleLineMode = true
        text.cell?.isScrollable = true
        text.cell?.wraps = false
        text.delegate = self
        addSubview(text)
    }

    required init?(coder: NSCoder) { fatalError("NewSessionField is never decoded") }

    override func layout() {
        super.layout()
        let height = text.intrinsicContentSize.height
        text.frame = NSRect(x: 12, y: (bounds.height - height) / 2, width: bounds.width - 24, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        ChromeTheme.current.accent.withAlphaComponent(0.10).setFill()
        wash(bounds).fill()
    }

    /// The name's colour, red after a refusal, and the caret's, in the current theme.
    func colour() {
        let theme = ChromeTheme.current
        text.textColor = refused == nil ? theme.fg.withAlphaComponent(0.96) : theme.danger
        (text.currentEditor() as? NSTextView)?.insertionPointColor = theme.fg
    }

    /// The draft as it stands: none hides the field and its tip; an open one keeps the focus in the field, and a
    /// refusal shows its tip under the field.
    func show(_ draft: Draft?) {
        guard let draft else {
            if refused != nil || tip != nil { dropTip() }
            text.stringValue = ""
            return
        }
        if refused != draft.error {
            dropTip()
            refused = draft.error
            if let error = draft.error {
                tip = Tip(error, under: self)
            }
        } else {
            placeTip()
        }
        if text.currentEditor() == nil { window?.makeFirstResponder(text) }
        colour()
    }

    /// A scroll or a rebuild moved the field; its refusal stays under it.
    func placeTip() { tip?.place(under: self) }

    private func dropTip() {
        refused = nil
        tip?.removeFromSuperview()
        tip = nil
        colour()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): bar.draft(.submit(text.stringValue))
        case #selector(NSResponder.cancelOperation(_:)): bar.draft(.cancel)
        default: return false
        }
        return true
    }

    /// Focus went elsewhere, as a click on the terminal moves it.
    func controlTextDidEndEditing(_ obj: Notification) {
        if bar.drafting { bar.draft(.cancel) }
    }

    /// A click on the field's margins keeps it, as one on its text does; it neither drags nor drops it.
    override func mouseDown(with event: NSEvent) {}

    override var mouseDownCanMoveWindow: Bool { false }
}
