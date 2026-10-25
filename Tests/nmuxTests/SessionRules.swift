import Foundation
import Testing
@testable import nmux
@testable import Terminal

// The Sessions: the move index, the shown Session after a diff, the reattach rule and `create`'s answer.
private let ids = (0...3).map { SessionID(number: $0) }
private let changed = clientSessionChanged("%client-session-changed /dev/ttys004 $2 my api")
private let ticked = { var card = closingCard; card.checked = true; return card }()

struct SessionRulesTests {
    @Test("a number goes to its Session") func aNumberGoesToItsSession() {
        #expect(sessionIndex(.number(2), active: 0, count: 3) == 1)
    }

    @Test("a number past the count goes to the last Session") func aNumberPastTheCountGoesToThe() {
        #expect(sessionIndex(.number(8), active: 0, count: 3) == 2)
    }

    @Test("last goes to the last Session") func lastGoesToTheLastSession() {
        #expect(sessionIndex(.last, active: 0, count: 3) == 2)
    }

    @Test("previous at the first Session wraps to the last") func previousAtTheFirstSessionWrapsToThe() {
        #expect(sessionIndex(.previous, active: 0, count: 3) == 2)
    }

    @Test("next at the last Session wraps to the first") func nextAtTheLastSessionWrapsToThe() {
        #expect(sessionIndex(.next, active: 2, count: 3) == 0)
    }

    @Test("every move among one Session stays on it",
          arguments: [SessionMove.number(1), .number(9), .last, .previous, .next])
    func everyMoveAmongOneSessionStaysOnIt(move: SessionMove) {
        #expect(sessionIndex(move, active: 0, count: 1) == 0)
    }

    @Test("the shown Session stays shown while it lives") func theShownSessionStaysShownWhileItLives() {
        #expect(activeIndex(old: ids, new: [ids[0], ids[2], ids[3]], active: ids[2]) == 1)
    }

    @Test("a removed shown Session in the middle passes the focus to the one now at its place")
    func aRemovedShownSessionInTheMiddlePasses() {
        #expect(activeIndex(old: ids, new: [ids[0], ids[2], ids[3]], active: ids[1]) == 1)
    }

    @Test("a removed shown Session at the end passes the focus to the new last")
    func aRemovedShownSessionAtTheEndPasses() {
        #expect(activeIndex(old: ids, new: [ids[0], ids[1], ids[2]], active: ids[3]) == 2)
    }

    @Test("two removed at once pass the focus to the Session at the old place, or the last")
    func twoRemovedAtOncePassTheFocusTo() {
        #expect(activeIndex(old: ids, new: [ids[0], ids[3]], active: ids[1]) == 1)
        #expect(activeIndex(old: ids, new: [ids[0], ids[1]], active: ids[2]) == 1)
    }

    @Test("no Session left has no shown one") func noSessionLeftHasNoShownOne() {
        #expect(activeIndex(old: ids, new: [], active: ids[0]) == nil)
    }

    @Test("a Session being killed never attaches again") func aSessionBeingKilledNeverAttachesAgain() {
        #expect(clientEnd(exited: true, waiting: false, killing: true, ranFor: 5) == .none)
    }

    @Test("a client that ends within a second waits for a key") func aClientThatEndsWithinASecondWaits() {
        #expect(clientEnd(exited: true, waiting: false, killing: false, ranFor: 0.3) == .wait)
    }

    @Test("a client that ended later attaches again") func aClientThatEndedLaterAttachesAgain() {
        #expect(clientEnd(exited: true, waiting: false, killing: false, ranFor: 5) == .attach)
    }

    @Test("a client that waits for a key already stays waiting") func aClientThatWaitsForAKeyAlreadyStays() {
        #expect(clientEnd(exited: true, waiting: true, killing: false, ranFor: 5) == .none)
    }

    @Test("a running client is left alone") func aRunningClientIsLeftAlone() {
        #expect(clientEnd(exited: false, waiting: false, killing: false, ranFor: 5) == .none)
    }

    @Test("an empty name leaves -s out") func anEmptyNameLeavesSOut() {
        #expect(createCommand("") == "new-session -d -P -F '#{session_id}'")
    }

    @Test("a name goes quoted, its own quote escaped") func aNameGoesQuotedItsOwnQuoteEscaped() {
        #expect(createCommand("it's x") == #"new-session -d -s 'it'\''s x' -P -F '#{session_id}'"#)
    }

    @Test("a line break in a name becomes a space") func aLineBreakInANameBecomesASpace() {
        #expect(createCommand("a\nb\rc\r\nd") == "new-session -d -s 'a b c d' -P -F '#{session_id}'")
    }

