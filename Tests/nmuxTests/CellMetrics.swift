import Foundation
import Testing
@testable import nmux
@testable import Terminal

private let full = cellMetrics(FaceMetrics(pxPerEm: 28, cellWidth: 16.8, ascent: 26.4, descent: -6.6, lineGap: 0,
                                   underlinePosition: -2.4, underlineThickness: 1.4, strikethroughPosition: 8,
                                   strikethroughThickness: 1.4, capHeight: 19.6, exHeight: 14.7))
private let sparse = cellMetrics(FaceMetrics(pxPerEm: 28, cellWidth: 17, ascent: 20, descent: -5, lineGap: 0,
                                             capHeight: 0, exHeight: -1))
private let down = cellMetrics(FaceMetrics(pxPerEm: 28, cellWidth: 17, ascent: 10.2, descent: -3, lineGap: 0))
private let up = cellMetrics(FaceMetrics(pxPerEm: 28, cellWidth: 17, ascent: 10.4, descent: -3, lineGap: 0.2))
private let gapped = cellMetrics(FaceMetrics(pxPerEm: 28, cellWidth: 17, ascent: 10, descent: -2, lineGap: 4))

private let primary = FaceMetrics(pxPerEm: 28, cellWidth: 17, ascent: 26, descent: -7, lineGap: 0, capHeight: 20,
                                  exHeight: 14)
private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

private let cell = cellMetrics(primary)

struct CellMetricsTests {
    @Test("a face with every metric gives the rounded cell") func aFaceWithEveryMetricGivesTheRounded() {
        #expect(full.width == 17)
        #expect(full.height == 33)
        #expect(full.baseline == 7)
    }

    @Test("its underline and strikethrough count from the cell's top, thickness ceiled")
    func itsUnderlineAndStrikethroughCountFromTheCells() {
        #expect(full.underlinePosition == 28)
        #expect(full.underlineThickness == 2)
        #expect(full.strikethroughPosition == 18)
        #expect(full.strikethroughThickness == 2)
    }

    @Test("the cell keeps the face's fractional size and offset") func theCellKeepsTheFacesFractionalSizeAnd() {
        #expect(full.faceWidth == 16.8)
        #expect(abs(full.faceHeight - 33) < 1e-9)
        #expect(abs(full.faceY - 0.4) < 1e-9)
    }

    @Test("a face missing cap and ex height gets Ghostty's estimates") func aFaceMissingCapAndExHeightGets() {
        #expect(sparse.underlineThickness == 2)
        #expect(sparse.underlinePosition == 22)
        #expect(sparse.strikethroughPosition == 14)
    }

    @Test("a height that rounds down keeps the baseline in the face's centre")
    func aHeightThatRoundsDownKeepsTheBaseline() {
        #expect(down.height == 13)
        #expect(down.baseline == 3)
    }

    @Test("a height that rounds up keeps the baseline in the face's centre")
    func aHeightThatRoundsUpKeepsTheBaseline() {
        #expect(up.height == 14)
        #expect(up.baseline == 3)
    }

    @Test("the line gap splits evenly above and below the face") func theLineGapSplitsEvenlyAboveAndBelow() {
        #expect(gapped.height == 16)
        #expect(gapped.baseline == 4)
        #expect(gapped.height - gapped.baseline - 10 == gapped.baseline - 2)
    }

    @Test("the fallback scale matches ex heights in ems") func theFallbackScaleMatchesExHeightsInEms() {
        #expect(near(fallbackScale(primary: primary, face: FaceMetrics(pxPerEm: 14, cellWidth: 8, ascent: 13,
            descent: -3, lineGap: 0, capHeight: 9, exHeight: 6)), 14.0 / 12))
    }

    @Test("a face without ex height falls to cap height") func aFaceWithoutExHeightFallsToCap() {
        #expect(near(fallbackScale(primary: primary, face: FaceMetrics(pxPerEm: 28, cellWidth: 17, ascent: 26,
            descent: -7, lineGap: 0, capHeight: 16)), 1.25))
    }

    @Test("a face with neither falls to line height") func aFaceWithNeitherFallsToLineHeight() {
        #expect(near(fallbackScale(primary: primary, face: FaceMetrics(pxPerEm: 28, cellWidth: 17, ascent: 24,
            descent: -6, lineGap: 0)), 1.1))
    }

    @Test("faces with no metric to match give 1") func facesWithNoMetricToMatchGive1() {
        #expect(fallbackScale(primary: FaceMetrics(pxPerEm: 28, cellWidth: 17, ascent: 0, descent: 0, lineGap: 0),
            face: FaceMetrics(pxPerEm: 28, cellWidth: 17, ascent: 0, descent: 0, lineGap: 0)) == 1)
    }

    @Test("the grid fits whole cells exactly") func theGridFitsWholeCellsExactly() {
        #expect(gridFit(width: 170, height: 330, cell: cell) == Grid(cols: 10, rows: 10))
    }

    @Test("a pixel short of a cell drops that column and row") func aPixelShortOfACellDropsThat() {
        #expect(gridFit(width: 169, height: 329, cell: cell) == Grid(cols: 9, rows: 9))
    }

    @Test("a size under one cell still gives 1 × 1") func aSizeUnderOneCellStillGives1() {
        #expect(gridFit(width: 5, height: 5, cell: cell) == Grid(cols: 1, rows: 1))
    }
}
