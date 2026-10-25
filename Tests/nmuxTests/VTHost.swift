import Testing
@testable import Terminal

// The client's last output, which a client that fails leaves on screen.
struct VTHostTests {
    @Test("a short read is appended and the tail trimmed to its limit") func aShortReadIsAppendedAndTheTailTrimmed() {
        var tail: [UInt8] = [1, 2, 3]
        keepTail(&tail, [4, 5][...], limit: 4)
        #expect(tail == [2, 3, 4, 5])
    }

    @Test("a read that fills the limit alone is the tail") func aReadThatFillsTheLimitAloneIsTheTail() {
        var tail: [UInt8] = [1, 2]
        keepTail(&tail, [3, 4, 5, 6, 7][...], limit: 4)
        #expect(tail == [4, 5, 6, 7])
    }
}
