#if NMUX_SELFTEST
import AppKit
import Terminal

/// The self-test's script interpreter and its view of the VT host and the drawing: it reads the lines
/// NMUX_SELFTEST_KEYS gains, watches every Session's view as its observer and acts on the shown one, and logs what it
/// sees. Tests/seam/lib.sh describes every command and every line it logs.
final class VTSelfTest: TerminalViewObserver {
    private var view: TerminalView
    private let create: (String) -> Void
    private let perform: (AppAction) -> Void
    /// Hands every terminal the font of that backing scale, as a move to another screen does.
    private let rescale: (Double) -> Void
    /// Resolves the theme for that appearance, nil for the window's own, and applies it, as a switch of the system's
    /// does.
    private let appearance: (Bool?) -> Void
    private var parsed = 0, outputs = 0, probed = false, watchingHold = false
    private var drawnFrames = 0, readBack = false
    private var lastFrame = CACurrentMediaTime(), longestGap = 0.0
    private let named: [(x: Int, y: Int)]
    private let usr1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    private let usr2 = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
    private var steps = 0
    private var keysPressed = 0
    private var loggedSelection = "none"
    /// What the text system does with the next key, `mark` or `insert` and its hex, empty for nothing.
    private var textCall: [String] = []
    /// Every Session's, as the general pasteboard is shared.
    private let pasteboard = NSPasteboard.withUniqueName()

    init(_ view: TerminalView, create: @escaping (String) -> Void, perform: @escaping (AppAction) -> Void,
         rescale: @escaping (Double) -> Void, appearance: @escaping (Bool?) -> Void) {
        (self.view, self.create, self.perform, self.rescale) = (view, create, perform, rescale)
        self.appearance = appearance
        named = (SelfTest.cells ?? "").split(separator: " ").compactMap { pair in
            let xy = pair.split(separator: ",").compactMap { Int($0) }
            return xy.count == 2 ? (xy[0], xy[1]) : nil
        }
        signal(SIGUSR1, SIG_IGN)
        usr1.setEventHandler { MainActor.assumeIsolated { self.framesAsked() } }
        usr1.resume()
        signal(SIGUSR2, SIG_IGN)
        usr2.setEventHandler { MainActor.assumeIsolated { self.resizeStep() } }
        usr2.resume()
        add(view)
        if let path = SelfTest.keys { pollKeys(path) }
    }

    /// The shown Session's view; its first settled frame is read back.
    func follow(_ view: TerminalView) {
        self.view = view
        readBack = false
    }

    /// Watches a new Session's view, before it gets its first drawable.
    func add(_ view: TerminalView) {
        view.observer = self
        view.keepFramesReadable()
        view.stepWhileHidden()
        // The window never becomes key under the self-test, so the cursor would stay hollow; the view is in its
        // window by the next turn.
        onMain { view.setFocused(true) }
        view.use(pasteboard)
    }

    /// Every Session takes each resize; only the shown one logs it.
    func resized(_ view: TerminalView, grid: Grid) {
        if view === self.view { selfTestLog("resize \(grid.cols)x\(grid.rows)") }
    }

    func scaled(_ scale: Double, cell: Cell) {
        selfTestLog("scale \(logNumber(scale)) cell \(cell.width)x\(cell.height)")
    }
    func lateFrame() { selfTestLog("late frame") }
    func holdStarted() { watchHold() }
    func key(_ code: UInt16, _ mods: UInt16, _ bytes: [UInt8]) {
        selfTestLog("key \(code) \(mods) -> \(bytes.isEmpty ? "none" : hex(bytes))")
    }
    func preedit(_ text: String) { selfTestLog("preedit \(hex(text.utf8))".trimmingCharacters(in: .whitespaces)) }

    /// A commit reads one frame back again, so the readback sees the cell it covered return.
    func committed(_ text: String) {
        selfTestLog("commit \(hex(text.utf8))")
        readBack = false
    }

    func mouse(_ action: String, _ button: String, _ cell: SIMD2<Int>, _ bytes: [UInt8]) {
        selfTestLog("mouse \(action) \(button) \(cell.x),\(cell.y) -> \(hex(bytes))")
    }

