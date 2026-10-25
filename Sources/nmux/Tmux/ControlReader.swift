nonisolated enum ControlEvent<Answer> {
    case notification(String)
    case answer(Answer, ok: Bool, lines: [String])
}

/// tmux's control-mode protocol, read line by line. A line outside a block is a notification; `%begin` opens the answer
/// to the oldest command still waiting, which the `%end` or `%error` with the same time, number and flags closes as a
/// success or a failure. The attach's own block comes first and answers nothing.
nonisolated struct ControlReader<Answer> {
    private var waiting: [Answer?] = [nil]
    private var block: (tag: Substring, lines: [String])?
    private var buffer: [UInt8] = []

    /// The answer to the command written next.
    mutating func expect(_ answer: Answer) { waiting.append(answer) }

    /// The events the complete lines in `bytes` give, in order; a partial line waits for the next bytes.
    mutating func feed(_ bytes: some Sequence<UInt8>) -> [ControlEvent<Answer>] {
        buffer += bytes
        var events: [ControlEvent<Answer>] = []
        while let nl = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<nl], as: UTF8.self)
            buffer.removeSubrange(...nl)
            guard let open = block else {
                if line.hasPrefix("%begin ") {
                    block = (line.dropFirst(7), [])
                } else {
                    events.append(.notification(line))
                }
                continue
            }
            let ok = line == "%end \(open.tag)"
            guard ok || line == "%error \(open.tag)" else {
                block?.lines.append(line)
                continue
            }
            block = nil
            if !waiting.isEmpty, let answer = waiting.removeFirst() {
                events.append(.answer(answer, ok: ok, lines: open.lines))
            }
        }
        return events
    }
}
