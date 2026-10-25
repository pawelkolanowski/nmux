import Foundation

// The wheel's accumulator, from `scrollCallback` in Ghostty's `src/Surface.zig` with its default
// `mouse-scroll-multiplier`, at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// Collects vertical wheel deltas into whole lines, keeping the remainder: a precise delta is in pixels, a notched one
/// in notches of at least one, three lines each. Positive is up.
struct WheelScroll: Sendable {
    private var pending = 0.0

    mutating func lines(_ delta: Double, precise: Bool, cell: Double) -> Int {
        guard delta != 0 else { return 0 }
        // macOS ramps a slow notch down to 0.1, so a notch is at least one.
        let pixels = precise ? delta : (delta > 0 ? max(delta, 1) : min(delta, -1)) * cell * 3
        let total = pending + pixels
        guard abs(total) >= cell else {
            pending = total
            return 0
        }
        // Ghostty's comment keeps the remainder, but its code subtracts the unrounded amount and keeps nothing.
        let lines = (total / cell).rounded(.towardZero)
        pending = total - lines * cell
        return Int(lines)
    }
}
