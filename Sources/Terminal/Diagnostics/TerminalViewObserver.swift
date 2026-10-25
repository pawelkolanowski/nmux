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
    /// Each key the view hands the PTY, with its keycode, its mods and its bytes, empty when the encoder made none.
    func key(_ code: UInt16, _ mods: UInt16, _ bytes: [UInt8])
    /// Each change of the marked text, empty when it goes, and each text committed.
    func preedit(_ text: String)
    func committed(_ text: String)
    /// Each mouse report the view hands the PTY: `press`, `release` or `motion`, the button's name or `none`, the cell
    /// under the pointer and the bytes.
    func mouse(_ action: String, _ button: String, _ cell: SIMD2<Int>, _ bytes: [UInt8])
    /// Each link a Cmd+click opens, in place of opening it.
    func opened(_ url: URL)
    /// Each copy's text, each paste sent with whether the pane takes it bracketed, each OSC 52 write that reached the
    /// pasteboard, and each OSC 52 read answered with its text, nil for no reply.
    func copied(_ text: String)
    func pasted(_ text: String, bracketed: Bool)
    func clipboardWritten(_ text: String)
    func clipboardRead(_ text: String?)
    /// The stand-in for the text system, which a synthetic key never reaches while the app is not active: true when it
    /// took the key in place of `interpretKeyEvents`.
    func textSystem(_ event: NSEvent) -> Bool
}

extension TerminalViewObserver {
    public func framed() {}
    public func output(_ bytes: Int) {}
    public func resized(_ view: TerminalView, grid: Grid) {}
    public func scaled(_ scale: Double, cell: Cell) {}
    public func lateFrame() {}
    public func holdStarted() {}
    public func key(_ code: UInt16, _ mods: UInt16, _ bytes: [UInt8]) {}
    public func preedit(_ text: String) {}
    public func committed(_ text: String) {}
    public func mouse(_ action: String, _ button: String, _ cell: SIMD2<Int>, _ bytes: [UInt8]) {}
    public func opened(_ url: URL) {}
    public func copied(_ text: String) {}
    public func pasted(_ text: String, bracketed: Bool) {}
    public func clipboardWritten(_ text: String) {}
    public func clipboardRead(_ text: String?) {}
    public func textSystem(_ event: NSEvent) -> Bool { false }
}
#endif
