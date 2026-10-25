import AppKit
import Terminal

/// The Session bar at the top of the window: one pill per Session in `$ID` order in a row that scrolls sideways, from
/// 10 pt after the zoom button, with the traffic lights on its centre. Every change goes through `update`, which
/// rebuilds the pills. No system control draws any of it.
final class SessionBar: NSView {
    /// The bar's height; the terminal starts right under it.
    static let height: CGFloat = 30
    /// Every pill's width.
    let pillWidth: CGFloat = 136
    let show: (SessionID) -> Void
    /// The New Session field's events go to the draft's owner, which hands the draft back through `update`.
    let draft: (DraftEvent) -> Void
    private(set) var pills: [Pill] = []
    private(set) lazy var plus = PlusSlot(bar: self)
    /// One field for the bar's life, moved by each update and never removed while a draft is open, so it keeps its text
    /// and its focus.
    private(set) lazy var field = NewSessionField(bar: self)
    let cup: CupSlot
    private(set) var drafting = false
    private let scroller = NSScrollView()
    var rowStart: CGFloat { scroller.frame.minX }
    private let row = NSView()
    private let mark = ActiveMark()
    private let leftFade = Fade(left: true), rightFade = Fade(left: false)
    /// The Session the active mark sits on, and the fade sides last logged.
    private var marked: SessionID?
    private var fades: Fades?
    private var lightObservers: [NSObjectProtocol] = []

