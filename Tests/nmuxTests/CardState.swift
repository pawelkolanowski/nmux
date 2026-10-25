import Foundation
import Testing
@testable import nmux
@testable import Terminal

private let old = AttachFailure.tooOld(path: "/usr/bin/tmux", version: "3.2a")
private let missingBrew = cardState(.missing, brew: true), missingNoBrew = cardState(.missing, brew: false)

struct CardStateTests {
    @Test("a card's kind gives the name the self-test logs", arguments: [
        (installingCard(""), "installing"), (installFailedCard("x"), "install-failed"),
    ])
    func aCardsKindGivesTheNameTheSelfTestLogs(card: CardState, name: String) {
        #expect(card.name == name)
    }

    @Test("missing tmux with brew offers Install last") func missingTmuxWithBrewOffersInstallLast() {
        #expect(missingBrew.name == "missing-brew")
        #expect(missingBrew.actions == [.quit, .restart, .install])
    }

    @Test("missing tmux says nmux needs tmux") func missingTmuxSaysNmuxNeedsTmux() {
        #expect(missingBrew.title == "nmux needs tmux.")
    }

    @Test("missing tmux without brew offers no Install") func missingTmuxWithoutBrewOffersNoInstall() {
        #expect(missingNoBrew.name == "missing-no-brew")
        #expect(missingNoBrew.actions == [.quit, .restart])
    }

    @Test("without brew the card gives Homebrew's and tmux's install commands")
    func withoutBrewTheCardGivesHomebrewsAndTmuxs() {
        #expect(missingNoBrew.commands == [homebrewInstall, "brew install tmux"])
    }

    @Test("an old tmux with brew offers Install") func anOldTmuxWithBrewOffersInstall() {
        #expect(cardState(old, brew: true).name == "too-old-brew")
        #expect(cardState(old, brew: true).actions.last == .install)
    }

    @Test("an old tmux names the version found and the one needed") func anOldTmuxNamesTheVersionFoundAnd() {
        #expect(cardState(old, brew: false).title == "nmux needs tmux 3.4 or newer; found 3.2a.")
        #expect(cardState(old, brew: false).name == "too-old-no-brew")
    }

    @Test("a server failure shows tmux's error, with Quit and Restart") func aServerFailureShowsTmuxsErrorWithQuit() {
        #expect(cardState(.server("boom"), brew: true)
            == CardState(kind: .server, title: "The tmux server cannot start.", detail: "boom",
                         actions: [.quit, .restart]))
    }

    @Test("a server or client failure never offers Install, with brew or without", arguments: [true, false])
    func aServerOrClientFailureNeverOffersInstall(brew: Bool) {
        #expect(cardState(.server("e"), brew: brew).actions == quitRestart)
        #expect(cardState(.client("e"), brew: brew).actions == quitRestart)
    }

    @Test("an old tmux without brew gives the install commands") func anOldTmuxWithoutBrewGivesTheInstall() {
        #expect(cardState(old, brew: false).commands == [homebrewInstall, "brew install tmux"])
    }

    @Test("a client failure shows tmux's error, with Quit and Restart") func aClientFailureShowsTmuxsErrorWithQuit() {
        #expect(cardState(.client("bad"), brew: true) == CardState(kind: .client, title: "nmux cannot attach to tmux.",
                                                                   detail: "bad", actions: [.quit, .restart]))
    }

    @Test("Install installs a missing tmux") func installInstallsAMissingTmux() {
        #expect(brewArguments(.missing) == ["install", "tmux"])
    }

    @Test("Install installs over an old tmux too") func installInstallsOverAnOldTmuxToo() {
        #expect(brewArguments(old) == ["install", "tmux"])
    }

    @Test("brew cannot help a server or client failure") func brewCannotHelpAServerOrClientFailure() {
        #expect(brewArguments(.server("e")) == nil)
        #expect(brewArguments(.client("e")) == nil)
    }

    @Test("installing shows a spinner and no buttons") func installingShowsASpinnerAndNoButtons() {
        #expect(installingCard("x").spinner)
        #expect(installingCard("x").actions.isEmpty)
    }

    @Test("a failed install offers Quit and Restart") func aFailedInstallOffersQuitAndRestart() {
        #expect(installFailedCard("e").actions == [.quit, .restart])
    }

    @Test("the latest line skips blank ones and splits on \\r") func theLatestLineSkipsBlankOnesAndSplits() {
        #expect(lastLines("a\nb\r  \nc\r\n\n", 1) == "c")
    }

    @Test("the last lines keep their order") func theLastLinesKeepTheirOrder() {
        #expect(lastLines("a\nb\nc\n", 2) == "b\nc")
    }
}
