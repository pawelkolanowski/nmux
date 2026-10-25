import Foundation
import Testing
@testable import Terminal

// Each test runs on a fresh pair of atlases, filled in the order the checks read them.
struct AtlasTests {
    var atlas = Atlas(size: 16), colors = Atlas(size: 4, depth: 4)
    let first, second, third, tall: (x: Int, y: Int)
    let drawn = (1...10).map(UInt8.init), bgra: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
    let dirtyAfterFill: [Int]?

    init() {
        (first, second) = (atlas.reserve(width: 5, height: 4), atlas.reserve(width: 5, height: 3))
        third = atlas.reserve(width: 5, height: 2)
        atlas.fill(x: third.x, y: third.y, width: 5, height: 2, rows: drawn)
        dirtyAfterFill = atlas.dirty.map { [$0.x, $0.y, $0.maxX, $0.maxY] }
        atlas.uploaded()
        tall = atlas.reserve(width: 4, height: 12)
        let swatch = colors.reserve(width: 2, height: 1)
        colors.fill(x: swatch.x, y: swatch.y, width: 2, height: 1, rows: bgra)
        _ = colors.reserve(width: 6, height: 1)
    }

    @Test("a glyph that fits the row goes beside the last, a pixel apart") func aGlyphThatFitsTheRowGoesBeside() {
        #expect(first == (0, 0))
        #expect(second == (6, 0))
    }

    @Test("a glyph past the row's end starts a row under its tallest glyph") func aGlyphPastTheRowsEndStartsA() {
        #expect(third == (0, 5))
    }

    @Test("a fill marks only its own region dirty") func aFillMarksOnlyItsOwnRegionDirty() {
        #expect(dirtyAfterFill == [0, 5, 5, 7])
    }

    @Test("a glyph that does not fit grows the texture to twice its side") func aGlyphThatDoesNotFitGrowsThe() {
        #expect(atlas.size == 32)
        #expect(atlas.grew)
        #expect(tall == (6, 5))
    }

    @Test("nothing drawn before the growth moves or is lost") func nothingDrawnBeforeTheGrowthMovesOrIs() {
        #expect(Array(atlas.pixels[5 * 32..<5 * 32 + 5] + atlas.pixels[6 * 32..<6 * 32 + 5]) == drawn)
    }

    @Test("a colour atlas grows with four bytes a pixel and keeps what it held")
    func aColourAtlasGrowsWithFourBytesA() {
        #expect(colors.size == 8)
        #expect(colors.pixels.count == 8 * 8 * 4)
        #expect(Array(colors.pixels[0..<8]) == bgra)
    }
}
