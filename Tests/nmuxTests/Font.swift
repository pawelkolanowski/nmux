import CoreText
import Foundation
import Testing
@testable import Terminal

// Monaco has only a regular face, Menlo all four; Symbols Nerd Font is registered as the app registers it at launch.
@MainActor
struct FontTests {
    let monaco: Font, menlo: Font
    let styles: [FontStyle] = [.regular, .bold, .italic, .boldItalic]

    init() {
        _ = symbolsRegistered
        monaco = Font(CTFontCreateWithName("Monaco" as CFString, 14, nil), points: 14, scale: 2)
        menlo = Font(CTFontCreateWithName("Menlo-Regular" as CFString, 14, nil), points: 14, scale: 2)
    }

    func bold(_ face: Face?) -> Bool { face.map { CTFontGetSymbolicTraits($0.font).contains(.traitBold) } ?? false }
    func colour(_ cluster: [UInt32], _ style: FontStyle = .regular) -> Bool? {
        menlo.face(for: cluster, style: style)?.color
    }

    @Test("a family with only regular synthesises bold, italic and bold italic")
    func aFamilyWithOnlyRegularSynthesisesBoldItalic() {
        #expect(styles.map { monaco[style: $0].synthetic } == [false, true, true, true])
    }

    @Test("the synthetic bold strokes its outline and the synthetic italic skews")
    func theSyntheticBoldStrokesItsOutlineAndThe() {
        #expect(monaco[style: .bold].stroke == 1)
        #expect(monaco[style: .bold].font === monaco.primary)
        #expect(CTFontGetMatrix(monaco[style: .italic].font).c > 0.26)
        #expect(monaco[style: .italic].stroke == nil)
    }

    @Test("the synthetic bold italic strokes the synthetic italic")
    func theSyntheticBoldItalicStrokesTheSyntheticItalic() {
        #expect(monaco[style: .boldItalic].stroke == 1)
        #expect(CTFontGetMatrix(monaco[style: .boldItalic].font).c > 0.26)
    }

    @Test("a family with four faces synthesises none") func aFamilyWithFourFacesSynthesisesNone() {
        let names = styles.map { CTFontCopyPostScriptName(menlo[style: $0].font) as String }
        #expect(names == ["Menlo-Regular", "Menlo-Bold", "Menlo-Italic", "Menlo-BoldItalic"])
        #expect(!styles.contains { menlo[style: $0].synthetic })
    }

    @Test("a codepoint the family has comes from the face in the cell's style")
    func aCodepointTheFamilyHasComesFromThe() {
        #expect(menlo.face(for: 0x41, style: .bold).map { CTFontCopyPostScriptName($0.font) as String } == "Menlo-Bold")
    }

    @Test("a codepoint the family lacks falls back in the cell's style") func aCodepointTheFamilyLacksFallsBackIn() {
        #expect(bold(menlo.face(for: 0x4E2D, style: .bold)))
        #expect(!bold(menlo.face(for: 0x4E2D)))
    }

    // 中 regular first leaves a regular fallback, which 文 in bold takes before the system picks a bold face.
    @Test("a styled miss takes a regular fallback before the system's") func aStyledMissTakesARegularFallbackBefore() {
        let fresh = Font(CTFontCreateWithName("Menlo-Regular" as CFString, 14, nil), points: 14, scale: 2)
        let regularHan = fresh.face(for: 0x4E2D)
        let boldWen = fresh.face(for: 0x6587, style: .bold)
        #expect(regularHan != nil)
        #expect(boldWen?.font === regularHan?.font)
        #expect(boldWen?.style == .regular)
    }

    @Test("an emoji draws from Apple Color Emoji in colour") func anEmojiDrawsFromAppleColorEmojiIn() {
        #expect(menlo.face(for: [0x1F642]).map { family($0.font) } == "Apple Color Emoji")
        #expect(colour([0x1F642]) == true)
    }

    @Test("a heart takes its text default, VS16 draws it in colour and VS15 as text")
    func aHeartTakesItsTextDefaultVs16Draws() {
        #expect(colour([0x2764]) == false)
        #expect(colour([0x2764, 0xFE0F]) == true)
        #expect(colour([0x2764, 0xFE0E]) == false)
    }

    // Ghostty's `indexForCell` asks the base for the requested presentation, so the cell draws U+FFFD.
    @Test("VS15 on an emoji that no text face has finds no face for the cluster, as in Ghostty")
    func vs15OnAnEmojiThatNoTextFace() {
        #expect(colour([0x1F642, 0xFE0E]) == nil)
        #expect(colour([0x1F642]) == true)
    }

    @Test("a keycap, a flag and a joined family each find one colour face") func aKeycapAFlagAndAJoinedFamily() {
        #expect(colour([0x31, 0xFE0F, 0x20E3]) == true)
        #expect(colour([0x1F1F5, 0x1F1F1]) == true)
        #expect(colour([0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467]) == true)
    }

    @Test("a bold emoji takes the regular colour face") func aBoldEmojiTakesTheRegularColourFace() {
        #expect(colour([0x1F642], .bold) == true)
    }

    @Test("a Nerd Font icon draws from the bundled Symbols Nerd Font, in a bold cell too")
    func aNerdFontIconDrawsFromTheBundled() {
        #expect([menlo.face(for: 0xF015), menlo.face(for: 0xF015, style: .bold)].allSatisfy {
            $0.map { family($0.font) } == "Symbols Nerd Font"
        })
        #expect(menlo.face(for: 0xF015, style: .bold)?.style == .regular)
    }

    @Test("the icon face takes the primary's size") func theIconFaceTakesThePrimarysSize() {
        #expect(menlo.face(for: 0xEA61).map { CTFontGetSize($0.font) } == CTFontGetSize(menlo.primary))
    }

    @Test("a full block Menlo has draws from the sprite face, in every style and presentation")
    func aFullBlockMenloHasDrawsFromThe() {
        #expect(glyph(menlo.primary, 0x2588) != nil)
        #expect([menlo.face(for: 0x2588), menlo.face(for: 0x2588, style: .bold), menlo.face(for: [0x2588, 0xFE0F])]
            .allSatisfy { $0?.sprite == true })
    }

    @Test("a letter and a box line with a combining mark draw from fonts") func aLetterAndABoxLineWithA() {
        #expect(menlo.face(for: 0x41)?.sprite == false)
        #expect(menlo.face(for: [0x2500, 0x301])?.sprite == false)
    }

    // The system picks Apple Color Emoji for ⌚; the primary's cascade list has a text face for it.
    @Test("VS15 on a symbol the system draws as emoji finds a text face in the cascade list")
    func vs15OnASymbolTheSystemDrawsAs() {
        #expect(colour([0x231A, 0xFE0E]) == false)
        #expect(colour([0x231A]) == true)
    }

    @Test("VS16 asks for emoji, VS15 for text, and a lone codepoint or a later selector for neither")
    func vs16AsksForEmojiVs15ForTextAnd() {
        #expect(requestedPresentation([0x2764, 0xFE0F]) == .emoji)
        #expect(requestedPresentation([0x2764, 0xFE0E]) == .text)
        #expect(requestedPresentation([0x2764]) == nil)
        #expect(requestedPresentation([0x1F468, 0x200D, 0xFE0F]) == nil)
    }

    @Test("Unicode's default presentation is emoji for 🙂 and text for ❤ and A")
    func unicodesDefaultPresentationIsEmojiForAndText() {
        #expect(defaultPresentation(0x1F642) == .emoji)
        #expect(defaultPresentation(0x2764) == .text)
        #expect(defaultPresentation(0x41) == .text)
    }
}
