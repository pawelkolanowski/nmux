import Foundation
import Testing
@testable import nmux
@testable import Terminal

// The wheel, against a cell 20 pixels high.
private func scrolled(_ deltas: [Double], precise: Bool) -> [Int] {
    var wheel = WheelScroll()
    return deltas.map { wheel.lines($0, precise: precise, cell: 20) }
}

// Cells as the terminal holds them: one string a cell.
private func urlAt(_ text: String, _ x: Int) -> String? {
    let cells = text.map(String.init)
    return urlCells(cells, at: x).map { cells[$0].joined() }
}

struct MouseTests {
    @Test("a precise run of small deltas makes exactly the lines their sum makes")
    func aPreciseRunOfSmallDeltasMakesExactly() {
        #expect(scrolled([Double](repeating: 6, count: 10), precise: true).reduce(0, +) == 3)
    }

    @Test("a precise delta under a cell makes no line until the next one makes it whole")
    func aPreciseDeltaUnderACellMakesNo() {
        #expect(scrolled([15, 5], precise: true) == [0, 1])
    }

    @Test("a notch makes three lines, a slow notch of 0.1 too") func aNotchMakesThreeLinesASlowNotch() {
        #expect(scrolled([1], precise: false) == [3])
        #expect(scrolled([0.1], precise: false) == [3])
    }

    @Test("a notch down makes three lines down") func aNotchDownMakesThreeLinesDown() {
        #expect(scrolled([-1], precise: false) == [-3])
    }

    @Test("a reversal undoes the pending part and never skips a line") func aReversalUndoesThePendingPartAndNever() {
        #expect(scrolled([15, -15, -15, -10], precise: true) == [0, 0, 0, -1])
    }

    @Test("a URL in a row is found from any of its cells") func aUrlInARowIsFoundFrom() {
        #expect(urlAt("see https://example.com/a?b=1 now", 10) == "https://example.com/a?b=1")
    }

    @Test("a cell beside the URL finds none") func aCellBesideTheUrlFindsNone() {
        #expect(urlAt("see https://example.com now", 2) == nil)
    }

    @Test("a URL ending a sentence leaves its full stop out") func aUrlEndingASentenceLeavesItsFull() {
        #expect(urlAt("at https://example.com.", 5) == "https://example.com")
    }

    @Test("a URL in parentheses leaves them out, one with its own pair keeps it")
    func aUrlInParenthesesLeavesThemOutOne() {
        #expect(urlAt("(https://example.com)", 3) == "https://example.com")
        #expect(urlAt("https://en.wikipedia.org/wiki/Rust_(video_game)", 3)
            == "https://en.wikipedia.org/wiki/Rust_(video_game)")
    }

    @Test("mailto and ssh URLs are found") func mailtoAndSshUrlsAreFound() {
        #expect(urlAt("mailto:a@b.c", 0) == "mailto:a@b.c")
        #expect(urlAt("ssh://host", 0) == "ssh://host")
    }

    @Test("a wide cell before the URL keeps the cells in step") func aWideCellBeforeTheUrlKeepsThe() {
        #expect(urlCells(["中", "", " ", "h", "t", "t", "p", ":", "/", "/", "a"], at: 4) == 3..<11)
    }

    @Test("a plain path is not a link") func aPlainPathIsNotALink() {
        #expect(urlAt("/usr/bin/tmux", 2) == nil)
    }

    @Test("an https URL with a host opens") func anHttpsUrlWithAHostOpens() {
        #expect(openable("https://example.com/x") != nil)
    }

    @Test("an http URL with no host never opens") func anHttpUrlWithNoHostNeverOpens() {
        #expect(openable("https:relative") == nil)
    }

    @Test("a mailto with an address opens, a bare mailto never") func aMailtoWithAnAddressOpensABare() {
        #expect(openable("mailto:a@b.c") != nil)
        #expect(openable("mailto:") == nil)
    }

    @Test("a custom scheme never opens") func aCustomSchemeNeverOpens() {
        #expect(openable("ssh://host") == nil)
    }

    @Test("a target with a hidden character never opens") func aTargetWithAHiddenCharacterNeverOpens() {
        #expect(openable("https://exa\u{200B}mple.com") == nil)
    }

    @Test("a local directory opens, an executable never") func aLocalDirectoryOpensAnExecutableNever() {
        #expect(openable("file:///Users") != nil)
        #expect(openable("file:///bin/ls") == nil)
    }

    @Test("a file on another host never opens") func aFileOnAnotherHostNeverOpens() {
        #expect(openable("file://elsewhere/Users") == nil)
    }
}
