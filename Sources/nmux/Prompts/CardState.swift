import Foundation

/// A button on a card. The self-test presses one by this name.
nonisolated enum CardAction: String, Sendable {
    case quit, restart, install, cancel, paste, deny, allow, close, dismiss, openConfig
}

/// Which card it is: a failed attach's, brew's install, a clipboard ask, Closing nmux or the Config's problems.
nonisolated enum CardKind: Equatable, Sendable {
    case missing(brew: Bool), tooOld(brew: Bool), server, client, installing, installFailed
    case paste, read, write, closing, configProblems(Int)

    /// The name the self-test logs it by.
    var name: String {
        switch self {
        case .missing(let brew): "missing-\(brew ? "brew" : "no-brew")"
        case .tooOld(let brew): "too-old-\(brew ? "brew" : "no-brew")"
        case .server: "server"
        case .client: "client"
        case .installing: "installing"
        case .installFailed: "install-failed"
        case .paste: "paste"
        case .read: "read"
        case .write: "write"
        case .closing: "closing"
        case .configProblems(let count): "config-problems \(count)"
        }
    }
}

/// What a card shows: a pure value the card view draws and the self-test logs by its kind's name. The excerpt is text a
/// program handles, drawn in the terminal's face. The default action, which Return presses, is `preferred`, else the
/// last one.
nonisolated struct CardState: Equatable, Sendable {
    let kind: CardKind
    let title: String
    var detail: String? = nil
    var excerpt: String? = nil
    var commands: [String] = []
    var spinner = false
    let actions: [CardAction]
    var preferred: CardAction? = nil
    /// A checkbox's label under the title, the closing card's `Kill all Sessions`, and whether it is ticked.
    var checkbox: String? = nil
    var checked = false

    var name: String { kind.name }
    var defaultAction: CardAction? { preferred ?? actions.last }
    /// What Escape presses; a click outside the panel presses it too, unless it quits.
    var escape: CardAction? { actions.first { [.cancel, .deny, .quit, .dismiss].contains($0) } }

    /// What a button reads now, and every label it may read, so its width never changes. Close reads `Kill All` while
    /// the box is ticked.
    func label(_ action: CardAction) -> String {
        switch action {
        case .close where checked: "Kill All"
        case .openConfig: "Open Config"
        default: action.rawValue.capitalized
        }
    }
    func labels(_ action: CardAction) -> [String] { action == .close ? ["Close", "Kill All"] : [label(action)] }
}

/// A button's width: its widest label with 16 pt each side, at least 80 pt.
nonisolated func buttonWidth(labels: [CGFloat]) -> CGFloat {
    max(80, (labels.max() ?? 0).rounded(.up) + 32)
}
