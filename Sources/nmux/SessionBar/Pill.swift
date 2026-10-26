import AppKit

/// One Session's pill in the Session bar, `pill-width` wide: its name between the left 28 pt and an equal right margin,
/// the close mark or the Bell mark's dot in that left slot. A click on the shown close mark closes the Session, any
/// other click shows it. A cut name spills whole over the bar while the pointer rests on the pill. While a close asks
/// on it, it keeps its size, drops its hover parts and shows the prompt: a wash of the danger colour, the name and a
/// bin at its right end.
final class Pill: NSView {
    static let slot: CGFloat = 28
    let session: Session
    let active: Bool
    private let separator: Bool
    private unowned let bar: SessionBar
    private var hovered = false { didSet { needsDisplay = true } }
    private var onClose = false { didSet { if onClose != oldValue { needsDisplay = true } } }
    private var onBin = false { didSet { if onBin != oldValue { needsDisplay = true } } }
    private var spill: NameSpill?
    private var font: NSFont { .systemFont(ofSize: 12, weight: active ? .semibold : .medium) }
    private var hovering: Bool { hovered && !session.asking }
    private var slot: LeftSlot { leftSlot(active: active, hovered: hovering, bell: session.bellMark) }

    init(_ session: Session, active: Bool, separator: Bool, bar: SessionBar) {
        (self.session, self.active, self.separator, self.bar) = (session, active, separator, bar)
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError("Pill is never decoded") }

    private var label: String {
        cutName(session.info.name) { textSize($0, [.font: font]).width <= bounds.width - 2 * Pill.slot }
    }

    override func draw(_ dirtyRect: NSRect) {
        let theme = ChromeTheme.current
        if session.asking { return drawPrompt(theme) }
        // The active pill's wash is the active mark's, which glides.
        if hovering && !active {
            theme.fg.withAlphaComponent(0.025).setFill()
            wash(bounds).fill()
        }
        if separator {
            theme.fg.withAlphaComponent(0.10).setFill()
            NSRect(x: bounds.maxX - 0.5, y: bounds.midY - 5, width: 0.5, height: 10).fill()
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let alpha: CGFloat = active ? 0.96 : hovering ? 0.80 : 0.58
        drawLine(label, [.font: font, .paragraphStyle: style, .foregroundColor: theme.fg.withAlphaComponent(alpha)],
                 x: Pill.slot, width: bounds.width - 2 * Pill.slot, in: bounds)
        switch slot {
        case .close:
            if onClose {
                theme.fg.withAlphaComponent(0.10).setFill()
                NSBezierPath(ovalIn: NSRect(x: 15 - 8, y: bounds.midY - 8, width: 16, height: 16)).fill()
            }
            drawSymbol("xmark", theme.fg.withAlphaComponent(onClose ? 0.80 : active ? 0.55 : 0.44),
                       centre: NSPoint(x: 15, y: bounds.midY))
        case .dot:
            theme.accent.setFill()
            // On the close mark's centre, so hover swaps one for the other in place.
            NSBezierPath(ovalIn: NSRect(x: 15 - 3, y: bounds.midY - 3, width: 6, height: 6)).fill()
        case .nothing: break
        }
    }

    /// The danger colour's wash, the name in the inactive font at 70% centred left of the bin, and the bin, brighter
    /// under the pointer, with the trash symbol in the background's colour.
    private func drawPrompt(_ theme: ChromeTheme) {
        theme.danger.withAlphaComponent(0.10).setFill()
        wash(bounds).fill()
        let bin = binRect(bounds), font = NSFont.systemFont(ofSize: 12, weight: .medium), x: CGFloat = 8
        let width = bin.minX - 6 - x
        let name = cutName(session.info.name) { textSize($0, [.font: font]).width <= width }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        drawLine(name, [.font: font, .paragraphStyle: style, .foregroundColor: theme.fg.withAlphaComponent(0.70)],
                 x: x, width: width, in: bounds)
        theme.danger.withAlphaComponent(onBin ? 1 : 0.85).setFill()
        NSBezierPath(roundedRect: bin, xRadius: 5, yRadius: 5).fill()
        drawSymbol("trash", theme.bg.withAlphaComponent(1), centre: NSPoint(x: bin.midX, y: bin.midY),
                   size: 10, weight: .semibold)
    }

    override func mouseEntered(with event: NSEvent) { enter() }

    func enter() {
        hovered = true
        // A rebuild under a resting pointer gets no move, so the bin brightens here.
        if session.asking, let window {
            onBin = binRect(bounds).contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        guard !session.asking, label != session.info.name, spill == nil else { return }
        spill = NameSpill(session.info.name, font: font, over: self, in: bar, from: bar.rowStart)
    }

    override func mouseMoved(with event: NSEvent) {
        let at = convert(event.locationInWindow, from: nil)
        onClose = !session.asking && at.x < Pill.slot
        onBin = session.asking && binRect(bounds).contains(at)
    }

    override func mouseExited(with event: NSEvent) {
        (hovered, onClose, onBin) = (false, false, false)
        dropSpill()
    }

    /// On the asking pill only the bin kills; a click elsewhere on it cancels, then shows its Session as usual.
    override func mouseDown(with event: NSEvent) {
        if session.asking {
            let kill = binRect(bounds).contains(convert(event.locationInWindow, from: nil))
            bar.answer(kill)
            if !kill { bar.show(session.info.id) }
            return
        }
        dropSpill()
        bar.dropField()
        if slot == .close, convert(event.locationInWindow, from: nil).x < Pill.slot {
            bar.close(session.info.id)
        } else {
            bar.show(session.info.id)
        }
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
