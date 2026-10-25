import Foundation
import Testing
@testable import nmux
@testable import Terminal

// Each cell's first codepoint, as a row holds them; 0 for an empty cell.
private func widths(_ row: [UInt32], wide: Int? = nil) -> [Int] {
    row.indices.map { constraintWidth(row, at: $0, wide: $0 == wide) }
}
private let straight = [1, 2].map { decorationSprite(.underline, span: $0, cell: decorated) }
private let curly = decorationSprite(.underlineCurly, span: 1, cell: decorated)
// Ghostty lets a sprite reach a quarter cell past each edge; a low curly underline dips into it, as Ghostty's does.
private let overline = decorationSprite(.overline, span: 1, cell: decorated)
private let strike = decorationSprite(.strike, span: 1, cell: decorated)

// Sprites at the same cell, its line thickness the underline's.
private func sprite(_ cp: UInt32, span: Int = 1) -> Sprite { charSprite(cp, span: span, cell: decorated) }
private let (light, heavy, vertical) = (sprite(0x2500), sprite(0x2501), sprite(0x2502))
private let fullBlock = sprite(0x2588)
private let medium = sprite(0x2592)
private let arrow = sprite(0xE0B0), wideArrow = sprite(0xE0B0, span: 2)
// Each of the eight bits alone draws one dot, in the column and row of the cell the bit names.
private let dots = (0..<8).map { sprite(0x2800 | 1 << $0) }
private let places = dots.map {
    ($0.left + $0.width / 2) * 2 / decorated.width * 10
        + (decorated.height - $0.top + $0.height / 2) * 4 / decorated.height
}
private let allDots = sprite(0x28FF)

struct SpriteTests {
    @Test("an icon followed by a space or an empty cell takes two cells, by a letter or a no-break space one")
    func anIconFollowedByASpaceOrAn() {
        #expect(widths([0xF015, 0x20, 0x7A])[0] == 2)
        #expect(widths([0xF015, 0])[0] == 2)
        #expect(widths([0xF015, 0x7A])[0] == 1)
        #expect(widths([0xF015, 0xA0])[0] == 1)
    }

    @Test("an icon at the row's end takes one cell") func anIconAtTheRowsEndTakesOne() {
        #expect(widths([0x20, 0xF015]) == [1, 1])
    }

    @Test("an icon after another icon takes one cell, after a Powerline glyph two")
    func anIconAfterAnotherIconTakesOneCell() {
        #expect(widths([0xF015, 0xF015, 0x20]) == [1, 1, 1])
        #expect(widths([0xE0B0, 0xF015, 0x20])[1] == 2)
    }

    @Test("a wide cell takes two cells, a letter one") func aWideCellTakesTwoCellsALetter() {
        #expect(widths([0x4E2D, 0, 0x41], wide: 0) == [2, 1, 1])
    }

    @Test("a straight underline reaches both edges of its span, one cell or two")
    func aStraightUnderlineReachesBothEdgesOfIts() {
        #expect(straight.map { [$0.left, $0.width] } == [[0, 17], [0, 34]])
    }

    @Test("a straight underline sits at the font's underline position and thickness")
    func aStraightUnderlineSitsAtTheFontsUnderline() {
        #expect(straight[0].top == decorated.height - decorated.underlinePosition)
        #expect(straight[0].height == 2)
        #expect(straight[0].pixels.allSatisfy { $0 == 255 })
    }

    @Test("a curly underline stays within its cell and Ghostty's quarter-cell margin")
    func aCurlyUnderlineStaysWithinItsCellAnd() {
        #expect(curly.height > 0)
        #expect(curly.left >= -decorated.width / 4)
        #expect(curly.left + curly.width <= decorated.width * 5 / 4)
        #expect(curly.top <= decorated.height)
        #expect(curly.top - curly.height >= -decorated.height / 4)
    }

    @Test("the overline sits at the cell's top and strikethrough at the font's strikeout")
    func theOverlineSitsAtTheCellsTopAnd() {
        #expect(overline.top == decorated.height)
        #expect(strike.top == decorated.height - decorated.strikethroughPosition)
    }

