import Foundation
import Terminal

/// What the mirror asks of the app: a listed Session's terminal, a Session shown, the bar drawn again, a pill's prompt
/// dropped, a failure's card and the quit.
protocol SessionMirrorDelegate: AnyObject {
    /// Nil when the terminal cannot start; the mirror then stops until the card's Restart.
    func makeSession(_ info: SessionInfo) -> Session?
    func show(_ id: SessionID)
    func updateBar()
    /// A pill that asks drops its prompt, as Escape would.
    func cancelAsking()
    func attachFailed(_ failure: AttachFailure)
    func quit()
}

/// Keeps nmux's Sessions in step with the server through the one control client: every Session the server lists is
/// shown and attached, each once, in the order tmux created it, and a change made anywhere reaches the bar at once.
final class SessionMirror {
    weak var delegate: SessionMirrorDelegate?
    /// The tmux nmux found, and the one control client.
    private(set) var tmux: Tmux?
    private(set) var control: Control?
    /// The Sessions in `$ID` order and the shown one.
    var sessions: [Session] = []
    private(set) var active: SessionID?
    /// The Session shown once it is listed, which `create` made or a follow moved to.
    /// limitation: one Session waits at a time, so a follow and a `create` in flight together keep the later one; queue
    /// them once that loses a switch.
    private var pendingActive: SessionID?
    /// Sessions nmux is killing, skipped until tmux no longer lists them, so a list sent before the kill never brings
    /// them back.
    private var killed: Set<SessionID> = []

    func session(_ id: SessionID) -> Session? { sessions.first { $0.info.id == id } }
    /// The app shows the Session; a list passes the focus from it from then on.
    func activate(_ id: SessionID) { active = id }
    var activeSession: Session? { active.flatMap(session) }
    /// The Session whose pill asks whether to kill it; one at a time.
    var asking: Session? { sessions.first { $0.asking } }

    /// The control client on the Session nmux found or made; its first list makes every Session's terminal.
    func start(_ tmux: Tmux, session id: SessionID) {
        self.tmux = tmux
        if control == nil {
            let control = Control(tmux)
            control.onNotification = { line in
                if line == "%sessions-changed" || line.hasPrefix("%session-renamed ") { self.relist() }
                if let (client, target) = clientSessionChanged(line) { self.moved(client, to: target) }
            }
            control.onEnd = { self.controlEnded() }
            self.control = control
        }
        startControl(on: id, logging: "started")
    }

    /// The control client goes with nmux, or a server keeps it attached and never finishes a later
    /// `kill-server`.
    func stop() { control?.stop() }

    /// Starts the control client on the Session, logs `control <event>` and lists the Sessions; nmux quits when the
    /// client cannot start.
    private func startControl(on id: SessionID, logging event: String) {
        do { try control?.start(on: id) } catch { return delegate?.quit() ?? () }
        selfTestLog("control \(event)")
        relist()
    }

    /// tmux ends the control client alone too, as `detach-client -a` does. While the server still lists a Session the
    /// client attaches again; one that ended within a second of its start quits nmux instead, so a hook that keeps
    /// detaching it never makes nmux spin. The list waits on tmux, off the main thread.
    private func controlEnded() {
        selfTestLog("control ended")
        guard let tmux, let control, Date().timeIntervalSince(control.started) >= 1
        else { return delegate?.quit() ?? () }
        DispatchQueue.global().async {
            let id = lowestSession(tmux.run(["list-sessions", "-F", "#{session_id}"]).out)
            onMain { if let id { self.startControl(on: id, logging: "restarted") } else { self.delegate?.quit() } }
        }
    }

    /// The Sessions in `$ID` order, asked over the control client, so the answer keeps its place among tmux's events;
    /// nmux's Sessions follow them, and `then` gets them. An empty list quits nmux.
    func relist(then: @escaping ([SessionInfo]) -> Void = { _ in }) {
        control?.send("list-sessions -F '\(sessionFormat)'") { ok, lines in
            guard ok else { return }
            var infos = parseSessions(lines)
            selfTestLog("sessions " + infos.map { "\($0.id):\($0.name)" }.joined(separator: " "))
            self.killed.formIntersection(infos.map(\.id))
            infos.removeAll { self.killed.contains($0.id) }
            if infos.isEmpty { return self.delegate?.quit() ?? () }
            self.mirror(infos)
            then(infos)
        }
    }

    /// A new list: a removed Session goes, a rename changes its name in place, a new Session comes last. The shown
    /// Session is the one `create` waits for once it is listed, else the same one while it lives, else the one now at
    /// its place or the last; at launch the lowest `$ID`.
    private func mirror(_ infos: [SessionInfo]) {
        let old = sessions.map(\.info.id)
        let changes = sessionChanges(from: sessions.map(\.info), to: infos)
        // A prompt never answers for a Session that changed: one killed or renamed elsewhere drops it.
        if let asking, changes.removed.contains(asking.info.id)
            || changes.renamed.contains(where: { $0.id == asking.info.id }) {
            delegate?.cancelAsking()
        }
        for id in changes.removed { session(id)?.view.removeFromSuperview() }
        sessions.removeAll { changes.removed.contains($0.info.id) }
        for info in changes.renamed { session(info.id)?.info = info }
        for info in changes.added {
            guard let made = delegate?.makeSession(info) else {
                // The mirror stops until the card's Restart, or every later list would build the failing Session again.
                stop()
                break
            }
            sessions.append(made)
        }
        var next = sessions.first?.info.id
        // The list after `create`'s answer always names its Session, unless it died meanwhile; either way the wait
        // ends.
        if let pendingActive, session(pendingActive) != nil {
            next = pendingActive
        } else if let active, let i = activeIndex(old: old, new: sessions.map(\.info.id), active: active) {
            next = sessions[i].info.id
        }
        pendingActive = nil
        if changes != SessionChanges() || next != active, let next { delegate?.show(next) }
        endClients()
    }

