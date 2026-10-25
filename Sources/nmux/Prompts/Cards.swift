import Foundation

/// What a card offers when nothing nmux can run fixes the problem.
nonisolated let quitRestart: [CardAction] = [.quit, .restart]

nonisolated let homebrewInstall = #"/bin/bash -c "$(curl -fsSL "#
    + #"https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

/// The card for a failed attach. Install is offered only for a missing or old tmux, and only with brew.
nonisolated func cardState(_ failure: AttachFailure, brew: Bool) -> CardState {
    let title: String, kind: (Bool) -> CardKind
    switch failure {
    case .missing: (title, kind) = ("nmux needs tmux.", { .missing(brew: $0) })
    case let .tooOld(_, version):
        (title, kind) = ("nmux needs tmux 3.4 or newer; found \(version).", { .tooOld(brew: $0) })
    case let .server(error):
        return CardState(kind: .server, title: "The tmux server cannot start.", detail: error, actions: quitRestart)
    case let .client(error):
        return CardState(kind: .client, title: "nmux cannot attach to tmux.", detail: error, actions: quitRestart)
    }
    if brew { return CardState(kind: kind(true), title: title, actions: [.quit, .restart, .install]) }
    return CardState(kind: kind(false), title: title,
                     detail: "Install Homebrew and tmux in another terminal, then press Restart.",
                     commands: [homebrewInstall, "brew install tmux"], actions: quitRestart)
}

/// What Install runs brew with; nil when brew cannot help. `brew install` also upgrades an outdated
/// tmux, and unlike `brew upgrade` it works on an old tmux that brew did not install.
nonisolated func brewArguments(_ failure: AttachFailure) -> [String]? {
    switch failure {
    case .missing, .tooOld: ["install", "tmux"]
    case .server, .client: nil
    }
}

nonisolated func installingCard(_ line: String) -> CardState {
    CardState(kind: .installing, title: "Installing tmux…", detail: line, spinner: true, actions: [])
}

nonisolated func installFailedCard(_ lines: String) -> CardState {
    CardState(kind: .installFailed, title: "brew could not install tmux.", detail: lines, actions: quitRestart)
}

/// The last `count` non-blank lines of brew's output; a `\r` progress update counts as a line.
nonisolated func lastLines(_ output: String, _ count: Int) -> String {
    output.split(whereSeparator: \.isNewline)
        .filter { !$0.allSatisfy(\.isWhitespace) }
        .suffix(count).joined(separator: "\n")
}
