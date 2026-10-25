import Foundation

// The Session bar's pure rules.

/// A thin separator stands at an inactive pill's right edge, unless it is the last pill or the next one is active.
nonisolated func separator(at i: Int, count: Int, active: Int?) -> Bool {
    i < count - 1 && i != active && i + 1 != active
}

/// The name as a pill shows it: whole when it fits, else cut in the middle with an ellipsis, its start one character
/// longer than its end where they differ. Cuts fall between characters, so a wide character is never split.
nonisolated func cutName(_ name: String, fits: (String) -> Bool) -> String {
    guard !fits(name) else { return name }
    let chars = Array(name)
    for kept in stride(from: chars.count - 1, through: 0, by: -1) {
        let label = String(chars.prefix((kept + 1) / 2)) + "…" + String(chars.suffix(kept / 2))
        if fits(label) { return label }
    }
    return "…"
}

/// The bin on an asking pill, which alone kills: 30 pt wide, 7 pt from the pill's top and bottom, 6 pt from its right
/// end.
nonisolated func binRect(_ pill: CGRect) -> CGRect {
    CGRect(x: pill.maxX - 6 - 30, y: pill.minY + 7, width: 30, height: pill.height - 14)
}

/// The row's edges where pills lie hidden: the left one once scrolled from its start, the right one while pills lie
/// past the visible end. Within half a point counts as there.
nonisolated enum Fades: String {
    case none, left, right, both

    init(content: CGFloat, visible: CGFloat, offset: CGFloat) {
        switch (offset > 0.5, offset + visible < content - 0.5) {
        case (true, true): self = .both
        case (true, false): self = .left
        case (false, true): self = .right
        case (false, false): self = .none
        }
    }
}

/// What a pill's left 28 pt shows: the close mark on the active pill and the one under the pointer, else the bell dot
/// on a Session with the Bell mark, else nothing.
nonisolated enum LeftSlot: Equatable {
    case close, dot, nothing
}

nonisolated func leftSlot(active: Bool, hovered: Bool, bell: Bool) -> LeftSlot {
    if active || hovered { return .close }
    return bell ? .dot : .nothing
}

/// What the Keep-awake cup shows and its tip says, from the assertion it holds: an ID is on, none is off.
nonisolated struct CupLook: Equatable {
    let icon, label, tip: String
}

nonisolated func cupLook(_ hold: UInt32?) -> CupLook {
    hold == nil
        ? CupLook(icon: "moon.zzz", label: "Sleep allowed", tip: "Click to keep the Mac awake while nmux runs.")
        : CupLook(icon: "cup.and.heat.waves.fill", label: "On the beans",
                  tip: "The Mac stays awake while nmux runs. Click to let it sleep.")
}

/// The cup's slot: padding each side, the icon and a gap before the wider label, so it never resizes.
nonisolated let cupPad: CGFloat = 10, cupIcon: CGFloat = 15, cupGap: CGFloat = 6

nonisolated func cupWidth(labels: [CGFloat]) -> CGFloat {
    (cupPad + cupIcon + cupGap + (labels.max() ?? 0) + cupPad).rounded(.up)
}
