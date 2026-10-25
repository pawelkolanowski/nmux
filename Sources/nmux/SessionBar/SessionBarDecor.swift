import AppKit

/// The active pill's wash and accent line, behind the pills, so it can glide from one pill to the next.
final class ActiveMark: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let theme = ChromeTheme.current
        theme.fg.withAlphaComponent(0.045).setFill()
        wash(bounds).fill()
        theme.accent.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 12, y: 5, width: 24, height: 1.5), xRadius: 0.75,
                     yRadius: 0.75).fill()
    }
}

/// A fade from the bar's background to clear over one edge of the row; it never takes a click.
final class Fade: NSView {
    private let left: Bool

    init(left: Bool) {
        self.left = left
        super.init(frame: .zero)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("Fade is never decoded") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let bg = ChromeTheme.current.bg
        NSGradient(starting: bg, ending: bg.withAlphaComponent(0))?.draw(in: bounds, angle: left ? 0 : 180)
    }
}

/// A cut name spilt whole to the right over the bar, from 8 pt before the end of its pill's close mark slot, cut at the
/// bar's end and never left of the row; it never takes a click.
final class NameSpill: NSView {
    private let name: String, font: NSFont
    private static let pad: CGFloat = 8

    init(_ name: String, font: NSFont, over pill: NSView, in bar: NSView, from rowStart: CGFloat) {
        (self.name, self.font) = (name, font)
        let r = pill.convert(pill.bounds, to: bar), x = max(r.minX + Pill.slot - NameSpill.pad, rowStart)
        let width = textSize(name, [.font: font]).width.rounded(.up) + 2 * NameSpill.pad
        super.init(frame: NSRect(x: x, y: r.minY, width: max(min(width, bar.bounds.width - 4 - x), 0),
                                 height: r.height))
        bar.addSubview(self)
    }

    required init?(coder: NSCoder) { fatalError("NameSpill is never decoded") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let theme = ChromeTheme.current
        let shape = wash(bounds, inset: 0)
        theme.bg.setFill()
        shape.fill()
        theme.fg.withAlphaComponent(0.06).setFill()
        shape.fill()
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        drawLine(name, [.font: font, .paragraphStyle: style, .foregroundColor: theme.fg.withAlphaComponent(0.96)],
                 x: NameSpill.pad, width: bounds.width - 2 * NameSpill.pad, in: bounds)
    }
}
