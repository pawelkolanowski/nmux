import CoreGraphics

/// The index of the first screen frame that holds the pointer, or nil when the pointer is on none.
/// Screen frames are not flipped, so a frame holds its top edge and not its bottom one, as `NSMouseInRect` does.
nonisolated func launchScreen(frames: [CGRect], pointer: CGPoint) -> Int? {
    frames.firstIndex { f in
        pointer.x >= f.minX && pointer.x < f.maxX && pointer.y > f.minY && pointer.y <= f.maxY
    }
}