    func opened(_ url: URL) { selfTestLog("open \(url.absoluteString)") }
    func copied(_ text: String) { selfTestLog("copy \(hex(text.utf8))") }
    func pasted(_ text: String, bracketed: Bool) {
        selfTestLog("paste \(hex(text.utf8)) bracketed=\(bracketed ? "yes" : "no")")
    }
    func clipboardWritten(_ text: String) { selfTestLog("osc52 write \(text.isEmpty ? "empty" : hex(text.utf8))") }
    func clipboardRead(_ text: String?) {
        selfTestLog("osc52 read \(text.map { $0.isEmpty ? "empty" : hex($0.utf8) } ?? "none")")
    }

    /// The text system's call the last key line named, taken by the first key that reaches it.
    func textSystem(_ event: NSEvent) -> Bool {
        defer { textCall = [] }
        return textCall.count == 2 && client(textCall[0], textCall[1])
    }

    private func pollKeys(_ path: String) {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).dropLast() // the last is unfinished
        for line in lines.dropFirst(keysPressed) { press(line.split(separator: " ").map(String.init)) }
        keysPressed = max(keysPressed, lines.count)
        onMain(after: 0.1) { self.pollKeys(path) }
    }

    /// A line whose first word names no command is a key.
    private func press(_ fields: [String]) {
        guard let first = fields.first else { return }
        if let command = commands[first] { return command(Array(fields.dropFirst())) }
        key(fields)
    }

    /// Each command by its first word, handed the words after it; a malformed one does nothing.
    private lazy var commands: [String: ([String]) -> Void] = {
        var table: [String: ([String]) -> Void] = [
            "pasteboard": { self.pasteboardLine($0.first) },
            "rect": { if $0.isEmpty { self.rect() } },
            "create": { self.create($0.joined(separator: " ")) },
            "goto": { args in
                if let action = shortcuts.map(\.action).first(where: { $0.name == args.first }) { self.perform(action) }
            },
        ]
        for verb in ["mark", "insert"] {
            table[verb] = { args in if args.count == 1 { _ = self.client(verb, args[0]) } }
        }
        for verb in ["click", "move", "wheel", "pointer", "drag"] {
            table[verb] = { self.mouse([verb] + $0) }
        }
        return table
    }()

    /// `<keycode> <flags> <characters> [<mark|insert>:<hex>]`: one key pressed and let go through NSApp.sendEvent.
    private func key(_ fields: [String]) {
        guard fields.count == 3 || fields.count == 4, let code = UInt16(fields[0]),
              let raw = UInt(fields[1], radix: 16), let window = view.window else { return }
        textCall = fields.count == 4
            ? fields[3].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init) : []
        let chars = fields[2] == "-" ? "" : fromHex(fields[2])
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero,
                                               modifierFlags: NSEvent.ModifierFlags(rawValue: raw), timestamp: 0,
                                               windowNumber: window.windowNumber, context: nil, characters: chars,
                                               charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)
            else { return }
            NSApp.sendEvent(event)
        }
    }

    /// A mouse line, `click`, `move`, `wheel`, `pointer` or `drag` and its words.
    private func mouse(_ fields: [String]) {
        if fields == ["pointer"] {
            let p = view.pointer
            return selfTestLog("pointer \(p == .pointingHand ? "hand" : p == .iBeam ? "ibeam" : "other")")
        }
        guard let raw = fields.last.flatMap({ UInt($0, radix: 16) }) else { return }
        let cells = fields.dropFirst().map { $0.split(separator: ",").compactMap { Int($0) } }
        if fields[0] == "wheel", fields.count == 5, let points = Int32(fields[1]), let count = Int(fields[3]) {
            wheel(points, precise: fields[2] == "1", count: count, raw)
        } else if fields[0] == "drag", fields.count == 4, cells[0].count == 2, cells[1].count == 2 {
            drag(from: cells[0], to: cells[1], NSEvent.ModifierFlags(rawValue: raw))
        } else if fields.count >= 3,
                  case let xy = fields[fields.count - 2].split(separator: ",").compactMap({ Int($0) }), xy.count == 2 {
            pointer(fields[0], button: fields.count == 4 ? fields[1] : "", at: xy, NSEvent.ModifierFlags(rawValue: raw))
        }
    }

    private func wheel(_ points: Int32, precise: Bool, count: Int, _ raw: UInt) {
        for _ in 0..<count {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 1,
                                   wheel1: points, wheel2: 0, wheel3: 0) else { return }
            cg.flags = CGEventFlags(rawValue: UInt64(raw))
            if let event = NSEvent(cgEvent: cg) { view.scrollWheel(with: event) }
        }
    }

    private func drag(from: [Int], to: [Int], _ flags: NSEvent.ModifierFlags) {
        guard let window = view.window else { return }
        let start = place(from, 0.1), end = place(to, 0.9)
        guard let down = mouseEvent(.leftMouseDown, start, flags, window),
              let moved = mouseEvent(.leftMouseDragged, end, flags, window),
              let up = mouseEvent(.leftMouseUp, end, flags, window) else { return }
        view.mouseDown(with: down)
        view.mouseDragged(with: moved)
        view.mouseUp(with: up)
    }

    /// A mouse event of the window at a point, made now, so clicks in one poll repeat.
    private func mouseEvent(_ type: NSEvent.EventType, _ at: NSPoint, _ flags: NSEvent.ModifierFlags,
                            _ window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: at, modifierFlags: flags,
                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    }

    /// A point in the window inside a cell, `across` of the way from its left edge, at its middle row.
    private func place(_ xy: [Int], _ across: Double) -> NSPoint {
        let cell = view.font.cell, scale = view.font.scale
        return view.convert(NSPoint(x: (Double(xy[0]) + across) * Double(cell.width) / scale,
                                    y: view.bounds.height - (Double(xy[1]) + 0.5) * Double(cell.height) / scale),
                            to: nil)
    }

    private func pasteboardLine(_ written: String?) {
        guard let written else {
            return selfTestLog("pasteboard \(pasteboard.string(forType: .string).map { hex($0.utf8) } ?? "none")")
        }
        pasteboard.clearContents()
        pasteboard.setString(fromHex(written), forType: .string)
    }

    /// A move, or a click that presses and lets go, at the cell's middle.
    private func pointer(_ verb: String, button: String, at xy: [Int], _ flags: NSEvent.ModifierFlags) {
        guard let window = view.window else { return }
        let at = place(xy, 0.5)
        func event(_ type: NSEvent.EventType) -> NSEvent? { mouseEvent(type, at, flags, window) }
        // Only a CGEvent carries the middle button's number; one with no window reads its place in screen points, so it
        // is placed where those points equal the window's.
        func middle(_ type: CGEventType) -> NSEvent? {
            let flipped = CGPoint(x: at.x, y: (NSScreen.screens.first?.frame.height ?? 0) - at.y)
            guard let cg = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: flipped,
                                   mouseButton: .center) else { return nil }
            cg.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
            return NSEvent(cgEvent: cg)
        }
        switch (verb, button) {
        case ("move", _): if let e = event(.mouseMoved) { view.mouseMoved(with: e) }
        case ("click", "left"):
            if let down = event(.leftMouseDown), let up = event(.leftMouseUp) {
                view.mouseDown(with: down)
                view.mouseUp(with: up)
            }
        case ("click", "right"):
            if let down = event(.rightMouseDown), let up = event(.rightMouseUp) {
                view.rightMouseDown(with: down)
                view.rightMouseUp(with: up)
            }
        case ("click", "middle"):
            if let down = middle(.otherMouseDown), let up = middle(.otherMouseUp) {
                view.otherMouseDown(with: down)
                view.otherMouseUp(with: up)
            }
        default: break
        }
    }

    private func rect() {
        guard let window = view.window else { return }
        let screen = view.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
        let r = view.convert(window.convertFromScreen(screen), from: nil)
        selfTestLog("rect \(logNumber(r.minX)) \(logNumber(view.bounds.height - r.maxY)) "
                    + "\(logNumber(r.width)) \(logNumber(r.height))")
    }

    /// A call the text system makes: `mark` sets marked text, `insert` inserts text. False for any other.
    private func client(_ verb: String, _ hex: String) -> Bool {
        let none = NSRange(location: NSNotFound, length: 0)
        switch verb {
        case "mark": view.setMarkedText(fromHex(hex), selectedRange: none, replacementRange: none)
        case "insert": view.insertText(fromHex(hex), replacementRange: none)
        default: return false
        }
        return true
    }

    private func resizeStep() {
        guard let window = view.window else { return }
        steps += 1
        let grid = view.grid, font = view.font
        switch steps {
        case 1: window.setContentSize(font.contentSize(Grid(cols: grid.cols - 3, rows: grid.rows - 2)))
        case 2:
            var size = font.contentSize(grid)
            size.width += CGFloat(font.cell.width) / font.scale / 2
            window.setContentSize(size)
        case 3: rescale(1)
        case 4: rescale(2)
        default: return
        }
        readBack = false
        onMain(after: 0.5) {
            let size = self.view.bounds.size, grid = self.view.grid, cell = self.view.font.cell
            selfTestLog("content \(logNumber(size.width))x\(logNumber(size.height)) grid \(grid.cols)x\(grid.rows) "
                        + "cell \(cell.width)x\(cell.height) scale \(logNumber(self.view.font.scale))")
        }
    }

    /// The gap counts from the request on, so a quiet spell before it is not one.
    private func framesAsked() {
        selfTestLog("frame gap \(Int((max(longestGap, CACurrentMediaTime() - lastFrame) * 1000).rounded()))")
        selfTestLog("frames \(view.frames)")
        (lastFrame, longestGap) = (CACurrentMediaTime(), 0)
    }

    func framed() {
        let now = CACurrentMediaTime()
        (longestGap, lastFrame) = (max(longestGap, now - lastFrame), now)
        drawnFrames += 1
        let mark = drawnFrames
        onMain(after: 0.4) {
            guard mark == self.drawnFrames else { return }
            for (x, y) in self.named {
                if let cell = self.view.describeCell(x, y) { selfTestLog("cell \(x),\(y) \(cell)") }
            }
            selfTestLog("shaped \(self.view.rowsShaped)")
            selfTestLog("cursor \(self.view.describeCursor())")
            let selection = self.view.describeSelection()
            // A new selection reads one frame back again.
            if selection != self.loggedSelection {
                self.loggedSelection = selection
                selfTestLog("selection \(selection)")
                self.readBack = false
            }
            guard !self.readBack, let ink = self.named.first, self.view.hasGlyph(ink.x, ink.y) else { return }
            self.readBack = true
            // An underlined named cell is checked against the first plain one with a glyph.
            let underlined = self.named.first { self.view.isUnderlined($0.x, $0.y) }
            let plain = self.named.first { self.view.hasGlyph($0.x, $0.y) && !self.view.isDecorated($0.x, $0.y) }
            let pair = underlined.flatMap { u in plain.map { (u, $0) } }
            self.view.readBack(ink: ink.x, ink.y, underline: pair) { selfTestLog("readback \($0)") }
        }
    }

    func output(_ bytes: Int) {
        parsed += bytes
        outputs += 1
        let mark = outputs
        onMain(after: 0.4) {
            guard mark == self.outputs else { return }
            selfTestLog("vt \(self.parsed) bytes parsed")
            if let path = SelfTest.screen {
                try? Data(self.view.host.screenText().utf8).write(to: URL(fileURLWithPath: path))
            }
            if !self.probed { self.probe() }
            self.probed = true
        }
    }

    /// The replies to primary device attributes and a cursor position report, the default background under a
    /// dark, a light and the window's own appearance, through the app's apply, then a hold no one ends.
    private func probe() {
        for query in ["\u{1b}[c", "\u{1b}[6n"] {
            selfTestLog("reply \(hex(view.host.probe(Array(query.utf8))))")
        }
        for (name, dark) in [("dark", true), ("light", false)] {
            appearance(dark)
            selfTestLog("background \(name) \(view.host.defaultBackground())")
        }
        appearance(nil)
        selfTestLog("background system \(view.host.defaultBackground())")
        selfTestLog("probe hold")
        _ = view.host.probe(Array("\u{1b}[?2026h".utf8))
    }

    private func watchHold() {
        guard !watchingHold else { return }
        watchingHold = true
        func poll() {
            guard view.host.isHolding else {
                watchingHold = false
                return selfTestLog("hold released")
            }
            onMain(after: 0.1) { poll() }
        }
        poll()
    }
}

private func fromHex(_ hex: String) -> String {
    let digits = Array(hex.utf8)
    let bytes = stride(from: 0, to: digits.count - 1, by: 2).compactMap {
        UInt8(String(decoding: digits[$0...$0 + 1], as: UTF8.self), radix: 16)
    }
    return String(decoding: bytes, as: UTF8.self)
}
#endif