    @Test("a light horizontal line reaches both side edges of the cell")
    func aLightHorizontalLineReachesBothSideEdges() {
        #expect(light.left == 0)
        #expect(light.width == decorated.width)
        #expect(light.pixels.allSatisfy { $0 == 255 })
    }

    @Test("a light vertical line reaches the top and the bottom of the cell")
    func aLightVerticalLineReachesTheTopAnd() {
        #expect(vertical.top == decorated.height)
        #expect(vertical.height == decorated.height)
        #expect(vertical.pixels.allSatisfy { $0 == 255 })
    }

    @Test("a light line is the underline's thickness, a heavy one twice it")
    func aLightLineIsTheUnderlinesThicknessA() {
        #expect(light.height == decorated.underlineThickness)
        #expect(heavy.height == 2 * light.height)
        #expect(vertical.width == light.height)
    }

    @Test("a box line sits at the same place in every cell, so a frame never wobbles")
    func aBoxLineSitsAtTheSamePlace() {
        #expect(sprite(0x250C).top == light.top)
        #expect(sprite(0x250C).left == vertical.left)
        #expect(sprite(0x2510).left + sprite(0x2510).width == vertical.left + vertical.width)
    }

    @Test("a full block covers every pixel of the cell") func aFullBlockCoversEveryPixelOfThe() {
        #expect([fullBlock.left, fullBlock.top, fullBlock.width, fullBlock.height]
            == [0, decorated.height, decorated.width, decorated.height] as [Int])
        #expect(fullBlock.pixels.allSatisfy { $0 == 255 })
    }

    @Test("a medium shade covers the cell at half coverage") func aMediumShadeCoversTheCellAtHalf() {
        #expect(medium.width == decorated.width)
        #expect(medium.pixels.allSatisfy { $0 == 0x80 })
    }

    @Test("a Powerline arrow touches the top and bottom rows of the cell and its left edge")
    func aPowerlineArrowTouchesTheTopAndBottom() {
        #expect(arrow.top == decorated.height)
        #expect(arrow.height == decorated.height)
        #expect(arrow.left == 0)
        #expect(arrow.pixels[0] > 0)
        #expect(arrow.pixels[(arrow.height - 1) * arrow.width] > 0)
    }

    @Test("a Powerline arrow over two cells spans both") func aPowerlineArrowOverTwoCellsSpansBoth() {
        #expect(wideArrow.width > decorated.width)
    }

    @Test("a braille dot pattern sets the dots its bits name") func aBrailleDotPatternSetsTheDotsIts() {
        #expect(places == [0, 1, 2, 10, 11, 12, 3, 13])
    }

    @Test("every braille dot has the same size") func everyBrailleDotHasTheSameSize() {
        #expect(Set(dots.map { [$0.width, $0.height] }).count == 1)
    }

    @Test("all eight braille dots cover eight dots' worth of pixels") func allEightBrailleDotsCoverEightDotsWorth() {
        #expect(allDots.pixels.filter { $0 == 255 }.count == 8 * dots[0].width * dots[0].height)
    }

    @Test("an unassigned codepoint in a sprite block draws nothing, a codepoint outside every block has no sprite")
    func anUnassignedCodepointInASpriteBlockDraws() {
        #expect(isSprite(0x1FB93))
        #expect(sprite(0x1FB93).width == 0)
        #expect(!isSprite(0x41))
        #expect(!isSprite(0x25A0))
        #expect(!isSprite(0x1FBF0))
    }

    @Test("each sprite block's ends are in the sprite face",
          arguments: [0x2500, 0x259F, 0x25E2, 0x25FF, 0x2800, 0x28FF, 0xE0B0, 0xE0D4, 0xF5D0, 0xF60D, 0x1CC1B,
                      0x1CEAF, 0x1FB00, 0x1FBEF] as [UInt32])
    func eachSpriteBlocksEndsAreInTheSpriteFace(codepoint: UInt32) {
        #expect(isSprite(codepoint))
    }
}
