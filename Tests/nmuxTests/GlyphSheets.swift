import CoreText
import Foundation
import GhosttyVt
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Terminal

// The five fixed glyph sets, the walk that checks each glyph, and the reference sheets drawn with nmux's own
// rasteriser. Only the sheets of sprites nmux draws itself are compared pixel for pixel with the ones the author
// approved; CoreText rasterises the others, and another macOS release may rasterise them differently.

// A set: its clusters, the face each is expected from (a family, or `sprite` for the sprite face), the cells the
// terminal lays each out over, and the cells it is drawn over with a free cell after. On a sheet each cluster takes
// `slot` cells.
private struct GlyphSet {
    var name: String
    var clusters: [[UInt32]]
    var source: ([UInt32]) -> String
    var grid: ([UInt32]) -> Int
    var width: ([UInt32]) -> Int
    var slot: Int
}

private let spriteSource = "sprite", sfMonoFamily = ".SF NS Mono", appleColorEmoji = "Apple Color Emoji"
// Ink may leave its cells by this much: Ghostty clips no glyph, and the antialiased edges of SF Mono's letters, of the
// icons fitted to their cells and of Ghostty's diagonal sprites reach up to 2 px past them at 14 pt and scale 2.
private let inkMargin = 2

// Latin-1 Supplement and Latin Extended-A codepoints SF Mono lacks, and the face nmux falls back to for each.
private let latinExceptions: [UInt32: String] = [
    0x138: "Menlo",
    0x149: "Menlo",
    0x14A: "Menlo",
    0x14B: "Menlo",
    0x17F: "Menlo",
]

// Every codepoint between the two that has a printable character: neither unassigned, a control, a format character
// such as the soft hyphen that draws nothing, nor a surrogate or a private use codepoint.
private func printable(_ range: ClosedRange<UInt32>) -> [[UInt32]] {
    range.filter { cp in
        guard let category = Unicode.Scalar(cp)?.properties.generalCategory else { return false }
        return ![.unassigned, .control, .format, .surrogate, .privateUse].contains(category)
    }.map { [$0] }
}

// Every assigned codepoint between the two, private use included.
private func assigned(_ range: ClosedRange<UInt32>) -> [[UInt32]] {
    range.filter { Unicode.Scalar($0).map { $0.properties.generalCategory != .unassigned } ?? false }.map { [$0] }
}

// A text-default base with a skin tone, which libghostty-vt lays out over one cell, as Ghostty does.
private func isNarrowEmoji(_ cluster: [UInt32]) -> Bool {
    cluster.count == 2 && defaultPresentation(cluster[0]) == .text && (0x1F3FB...0x1F3FF).contains(cluster[1])
}

private func glyphSets(emojiTest: String) -> [GlyphSet] {
    let symbols = CTFontCreateWithName(symbolsPostScriptName as CFString, 28, nil)
    // Unregistered, CoreText hands back another face under the name.
    precondition(CTFontCopyPostScriptName(symbols) as String == symbolsPostScriptName,
                 "Symbols Nerd Font is not registered")
    let icons = CTFontCopyCharacterSet(symbols) as CharacterSet
    let iconCodepoints = (0...0x10FFFF as ClosedRange<UInt32>).filter {
        Unicode.Scalar($0).map(icons.contains) ?? false
    }
    // A fully-qualified line opens with the sequence's codepoints in hex, before its `;`.
    let emoji = emojiTest.split(separator: "\n").filter { $0.contains("; fully-qualified") }.map {
        $0.prefix { $0 != ";" }.split(separator: " ").map { UInt32($0, radix: 16)! }
    }
    let spriteRanges: [ClosedRange<UInt32>] = [0x2500...0x28FF, 0xE0B0...0xE0D7, 0xF5D0...0xF60D, 0x1CC00...0x1CEBF,
                                               0x1FB00...0x1FBFF]
    return [
        GlyphSet(name: "ascii", clusters: (0x20...0x7E as ClosedRange<UInt32>).map { [$0] },
                 source: { _ in sfMonoFamily },
                 grid: { _ in 1 }, width: { _ in 1 }, slot: 1),
        GlyphSet(name: "latin", clusters: printable(0xA0...0x17F), source: { latinExceptions[$0[0]] ?? sfMonoFamily },
                 grid: { _ in 1 }, width: { _ in 1 }, slot: 1),
        // Ghostty's sprite face draws a few unassigned codepoints of its blocks too; they draw nothing.
        GlyphSet(name: "sprites", clusters: spriteRanges.flatMap { assigned($0) }.filter { isSprite($0[0]) },
                 source: { _ in spriteSource }, grid: { _ in 1 }, width: { _ in 1 }, slot: 1),
        // The Powerline codepoints the face maps draw from the sprite face, which comes first; U+26A1 has an emoji
        // presentation, so Apple Color Emoji draws it, and it and U+2630, East Asian Wide, take two cells of the grid.
        // An icon with a free cell after is drawn over two cells where Ghostty's `constraintWidth` lets a symbol.
        GlyphSet(name: "nerd-font", clusters: iconCodepoints.map { [$0] },
                 source: { isSprite($0[0]) ? spriteSource : $0[0] == 0x26A1 ? appleColorEmoji : "Symbols Nerd Font" },
                 grid: { [0x26A1, 0x2630].contains($0[0]) ? 2 : 1 },
                 width: { isSprite($0[0]) || !isSymbol($0[0]) ? 1 : 2 }, slot: 2),
        GlyphSet(name: "emoji", clusters: emoji, source: { _ in appleColorEmoji }, grid: { isNarrowEmoji($0) ? 1 : 2 },
                 width: { _ in 2 }, slot: 2),
    ]
}