    @Test("create answers the new $ID") func createAnswersTheNewId() {
        #expect(created(ok: true, lines: ["$4"]) == .session(SessionID(number: 4)))
    }

    @Test("create hands back tmux's refusal, trimmed") func createHandsBackTmuxsRefusalTrimmed() {
        #expect(created(ok: false, lines: ["duplicate session: a "]) == .refused("duplicate session: a"))
    }

    @Test("create with no stderr says tmux did not create the Session") func createWithNoStderrSaysTmuxDidNot() {
        #expect(created(ok: false, lines: []) == .refused("tmux did not create the Session."))
    }

    @Test("a client's Session change names its tty and the Session, spaces and all")
    func aClientsSessionChangeNamesItsTtyAnd() {
        #expect(changed?.client == "/dev/ttys004")
        #expect(changed?.info == SessionInfo(id: SessionID(number: 2), name: "my api"))
    }

    @Test("any other line is no Session change") func anyOtherLineIsNoSessionChange() {
        #expect(clientSessionChanged("%session-changed $2 api") == nil)
        #expect(clientSessionChanged("%client-session-changed x y") == nil)
    }

    @Test("a move to the Session's own is ignored") func aMoveToTheSessionsOwnIsIgnored() {
        #expect(!checksMove(own: ids[1], target: ids[1], killing: false))
    }

    @Test("a move to another Session checks the own one") func aMoveToAnotherSessionChecksTheOwnOne() {
        #expect(checksMove(own: ids[1], target: ids[2], killing: false))
    }

    @Test("a Session being killed is left alone") func aSessionBeingKilledIsLeftAlone() {
        #expect(!checksMove(own: ids[1], target: ids[2], killing: true))
    }

    @Test("the closing card's default reads Close unticked and Kill All ticked")
    func theClosingCardsDefaultReadsCloseUntickedAnd() {
        #expect(closingCard.defaultAction == .close)
        #expect(closingCard.label(.close) == "Close")
        #expect(ticked.label(.close) == "Kill All")
    }

    @Test("the default button lists both labels either way") func theDefaultButtonListsBothLabelsEitherWay() {
        #expect(closingCard.labels(.close) == ["Close", "Kill All"])
        #expect(ticked.labels(.close) == closingCard.labels(.close))
    }

    @Test("a button is as wide as its wider label, padded, at least 80 pt") func aButtonIsAsWideAsItsWider() {
        #expect(buttonWidth(labels: [40.2, 61]) == 93)
        #expect(buttonWidth(labels: [61, 40.2]) == 93)
        #expect(buttonWidth(labels: [20]) == 80)
    }

    @Test("the closing card's box starts unticked, and Escape cancels")
    func theClosingCardsBoxStartsUntickedAndEscape() {
        #expect(!closingCard.checked)
        #expect(closingCard.escape == .cancel)
    }

    @Test("the Dock's Quit asks, with no reason or another one") func theDocksQuitAsksWithNoReasonOr() {
        #expect(quitAsks(own: false, reason: nil))
        #expect(quitAsks(own: false, reason: 0x7175_6974))
    }

    // The Apple event's `why` codes: 'shut', 'rest' and 'rlgo'.
    @Test("a shutdown, a restart and a logout never ask",
          arguments: [0x7368_7574, 0x7265_7374, 0x726c_676f] as [UInt32])
    func aShutdownARestartAndALogoutNeverAsk(reason: UInt32) {
        #expect(!quitAsks(own: false, reason: reason))
    }

    @Test("nmux's own quits never ask") func nmuxsOwnQuitsNeverAsk() {
        #expect(!quitAsks(own: true, reason: nil))
    }

    @Test("a bell in a hidden Session marks it") func aBellInAHiddenSessionMarksIt() {
        #expect(bell(active: false, front: true, bouncedSinceActive: false) == Bell(mark: true, attention: false))
    }

    @Test("a bell in the shown Session with nmux in front does nothing") func aBellInTheShownSessionWithNmux() {
        #expect(bell(active: true, front: true, bouncedSinceActive: false) == Bell(mark: false, attention: false))
    }

    @Test("a bell behind another app bounces the Dock icon, hidden or active")
    func aBellBehindAnotherAppBouncesTheDock() {
        #expect(bell(active: true, front: false, bouncedSinceActive: false) == Bell(mark: false, attention: true))
        #expect(bell(active: false, front: false, bouncedSinceActive: false) == Bell(mark: true, attention: true))
    }

    @Test("a second bell before nmux was active again bounces nothing") func aSecondBellBeforeNmuxWasActiveAgain() {
        #expect(bell(active: false, front: false, bouncedSinceActive: true) == Bell(mark: true, attention: false))
    }
}
