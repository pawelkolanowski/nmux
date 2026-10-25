// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The CPU copy of the glyph atlas: one byte of alpha a pixel, packed in rows, left to right and top to bottom. It only
/// grows, doubling and keeping every pixel where it was, as Ghostty's `src/font/Atlas.zig` (`grow`) does at commit
/// 22f100c6, so a glyph's place never moves.
struct Atlas {
    private(set) var size: Int
    private(set) var pixels: [UInt8]
    /// What changed since the last upload; `grew` means the whole texture is new.
    private(set) var dirty: (x: Int, y: Int, maxX: Int, maxY: Int)?
    private(set) var grew = false
    private var rowX = 0, rowY = 0, rowHeight = 0

    init(size: Int = 512) {
        self.size = size
        pixels = [UInt8](repeating: 0, count: size * size)
    }

    /// A free place for `width` × `height`, with a pixel of gap so sampling never bleeds into a neighbour.
    mutating func reserve(width: Int, height: Int) -> (x: Int, y: Int) {
        if rowX + width + 1 > size { (rowX, rowY, rowHeight) = (0, rowY + rowHeight + 1, 0) }
        while rowY + height + 1 > size || width + 1 > size { grow() }
        defer { rowX += width + 1; rowHeight = max(rowHeight, height) }
        return (rowX, rowY)
    }

    /// Copies `rows`, top row first, into the place `reserve` gave.
    mutating func fill(x: Int, y: Int, width: Int, height: Int, rows: [UInt8]) {
        for r in 0..<height {
            let at = (y + r) * size + x
            pixels.replaceSubrange(at..<at + width, with: rows[r * width..<(r + 1) * width])
        }
        let d = dirty ?? (x, y, x + width, y + height)
        dirty = (min(d.x, x), min(d.y, y), max(d.maxX, x + width), max(d.maxY, y + height))
    }

    /// Called once the renderer uploaded what changed.
    mutating func uploaded() {
        dirty = nil
        grew = false
    }

    private mutating func grow() {
        let old = size
        size *= 2
        var next = [UInt8](repeating: 0, count: size * size)
        for r in 0..<old { next.replaceSubrange(r * size..<r * size + old, with: pixels[r * old..<(r + 1) * old]) }
        pixels = next
        grew = true
    }
}