// A cluster as nmux draws it in a cell with a free cell after: the face it resolves to, its family or `sprite`, the
// glyphs the shaper put on the cell, the cells the grid lays it out over and the cells it is drawn over, and its
// rasters placed from the cell's left edge and bottom.
private struct Drawing {
    var face: Face?
    var source = "none"
    var glyphs: [CGGlyph] = []
    var grid = 1
    var cells = 1
    var rasters: [Sprite] = []
    var color = false
}

// libghostty-vt's width of the cluster, as the terminal lays it out with grapheme clustering on.
private func gridWidth(_ cluster: [UInt32]) -> Int {
    var width: UInt8 = 0
    _ = cluster.withUnsafeBufferPointer { ghostty_unicode_grapheme_width($0.baseAddress, $0.count, &width) }
    return Int(width)
}

// Each glyph the shaper puts on the row's cells in the face, rasterised as `Cells.drawRow` does, with the constraint of
// its cell's first codepoint over `span` cells, and moved by its offset in that cell; a glyph with no outline has an
// empty raster.
@MainActor
private func shapedRasters(_ row: [RunCell], in face: Face, font: Font,
                           span: Int) -> [(cell: Int, glyph: CGGlyph, raster: Sprite)] {
    let text = runText(row[...])
    let laid = shape(text, in: shapingFont(face.font))
    return zip(laid, cellsOf(laid.map(\.laid), map: text.map)).map { glyph, place in
        var raster = rasterise(face, glyph.glyph, constraint: glyphConstraint(row[place.cell].codepoints[0]),
                               cells: span, cell: font.cell, thicken: font.thicken)
        (raster.left, raster.top) = (raster.left + place.x, raster.top + place.y)
        return (place.cell, glyph.glyph, raster)
    }
}

// As `Cells.drawRow` draws it: the face from `resolve`, else nmux's resolver, the cluster shaped in it with a space
// after, and each glyph on the cell over its constraint width; a sprite over the grid width.
@MainActor
private func drawing(_ cluster: [UInt32], in font: Font, resolve: ([UInt32]) -> Face? = { _ in nil }) -> Drawing {
    var drawn = Drawing()
    guard let face = resolve(cluster) ?? font.face(for: cluster) else { return drawn }
    drawn.grid = gridWidth(cluster)
    (drawn.face, drawn.source, drawn.color) = (face, face.sprite ? spriteSource : family(face.font), face.color)
    if face.sprite {
        drawn.cells = drawn.grid
        let sprite = charSprite(cluster[0], span: drawn.cells, cell: font.cell)
        if sprite.width > 0 { drawn.rasters = [sprite] }
        return drawn
    }
    drawn.cells = constraintWidth([cluster[0], 0x20], at: 0, wide: drawn.grid == 2)
    let row = [RunCell(codepoints: Cluster(cluster), empty: false), RunCell(codepoints: [0x20], empty: false)]
    for placed in shapedRasters(row, in: face, font: font, span: drawn.cells) where placed.cell == 0 {
        drawn.glyphs.append(placed.glyph)
        if placed.raster.width > 0 { drawn.rasters.append(placed.raster) }
    }
    return drawn
}

