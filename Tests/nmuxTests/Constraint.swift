import Foundation
import Testing
@testable import nmux
@testable import Terminal

private let covered = Constraint.emoji.constrain(GlyphBox(x: 3, y: -5, width: 100, height: 100), cell: decorated,
                                                 width: 2)
private let narrow = Constraint.emoji.constrain(GlyphBox(x: 0, y: 0, width: 100, height: 100), cell: decorated,
                                                width: 1)

// Ghostty's own constraint test: JetBrains Mono's cell at 12 pt and 96 dpi, Symbols Nerd Font's boxes at 16 px with the
// baseline added. The Font Awesome and Material Design results come from a transliteration of Ghostty's Zig.
private let jetBrains = Cell(width: 10, height: 22, baseline: 5, underlinePosition: 19, underlineThickness: 1,
                             strikethroughPosition: 12, strikethroughThickness: 1, cursorThickness: 1, faceWidth: 9.6,
                             faceHeight: 21.12, faceY: 0.2, iconHeight: 21.12, iconHeightSingle: 44.48 / 3)
private func rounded(_ b: GlyphBox) -> [Double] { [b.x, b.y, b.width, b.height].map { ($0 * 1e5).rounded() / 1e5 } }
private func placed(_ cp: UInt32, _ box: GlyphBox, width: Int) -> [Double] {
    rounded(glyphConstraint(cp).constrain(box, cell: jetBrains, width: width))
}
private let lightbulb = GlyphBox(x: 3.015625, y: 3.76525, width: 9.015625, height: 13.015625)
private let home = GlyphBox(x: 0, y: 2.4140625, width: 16.65625, height: 14.765625)
private let square = GlyphBox(x: 0, y: 3.140625, width: 13.3125, height: 13.3125)
private let flame = GlyphBox(x: -0.796875, y: 1.7109375, width: 16.796875, height: 16.46875)
private let blackSquare = GlyphBox(x: 2.864, y: 5.304, width: 10.272, height: 10.272)
private func fitted(_ width: Int) -> [Double] {
    rounded(Constraint.fit.constrain(blackSquare, cell: jetBrains, width: width))
}

struct ConstraintTests {
    @Test("a square emoji covers the face's height over two cells and centres in them")
    func aSquareEmojiCoversTheFacesHeightOver() {
        #expect([covered.x, covered.y, covered.width, covered.height].map { ($0 * 1e6).rounded() / 1e6 }
            == [0.5, 0, 33, 33])
    }

    @Test("in one cell it covers the cell's width less its padding") func inOneCellItCoversTheCellsWidth() {
        #expect(abs(narrow.width - 0.95 * 17) < 1e-9)
        #expect(narrow.x > 0)
    }

    @Test("a Codicon scales its icon group to one cell's icon height and centres it there, as Ghostty")
    func aCodiconScalesItsIconGroupToOne() {
        #expect(placed(0xEA61, lightbulb, width: 1) == [0.8125, 5.9507, 7.2125, 10.4125])
    }

    @Test("over two cells the Codicon keeps its size and its group aligns to the first cell, as Ghostty")
    func overTwoCellsTheCodiconKeepsItsSize() {
        #expect(placed(0xEA61, lightbulb, width: 2)
            == [1.01563, 4.74837, 9.015625, 13.015625].map { ($0 * 1e5).rounded() / 1e5 })
    }

    @Test("a Font Awesome icon shrinks to one face width, and over two cells keeps its own size")
    func aFontAwesomeIconShrinksToOneFace() {
        #expect(placed(0xF015, home, width: 1) == [0, 6.50484, 9.6, 8.51032])
        #expect(placed(0xF015, home, width: 2) == [0, 3.37719, 16.65625, 14.76563])
    }

    @Test("a Material Design icon fits one face width, and over two cells keeps its own size")
    func aMaterialDesignIconFitsOneFaceWidth() {
        #expect(placed(0xF0001, square, width: 1) == [0, 5.96, 9.6, 9.6])
        #expect(placed(0xF0001, square, width: 2) == [0, 4.10375, 13.3125, 13.3125])
    }

    @Test("a Powerline extra glyph stretches over exactly its cells, as Ghostty")
    func aPowerlineExtraGlyphStretchesOverExactlyIts() {
        #expect(placed(0xE0C0, flame, width: 1) == [0, 0, 10, 22])
        #expect(placed(0xE0C0, flame, width: 2) == [0, 0, 20, 22])
    }

    @Test("a symbol that fits scales down into one cell and leaves two alone, as Ghostty")
    func aSymbolThatFitsScalesDownIntoOne() {
        #expect(fitted(1) == [0, 5.64, 9.6, 9.6])
        #expect(fitted(2) == [2.864, 5.304, 10.272, 10.272])
    }

    @Test("a symbol without a table entry fits, a letter takes no constraint") func aSymbolWithoutATableEntryFitsA() {
        #expect(nerdFontConstraint(0x1F680) == nil)
        #expect(glyphConstraint(0x1F680) == .fit)
        #expect(glyphConstraint(0x41) == .none)
    }

    @Test("the table's first and last ranges end where Ghostty's do") func theTablesFirstAndLastRangesEndWhere() {
        #expect(nerdFontConstraint(0xF0001) != nil)
        #expect(nerdFontConstraint(0xF1AF0) != nil)
        #expect(nerdFontConstraint(0xF1AF1) == nil)
        #expect(nerdFontConstraint(0x10FFFF) == nil)
        #expect(nerdFontConstraint(0) == nil)
    }
}
