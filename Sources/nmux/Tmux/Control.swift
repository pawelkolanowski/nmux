import Foundation
import Terminal

/// nmux's one control-mode client. It never resizes a window and gets no pane output, and it outlives the
/// Session it sits on. Commands go to its stdin, and tmux answers them in the order they were written.
final class Control {
    typealias Answer = (Bool, [String]) -> Void
    private let tmux: Tmux
    private var process: Process?
    private var input: FileHandle?
    private var reader = ControlReader<Answer>()
    /// Each start and stop counts up, so the lines an earlier client still delivers are dropped.
    private var generation = 0
    private(set) var started = Date()
    /// Every notification but `%exit`, on the main queue.
    var onNotification: (String) -> Void = { _ in }
    /// `%exit` or the end of the pipe, once per client.
    var onEnd: () -> Void = {}

    init(_ tmux: Tmux) { self.tmux = tmux }

    /// Attaches a new client to the Session, in place of any earlier one, whose unanswered commands are dropped.
    func start(on id: SessionID) throws {
        stop()
        let out = Pipe(), inp = Pipe()
        let p = makeProcess(tmux.path, tmux.base + ["-C", "attach-session", "-t", "\(id)",
                                                    "-f", "no-output,ignore-size,no-detach-on-destroy"],
                            input: inp, output: out, error: FileHandle.nullDevice)
        reader = ControlReader()
        let generation = generation
        out.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil }
            onMain { self.feed(data, generation) }
        }
        try p.run()
        (process, input, started) = (p, inp.fileHandleForWriting, Date())
    }

    /// A server keeps an orphaned control client attached, and then never finishes `kill-server`: every new client
    /// then gets `server exited unexpectedly`.
    func stop() {
        generation += 1
        if process?.isRunning == true { process?.terminate() }
        (process, input) = (nil, nil)
    }

    /// Sends one tmux command; `answer` gets whether it succeeded and its output lines, and a failure at once while no
    /// client runs or the write fails. A Session in it goes as `'$id'`, because tmux expands an unquoted `$0`.
    func send(_ command: String, then answer: @escaping Answer = { _, _ in }) {
        guard let input else { return answer(false, []) }
        do {
            try input.write(contentsOf: Data((command + "\n").utf8))
        } catch {
            // On the next turn, so the caller never runs its answer inside its own call.
            return onMain { answer(false, []) }
        }
        reader.expect(answer)
    }

    private func feed(_ data: Data, _ generation: Int) {
        guard generation == self.generation else { return }
        guard !data.isEmpty else { return end() }
        for event in reader.feed(data) {
            switch event {
            case .notification(let line) where line == "%exit" || line.hasPrefix("%exit "): return end()
            case .notification(let line): onNotification(line)
            case let .answer(answer, ok, lines): answer(ok, lines)
            }
            // An answer or a notification may have stopped or restarted the client.
            guard generation == self.generation else { return }
        }
    }

    private func end() {
        stop()
        onEnd()
    }
}