// The codepoints as a person reads them: `U+0041 A`.
private func label(_ cluster: [UInt32]) -> String {
    let hex = cluster.map { String(format: "U+%04X", $0) }.joined(separator: " ")
    let text = String(String.UnicodeScalarView(cluster.compactMap(Unicode.Scalar.init)))
    return "\(hex) \(text)"
}

// What is wrong with each cluster of the set, one line each: no glyph or LastResort's, a sequence that did not join,
// another source, another width in the grid or drawn, ink past its cells. `resolve` stands in for nmux's resolver
// where it gives a face.
@MainActor
private func walk(_ set: GlyphSet, in font: Font, resolve: ([UInt32]) -> Face? = { _ in nil }) -> [String] {
    var failures: [String] = []
    for cluster in set.clusters {
        let drawn = drawing(cluster, in: font, resolve: resolve)
        var wrong: [String] = []
        // Joiners and selectors draw nothing; a sequence the face joins takes fewer glyphs than it has parts.
        let parts = cluster.filter { $0 != 0x200D && !isPresentationSelector($0) }.count
        if drawn.face == nil || drawn.source.hasSuffix("LastResort") {
            wrong.append("no real glyph (\(drawn.source))")
        } else if !drawn.face!.sprite && (drawn.glyphs.isEmpty || drawn.glyphs.contains { $0 == 0 || $0 == 0xFFFF }) {
            wrong.append("no real glyph (\(drawn.glyphs))")
        } else if parts > 1 && drawn.glyphs.count >= parts {
            wrong.append("\(drawn.glyphs.count) glyphs, not joined")
        }
        let source = set.source(cluster)
        if drawn.source != source { wrong.append("from \(drawn.source), not \(source)") }
        if drawn.color != (source == appleColorEmoji) { wrong.append(drawn.color ? "in colour" : "not in colour") }
        if drawn.grid != set.grid(cluster) { wrong.append("\(drawn.grid) cells in the grid, not \(set.grid(cluster))") }
        if drawn.cells != set.width(cluster) {
            wrong.append("drawn over \(drawn.cells) cells, not \(set.width(cluster))")
        }
        let out = drawn.rasters.map { inkPast($0, cells: drawn.cells, cell: font.cell) }.max() ?? 0
        if out > inkMargin { wrong.append("ink \(out) px past its cells") }
        if !wrong.isEmpty { failures.append("\(set.name) \(label(cluster)): \(wrong.joined(separator: ", "))") }
    }
    return failures
}

// How far, in pixels, the raster's ink reaches past `cells` cells; a pixel with no coverage is no ink.
private func inkPast(_ raster: Sprite, cells: Int, cell: Cell) -> Int {
    let depth = raster.pixels.count / (raster.width * raster.height)
    var most = 0
    for y in 0..<raster.height {
        for x in 0..<raster.width where raster.pixels[(y * raster.width + x) * depth + depth - 1] > 0 {
            let px = raster.left + x, py = cell.height - raster.top + y
            most = max(most, -px, px - (cells * cell.width - 1), -py, py - (cell.height - 1))
        }
    }
    return most
}

// A sheet: black on white, one byte of grey a pixel, or premultiplied BGRA for the emoji, its first row the top; and
// the place of each item a mismatch names.
private struct Sheet {
    var name: String
    var width, height: Int
    var color: Bool
    var pixels: [UInt8]
    var items: [(label: String, x: Int, y: Int, width: Int, height: Int)] = []

    var depth: Int { color ? 4 : 1 }

    init(name: String, cols: Int, rows: Int, cell: Cell, color: Bool) {
        (self.name, width, height, self.color) = (name, cols * cell.width, rows * cell.height, color)
        pixels = [UInt8](repeating: 255, count: width * height * (color ? 4 : 1))
    }

