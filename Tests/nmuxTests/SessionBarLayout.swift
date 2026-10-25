import Foundation
import Testing
@testable import nmux
@testable import Terminal

// The Session bar: the separator rule, the name cut, the fade sides and the cup.
// Widths in columns: a wide character takes two.
private func columns(_ s: String) -> Int {
    s.reduce(0) { $0 + (($1.unicodeScalars.first?.value ?? 0) >= 0x1100 && $1 != "…" ? 2 : 1) }
}
private func fitsTen(_ s: String) -> Bool { columns(s) <= 10 }

struct SessionBarLayoutTests {
    @Test("a separator stands between two inactive pills") func aSeparatorStandsBetweenTwoInactivePills() {
        #expect(separator(at: 1, count: 4, active: 0))
    }

    @Test("the first pill has a separator when the active one is further on") func theFirstPillHasASeparatorWhenThe() {
        #expect(separator(at: 0, count: 4, active: 2))
    }

    @Test("no separator after the last pill") func noSeparatorAfterTheLastPill() {
        #expect(!separator(at: 3, count: 4, active: 0))
    }

    @Test("no separator beside the active pill") func noSeparatorBesideTheActivePill() {
        #expect(!separator(at: 1, count: 4, active: 1))
        #expect(!separator(at: 0, count: 4, active: 1))
    }

    @Test("a single pill has no separator") func aSinglePillHasNoSeparator() {
        #expect(!separator(at: 0, count: 1, active: 0))
    }

    @Test("a short name stays whole") func aShortNameStaysWhole() {
        #expect(cutName("api", fits: fitsTen) == "api")
    }

    @Test("a name that fits exactly stays whole") func aNameThatFitsExactlyStaysWhole() {
        #expect(cutName("abcdefghij", fits: fitsTen) == "abcdefghij")
    }

    @Test("a long name is cut in the middle, its start the longer part") func aLongNameIsCutInTheMiddle() {
        #expect(cutName("abcdefghijklmnop", fits: fitsTen) == "abcde…mnop")
    }

    @Test("a wide name is cut between characters and fits") func aWideNameIsCutBetweenCharactersAnd() {
        #expect({ let c = cutName("中文中文中文中文", fits: fitsTen); return c == "中文…中文" && fitsTen(c) }())
    }

    @Test("a row that fits fades nowhere") func aRowThatFitsFadesNowhere() {
        #expect(Fades(content: 300, visible: 400, offset: 0) == .none)
    }

    @Test("a row at its start fades right") func aRowAtItsStartFadesRight() {
        #expect(Fades(content: 1000, visible: 400, offset: 0) == .right)
    }

    @Test("a row in the middle fades both sides") func aRowInTheMiddleFadesBothSides() {
        #expect(Fades(content: 1000, visible: 400, offset: 300) == .both)
    }

    @Test("a row at its end fades left") func aRowAtItsEndFadesLeft() {
        #expect(Fades(content: 1000, visible: 400, offset: 600) == .left)
    }

    @Test("the cup off shows a moon and Sleep allowed, its tip offering to keep the Mac awake")
    func theCupOffShowsAMoonAndSleep() {
        #expect(cupLook(nil) == CupLook(icon: "moon.zzz", label: "Sleep allowed",
                                        tip: "Click to keep the Mac awake while nmux runs."))
    }

    @Test("the cup holding an assertion shows a cup and On the beans, its tip offering to let it sleep")
    func theCupHoldingAnAssertionShowsACup() {
        #expect(cupLook(7) == CupLook(icon: "cup.and.heat.waves.fill", label: "On the beans",
            tip: "The Mac stays awake while nmux runs. Click to let it sleep."))
    }

    @Test("the cup's slot takes the wider label") func theCupsSlotTakesTheWiderLabel() {
        #expect(cupWidth(labels: [80, 72.5]) == 121)
        #expect(cupWidth(labels: [72.5, 80]) == 121)
    }

    @Test("open with no draft starts an empty one") func openWithNoDraftStartsAnEmptyOne() {
        #expect(nextDraft(nil, .open) == Draft())
    }

    @Test("open with a draft keeps it") func openWithADraftKeepsIt() {
        #expect(nextDraft(Draft(name: "a", error: "e"), .open) == Draft(name: "a", error: "e"))
    }

    @Test("a submit keeps the name and drops the refusal") func aSubmitKeepsTheNameAndDropsThe() {
        #expect(nextDraft(Draft(name: "a", error: "e"), .submit("b")) == Draft(name: "b"))
    }

    @Test("a new $ID ends the draft") func aNewIdEndsTheDraft() {
        #expect(nextDraft(Draft(name: "b"), .answer(.session(SessionID(number: 3)))) == nil)
    }

    @Test("a refusal keeps the name with tmux's error") func aRefusalKeepsTheNameWithTmuxsError() {
        #expect(nextDraft(Draft(name: "a"), .answer(.refused("duplicate session: a")))
            == Draft(name: "a", error: "duplicate session: a"))
    }

    @Test("cancel ends the draft") func cancelEndsTheDraft() {
        #expect(nextDraft(Draft(name: "a", error: "e"), .cancel) == nil)
    }

    @Test("a refusal then a good name ends the draft") func aRefusalThenAGoodNameEndsThe() {
        #expect(nextDraft(nextDraft(nextDraft(Draft(name: "a", error: "e"), .submit("b")),
                                    .answer(.session(SessionID(number: 4)))), .open) == Draft())
    }

    @Test("an answer after a cancel opens nothing") func anAnswerAfterACancelOpensNothing() {
        #expect(nextDraft(nil, .answer(.refused("e"))) == nil)
        #expect(nextDraft(nil, .submit("a")) == nil)
    }
}
