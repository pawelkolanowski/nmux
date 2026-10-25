import CoreText
import Foundation
import Testing
@testable import nmux
@testable import Terminal

// A row as the run iterator sees it: one cell per character, all in style 0 and face 0 unless set.
private func row(_ text: String) -> [RunCell] {
    text.unicodeScalars.map { RunCell(codepoints: [$0.value], empty: false) }
}
// The row with `change` applied to it.
private func row(_ text: String, _ change: (inout [RunCell]) -> Void) -> [RunCell] {
    var cells = row(text)
    change(&cells)
    return cells
}
private let styled = row("abcd") { $0[2].style = 1; $0[3].style = 1 }
private let faced = row("ab中") { $0[2].face = 1 }
private let wide = row("中 a") { $0[1] = RunCell(spacer: true); $0 += [RunCell(), RunCell()] }
private let hidden = row("ab") { $0[0].invisible = true; $0[0].style = 1 }
private let marked = row("ab") { $0[1].codepoints = [0x65, 0x301] }

private let pair = runText(row("\u{1D400}a")[...])
private let ligature = runText(row("->x")[...])
private let accent = runText([RunCell(codepoints: [0x65, 0x301], empty: false),
                              RunCell(codepoints: [0x61], empty: false)][...])
private let rtl = runText(row("a\u{5D0}b")[...])

struct RunTests {
    @Test("a run breaks where the style changes") func aRunBreaksWhereTheStyleChanges() {
        #expect(runs(styled, cursor: nil) == [0..<2, 2..<4])
    }

    @Test("a run breaks where the face changes") func aRunBreaksWhereTheFaceChanges() {
        #expect(runs(faced, cursor: nil) == [0..<2, 2..<3])
    }

    @Test("a run breaks on both sides of the cursor") func aRunBreaksOnBothSidesOfThe() {
        #expect(runs(row("a->b"), cursor: 2) == [0..<2, 2..<3, 3..<4])
    }

    @Test("a run breaks between f and i, f and l, s and t") func aRunBreaksBetweenFAndIF() {
        #expect(runs(row("xfiflst"), cursor: nil) == [0..<2, 2..<4, 4..<6, 6..<7])
    }

    @Test("a spacer rides with its run and trailing empty cells are trimmed") func aSpacerRidesWithItsRunAndTrailing() {
        #expect(runs(wide, cursor: nil) == [0..<3])
    }

    @Test("an invisible cell is never shaped") func anInvisibleCellIsNeverShaped() {
        #expect(runs(hidden, cursor: nil) == [1..<2])
    }

    @Test("the cursor on a grapheme breaks no run, as in Ghostty") func theCursorOnAGraphemeBreaksNoRun() {
        #expect(runs(marked + row("c"), cursor: 1) == [0..<3])
    }

    @Test("a run breaks at a selection's edges inside a row") func aRunBreaksAtASelectionsEdgesInside() {
        #expect(runs(row("a->b"), cursor: nil, selection: 1...1) == [0..<1, 1..<2, 2..<4])
    }

    @Test("a selection from the row's start breaks only after its end") func aSelectionFromTheRowsStartBreaksOnly() {
        #expect(runs(row("->"), cursor: nil, selection: 0...0) == [0..<1, 1..<2])
    }

    @Test("a surrogate pair maps both its units to its cell, the second as codepoint 0")
    func aSurrogatePairMapsBothItsUnitsTo() {
        #expect(pair.utf16.count == 3)
        #expect(pair.map.map(\.codepoint) == [0x1D400, 0, 0x61])
        #expect(pair.map.map(\.cluster) == [0, 0, 1])
    }

    @Test("a glyph after a surrogate pair opens the next cell") func aGlyphAfterASurrogatePairOpensThe() {
        #expect(cellsOf([LaidGlyph(index: 0, advance: 10), LaidGlyph(index: 2, x: 10, advance: 10)], map: pair.map)
            .map(\.cell) == [0, 1])
    }

    @Test("a ligature stays on its first cell and the next cluster opens its own")
    func aLigatureStaysOnItsFirstCellAnd() {
        #expect(cellsOf([LaidGlyph(index: 0, advance: 20), LaidGlyph(index: 2, x: 20, advance: 10)], map: ligature.map)
            .map { [$0.cell, $0.x] } == [[0, 0], [2, 0]])
    }

    @Test("the shaping tests run in SF Mono") func theShapingTestsRunInSfMono() {
        #expect((CTFontCopyFamilyName(sfMono(28)) as String).hasSuffix("SF NS Mono"))
    }

    @Test("CoreText shapes a decomposed accent onto its base's cell and the next letter onto its own")
    func coretextShapesADecomposedAccentOntoItsBases() {
        let accented = shape(accent, in: shapingFont(sfMono(28)))
        #expect(cellsOf(accented.map(\.laid), map: accent.map).map(\.cell)
            .reduce(into: [Int]()) { if $0.last != $1 { $0.append($1) } } == [0, 1])
    }

    @Test("a right-to-left letter never reorders the run") func aRightToLeftLetterNeverReordersThe() {
        #expect(shape(rtl, in: shapingFont(sfMono(28))).map(\.laid.index) == [0, 1, 2])
    }
}