    // The raster over the cell whose top-left pixel is (x, y), in black at `alpha`, or in its own colours on a colour
    // sheet.
    mutating func draw(_ raster: Sprite, x: Int, y: Int, cell: Cell, alpha: Int = 255) {
        let rasterDepth = raster.pixels.count / (raster.width * raster.height)
        precondition(rasterDepth <= depth, "a colour raster on the grey sheet \(name)")
        for ry in 0..<raster.height {
            let py = y + cell.height - raster.top + ry
            guard py >= 0 && py < height else { continue }
            for rx in 0..<raster.width {
                let px = x + raster.left + rx
                guard px >= 0 && px < width else { continue }
                let at = (py * width + px) * depth, from = (ry * raster.width + rx) * rasterDepth
                if rasterDepth == 1 {
                    let a = Int(raster.pixels[from]) * alpha / 255
                    for c in 0..<min(depth, 3) { pixels[at + c] = UInt8((Int(pixels[at + c]) * (255 - a) + 127) / 255) }
                } else {
                    // Premultiplied over: the raster's colour, then the sheet's through what it leaves.
                    let a = Int(raster.pixels[from + 3])
                    for c in 0..<3 {
                        pixels[at + c] = UInt8(Int(raster.pixels[from + c])
                                               + (Int(pixels[at + c]) * (255 - a) + 127) / 255)
                    }
                }
            }
        }
    }

    var image: CGImage {
        var copy = pixels
        return copy.withUnsafeMutableBytes { bitmap($0, width: width, height: height, color: color).makeImage()! }
    }

    // The image's pixels in this sheet's format, nil when its size differs.
    func pixels(of image: CGImage) -> [UInt8]? {
        guard image.width == width && image.height == height else { return nil }
        var out = [UInt8](repeating: 0, count: pixels.count)
        out.withUnsafeMutableBytes {
            bitmap($0, width: width, height: height, color: color)
                .draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return out
    }
}

// Opaque grey, or the BGRA colour glyphs rasterise in.
private func bitmap(_ buf: UnsafeMutableRawBufferPointer, width: Int, height: Int, color: Bool) -> CGContext {
    color ? colorContext(buf, width: width, height: height)!
        : CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                    space: CGColorSpace(name: CGColorSpace.linearGray)!, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
}

private let sheetCols = 64

// The set's clusters, each drawn in its slot, `sheetCols` cells a row.
@MainActor
private func sheet(_ set: GlyphSet, in font: Font, suffix: String) -> Sheet {
    let perRow = sheetCols / set.slot, cell = font.cell
    let drawings = set.clusters.map { drawing($0, in: font) }
    var sheet = Sheet(name: set.name + suffix, cols: sheetCols, rows: (set.clusters.count + perRow - 1) / perRow,
                      cell: cell, color: drawings.contains(where: \.color))
    for (i, (cluster, drawn)) in zip(set.clusters, drawings).enumerated() {
        let x = i % perRow * set.slot * cell.width, y = i / perRow * cell.height
        for raster in drawn.rasters { sheet.draw(raster, x: x, y: y, cell: cell) }
        sheet.items.append((label(cluster), x, y, set.slot * cell.width, cell.height))
    }
    return sheet
}

// One ASCII line in each style and faint, then under each decoration.
@MainActor
private func stylesSheet(in font: Font, suffix: String) -> Sheet {
    let line = Array("The quick brown fox jumps over the lazy dog: 0123456789 {}[]()".unicodeScalars.map(\.value))
    let cell = font.cell
    let lines: [(name: String, style: FontStyle, alpha: Int, decoration: Decoration?)] =
        [("regular", .regular, 255, nil), ("bold", .bold, 255, nil), ("italic", .italic, 255, nil),
         ("bold italic", .boldItalic, 255, nil), ("faint", .regular, 128, nil)]
        + [Decoration.underline, .underlineDouble, .underlineCurly, .underlineDotted, .underlineDashed, .strike,
           .overline]
        .map { ($0.rawValue, .regular, 255, $0) }
    var sheet = Sheet(name: "styles" + suffix, cols: sheetCols, rows: lines.count, cell: cell, color: false)
    let cells = line.map { RunCell(codepoints: [$0], empty: false) }
    for (row, styled) in lines.enumerated() {
        for placed in shapedRasters(cells, in: font[style: styled.style], font: font, span: 1)
            where placed.raster.width > 0 {
            sheet.draw(placed.raster, x: placed.cell * cell.width, y: row * cell.height, cell: cell,
                       alpha: styled.alpha)
        }
        for (i, cp) in line.enumerated() {
            if let decoration = styled.decoration {
                sheet.draw(decorationSprite(decoration, span: 1, cell: cell), x: i * cell.width, y: row * cell.height,
                           cell: cell)
            }
            sheet.items.append(("\(styled.name), column \(i + 1), \(label([cp]))", i * cell.width, row * cell.height,
                                cell.width, cell.height))
        }
    }
    return sheet
}

// The twelve sheets: each of the five sets and the styles, thin and thickened.
@MainActor
private func referenceSheets(_ sets: [GlyphSet], primary: CTFont) -> [Sheet] {
    [(false, ""), (true, "-thickened")].flatMap { thicken, suffix in
        let font = Font(primary, points: 14, scale: 2, thicken: thicken)
        return sets.map { sheet($0, in: font, suffix: suffix) } + [stylesSheet(in: font, suffix: suffix)]
    }
}

private func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let out = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(out, image, nil)
    CGImageDestinationFinalize(out)
}

