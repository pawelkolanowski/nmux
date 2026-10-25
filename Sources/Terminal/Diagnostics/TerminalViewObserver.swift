#if NMUX_SELFTEST
import AppKit

/// What the view reports to the self-test, which is its one observer. Every method does nothing by default.
@MainActor
public protocol TerminalViewObserver: AnyObject {
    /// After each frame that drew a change.
    func framed()
    /// Each time output resumes the frames, with the bytes parsed since the last call.
    func output(_ bytes: Int)
    /// Each grid the host accepts, and each scale change with its new cell.
    func resized(_ view: TerminalView, grid: Grid)
    func scaled(_ scale: Double, cell: Cell)
    /// Each frame that missed its 1000 ms wait inside a live resize, and each mode 2026 hold that begins.
    func lateFrame()
    func holdStarted()
}

extension TerminalViewObserver {
    public func framed() {}
    public func output(_ bytes: Int) {}
    public func resized(_ view: TerminalView, grid: Grid) {}
    public func scaled(_ scale: Double, cell: Cell) {}
    public func lateFrame() {}
    public func holdStarted() {}
}
#endif
