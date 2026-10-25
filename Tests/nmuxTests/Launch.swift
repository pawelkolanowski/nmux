import Foundation
import Testing
@testable import nmux
@testable import Terminal

// Two screens side by side: the main one, and a smaller one to its right.
private let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1080)]

private let homebrew = "/opt/homebrew/bin/tmux", own = "/Users/a/bin/tmux"

struct LaunchTests {
    @Test("the pointer on the main screen picks it") func thePointerOnTheMainScreenPicksIt() {
        #expect(launchScreen(frames: screens, pointer: CGPoint(x: 700, y: 500)) == 0)
    }

    @Test("the pointer on the second screen picks it") func thePointerOnTheSecondScreenPicksIt() {
        #expect(launchScreen(frames: screens, pointer: CGPoint(x: 2000, y: 1000)) == 1)
    }

    @Test("the pointer on a screen's top edge picks that screen") func thePointerOnAScreensTopEdgePicks() {
        #expect(launchScreen(frames: screens, pointer: CGPoint(x: 700, y: 982)) == 0)
    }

    @Test("the pointer off every screen picks none") func thePointerOffEveryScreenPicksNone() {
        #expect(launchScreen(frames: screens, pointer: CGPoint(x: 700, y: 1000)) == nil)
    }

    @Test("a locale that names UTF-8 is kept",
          arguments: [["LC_CTYPE": "UTF-8"], ["LANG": "pl_PL.utf8"], ["LC_ALL": "en_GB.UTF-8"]])
    func aLocaleThatNamesUtf8IsKept(environment: [String: String]) {
        #expect(utf8Lang(environment, locale: Locale(identifier: "pl_PL"), valid: { _ in true }) == nil)
    }

    @Test("no UTF-8 locale takes the user's language and region") func noUtf8LocaleTakesTheUsersLanguage() {
        #expect(utf8Lang([:], locale: Locale(identifier: "pl_PL"), valid: { _ in true }) == "pl_PL.UTF-8")
        #expect(utf8Lang(["LC_ALL": "C"], locale: Locale(identifier: "pl_PL"), valid: { _ in true }) == "pl_PL.UTF-8")
    }

    @Test("a locale the C library lacks, or one with no region, is en_US") func aLocaleTheCLibraryLacksIsEnUs() {
        #expect(utf8Lang([:], locale: Locale(identifier: "pl_PL"), valid: { _ in false }) == "en_US.UTF-8")
        #expect(utf8Lang([:], locale: Locale(identifier: "pl"), valid: { _ in true }) == "en_US.UTF-8")
    }

    @Test("the lookup's answer is the line after the marker") func theLookupsAnswerIsTheLineAfterTheMarker() {
        #expect(lookupAnswer("Welcome!\nnmux-lookup\n/Users/a/bin/tmux\nbye\n") == "/Users/a/bin/tmux")
    }

    @Test("no line after the marker is no answer") func noLineAfterTheMarkerIsNoAnswer() {
        #expect(lookupAnswer("nmux-lookup\n") == nil)
        #expect(lookupAnswer("/opt/homebrew/bin/tmux\n") == nil)
    }

    @Test("the login shell's tmux comes first") func theLoginShellsTmuxComesFirst() {
        #expect(pickExecutable(loginAnswer: own, known: knownTmuxPaths) { [own, homebrew].contains($0) } == own)
    }

    @Test("a login answer that is not executable is skipped") func aLoginAnswerThatIsNotExecutableIs() {
        #expect(pickExecutable(loginAnswer: own, known: knownTmuxPaths) { $0 == homebrew } == homebrew)
    }

    @Test("no login answer goes to the known paths") func noLoginAnswerGoesToTheKnownPaths() {
        #expect(pickExecutable(loginAnswer: nil, known: knownTmuxPaths) { $0 == homebrew } == homebrew)
    }

    @Test("the first existing known path wins") func theFirstExistingKnownPathWins() {
        #expect(pickExecutable(loginAnswer: nil, known: knownTmuxPaths) {
            ["/usr/bin/tmux", "/opt/local/bin/tmux"].contains($0)
        } == "/opt/local/bin/tmux")
    }

    @Test("no tmux anywhere finds none") func noTmuxAnywhereFindsNone() {
        #expect(pickExecutable(loginAnswer: own, known: knownTmuxPaths) { _ in false } == nil)
    }
}
