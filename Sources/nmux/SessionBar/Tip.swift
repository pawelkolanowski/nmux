import AppKit
import Terminal

/// The window washed in the accent at 20%, fading out over 0.6 s ease-out above everything, then gone. It fades in
/// place, so Reduce Motion keeps it. It never takes a click.
final class Wash: NSView {
    static func flash(over content: NSView, accent: NSColor) {
        let wash = Wash(frame: content.bounds)
        wash.wantsLayer = true
        wash.layer?.backgroundColor = accent.withAlphaComponent(0.2).cgColor
        content.addSubview(wash, positioned: .above, relativeTo: nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            wash.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { wash.removeFromSuperview() }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The tip a view shows once the pointer has rested on it half a second; the view drops it on exit or a click.
final class RestingTip {
    /// Counts the arms and drops, so a rest that a drop or a later arm overtook shows nothing.
    private var generation = 0
    private var tip: Tip?

    func arm(_ text: String, under view: NSView) {
        drop()
        let armed = generation
        onMain(after: 0.5) { [weak self, weak view] in
            guard let self, let view, self.generation == armed, !view.isHidden else { return }
            self.tip = Tip(text, under: view)
        }
    }

    func drop() {
        generation += 1
        tip?.removeFromSuperview()
        tip = nil
    }
}

/// A one-line drawn card under a view in the Session bar: the theme's background blended 5% toward the foreground,
/// a 1 pt edge of the foreground at 12% and a soft shadow, 7 pt round. It sits 4 pt under the view, their right edges
/// aligned, at least 4 pt inside the window, above everything in it, and fades in over 0.12 s. It never takes a click.
final class Tip: NSView {
    let text: String
    private let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)

    init(_ text: String, under view: NSView) {
        self.text = text
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        alphaValue = 0
        place(under: view)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
        selfTestLog("tip \(text)")
    }

    required init?(coder: NSCoder) { fatalError("Tip is never decoded") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Into the window's content view, on top of every other view, under `view` again.
    func place(under view: NSView) {
        guard let content = view.window?.contentView else { return }
        let size = textSize(text, [.font: font])
        let width = min(size.width.rounded(.up) + 20, content.bounds.width - 8), height = size.height.rounded(.up) + 10
        let r = view.convert(view.bounds, to: content)
        frame = NSRect(x: max(min(r.maxX, content.bounds.width - 4) - width, 4), y: r.minY - 4 - height,
                       width: width, height: height)
        content.addSubview(self, positioned: .above, relativeTo: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let theme = ChromeTheme.current
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        (theme.bg.blended(withFraction: 0.05, of: theme.fg) ?? theme.bg).withAlphaComponent(1).setFill()
        shape.fill()
        theme.fg.withAlphaComponent(0.12).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        drawLine(text, [.font: font, .paragraphStyle: style, .foregroundColor: theme.fg.withAlphaComponent(0.85)],
                 x: 10, width: bounds.width - 20, in: bounds)
    }
}
