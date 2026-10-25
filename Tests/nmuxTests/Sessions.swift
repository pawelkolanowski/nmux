import Foundation
import Testing
@testable import nmux
@testable import Terminal

// The `list-sessions` parser and the diff by `$ID`.
private let s0 = SessionInfo(id: SessionID(number: 0), name: "api")
private let s1 = SessionInfo(id: SessionID(number: 1), name: "web")
private let s2 = SessionInfo(id: SessionID(number: 2), name: "zeta")
private let s0renamed = SessionInfo(id: SessionID(number: 0), name: "aaa-api")

struct SessionsTests {
    @Test("a Session name keeps its spaces") func aSessionNameKeepsItsSpaces() {
        #expect(parseSessions(["$3 my work"]) == [SessionInfo(id: SessionID(number: 3), name: "my work")])
    }

    @Test("$10 comes after $9") func n10ComesAfter9() {
        #expect(parseSessions(["$10 b", "$9 a"]).map(\.id.number) == [9, 10])
    }

    @Test("an empty output lists no Session") func anEmptyOutputListsNoSession() {
        #expect(parseSessions([]).isEmpty)
        #expect(parseSessions([""]).isEmpty)
    }

    @Test("a new Session is added") func aNewSessionIsAdded() {
        #expect(sessionChanges(from: [s0, s1], to: [s0, s1, s2]) == SessionChanges(added: [s2]))
    }

    @Test("a new name is a rename") func aNewNameIsARename() {
        #expect(sessionChanges(from: [s0, s1], to: [s0renamed, s1]) == SessionChanges(renamed: [s0renamed]))
    }

    @Test("a missing Session is removed") func aMissingSessionIsRemoved() {
        #expect(sessionChanges(from: [s0, s1], to: [s1]) == SessionChanges(removed: [s0.id]))
    }

    @Test("two changes at once come in one diff") func twoChangesAtOnceComeInOneDiff() {
        #expect(sessionChanges(from: [s0, s1], to: [s0renamed, s2])
            == SessionChanges(added: [s2], renamed: [s0renamed], removed: [s1.id]))
    }

    @Test("an empty list removes every Session") func anEmptyListRemovesEverySession() {
        #expect(sessionChanges(from: [s0, s1], to: []) == SessionChanges(removed: [s0.id, s1.id]))
    }
}
