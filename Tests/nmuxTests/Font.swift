import CoreText
import Foundation
import Testing
@testable import Terminal

// Menlo has Latin letters and no ideographs, and nothing has U+10FFFD but LastResort.
@MainActor
struct FontTests {
    let menlo = Font(CTFontCreateWithName("Menlo-Regular" as CFString, 14, nil), points: 14, scale: 2)

    @Test("a codepoint the face has comes from the primary") func aCodepointTheFaceHasComesFromThePrimary() {
        #expect(menlo.face(for: 0x41) === menlo.primary)
    }

    @Test("a codepoint the face lacks falls back to another family") func aCodepointTheFaceLacksFallsBackToAnother() {
        #expect(menlo.face(for: 0x4E2D).map(family).map { $0 != "Menlo" && !$0.hasSuffix("LastResort") } == true)
    }

    @Test("the same fallback comes back for a later codepoint it has") func theSameFallbackComesBackForALater() {
        #expect(menlo.face(for: 0x4E2D) === menlo.face(for: 0x6587))
    }

    @Test("a codepoint only LastResort has finds no face") func aCodepointOnlyLastResortHasFindsNoFace() {
        #expect(menlo.face(for: 0x10FFFD) == nil)
    }
}
