import CoreText
import Darwin
import Foundation
import Synchronization
import Testing
@testable import Terminal

// `make bench`: the cost of rebuilding every row of a full 4K screen, 380 x 100 cells of SF Mono at 13 pt and scale 2,
// as a full-screen pane scrolls. It prints the heap allocations and the time of one rebuild, and checks nothing.
struct BenchTests {
    @Test("rebuild a full screen of rows", .enabled(if: ProcessInfo.processInfo.environment["NMUX_BENCH"] != nil))
    @MainActor func rebuildAFullScreenOfRows() throws {
        let grid = Grid(cols: 380, rows: 100), font = Font(sfMono(13), points: 13, scale: 2)
        let screen = NSTemporaryDirectory() + "nmux-bench-\(getpid())"
        let text = benchScreen(grid)
        try text.write(toFile: screen, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: screen) }
        let parsed = Atomic<Int>(0)
        let handlers = VTHost.Handlers(output: { parsed.add($0, ordering: .relaxed) }, exit: { _, _ in })
        let host = try VTHost(argv: ["/bin/cat", screen], grid: grid, cell: font.cell, handlers: handlers)
        host.start()
        let size = text.utf8.count
        let deadline = ContinuousClock.now + .seconds(10)
        while parsed.load(ordering: .relaxed) < size, ContinuousClock.now < deadline { usleep(1000) }
        try #require(parsed.load(ordering: .relaxed) >= size, "the terminal parsed the whole screen")

        let cells = Cells(font: font)
        // The first rebuild shapes every row and fills the atlas; the ones after it find both kept, as scrolling does.
        _ = cells.update(host)
        let frames = 50
        countAllocations(true)
        let start = ContinuousClock.now
        for _ in 0..<frames {
            cells.restyled = true
            _ = cells.update(host)
        }
        let elapsed = ContinuousClock.now - start
        countAllocations(false)
        let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        print("""
            bench: \(grid.cols) x \(grid.rows) cells, \(allocations.load(ordering: .relaxed) / frames) allocations \
            and \(String(format: "%.2f", ms / Double(frames))) ms per full rebuild
            """)
    }
}

// Rows as a full-screen program draws them: mostly ASCII in a few colours, with some Polish, box drawing and an icon.
private func benchScreen(_ grid: Grid) -> String {
    let words = ["func", "let", "return", "\u{1b}[32mstring\u{1b}[0m", "\u{1b}[1mbold\u{1b}[0m", "zażółć", "│",
                 "→", "\u{1b}[38;5;208mvalue\u{1b}[0m", "if", "else", "{", "}", "\u{f015}", "self.cells", "0x1f"]
    var rows: [String] = []
    for y in 0..<grid.rows {
        var row = "", width = 0, i = y
        while width < grid.cols - 12 {
            let word = words[i % words.count]
            row += word + " "
            width += word.replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression).count + 1
            i += 7
        }
        rows.append(row)
    }
    return "\u{1b}[H\u{1b}[2J" + rows.joined(separator: "\r\n")
}

// The heap allocations on every thread while counting is on, through the hook Instruments' allocation tracking uses.
private let allocations = Atomic<Int>(0)

private typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

private func countAllocations(_ on: Bool) {
    guard let hook = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else { return }
    let logger: MallocLogger = { type, _, _, _, _, _ in
        // MALLOC_LOG_TYPE_ALLOCATE
        if type & 2 != 0 { allocations.add(1, ordering: .relaxed) }
    }
    if on { allocations.store(0, ordering: .relaxed) }
    hook.assumingMemoryBound(to: MallocLogger?.self).pointee = on ? logger : nil
}
