import Foundation
import Terminal

/// A Session as nmux shows it: what tmux lists for it, and the view that owns its pty, its libghostty-vt terminal and
/// its tmux client.
final class Session {
    var info: SessionInfo
    let view: TerminalView
    /// When its client last started, and whether a client that failed within a second waits on tmux's error for a key.
    var started = Date()
    var waiting = false
    /// The close confirmed: the Session is being killed, so it never attaches again and no follow moves it.
    var killing = false
    /// A bell rang while the Session was not shown, and it has not been shown since. Its pill shows the dot.
    var bellMark = false
    /// A close asks on the pill whether to kill the Session; the pill keeps its size and drops its hover parts
    /// meanwhile.
    var asking = false
    /// Its client's tty, the name tmux knows the client by.
    var tty: String { view.host.tty }

    init(_ info: SessionInfo, _ view: TerminalView) {
        (self.info, self.view) = (info, view)
    }
}
