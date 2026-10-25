// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The CPU copy of a glyph atlas: `depth` bytes a pixel, one of alpha or four of BGRA, packed in rows, left to right
/// and top to bottom. It only grows, doubling and keeping every pixel where it was, as Ghostty's `src/font/Atlas.zig`
/// (`grow`) does at commit 22f100c6, so a glyph's place never moves.
struct Atlas {
    private(set) var size: Int
    let depth: Int
    private(set) var pixels: [UInt8]
    /// What changed since the last upload; `grew` means the whole texture is new.
    private(set) var dirty: (x: Int, y: Int, maxX: Int, maxY: Int)?
    private(set) var grew = false
    private var rowX = 0, rowY = 0, rowHeight = 0

    init(size: Int = 512, depth: Int = 1) {
        (self.size, self.depth) = (size, depth)
        pixels = [UInt8](repeating: 0, count: size * size * depth)
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
        let line = width * depth
        for r in 0..<height {
            let at = ((y + r) * size + x) * depth
            pixels.replaceSubrange(at..<at + line, with: rows[r * line..<(r + 1) * line])
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
        let old = size * depth
        size *= 2
        let line = size * depth
        var next = [UInt8](repeating: 0, count: size * line)
        for r in 0..<old / depth {
            next.replaceSubrange(r * line..<r * line + old, with: pixels[r * old..<(r + 1) * old])
        }
        pixels = next
        grew = true
    }
}
