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

/// The lines a card's excerpt keeps, and the characters it keeps of each.
nonisolated let excerptLines = 5, excerptWidth = 120

/// The card for an unsafe paste: its line count, a final line break not counting, and its first lines.
nonisolated func pasteCard(_ text: String) -> CardState {
    let lines = lines(text)
    return CardState(kind: .paste, title: "Paste \(lines.count) line\(lines.count == 1 ? "" : "s")?",
                     excerpt: excerpt(lines), actions: [.cancel, .paste])
}

/// OSC 52's cards: Deny comes first and is the default, so a stray Return refuses.
nonisolated let readCard = CardState(kind: .read, title: "Allow reading the clipboard?",
                         detail: "A program in this Session asks for the clipboard's text.",
                         actions: [.deny, .allow], preferred: .deny)

nonisolated func writeCard(_ text: String) -> CardState {
    CardState(kind: .write, title: "Allow writing to the clipboard?",
              detail: "A program in this Session asks to copy this text.",
              excerpt: excerpt(lines(text)),
              actions: [.deny, .allow], preferred: .deny)
}

/// The text's lines, a final line break not opening one more.
nonisolated private func lines(_ text: String) -> [Substring] {
    var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    if lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
    return lines
}

nonisolated private func excerpt(_ lines: [Substring]) -> String {
    let cut = lines.prefix(excerptLines).map { $0.count > excerptWidth ? $0.prefix(excerptWidth) + "…" : String($0) }
    return (cut + (lines.count > excerptLines ? ["…"] : [])).joined(separator: "\n")
}
