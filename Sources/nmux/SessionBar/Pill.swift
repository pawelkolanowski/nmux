import AppKit

/// One Session's pill in the Session bar, 136 pt wide: its name between the left 28 pt and an equal right margin, the
/// Bell mark's dot in that left slot. A click shows its Session. A cut name spills whole over the bar while the pointer
/// rests on the pill.
final class Pill: NSView {
    static let slot: CGFloat = 28
    let session: Session
    let active: Bool
    private let separator: Bool
    private unowned let bar: SessionBar
    private var hovered = false { didSet { needsDisplay = true } }
    private var spill: NameSpill?
    private var font: NSFont { .systemFont(ofSize: 12, weight: active ? .semibold : .medium) }

    init(_ session: Session, active: Bool, separator: Bool, bar: SessionBar) {
        (self.session, self.active, self.separator, self.bar) = (session, active, separator, bar)
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError("Pill is never decoded") }

    private var label: String {
        cutName(session.info.name) { textSize($0, [.font: font]).width <= bounds.width - 2 * Pill.slot }
    }

    override func draw(_ dirtyRect: NSRect) {
        let theme = ChromeTheme.current
        // The active pill's wash is the active mark's, which glides.
        if hovered && !active {
            theme.fg.withAlphaComponent(0.025).setFill()
            wash(bounds).fill()
        }
        if separator {
            theme.fg.withAlphaComponent(0.10).setFill()
            NSRect(x: bounds.maxX - 0.5, y: bounds.midY - 5, width: 0.5, height: 10).fill()
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let alpha: CGFloat = active ? 0.96 : hovered ? 0.80 : 0.58
        drawLine(label, [.font: font, .paragraphStyle: style, .foregroundColor: theme.fg.withAlphaComponent(alpha)],
                 x: Pill.slot, width: bounds.width - 2 * Pill.slot, in: bounds)
        if session.bellMark {
            theme.accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: 15 - 3, y: bounds.midY - 3, width: 6, height: 6)).fill()
        }
    }

    override func mouseEntered(with event: NSEvent) { enter() }

    func enter() {
        hovered = true
        guard label != session.info.name, spill == nil else { return }
        spill = NameSpill(session.info.name, font: font, over: self, in: bar, from: bar.rowStart)
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        dropSpill()
    }

    override func mouseDown(with event: NSEvent) {
        dropSpill()
        bar.dropField()
        bar.show(session.info.id)
    }

    /// A rebuild drops the pill under the pointer, and its spill with it.
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil { dropSpill() }
    }

    func dropSpill() {
        spill?.removeFromSuperview()
        spill = nil
    }

    /// A click on a pill always switches; only the bar's empty parts drag the window.
    override var mouseDownCanMoveWindow: Bool { false }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { session.info.name }
    override func accessibilityPerformPress() -> Bool {
        bar.show(session.info.id)
        return true
    }
}
