import Foundation

/// A button on a card. The self-test presses one by this name.
nonisolated enum CardAction: String, Sendable {
    case quit, restart, install
}

/// Which card it is: a failed attach's or brew's install.
nonisolated enum CardKind: Equatable, Sendable {
    case missing(brew: Bool), tooOld(brew: Bool), server, client, installing, installFailed

    /// The name the self-test logs it by.
    var name: String {
        switch self {
        case .missing(let brew): "missing-\(brew ? "brew" : "no-brew")"
        case .tooOld(let brew): "too-old-\(brew ? "brew" : "no-brew")"
        case .server: "server"
        case .client: "client"
        case .installing: "installing"
        case .installFailed: "install-failed"
        }
    }
}

/// What a card shows: a pure value the card view draws and the self-test logs by its kind's name. The default action,
/// which Return presses, is the last one.
nonisolated struct CardState: Equatable, Sendable {
    let kind: CardKind
    let title: String
    var detail: String? = nil
    var commands: [String] = []
    var spinner = false
    let actions: [CardAction]

    var name: String { kind.name }
    var defaultAction: CardAction? { actions.last }
    /// What Escape presses.
    var escape: CardAction? { actions.first { $0 == .quit } }

    /// What a button reads.
    func label(_ action: CardAction) -> String { action.rawValue.capitalized }
}

/// A button's width: its widest label with 16 pt each side, at least 80 pt.
nonisolated func buttonWidth(labels: [CGFloat]) -> CGFloat {
    max(80, (labels.max() ?? 0).rounded(.up) + 32)
}