    init(keepAwake: KeepAwake, show: @escaping (SessionID) -> Void, draft: @escaping (DraftEvent) -> Void) {
        (self.show, self.draft) = (show, draft)
        cup = CupSlot(keepAwake)
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .minYMargin]
        scroller.documentView = row
        scroller.drawsBackground = false
        // Or it insets the row by the title bar it sits in, and a click on a pill hits the scroll view.
        scroller.automaticallyAdjustsContentInsets = false
        scroller.contentView.postsBoundsChangedNotifications = true
        row.addSubview(mark)
        row.addSubview(plus)
        row.addSubview(field)
        for view in [scroller, leftFade, rightFade, cup] { addSubview(view) }
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                               object: scroller.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.plus.exit()
                self?.field.placeTip()
                self?.scrolled()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("SessionBar is never decoded") }

    override func draw(_ dirtyRect: NSRect) {
        ChromeTheme.current.bg.setFill()
        bounds.fill()
    }

    /// The bar's empty parts drag the window, its bottom 2 pt below AppKit's 28 pt title bar too. A click there takes
    /// no focus, so it drops the field itself.
    override func mouseDown(with event: NSEvent) {
        dropField()
        window?.performDrag(with: event)
    }

    /// A click on the bar outside the field, which takes no focus from it.
    func dropField() { if drafting { draft(.cancel) } }

    /// AppKit lays the lights out again for its own 28 pt title bar on a resize and other changes; each change of a
    /// button's frame moves them back.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lightObservers.forEach(NotificationCenter.default.removeObserver)
        lightObservers = lights.map { button in
            NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: button,
                                                   queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.centreLights() }
            }
        }
        centreLights()
    }

    private var lights: [NSButton] {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window?.standardWindowButton($0) }
    }

    /// A move posts a frame change of its own, so a button moves only when its origin differs.
    private func centreLights() {
        guard let window else { return }
        for button in lights {
            guard let parent = button.superview else { continue }
            let y = parent.convert(NSPoint(x: 0, y: window.frame.height - SessionBar.height / 2),
                                   from: nil).y - button.frame.height / 2
            if button.frame.minY != y { button.setFrameOrigin(NSPoint(x: button.frame.minX, y: y)) }
        }
    }

    /// Rebuilds the pills from the Sessions at the top of the superview, keeping the bar's height and the row's offset,
    /// then brings the active pill into view, or the field while a draft is open. The plus or the field follows the
    /// last pill. The active mark glides to a newly active pill, except at launch and under Reduce Motion.
    func update(_ sessions: [Session], active: SessionID?, draft: Draft?) {
        guard let superview else { return }
        frame = NSRect(x: 0, y: superview.bounds.height - SessionBar.height, width: superview.bounds.width,
                       height: SessionBar.height)
        centreLights()
        let start = window?.standardWindowButton(.zoomButton).map { $0.convert($0.bounds, to: self).maxX + 10 } ?? 68
        cup.frame = NSRect(x: bounds.width - 4 - CupSlot.width, y: 0, width: CupSlot.width, height: SessionBar.height)
        scroller.frame = NSRect(x: start, y: 0, width: max(cup.frame.minX - 4 - start, 0), height: SessionBar.height)
        let offset = scroller.contentView.bounds.origin
        pills.forEach { $0.removeFromSuperview() }
        let at = sessions.firstIndex { $0.info.id == active }
        let end = CGFloat(sessions.count) * pillWidth
        drafting = draft != nil
        row.frame = NSRect(x: 0, y: 0, width: end + (drafting ? pillWidth : PlusSlot.width), height: SessionBar.height)
        plus.frame = NSRect(x: end, y: 0, width: PlusSlot.width, height: SessionBar.height)
        field.frame = NSRect(x: end, y: 0, width: pillWidth, height: SessionBar.height)
        plus.isHidden = drafting
        field.isHidden = !drafting
        pills = sessions.enumerated().map { i, session in
            let pill = Pill(session, active: i == at, separator: separator(at: i, count: sessions.count, active: at),
                            bar: self)
            pill.frame = NSRect(x: CGFloat(i) * pillWidth, y: 0, width: pillWidth, height: SessionBar.height)
            row.addSubview(pill)
            return pill
        }
        if let at {
            let target = pills[at].frame
            if marked != nil, marked != active, !mark.isHidden,
               !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    mark.animator().frame = target
                }
            } else {
                mark.frame = target
            }
        }
        mark.isHidden = at == nil
        marked = active
        let clip = scroller.contentView
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: offset, size: clip.bounds.size)).origin)
        if drafting {
            field.scrollToVisible(field.bounds)
        } else if let at {
            pills[at].scrollToVisible(pills[at].bounds)
            // The last pill brings the plus after it too, so no fade hides it.
            if at == pills.count - 1 { plus.scrollToVisible(plus.bounds) }
        }
        scroller.reflectScrolledClipView(clip)
        leftFade.frame = NSRect(x: scroller.frame.minX, y: 0, width: 24, height: SessionBar.height)
        rightFade.frame = NSRect(x: scroller.frame.maxX - 24, y: 0, width: 24, height: SessionBar.height)
        scrolled()
        field.show(draft)
        // The pointer may rest on a new pill or the moved plus, which no `mouseEntered` reaches until it moves.
        if let window {
            let under = { (view: NSView) in
                view.bounds.contains(view.convert(window.mouseLocationOutsideOfEventStream, from: nil))
            }
            pills.first(where: under)?.enter()
            if !plus.isHidden, under(plus) { plus.enter() } else { plus.exit() }
        }
        needsDisplay = true
        cup.needsDisplay = true
        selfTestLog("pills " + pills.map {
            $0.session.info.name + ($0.active ? "*" : "") + ($0.session.bellMark ? "!" : "")
        }.joined(separator: " "))
    }

    /// A fade shows on each edge with pills hidden behind it, and follows every scroll; a spill would stay behind.
    /// The log line comes only when the sides change, so a trackpad's stream of scrolls does not flood it.
    private func scrolled() {
        pills.forEach { $0.dropSpill() }
        let clip = scroller.contentView.bounds
        let sides = Fades(content: row.frame.width, visible: clip.width, offset: clip.minX)
        leftFade.isHidden = sides != .left && sides != .both
        rightFade.isHidden = sides != .right && sides != .both
        if sides != fades { selfTestLog("fades \(sides.rawValue)") }
        fades = sides
    }
}
