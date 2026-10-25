import CoreText
import Foundation

// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The primary face at its pixel size in its four styles, its cell, and the fallback faces found for what it lacks. The
/// face's numbers are read the way Ghostty's `src/font/face/coretext.zig` (`getMetrics`) reads them; a style the family
/// lacks is synthesised as `src/font/Collection.zig` (`completeStyles`) and `coretext.zig` (`syntheticBold`,
/// `syntheticItalic`) do, and fallback follows `src/font/CodepointResolver.zig` (`getIndex`) and
/// `src/font/Collection.zig` (`Entry.hasCodepoint`), at commit 22f100c6.
@MainActor
public final class Font {
    public let primary: CTFont
    public let cell: Cell
    /// The size in points, and pixels per point: the window's backing scale.
    public let points: Double
    public let scale: Double
    /// Whether glyphs rasterise with CoreGraphics font smoothing, Ghostty's `font-thicken`.
    public let thicken: Bool
    /// Regular, bold, italic and bold italic.
    let faces: [FontStyle: Face]
    private let metrics: FaceMetrics
    /// Every codepoint looked up in each style and presentation, kept for the session; nil when no real face has it. A
    /// fallback face is scaled once and kept by its PostScript name, so its glyphs share one face in the glyph cache,
    /// and joins its style's fallbacks, which later codepoints search before the system does. Symbols Nerd Font, when
    /// the process registered it, and then Apple Color Emoji are the first regular fallbacks, as in Ghostty.
    private var found: [FoundKey: Face?] = [:]
    /// Each single-codepoint cluster's face by style, so a rebuilt row asks CoreText nothing, not even whether the face
    /// has the codepoint, for one seen before.
    private var singles: [FoundKey: Face?] = [:]
    private var scaled: [String: CTFont] = [:]
    private var fallbacks: [FontStyle: [CTFont]] = [:]

    private struct FoundKey: Hashable {
        var codepoint: UInt32
        var style: FontStyle
        var presentation: Presentation?
    }

    /// `face` is the primary at any size; nmux takes it at `points` times `scale` pixels. The cell is always measured
    /// from the regular face.
    public init(_ face: CTFont, points: Double, scale: Double, thicken: Bool = false) {
        primary = CTFontCreateCopyWithAttributes(face, points * scale, nil, nil)
        self.points = points
        self.scale = scale
        self.thicken = thicken
        faces = styleFaces(primary, points: points)
        metrics = faceMetrics(primary)
        cell = cellMetrics(metrics)
        // At the primary's size, as Ghostty adds it without a size adjustment: its icons take their constraints.
        let symbols = CTFontCreateWithName(symbolsPostScriptName as CFString, CTFontGetSize(primary), nil)
        if CTFontCopyPostScriptName(symbols) as String == symbolsPostScriptName {
            _ = scaledFallback(symbols, style: .regular, factor: 1)
        }
        _ = scaledFallback(CTFontCreateWithName("AppleColorEmoji" as CFString, CTFontGetSize(primary), nil),
                           style: .regular)
    }

    /// The face that draws the codepoint in the style: the sprite face, which comes before every font in any
    /// presentation, the primary in that style or a fallback found in it, the regular primary or a regular fallback, a
    /// fallback the system picks for the primary in that style scaled to match it, else any regular face that has it,
    /// or nil for a codepoint only LastResort has. The primary draws in any presentation unless one is asked for; a
    /// fallback draws only in the one asked for, else the codepoint's default.
    public func face(for codepoint: UInt32, style: FontStyle = .regular, presentation: Presentation? = nil) -> Face? {
        let key = FoundKey(codepoint: codepoint, style: style, presentation: presentation)
        if let face = found[key] { return face }
        let face = lookUp(codepoint, style: style, presentation: presentation)
        found[key] = face
        return face
    }

