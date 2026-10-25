import CoreText
import Foundation

// A run's text laid out by CoreText, adapted from Ghostty's `src/font/shaper/coretext.zig` (`init`, `shape`,
// `getFont`) at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The face as the shaper uses it: `liga` on, Ghostty's one default feature. Ghostty's quirk that turns the defaults
/// off for some faces (`disableDefaultFontFeatures`) names none at 22f100c6.
func shapingFont(_ font: CTFont) -> CTFont {
    let liga = [kCTFontOpenTypeFeatureTag: "liga", kCTFontOpenTypeFeatureValue: 1] as [CFString: Any]
    let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFeatureSettingsAttribute: [liga]] as CFDictionary)
    return CTFontCreateCopyWithAttributes(font, 0, nil, descriptor)
}

/// The run's glyphs in `font`, each with its string index, position and advance. A typesetter forced to embedding
/// level 0 lays the text out strictly left to right, as an attributed string's writing direction still lets CoreText
/// reorder a row around a right-to-left character.
func shape(_ text: RunText, in font: CTFont) -> [(glyph: CGGlyph, laid: LaidGlyph)] {
    let string = CFStringCreateWithCharacters(nil, text.utf16, text.utf16.count)!
    let attributed = CFAttributedStringCreate(nil, string, [kCTFontAttributeName: font] as CFDictionary)!
    let options = [kCTTypesetterOptionForcedEmbeddingLevel: 0] as CFDictionary
    let typesetter = CTTypesetterCreateWithAttributedStringAndOptions(attributed, options)!
    let line = CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: 0))
    var out: [(glyph: CGGlyph, laid: LaidGlyph)] = []
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let n = CTRunGetGlyphCount(run), all = CFRange(location: 0, length: 0)
        var glyphs = [CGGlyph](repeating: 0, count: n), positions = [CGPoint](repeating: .zero, count: n)
        var advances = [CGSize](repeating: .zero, count: n), indices = [CFIndex](repeating: 0, count: n)
        CTRunGetGlyphs(run, all, &glyphs)
        CTRunGetPositions(run, all, &positions)
        CTRunGetAdvances(run, all, &advances)
        CTRunGetStringIndices(run, all, &indices)
        for i in 0..<n {
            let laid = LaidGlyph(index: indices[i], x: positions[i].x, y: positions[i].y, advance: advances[i].width)
            out.append((glyphs[i], laid))
        }
    }
    return out
}