    /// Each listed Session whose client exited, and that neither waits nor is being killed, attaches again or waits on
    /// tmux's error. Every list checks, so an exit whose own list got no answer, as while the control client restarts,
    /// is never lost.
    /// limitation: a client's run is counted to the list that finds it exited, not to its exit, so one that failed
    /// within a second while the control client restarted attaches again once before it waits.
    private func endClients() {
        for session in sessions {
            let end = clientEnd(exited: !session.view.host.running, waiting: session.waiting, killing: session.killing,
                                ranFor: Date().timeIntervalSince(session.started))
            if end == .none { continue }
            selfTestLog("ended \(session.info.id) \(end)")
            if end == .attach { attachAgain(session) } else { session.waiting = true }
        }
    }

    /// A confirmed kill, in order: the Session is marked, so it never attaches again and no follow moves it; it leaves
    /// the list, unless it is the last, so the empty list after the kill quits nmux; its terminal and its client go,
    /// the detach ahead of the kill over the same pipe, so tmux never moves the client to another Session; then
    /// `kill-session`. The mirror confirms the removal once tmux lists the Session gone, and a refused `kill-session`,
    /// the Session already gone, needs nothing more. The shown Session passes as for any removed one.
    func kill(_ session: Session) {
        let id = session.info.id, old = sessions.map(\.info.id)
        session.killing = true
        if sessions.count > 1 {
            sessions.removeAll { $0 === session }
            killed.insert(id)
        }
        session.view.removeFromSuperview()
        control?.send("detach-client -t \(session.tty)")
        session.view.host.hangUp()
        control?.send("kill-session -t '\(id)'")
        if active == id, let i = activeIndex(old: old, new: sessions.map(\.info.id), active: id),
           sessions[i] !== session {
            delegate?.show(sessions[i].info.id)
        } else {
            delegate?.updateBar()
        }
    }

    /// Every Session it mirrors, killed in their order; `done` runs after the last answer, or as the control client
    /// ends with a server that ended first. False when there is none to kill.
    func killAll(then done: @escaping () -> Void) -> Bool {
        let kills = sessions.map(\.info.id)
        guard let control, let last = kills.last else { return false }
        // A Session being killed never follows its client or attaches again, and a list that still names it counts it
        // gone, so a control client restarted on one quits on the empty list.
        for session in sessions { session.killing = true }
        killed.formUnion(kills)
        for id in kills {
            control.send("kill-session -t '\(id)'") { _, _ in if id == last { done() } }
        }
        return true
    }

    /// tmux moved a client to another Session, as prefix+s or `switch-client` do. A Session's own client, known by its
    /// tty, goes back to its Session and the target is shown, once it is listed; a client moved because its own Session
    /// died is left to the list, which removes that Session. Any other client, nmux's control client among them, is
    /// ignored. `has-session` goes over the same pipe, so tmux answers it after its own state changed.
    private func moved(_ client: String, to target: SessionInfo) {
        guard let moved = sessions.first(where: { $0.tty == client }) else { return }
        let own = moved.info
        guard checksMove(own: own.id, target: target.id, killing: moved.killing) else { return }
        control?.send("has-session -t '\(own.id)'") { alive, _ in
            guard alive else {
                // Under `detach-on-destroy off` the client lives on in another Session; it goes with its Session.
                selfTestLog("follow dropped \(own.id)")
                self.control?.send("detach-client -t \(client)")
                return self.relist()
            }
            selfTestLog("follow \(own.name) -> \(target.name)")
            self.control?.send("switch-client -c \(client) -t '\(own.id)'")
            if self.session(target.id) != nil { return self.delegate?.show(target.id) ?? () }
            self.pendingActive = target.id
            self.relist()
        }
    }

    /// Creates a Session by name, numbered by tmux for an empty one, and shows it once it is listed; `answer` gets the
    /// new `$ID` or tmux's refusal.
    func create(_ name: String, then answer: @escaping (Created) -> Void = { _ in }) {
        guard let control else { return answer(.refused("tmux did not create the Session.")) }
        control.send(createCommand(name)) { ok, lines in
            let result = created(ok: ok, lines: lines)
            switch result {
            case .session(let id):
                selfTestLog("created \(id)")
                self.pendingActive = id
                self.relist()
            case .refused(let error): selfTestLog("refused \(error)")
            }
            answer(result)
        }
    }

    /// The Session's client starts again in the same terminal, which keeps its screen and scrollback until tmux
    /// redraws.
    func attachAgain(_ session: Session) {
        (session.waiting, session.started) = (false, Date())
        do {
            try session.view.host.restart()
        } catch {
            // It waits for a key, or every later list would try again and show the card again.
            session.waiting = true
            return delegate?.attachFailed(.client("\(error)")) ?? ()
        }
        selfTestLog("attached \(session.info.id) again")
    }
}