// Each item whose pixels differ from the reference's, with how many, and the pixels that differ outside every item;
// empty when the sheet matches.
private func mismatches(_ sheet: Sheet, reference: [UInt8]) -> [(label: String, pixels: Int)] {
    func differs(_ x: Int, _ y: Int) -> Bool {
        let at = (y * sheet.width + x) * sheet.depth
        return sheet.pixels[at..<at + sheet.depth] != reference[at..<at + sheet.depth]
    }
    var inItems = 0
    var out: [(label: String, pixels: Int)] = sheet.items.compactMap { item in
        var count = 0
        for y in item.y..<item.y + item.height {
            for x in item.x..<item.x + item.width where differs(x, y) { count += 1 }
        }
        inItems += count
        return count == 0 ? nil : (item.label, count)
    }
    let all = (0..<sheet.height).reduce(0) { sum, y in sum + (0..<sheet.width).filter { differs($0, y) }.count }
    if all > inItems { out.append(("outside every item", all - inItems)) }
    return out
}

// The reference faded, and every pixel that differs in red.
private func diffImage(_ sheet: Sheet, reference: [UInt8]) -> CGImage {
    var diff = [UInt8](repeating: 255, count: sheet.width * sheet.height * 4)
    for i in 0..<sheet.width * sheet.height {
        let at = i * sheet.depth
        let differs = sheet.pixels[at..<at + sheet.depth] != reference[at..<at + sheet.depth]
        let grey = UInt8(191 + Int(reference[at]) / 4)
        // BGRA.
        diff.replaceSubrange(i * 4..<i * 4 + 4, with: differs ? [0, 0, 255, 255] : [grey, grey, grey, 255])
    }
    return diff.withUnsafeMutableBytes {
        bitmap($0, width: sheet.width, height: sheet.height, color: true).makeImage()!
    }
}

private let referencesDirectory = repositoryPath("Tests/references")
private let freshDirectory = repositoryPath("build/references")
private let diffDirectory = repositoryPath("build/reference-diffs")

// SF Mono at 14 pt, with Symbols Nerd Font registered as the app registers it.
private func referencePrimary() -> CTFont {
    _ = symbolsRegistered
    return sfMono(14)
}

// The sets need Symbols Nerd Font registered, whichever global the suite reads first.
private func loadGlyphSets() -> [GlyphSet] {
    _ = symbolsRegistered
    return glyphSets(emojiTest: try! String(contentsOfFile: repositoryPath("vendor/unicode/emoji-test.txt"),
                                            encoding: .utf8))
}

// What is wrong with the sheet against its approved reference, one line each; empty when it matches.
private func referenceReport(_ sheet: Sheet) -> [String] {
    let path = "\(referencesDirectory)/\(sheet.name).png"
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return ["no \(path): run `make references`, look at the sheets, and copy them in"]
    }
    guard let reference = sheet.pixels(of: image) else {
        return ["\(path) is \(image.width) × \(image.height), the sheet \(sheet.width) × \(sheet.height)"]
    }
    return compare(sheet, reference: reference)
}

// Each item that differs from the reference, with its count of pixels, and the diff image written for them; nothing
// when the sheet matches.
private func compare(_ sheet: Sheet, reference: [UInt8]) -> [String] {
    let wrong = mismatches(sheet, reference: reference)
    guard !wrong.isEmpty else { return [] }
    let path = "\(diffDirectory)/\(sheet.name)-diff.png"
    try? FileManager.default.createDirectory(atPath: diffDirectory, withIntermediateDirectories: true)
    writePNG(diffImage(sheet, reference: reference), to: path)
    return wrong.map { "\(sheet.name) \($0.label): \($0.pixels) pixels differ" } + ["diff in \(path)"]
}