    private func lookUp(_ codepoint: UInt32, style: FontStyle, presentation: Presentation?) -> Face? {
        if isSprite(codepoint) { return Face(font: primary, style: style, sprite: true) }
        let styled = self[style: style]
        if draws(styled.font, codepoint, presentation) { return styled }
        let wanted = presentation ?? defaultPresentation(codepoint)
        func fallbackIn(_ style: FontStyle, _ p: Presentation?) -> Face? {
            (fallbacks[style] ?? []).first { draws($0, codepoint, p) }.map { Face(font: $0, style: style) }
        }
        let regular = style == .regular ? nil : draws(primary, codepoint, presentation) ? self[style: .regular]
            : fallbackIn(.regular, wanted)
        return fallbackIn(style, wanted) ?? regular
            ?? fallback(codepoint, over: styled.font, style: style, wanted).map { Face(font: $0, style: style) }
            ?? (glyph(primary, codepoint) != nil ? self[style: .regular] : fallbackIn(.regular, nil))
    }

    /// The face that draws the whole cluster in the style, Ghostty's `indexForCell` (`src/font/shaper/run.zig`): the
    /// base codepoint's face in the presentation the cluster asks for, else the face of each later codepoint in turn,
    /// the first that has every codepoint and draws the base in that presentation; joiners and presentation selectors
    /// need no glyph.
    public func face(for cluster: some Collection<UInt32>, style: FontStyle = .regular) -> Face? {
        guard let first = cluster.first else { return nil }
        guard cluster.count > 1 else {
            let key = FoundKey(codepoint: first, style: style, presentation: nil)
            if let face = singles[key] { return face }
            let face = clusterFace(cluster, style: style)
            singles[key] = face
            return face
        }
        return clusterFace(cluster, style: style)
    }

    private func clusterFace(_ cluster: some Collection<UInt32>, style: FontStyle) -> Face? {
        let cluster = Array(cluster)
        let presentation = requestedPresentation(cluster)
        guard let base = face(for: cluster[0], style: style, presentation: presentation) else { return nil }
        // Unlike the shaper, the lookup skips the zero-width joiner too, as Ghostty's does.
        let rest = cluster.dropFirst().filter { !isPresentationSelector($0) && $0 != 0x200D }
        func drawsAll(_ face: Face) -> Bool {
            face.has(cluster[0], presentation) && rest.allSatisfy { face.has($0, nil) }
        }
        if drawsAll(base) { return base }
        for cp in rest {
            guard let face = face(for: cp, style: style) else { return nil }
            if drawsAll(face) { return face }
        }
        return nil
    }

    subscript(style style: FontStyle) -> Face { faces[style]! }

    /// The face the system picks for the codepoint, else the first face of the primary's cascade list, that draws it in
    /// the presentation.
    private func fallback(_ codepoint: UInt32, over font: CTFont, style: FontStyle,
                          _ presentation: Presentation) -> CTFont? {
        guard let scalar = Unicode.Scalar(codepoint) else { return nil }
        let text = String(Character(scalar)) as CFString
        // Its family reads `.LastResort` on macOS 26.
        func usable(_ face: CTFont) -> Bool {
            !family(face).hasSuffix("LastResort") && draws(face, codepoint, presentation)
        }
        let first = CTFontCreateForString(font, text, CFRange(location: 0, length: CFStringGetLength(text)))
        let cascade = CTFontCopyDefaultCascadeListForLanguages(font, nil) as? [CTFontDescriptor] ?? []
        guard let picked = usable(first) ? first
            : cascade.lazy.map({ CTFontCreateWithFontDescriptor($0, CTFontGetSize(font), nil) }).first(where: usable)
        else { return nil }
        return scaledFallback(picked, style: style)
    }

    /// The face scaled to match the primary, or by `factor`, once, and added to the style's fallbacks.
    private func scaledFallback(_ picked: CTFont, style: FontStyle, factor: Double? = nil) -> CTFont {
        let name = CTFontCopyPostScriptName(picked) as String
        if let face = scaled[name] { return face }
        let factor = factor ?? fallbackScale(primary: metrics, face: faceMetrics(picked))
        let face = CTFontCreateCopyWithAttributes(picked, CTFontGetSize(picked) * factor, nil, nil)
        scaled[name] = face
        fallbacks[style, default: []].append(face)
        return face
    }
}

/// The style SGR asks for, named as the self-test logs it.
public enum FontStyle: String, Sendable {
    case regular, bold, italic, boldItalic = "bolditalic"

    init(bold: Bool, italic: Bool) { self = bold ? italic ? .boldItalic : .bold : italic ? .italic : .regular }
}

