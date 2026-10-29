import Foundation
import GhosttyVt
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

// Kitty images as Ghostty takes them: a PNG stored, every medium on, and the storage limit set.
@MainActor struct VTHostImageTests {
    @Test("a PNG is stored, answered OK and placed") func aPngIsStoredAnsweredOkAndPlaced() throws {
        let host = try idleHost()
        defer { host.hangUp() }
        let reply = host.probe(Array("\u{1b}_Ga=T,f=100,i=9;\(redBlue.base64EncodedString())\u{1b}\\".utf8))
        #expect(String(decoding: reply, as: UTF8.self) == "\u{1b}_Gi=9;OK\u{1b}\\")
        #expect(placements(host) == 1)
    }

    @Test("every medium is on, temporary files only from the temp directory")
    func everyMediumIsOnTemporaryFilesOnlyFromTheTempDirectory() throws {
        let host = try idleHost()
        defer { host.hangUp() }
        var file = false, shared = false, temp = GhosttyString()
        host.locked {
            #expect(ghostty_terminal_get($0, GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_MEDIUM_FILE, &file) == GHOSTTY_SUCCESS)
            #expect(ghostty_terminal_get($0, GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_MEDIUM_SHARED_MEM, &shared)
                == GHOSTTY_SUCCESS)
            #expect(ghostty_terminal_get($0, GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_MEDIUM_TEMP_FILE, &temp)
                == GHOSTTY_SUCCESS)
        }
        #expect(file && shared)
        #expect(String(decoding: UnsafeBufferPointer(start: temp.ptr, count: temp.len), as: UTF8.self)
            == tempDirectory())
    }

    @Test("the storage limit starts at 320 MB and reads back each new value")
    func theStorageLimitStartsAt320MbAndReadsBack() throws {
        let host = try idleHost()
        defer { host.hangUp() }
        #expect(limit(host) == 320_000_000)
        host.setImageStorageLimit(1000)
        #expect(limit(host) == 1000)
        host.setImageStorageLimit(0)
        #expect(limit(host) == 0)
    }

    @Test("the temp directory is TMPDIR, else TMP, else /tmp, without its trailing /",
          arguments: [(["TMPDIR": "/var/x/", "TMP": "/t"], "/var/x"), (["TMPDIR": "", "TMP": "/t/"], "/t"),
                      ([:], "/tmp")])
    func theTempDirectoryIsTmpdirElseTmp(env: [String: String], expected: String) {
        #expect(tempDirectory(env) == expected)
    }
}

/// A host whose client, `cat`, prints nothing, so only `probe` writes to its terminal; a test hangs it up at its end so
/// the reader reaps it.
@MainActor private func idleHost() throws -> VTHost {
    let handlers = VTHost.Handlers(output: { _ in }, exit: { _, _ in }, clipboardWrite: { _ in }, clipboardRead: {},
                                   bell: {})
    let host = try VTHost(argv: ["/bin/cat"], grid: Grid(cols: 80, rows: 24),
                          cell: Font(sfMono(13), points: 13, scale: 2).cell, handlers: handlers)
    host.start()
    return host
}

private func limit(_ host: VTHost) -> UInt64 {
    var bytes: UInt64 = 1
    host.locked {
        #expect(ghostty_terminal_get($0, GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_STORAGE_LIMIT, &bytes) == GHOSTTY_SUCCESS)
    }
    return bytes
}

/// The placements the render state lists after one update.
private func placements(_ host: VTHost) -> Int {
    var state: GhosttyRenderState?, images: GhosttyRenderStateImageIterator?
    #expect(ghostty_render_state_new(nil, &state) == GHOSTTY_SUCCESS)
    #expect(ghostty_render_state_image_iterator_new(nil, &images) == GHOSTTY_SUCCESS)
    defer {
        ghostty_render_state_image_iterator_free(images)
        ghostty_render_state_free(state)
    }
    #expect(host.locked { ghostty_render_state_update(state, $0) } == GHOSTTY_SUCCESS)
    #expect(ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_IMAGE_ITERATOR, &images) == GHOSTTY_SUCCESS)
    var count = 0
    while ghostty_render_state_image_iterator_next(images) { count += 1 }
    return count
}
