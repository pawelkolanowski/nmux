import Foundation
import Testing
@testable import nmux
@testable import Terminal

// The control-mode reader, with commands named by a string, its events written out as text.
private func controlRead(_ chunks: [String], expecting: [String] = []) -> [String] {
    var reader = ControlReader<String>()
    for command in expecting { reader.expect(command) }
    return chunks.flatMap { chunk in
        reader.feed(Array(chunk.utf8)).map { event in
            switch event {
            case .notification(let line): "note \(line)"
            case let .answer(command, ok, lines): "\(command) \(ok ? "ok" : "error") \(lines.joined(separator: "|"))"
            }
        }
    }
}
private let attachBlock = "%begin 1 1 0\n%end 1 1 0\n"

struct ControlReaderTests {
    @Test("a line outside a block is a notification") func aLineOutsideABlockIsANotification() {
        #expect(controlRead(["%sessions-changed\n"]) == ["note %sessions-changed"])
    }

    @Test("the attach's first block answers nothing") func theAttachsFirstBlockAnswersNothing() {
        #expect(controlRead([attachBlock + "%session-renamed $1 b\n"], expecting: ["ls"])
            == ["note %session-renamed $1 b"])
    }

    @Test("a block answers the command waiting") func aBlockAnswersTheCommandWaiting() {
        #expect(controlRead([attachBlock + "%begin 2 2 1\n$0 a\n$1 b c\n%end 2 2 1\n"], expecting: ["ls"])
            == ["ls ok $0 a|$1 b c"])
    }

    @Test("an %error block answers as a failure") func anErrorBlockAnswersAsAFailure() {
        #expect(controlRead([attachBlock + "%begin 2 2 1\nno such session\n%error 2 2 1\n"], expecting: ["has"])
            == ["has error no such session"])
    }

    @Test("two commands are answered in the order sent") func twoCommandsAreAnsweredInTheOrderSent() {
        #expect(controlRead(
            [attachBlock + "%begin 2 2 1\none\n%end 2 2 1\n%sessions-changed\n%begin 3 3 1\ntwo\n%end 3 3 1\n"],
            expecting: ["first", "second"]) == ["first ok one", "note %sessions-changed", "second ok two"])
    }

    @Test("a block split over two reads waits for its end") func aBlockSplitOverTwoReadsWaitsFor() {
        #expect(controlRead([attachBlock + "%begin 2 2 1\n$0 a", "pi\n%end 2", " 2 1\n"], expecting: ["ls"])
            == ["ls ok $0 api"])
    }

    @Test("an %end line with another tag stays in the block") func anEndLineWithAnotherTagStaysIn() {
        #expect(controlRead([attachBlock + "%begin 2 2 1\n%end 9 9 0\n%end 2 2 1\n"], expecting: ["x"])
            == ["x ok %end 9 9 0"])
    }
}
