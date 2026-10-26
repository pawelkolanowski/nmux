import AppKit
import Terminal

/// The cards: a failed attach's and brew's install, the clipboard's asks, the Config's problems and Closing nmux. One
/// card shows at a time, over the window, and takes the keys while it shows.
extension AppDelegate {
    var closingCardShows: Bool { card?.state.kind == .closing }
    var configCardShows: Bool {
        if case .configProblems = card?.state.kind { true } else { false }
    }
    /// A card that asks nothing, a failed attach's or brew's install, which a close quits past.
    var cardOnlyReports: Bool { card != nil && !closingCardShows && !configCardShows && clipboardAnswer == nil }

    /// The Config's card, once a Session shows and no other prompt is open; one already showing takes the new list.
    func showConfigProblems() {
        guard let problems = appearance.problems, card == nil || configCardShows, mirror.asking == nil, let font,
              mirror.activeSession != nil, let content else { return }
        // The terminal's face at 12 pt for these lines; the clipboard's excerpt keeps the terminal's size.
        let face = CTFontCreateCopyWithAttributes(font.primary, 12, nil, nil) as NSFont,
            room = CardView.textWidth(in: content.bounds.width)
        showCard(configCard(problems) { textSize($0, [.font: face]).width <= room })
        card?.excerptFont = face
    }

    /// Every failure shows its card. The brew lookup may wait 2 s on the login shell, so it runs off the main thread,
    /// and only for a failure brew can fix.
    nonisolated func attachFailed(_ failure: AttachFailure) {
        selfTestLog("failure \(failure.log)")
        DispatchQueue.global().async {
            let brew = brewArguments(failure).flatMap { arguments in
                findBrew().map { Brew(path: $0, arguments: arguments) }
            }
            onMain {
                self.brew = brew
                self.showCard(cardState(failure, brew: brew != nil))
            }
        }
    }

    func showCard(_ state: CardState) {
        guard let content else { return }
        if card?.state.name != state.name { selfTestLog("card \(state.name)") }
        if let card {
            card.state = state
        } else {
            let card = CardView(state) { self.press($0) }
            card.frame = content.bounds
            content.addSubview(card)
            // The card fades in over its dim. Core Animation's own fade, since AppKit's animator leaves the alpha at
            // its start while the window does not show.
            card.wantsLayer = true
            let fade = CABasicAnimation(keyPath: "opacity")
            (fade.fromValue, fade.duration) = (0, 0.14)
            card.layer?.add(fade, forKey: "fade")
            window?.makeFirstResponder(card)
            self.card = card
        }
#if NMUX_SELFTEST
        // The self-test presses NMUX_SELFTEST_PRESS on every card that offers it, a moment after it shows.
        if let name = SelfTest.press, let action = CardAction(rawValue: name), state.actions.contains(action) {
            onMain(after: 0.2) { if self.card?.state == state { self.press(action) } }
        }
#endif
    }

    func press(_ action: CardAction) {
        selfTestLog("press \(action.rawValue)")
        switch action {
        case .quit: quit()
        case .close: closeAnswered(all: card?.state.checked == true)
        case .restart: restart()
        case .install: if let brew { install(brew) }
        case .paste, .allow: answered(true)
        case .dismiss:
            appearance.problems = nil
            answered(false)
        case .openConfig:
            appearance.problems = nil
            answered(false)
            openConfig()
        case .cancel, .deny:
            if closingCardShows { selfTestLog("answer cancel" + (card?.state.checked == true ? " all" : "")) }
            answered(false)
        }
    }

    /// A clipboard card over the terminal. A card already showing, or an asking pill, refuses the ask.
    /// limitation: one card covers the window, whichever Session asked; give each Session its own card once a hidden
    /// Session's ask misleads.
    func ask(_ ask: ClipboardAsk, _ answer: @escaping (Bool) -> Void) {
        guard card == nil, mirror.asking == nil else { return answer(false) }
        clipboardAnswer = answer
        switch ask {
        case .paste(let text): showCard(pasteCard(text))
        case .read: showCard(readCard)
        case .write(let text): showCard(writeCard(text))
        }
        if let font {
            card?.excerptFont = CTFontCreateCopyWithAttributes(font.primary, font.points, nil, nil) as NSFont
        }
    }

    func answered(_ yes: Bool) {
        card?.removeFromSuperview()
        card = nil
        window?.makeFirstResponder(terminal)
        let answer = clipboardAnswer
        clipboardAnswer = nil
        answer?(yes)
        showConfigProblems()
    }

    /// The lookup, the version check and the attach again, in place; a failure brings the card back.
    func restart() {
        card?.removeFromSuperview()
        card = nil
        if let window { attach(window) }
    }

    /// The card shows brew's latest line while it runs; exit 0 restarts, anything else shows its last lines.
    func install(_ brew: Brew) {
        brewOutput = Data()
        showCard(installingCard(""))
        do {
            brewPID = try brew.run(onOutput: { data in
                onMain {
                    self.brewOutput += data
                    self.showCard(installingCard(lastLines(String(decoding: self.brewOutput, as: UTF8.self), 1)))
                }
            }, onExit: { status in
                onMain {
                    self.brewPID = nil
                    if status == 0 { return self.restart() }
                    self.showCard(installFailedCard(lastLines(String(decoding: self.brewOutput, as: UTF8.self), 5)))
                }
            })
        } catch {
            showCard(installFailedCard("\(error)"))
        }
    }
}
