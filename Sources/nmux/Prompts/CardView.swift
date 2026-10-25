import AppKit
import Terminal

/// A card nmux draws in the theme over a dim of the window: a title, an optional detail, an optional excerpt, command
/// lines to copy, an optional box and a row of buttons, right-aligned, the default one filled with the accent. No
/// system control draws any of it. A card with a box, the window's, is 300 x 128 pt.
final class CardView: NSView {
    var state: CardState {
        didSet {
            // Other parts drop the focus, so it never rings or presses a part it was not moved to.
            if (oldValue.kind, oldValue.commands, oldValue.checkbox, oldValue.actions)
                != (state.kind, state.commands, state.checkbox, state.actions) { focus = nil }
            needsDisplay = true
            spinWhileNeeded()
        }
    }
    private let press: (CardAction) -> Void
    /// The command whose Copy button reads "Copied" for a moment.
    private var copied: Int?
    /// The part Tab moved to, ringed in the accent; nil until the first Tab.
    private var focus: Int?
    private var spin = 0
    private var timer: Timer?

    /// A card fits its content, up to 520 pt wide; the window's card, the one with a checkbox, is 300 x 128 pt.
    /// limitation: the window's card keeps 300 x 128 pt whatever its text, so a longer title or label would run into
    /// its buttons; let it grow once a card with a checkbox says more.
    private struct Measures {
        let width, height: CGFloat?, pad: CGFloat, title: NSFont
    }
    private var measures: Measures {
        state.checkbox == nil ? Measures(width: nil, height: nil, pad: 24, title: .boldSystemFont(ofSize: 15))
            : Measures(width: 300, height: 128, pad: 20, title: .systemFont(ofSize: 14, weight: .semibold))
    }
    private var titleFont: NSFont { measures.title }
    private let textFont = NSFont.systemFont(ofSize: 13)
    private let boxFont = NSFont.systemFont(ofSize: 12)
    private let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    /// The terminal's face, for the excerpt.
    var excerptFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let gap: CGFloat = 12, buttonHeight: CGFloat = 28
    private var pad: CGFloat { measures.pad }
    private static let spinner = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")

    init(_ state: CardState, press: @escaping (CardAction) -> Void) {
        self.state = state
        self.press = press
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        spinWhileNeeded()
    }

    required init?(coder: NSCoder) { fatalError("CardView is never decoded") }