// Built once for every test of the suite: the walk of all five sets is the slow part.
@MainActor private let primary = referencePrimary(), sets = loadGlyphSets()

@MainActor private func set(_ name: String) -> GlyphSet { sets.first { $0.name == name }! }

@MainActor
struct GlyphTests {

    @Test("each glyph of the set is real, from its source, at its width and in its cells",
          arguments: ["ascii", "latin", "sprites", "nerd-font", "emoji"])
    func eachGlyphOfTheSetIsReal(name: String) {
        let glyphs = set(name)
        #expect(walk(glyphs, in: Font(primary, points: 14, scale: 2)) == [], "\(glyphs.clusters.count) \(name) glyphs")
    }

    @Test("a codepoint that resolves to LastResort fails the walk once, named")
    func aCodepointThatResolvesToLastResortFails() throws {
        let lastResort = Face(font: CTFontCreateWithName("LastResort" as CFString, 28, nil), style: .regular)
        let caught = walk(set("ascii"), in: Font(primary, points: 14, scale: 2)) { $0 == [0x41] ? lastResort : nil }
        try #require(caught.count == 1)
        #expect(caught[0].contains("U+0041 A"))
    }

    @Test("a sheet with one pixel moved names the codepoint and the count") func aSheetWithOnePixelMovedNamesThe() {
        let ascii = sheet(set("ascii"), in: Font(primary, points: 14, scale: 2), suffix: "")
        var moved = ascii
        let a = moved.items[0x41 - 0x20]
        moved.pixels[(a.y + a.height / 2) * moved.width + a.x + a.width / 2] ^= 0xFF
        #expect(mismatches(moved, reference: ascii.pixels).map { "\($0.label) \($0.pixels)" } == ["U+0041 A 1"])
    }

    // A sprite drawn a pixel shorter: the bottom row of U+2502's line turns white.
    @Test("a sprite drawn a pixel shorter fails the sprites sheet, naming it, and writes a diff image")
    func aSpriteDrawnAPixelShorterFailsThe() {
        let sprites = sheet(set("sprites"), in: Font(primary, points: 14, scale: 2), suffix: "")
        var shorter = sprites
        shorter.name = "sprites-shorter"
        let line = shorter.items.first { $0.label.hasPrefix("U+2502 ") }!
        for x in line.x..<line.x + line.width { shorter.pixels[(line.y + line.height - 1) * shorter.width + x] = 255 }
        try? FileManager.default.removeItem(atPath: "\(diffDirectory)/sprites-shorter-diff.png")
        let report = compare(shorter, reference: sprites.pixels)
        #expect(report.first == "sprites-shorter U+2502 │: 2 pixels differ")
        #expect(report.count == 2)
        #expect(FileManager.default.fileExists(atPath: "\(diffDirectory)/sprites-shorter-diff.png"))
    }

    @Test("the sprites sheet matches its approved reference, thin and thickened", arguments: [false, true])
    func theSpritesSheetMatchesItsApprovedReference(thicken: Bool) {
        let sprites = sheet(set("sprites"), in: Font(primary, points: 14, scale: 2, thicken: thicken),
                            suffix: thicken ? "-thickened" : "")
        #expect(referenceReport(sprites) == [])
    }

    // `make references`: the twelve sheets into the build directory, for the author to look at and copy over the
    // approved ones. It checks nothing.
    @Test("draw the twelve reference sheets",
          .enabled(if: ProcessInfo.processInfo.environment["NMUX_REFERENCES"] != nil))
    func drawTheTwelveReferenceSheets() throws {
        try FileManager.default.createDirectory(atPath: freshDirectory, withIntermediateDirectories: true)
        for sheet in referenceSheets(sets, primary: primary) {
            writePNG(sheet.image, to: "\(freshDirectory)/\(sheet.name).png")
            print("\(freshDirectory)/\(sheet.name).png")
        }
        print("Approve the sprite sheets with: cp \(freshDirectory)/sprites*.png \(referencesDirectory)/")
    }
}
