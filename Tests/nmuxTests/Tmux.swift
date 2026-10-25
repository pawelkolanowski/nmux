import Foundation
import Testing
@testable import nmux
@testable import Terminal

struct TmuxTests {
    @Test("the version is what follows tmux") func theVersionIsWhatFollowsTmux() {
        #expect(tmuxVersion("tmux 3.7c") == "3.7c")
    }

    @Test("tmux 3.4 or newer is new enough", arguments: ["3.7c", "3.4", "next-3.8", "4.0"])
    func newEnough(version: String) {
        #expect(tmuxIsNewEnough(version))
    }

    @Test("an older or a garbage version is too old", arguments: ["3.3a", "master", "garbage", ""])
    func tooOld(version: String) {
        #expect(!tmuxIsNewEnough(version))
    }

    @Test("the lowest $ID wins, $10 after $9") func theLowestIdWins10After9() {
        #expect(lowestSession("$10\n$9\n$11\n")?.description == "$9")
    }

    @Test("$1 wins over $3") func n1WinsOver3() {
        #expect(lowestSession("$3\n$1")?.description == "$1")
    }

    @Test("no Session gives none") func noSessionGivesNone() {
        #expect(lowestSession("") == nil)
    }

    @Test("the status line takes the rows its option names") func theStatusLineTakesTheRowsItsOption() {
        #expect(statusRows("off\n") == 0)
        #expect(statusRows("on\n") == 1)
        #expect(statusRows("3") == 3)
    }

    @Test("an unreadable status option counts one row") func anUnreadableStatusOptionCountsOneRow() {
        #expect(statusRows("") == 1)
    }

    @Test("brew is looked up at its known paths in order") func brewIsLookedUpAtItsKnownPaths() {
        #expect(pickExecutable(loginAnswer: nil, known: knownBrewPaths) { _ in true } == "/opt/homebrew/bin/brew")
    }
}
