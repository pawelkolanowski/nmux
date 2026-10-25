import Foundation
import Testing
@testable import Lock

private func refuses(_ text: String, saying words: String) -> Bool {
    do { _ = try Lock(text); return false } catch { return "\(error)".contains(words) }
}

// sha256 is the sum of "abc".
private let lockText = """
    # a comment, then a blank line

    commit = abc
    date = 2026-10-23
    url = https://example.com/vt.zip
    sha256 = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    size = 3
    signature = vendor/vt.zip.minisig
    minisign-key = RWQabc==
    """
struct LockTests {
    let lock: Lock

    init() throws { lock = try Lock(lockText) }

    @Test("the lock gives every key") func theLockGivesEveryKey() {
        #expect(Lock.keys.allSatisfy { lock.values[$0] != nil })
    }

    @Test("a value keeps its own =") func aValueKeepsItsOwn() {
        #expect(lock.values["minisign-key"] == "RWQabc==")
    }

    @Test("the lock refuses a missing key") func theLockRefusesAMissingKey() {
        #expect(refuses(lockText.replacingOccurrences(of: "size = 3", with: ""), saying: "no size"))
    }

    @Test("the lock refuses a line without =") func theLockRefusesALineWithout() {
        #expect(refuses(lockText + "\nsize 3", saying: "size 3"))
    }

    @Test("sha256 of abc") func sha256OfAbc() {
        #expect(Lock.sha256(of: Data("abc".utf8)) == lock.sha256)
    }

    @Test("a zip with the lock's sum passes") func aZipWithTheLocksSumPasses() {
        #expect(lock.mismatch(zip: Data("abc".utf8)) == nil)
    }

    @Test("a zip with another sum fails, with both sums") func aZipWithAnotherSumFailsWithBoth() {
        let reason = lock.mismatch(zip: Data("abd".utf8)) ?? ""
        #expect(reason.contains(lock.sha256))
        #expect(reason.contains(Lock.sha256(of: Data("abd".utf8))))
    }

    @Test("the repository's lock parses") func theRepositorysLockParses() {
        #expect((try? Lock(String(contentsOfFile: repositoryPath("vendor/libghostty-vt.lock"),
                                  encoding: .utf8))) != nil)
    }
}