    /// The spinner turns at 10 frames a second, only while the card shows one and is in a window.
    private func spinWhileNeeded() {
        guard state.spinner, timer == nil else {
            if !state.spinner { stopSpinning() }
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.spin += 1
                self?.needsDisplay = true
            }
        }
    }

    private func stopSpinning() {
        timer?.invalidate()
        timer = nil
    }

    override func viewDidMoveToWindow() {
        if window == nil { stopSpinning() }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// A card that fits its content, in a view `width` wide.
    static func width(in width: CGFloat) -> CGFloat { min(520, width - 32) }

    private struct Layout {
        var panel = NSRect.zero, title = NSRect.zero, detail = NSRect.zero, excerpt = NSRect.zero
        var detailText: String?
        var commands: [(line: NSRect, copy: NSRect)] = []
        /// The box's square, and the square with its label, which a click turns.
        var box = NSRect.zero, boxTarget = NSRect.zero
        var buttons: [NSRect] = []
    }

    /// What Tab moves among, in the order they stand: the Copy buttons, the box, then the buttons.
    private enum Part {
        case copy(Int), box, button(Int)
    }
    private var parts: [Part] {
        state.commands.indices.map(Part.copy) + (state.checkbox == nil ? [] : [.box])
            + state.actions.indices.map(Part.button)
    }

    private func rect(_ part: Part, _ l: Layout) -> NSRect {
        switch part {
        case .copy(let i): l.commands[i].copy
        case .box: l.boxTarget
        case .button(let i): l.buttons[i]
        }
    }

    private var detail: String? {
        state.spinner ? "\(Self.spinner[spin % Self.spinner.count]) \(state.detail ?? "")" : state.detail
    }

    /// Laid out in the panel's own space top-down, then centred in the view. A detail too tall for the
    /// window drops its first lines, so the panel fits and the latest lines stay.
    private func cardLayout() -> Layout {
        let width = measures.width ?? Self.width(in: bounds.width), inner = width - 2 * pad
        var l = Layout(), y = pad
        let titleHeight = height(state.title, titleFont, inner)
        l.title = NSRect(x: pad, y: y, width: inner, height: titleHeight)
        y += titleHeight
        if var detail {
            let room = bounds.height - 32 - restHeight(inner) - titleHeight - gap
            var h = height(detail, textFont, inner)
            while h > room, let cut = detail.firstIndex(of: "\n") {
                detail = String(detail[detail.index(after: cut)...])
                h = height(detail, textFont, inner)
            }
            l.detailText = detail
            l.detail = NSRect(x: pad, y: y + gap, width: inner, height: min(h, max(room, 0)))
            y += gap + l.detail.height
        }
        if let excerpt = state.excerpt {
            l.excerpt = NSRect(x: pad, y: y + gap, width: inner, height: height(excerpt, excerptFont, inner))
            y += gap + l.excerpt.height
        }
        for command in state.commands {
            let lineWidth = inner - copyWidth - gap, h = height(command, codeFont, lineWidth)
            let row = max(h, buttonHeight)
            l.commands.append((NSRect(x: pad, y: y + gap + (row - h) / 2, width: lineWidth, height: h),
                               NSRect(x: pad + inner - copyWidth, y: y + gap + (row - buttonHeight) / 2,
                                      width: copyWidth, height: buttonHeight)))
            y += gap + row
        }
        if let box = state.checkbox {
            let line = height(box, boxFont, inner), row = max(14, line)
            l.box = NSRect(x: pad, y: y + gap + (row - 14) / 2, width: 14, height: 14)
            l.boxTarget = NSRect(x: pad, y: y + gap,
                                 width: 14 + 8 + textSize(box, [.font: boxFont]).width.rounded(.up), height: row)
            y += gap + row
        }
        if !state.actions.isEmpty {
            // A card of a fixed height keeps its buttons at its foot.
            y = measures.height.map { $0 - pad - buttonHeight } ?? y + 2 * gap
            var x = pad + inner
            for action in state.actions.reversed() {
                let w = buttonWidth(labels: state.labels(action).map { textWidth($0) })
                x -= w
                l.buttons.insert(NSRect(x: x, y: y, width: w, height: buttonHeight), at: 0)
                x -= gap / 1.5
            }
            y += buttonHeight
        }
        y += pad
        let dx = ((bounds.width - width) / 2).rounded(), dy = ((bounds.height - y) / 2).rounded()
        func place(_ r: NSRect) -> NSRect { r.offsetBy(dx: dx, dy: dy) }
        l.panel = place(NSRect(x: 0, y: 0, width: width, height: y))
        l.title = place(l.title)
        l.detail = place(l.detail)
        l.excerpt = place(l.excerpt)
        l.commands = l.commands.map { (place($0.line), place($0.copy)) }
        (l.box, l.boxTarget) = (place(l.box), place(l.boxTarget))
        l.buttons = l.buttons.map(place)
        return l
    }

    /// The panel's height without its title and detail: the padding, the excerpt, the command lines and the buttons.
    private func restHeight(_ inner: CGFloat) -> CGFloat {
        let lineWidth = inner - copyWidth - gap
        let commands = state.commands.reduce(0) { $0 + gap + max(height($1, codeFont, lineWidth), buttonHeight) }
        let excerpt = state.excerpt.map { gap + height($0, excerptFont, inner) } ?? 0
        return 2 * pad + excerpt + commands + (state.actions.isEmpty ? 0 : 2 * gap + buttonHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let theme = ChromeTheme.current, fg = theme.fg, bg = theme.bg.withAlphaComponent(1)
        theme.bg.withAlphaComponent(0.35).setFill()
        bounds.fill(using: .sourceOver)
        let l = cardLayout()
        let panel = NSBezierPath(roundedRect: l.panel, xRadius: 12, yRadius: 12)
        bg.setFill()
        panel.fill()
        // The panel, the dim and the content share the background; only the outline shows the edge.
        fg.withAlphaComponent(0.25).setStroke()
        panel.stroke()
        text(state.title, titleFont, fg, in: l.title)
        if let detail = l.detailText { text(detail, textFont, fg, in: l.detail) }
        if let excerpt = state.excerpt { text(excerpt, excerptFont, fg, in: l.excerpt) }
        for (i, (command, rects)) in zip(state.commands, l.commands).enumerated() {
            text(command, codeFont, fg, in: rects.line)
            button(copied == i ? "Copied" : "Copy", filled: false, in: rects.copy, theme, bg)
        }
        if let box = state.checkbox { drawBox(box, l, theme, bg) }
        for (action, rect) in zip(state.actions, l.buttons) {
            button(state.label(action), filled: action == state.defaultAction, in: rect, theme, bg)
        }
        if let focus, parts.indices.contains(focus) {
            let ring = NSBezierPath(roundedRect: rect(parts[focus], l).insetBy(dx: -3, dy: -3), xRadius: 8, yRadius: 8)
            ring.lineWidth = 2
            theme.accent.setStroke()
            ring.stroke()
        }
    }

    /// Unticked: the foreground at 6% with a 1 pt line at 45%; ticked: the accent with a 1.8 pt tick in the
    /// background's colour. The label at 12 pt, the foreground at 80%, 8 pt to its right.
    private func drawBox(_ label: String, _ l: Layout, _ theme: ChromeTheme, _ bg: NSColor) {
        let square = NSBezierPath(roundedRect: l.box, xRadius: 4, yRadius: 4)
        if state.checked {
            theme.accent.setFill()
            square.fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: l.box.minX + 3.5, y: l.box.midY))
            tick.line(to: NSPoint(x: l.box.minX + 6, y: l.box.maxY - 4))
            tick.line(to: NSPoint(x: l.box.maxX - 3, y: l.box.minY + 4))
            tick.lineWidth = 1.8
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            bg.setStroke()
            tick.stroke()
        } else {
            theme.fg.withAlphaComponent(0.06).setFill()
            square.fill()
            let edge = NSBezierPath(roundedRect: l.box.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5)
            edge.lineWidth = 1
            theme.fg.withAlphaComponent(0.45).setStroke()
            edge.stroke()
        }
        let size = textSize(label, [.font: boxFont])
        text(label, boxFont, theme.fg.withAlphaComponent(0.8),
             in: NSRect(x: l.box.maxX + 8, y: l.box.midY - size.height / 2, width: size.width + 1, height: size.height))
    }

    /// A point inside the default button, 5 pt from its right edge, in the window, where the self-test reads its
    /// colour.
    var defaultPoint: NSPoint? {
        let l = cardLayout()
        guard let i = state.actions.firstIndex(where: { $0 == state.defaultAction }) else { return nil }
        return convert(NSPoint(x: l.buttons[i].maxX - 5, y: l.buttons[i].midY), to: nil)
    }

    /// The end of the checkbox's label, in the window, where the self-test clicks.
    var boxPoint: NSPoint {
        let target = cardLayout().boxTarget
        return convert(NSPoint(x: target.maxX - 4, y: target.midY), to: nil)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil), l = cardLayout()
        // The box and its label are one target, the box's part.
        if let part = parts.first(where: { rect($0, l).contains(point) }) { return activate(part) }
        if !l.panel.contains(point), let escape = state.escape, escape != .quit { press(escape) }
    }

    private func activate(_ part: Part) {
        switch part {
        case .copy(let i): copy(i)
        case .box: state.checked.toggle()
        case .button(let i): press(state.actions[i])
        }
    }

    private func copy(_ i: Int) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.commands[i], forType: .string)
        copied = i
        needsDisplay = true
        onMain(after: 1.2) {
            guard self.copied == i else { return }
            self.copied = nil
            self.needsDisplay = true
        }
    }

    /// Return presses the default action and Escape the dismissing one; a card without them ignores both. Tab and
    /// Shift-Tab move the focus, and Space presses the part it is on, else ticks the box.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case KeyCode.return, KeyCode.enter: if let action = state.defaultAction { press(action) }
        case KeyCode.escape: if let action = state.escape { press(action) }
        case KeyCode.tab:
            let n = parts.count, back = event.modifierFlags.contains(.shift)
            guard n > 0 else { return }
            focus = focus.map { (back ? $0 - 1 + n : $0 + 1) % n } ?? (back ? n - 1 : 0)
            needsDisplay = true
        case KeyCode.space:
            if let focus, parts.indices.contains(focus) {
                activate(parts[focus])
            } else if state.checkbox != nil {
                state.checked.toggle()
            }
        default: break
        }
    }

    private func textWidth(_ title: String) -> CGFloat { textSize(title, [.font: textFont]).width }
    private var copyWidth: CGFloat { buttonWidth(labels: [textWidth("Copied")]) }

    private func height(_ string: String, _ font: NSFont, _ width: CGFloat) -> CGFloat {
        NSAttributedString(string: string, attributes: [.font: font])
            .boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
            .height.rounded(.up)
    }

    private func text(_ string: String, _ font: NSFont, _ color: NSColor, in rect: NSRect) {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
            .draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private func button(_ title: String, filled: Bool, in rect: NSRect, _ theme: ChromeTheme, _ bg: NSColor) {
        let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        if filled {
            theme.accent.setFill()
            shape.fill()
        } else {
            theme.fg.setStroke()
            shape.stroke()
        }
        let size = textSize(title, [.font: textFont])
        text(title, textFont, filled ? bg : theme.fg,
             in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                        width: size.width + 1, height: size.height))
    }
}
