import AppKit

/// The 32 pt slot after the last pill: a plus that brightens under the pointer, explains itself in a tip after the
/// pointer rests on it half a second, and opens the New Session field on a click.
final class PlusSlot: NSView {
    static let width: CGFloat = 32
    private unowned let bar: SessionBar
    private var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }
    private let tip = RestingTip()

    init(bar: SessionBar) {
        self.bar = bar
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError("PlusSlot is never decoded") }

    override func draw(_ dirtyRect: NSRect) {
        let theme = ChromeTheme.current
        drawSymbol("plus", theme.fg.withAlphaComponent(hovered ? 0.80 : 0.45),
                   centre: NSPoint(x: bounds.midX, y: bounds.midY), size: 10, weight: .medium)
    }

    override func mouseEntered(with event: NSEvent) { enter() }
    override func mouseExited(with event: NSEvent) { exit() }

    /// The pointer came to rest here: the tip waits half a second.
    func enter() {
        guard !hovered else { return }
        hovered = true
        tip.arm("New Session", under: self)
    }

    /// The pointer left, clicked, the row scrolled or the plus moved away: no tip stays or comes.
    func exit() {
        hovered = false
        tip.drop()
    }

    override func mouseDown(with event: NSEvent) {
        exit()
        bar.draft(.open)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "New Session" }
    override func accessibilityPerformPress() -> Bool {
        exit()
        bar.draft(.open)
        return true
    }
}