/// A face as nmux draws it, in the style it draws: a synthetic bold strokes each glyph's outline `stroke` pixels wide.
/// The sprite face draws its glyphs itself, in the style asked for; its font is the primary's and draws nothing.
public struct Face {
    public let font: CTFont
    public let style: FontStyle
    var stroke: Double?
    var synthetic = false
    public var sprite = false

    /// Every glyph of a colour face draws in colour.
    var color: Bool { !sprite && isColor(font) }

    /// Whether the face has the codepoint, in the presentation when one is given; the sprite face in any.
    func has(_ codepoint: UInt32, _ presentation: Presentation?) -> Bool {
        sprite ? isSprite(codepoint) : draws(font, codepoint, presentation)
    }
}

/// The four styles of the family: each one it has, else Ghostty's synthetic. Italic skews 15°; bold strokes the outline
/// at a width of a pixel per 14 points, at least 1; bold italic skews a real bold, else strokes the italic.
func styleFaces(_ regular: CTFont, points: Double) -> [FontStyle: Face] {
    let skew = CGAffineTransform(a: 1, b: 0, c: 0.267949, d: 1, tx: 0, ty: 0)
    func italicised(_ face: Face, _ style: FontStyle) -> Face {
        var matrix = skew
        return Face(font: CTFontCreateCopyWithAttributes(face.font, 0, &matrix, nil), style: style, stroke: face.stroke,
                    synthetic: true)
    }
    func boldened(_ face: Face, _ style: FontStyle) -> Face {
        Face(font: face.font, style: style, stroke: max(points / 14, 1), synthetic: true)
    }
    let plain = Face(font: regular, style: .regular)
    let bold = styled(regular, .traitBold).map { Face(font: $0, style: .bold) }
    let italic = styled(regular, .traitItalic).map { Face(font: $0, style: .italic) } ?? italicised(plain, .italic)
    let boldItalic = styled(regular, [.traitBold, .traitItalic]).map { Face(font: $0, style: .boldItalic) }
        ?? bold.map { italicised($0, .boldItalic) } ?? boldened(italic, .boldItalic)
    return [.regular: plain, .bold: bold ?? boldened(plain, .bold), .italic: italic, .boldItalic: boldItalic]
}

/// The family's own face with the traits, nil when the family has none.
private func styled(_ regular: CTFont, _ traits: CTFontSymbolicTraits) -> CTFont? {
    guard let font = CTFontCreateCopyWithSymbolicTraits(regular, 0, nil, traits, traits),
          family(font) == family(regular), CTFontGetSymbolicTraits(font).contains(traits) else { return nil }
    return font
}

extension Font {
    /// The grid `size` in points holds, in whole cells.
    public func grid(in size: NSSize) -> Grid {
        gridFit(width: Int(size.width * scale), height: Int(size.height * scale), cell: cell)
    }

    /// The content size that holds `grid`, rounded up to the half point, so rounding never costs the last column or
    /// row.
    public func contentSize(_ grid: Grid) -> NSSize {
        func span(_ cells: Int, _ pixels: Int) -> CGFloat { (CGFloat(cells * pixels) / scale * 2).rounded(.up) / 2 }
        return NSSize(width: span(grid.cols, cell.width), height: span(grid.rows, cell.height))
    }
}

/// The bundled Symbols Nerd Font, by the name CoreText finds it under once registered.
let symbolsPostScriptName = "SymbolsNF"

public func family(_ font: CTFont) -> String { CTFontCopyFamilyName(font) as String }

func isColor(_ font: CTFont) -> Bool { CTFontGetSymbolicTraits(font).contains(.traitColorGlyphs) }

/// Whether the face has the codepoint, in the presentation when one is given.
func draws(_ font: CTFont, _ codepoint: UInt32, _ presentation: Presentation?) -> Bool {
    glyph(font, codepoint) != nil && presentation.map { isColor(font) == ($0 == .emoji) } ?? true
}

