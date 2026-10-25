import AppKit
import IOKit.pwr_mgt

/// The Keep-awake cup at the Session bar's right end: off, a moon and "Sleep allowed"; on, a cup and "On the beans" in
/// the accent, while its KeepAwake holds. A click turns it on or off, and turning it on washes the window in the
/// accent. It explains itself in a tip after the pointer rests on it half a second, and starts off.
final class CupSlot: NSView {
    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let width = cupWidth(labels: [cupLook(nil).label, cupLook(0).label]
        .map { textSize($0, [.font: font]).width })
    private let keepAwake: KeepAwake
    private var hold: IOPMAssertionID? { keepAwake.hold }
    private var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }
    private let tip = RestingTip()

    init(_ keepAwake: KeepAwake) {
        self.keepAwake = keepAwake
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
        selfTestLog("cup off")
    }

    required init?(coder: NSCoder) { fatalError("CupSlot is never decoded") }

    override func draw(_ dirtyRect: NSRect) {
        let theme = ChromeTheme.current, look = cupLook(hold)
        let capsule = hold == nil ? theme.fg.withAlphaComponent(hovered ? 0.07 : 0.045)
            : theme.accent.withAlphaComponent(hovered ? 0.18 : 0.13)
        let ink = hold == nil ? theme.fg.withAlphaComponent(hovered ? 0.75 : 0.45) : theme.accent
        capsule.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 4), xRadius: 11, yRadius: 11).fill()
        // The icon and the label centred together in the slot.
        let attributes: [NSAttributedString.Key: Any] = [.font: CupSlot.font, .foregroundColor: ink]
        let label = textSize(look.label, attributes).width
        let x = (bounds.width - cupIcon - cupGap - label) / 2
        drawSymbol(look.icon, ink, centre: NSPoint(x: x + cupIcon / 2, y: bounds.midY), size: 11.5, weight: .medium)
        drawLine(look.label, attributes, x: x + cupIcon + cupGap, width: label.rounded(.up), in: bounds)
    }

    override func mouseEntered(with event: NSEvent) { enter() }
    override func mouseExited(with event: NSEvent) { exit() }

    func enter() {
        guard !hovered else { return }
        hovered = true
        tip.arm(cupLook(hold).tip, under: self)
    }

    func exit() {
        hovered = false
        tip.drop()
    }

    /// The tip goes on a click; the pointer resting on afterwards shows the new state's.
    override func mouseDown(with event: NSEvent) {
        exit()
        toggle()
        enter()
    }

    /// On holds and washes the window, and stays off when the system refuses the hold; off lets the Mac sleep again.
    func toggle() {
        if hold == nil {
            if keepAwake.start(), let content = window?.contentView {
                Wash.flash(over: content, accent: ChromeTheme.current.accent)
            }
        } else {
            keepAwake.release()
        }
        needsDisplay = true
        selfTestLog("cup " + (hold.map { "on \($0)" } ?? "off"))
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { cupLook(hold).label }
    override func accessibilityHelp() -> String? { cupLook(hold).tip }
    override func accessibilityPerformPress() -> Bool {
        tip.drop()
        toggle()
        return true
    }
}
