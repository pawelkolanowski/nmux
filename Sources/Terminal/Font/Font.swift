import CoreText
import Foundation

// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The primary face at its pixel size, its cell, and the fallback faces found for what it lacks. The face's numbers are
/// read the way Ghostty's `src/font/face/coretext.zig` (`getMetrics`) reads them, at commit 22f100c6.
@MainActor
public final class Font {
    public let primary: CTFont
    public let cell: Cell
    /// The size in points, and pixels per point: the window's backing scale.
    public let points: Double
    public let scale: Double
    private let metrics: FaceMetrics
    /// Every codepoint looked up, kept for the session; nil when no real face has it. A fallback face is scaled once
    /// and kept by its PostScript name, so its glyphs share one face in the glyph cache.
    private var found: [UInt32: CTFont?] = [:]
    private var scaled: [String: CTFont] = [:]

    /// `face` is the primary at any size; nmux takes it at `points` times `scale` pixels.
    public init(_ face: CTFont, points: Double, scale: Double) {
        primary = CTFontCreateCopyWithAttributes(face, points * scale, nil, nil)
        self.points = points
        self.scale = scale
        metrics = faceMetrics(primary)
        cell = cellMetrics(metrics)
    }

    /// The face that draws the codepoint: the primary, a fallback the system picks scaled to match it, or nil for a
    /// codepoint only LastResort has.
    public func face(for codepoint: UInt32) -> CTFont? {
        if glyph(primary, codepoint) != nil { return primary }
        if let face = found[codepoint] { return face }
        let face = fallback(codepoint)
        found[codepoint] = face
        return face
    }

    private func fallback(_ codepoint: UInt32) -> CTFont? {
        guard let scalar = Unicode.Scalar(codepoint) else { return nil }
        let text = String(Character(scalar)) as CFString
        let picked = CTFontCreateForString(primary, text, CFRange(location: 0, length: CFStringGetLength(text)))
        // Its family reads `.LastResort` on macOS 26.
        guard !family(picked).hasSuffix("LastResort"), glyph(picked, codepoint) != nil else { return nil }
        let name = CTFontCopyPostScriptName(picked) as String
        if let face = scaled[name] { return face }
        let factor = fallbackScale(primary: metrics, face: faceMetrics(picked))
        let face = CTFontCreateCopyWithAttributes(picked, CTFontGetSize(picked) * factor, nil, nil)
        scaled[name] = face
        return face
    }
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

public func family(_ font: CTFont) -> String { CTFontCopyFamilyName(font) as String }

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