/// The face's glyph for the codepoint, nil when it has none. It runs for each new codepoint of a rebuilt row, so it
/// allocates nothing.
func glyph(_ font: CTFont, _ codepoint: UInt32) -> CGGlyph? {
    guard let scalar = Unicode.Scalar(codepoint) else { return nil }
    var units: (UniChar, UniChar) = (0, 0), glyphs: (CGGlyph, CGGlyph) = (0, 0)
    let count = scalar.utf16.count
    (units.0, units.1) = (scalar.utf16[0], count == 2 ? scalar.utf16[1] : 0)
    return withUnsafePointer(to: &units) { u in
        withUnsafeMutablePointer(to: &glyphs) { g in
            CTFontGetGlyphsForCharacters(font, UnsafeRawPointer(u).assumingMemoryBound(to: UniChar.self),
                                         UnsafeMutableRawPointer(g).assumingMemoryBound(to: CGGlyph.self), count)
        }
    } ? glyphs.0 : nil
}

/// The face's numbers: the vertical metrics as below, post's underline, OS/2's strikeout, cap height and
/// ex height, and the widest printable ASCII advance.
func faceMetrics(_ font: CTFont) -> FaceMetrics {
    let pxPerEm = Double(CTFontGetSize(font))
    let unit = pxPerEm / Double(CTFontGetUnitsPerEm(font))
    let os2 = table(font, kCTFontTableOS2), hhea = table(font, kCTFontTableHhea), post = table(font, kCTFontTablePost)

    var ascent = Double(CTFontGetAscent(font)), descent = -Double(CTFontGetDescent(font)),
        lineGap = Double(CTFontGetLeading(font))
    // Without hhea CoreText's; without OS/2 hhea's. Otherwise OS/2's typo metrics when its fsSelection bit 7,
    // USE_TYPO_METRICS, asks for them, else the first of hhea's, the typo ones and usWin's that is not zero.
    if let hhea, hhea.count >= 10 {
        let fromHhea = (hhea.int16(4) * unit, hhea.int16(6) * unit, hhea.int16(8) * unit)
        (ascent, descent, lineGap) = fromHhea
        if let os2, os2.count >= 78 {
            let typo = (os2.int16(68) * unit, os2.int16(70) * unit, os2.int16(72) * unit)
            // usWinDescent counts down, unlike the other descents.
            let win = (Double(os2.uint16(74)) * unit, -Double(os2.uint16(76)) * unit, 0.0)
            if os2.uint16(62) & 0x80 != 0 {
                (ascent, descent, lineGap) = typo
            } else if fromHhea.0 == 0 && fromHhea.1 == 0 {
                (ascent, descent, lineGap) = typo.0 != 0 || typo.1 != 0 ? typo : win
            }
        }
    }

    var m = FaceMetrics(pxPerEm: pxPerEm, cellWidth: widestASCII(font), ascent: ascent, descent: descent,
                        lineGap: lineGap, capHeight: Double(CTFontGetCapHeight(font)),
                        exHeight: Double(CTFontGetXHeight(font)))
    // A zero thickness marks a broken table; its position still counts unless it is zero too.
    if let post, post.count >= 12 {
        let position = post.int16(8), thickness = post.int16(10)
        m.underlinePosition = thickness == 0 && position == 0 ? nil : position * unit
        m.underlineThickness = thickness == 0 ? nil : thickness * unit
    }
    if let os2, os2.count >= 30 {
        let size = os2.int16(26), position = os2.int16(28)
        m.strikethroughPosition = size == 0 && position == 0 ? nil : position * unit
        m.strikethroughThickness = size == 0 ? nil : size * unit
    }
    // OS/2 version 2 and later carries sxHeight and sCapHeight.
    if let os2, os2.count >= 90, os2.uint16(0) >= 2 {
        m.exHeight = os2.int16(86) * unit
        m.capHeight = os2.int16(88) * unit
    }
    return m
}

private func widestASCII(_ font: CTFont) -> Double {
    let units = (32..<127).map { UInt16($0) }
    var glyphs = [CGGlyph](repeating: 0, count: units.count)
    _ = CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
    var advances = [CGSize](repeating: .zero, count: units.count)
    _ = CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, units.count)
    return Double(advances.map(\.width).max() ?? 0)
}

private func table(_ font: CTFont, _ tag: Int) -> Data? {
    CTFontCopyTable(font, CTFontTableTag(tag), []) as Data?
}

/// Big-endian reads, as OpenType stores its numbers.
private extension Data {
    func uint16(_ at: Int) -> UInt16 { UInt16(self[startIndex + at]) << 8 | UInt16(self[startIndex + at + 1]) }
    func int16(_ at: Int) -> Double { Double(Int16(bitPattern: uint16(at))) }
}
