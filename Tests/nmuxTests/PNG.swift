import Foundation
import GhosttyVt
import Testing
@testable import Terminal

// The PNG decoder libghostty-vt calls: the file's exact pixels as straight RGBA, or false.
struct PNGTests {
    @Test("red then blue, 2 x 1, decodes to their 8 bytes") func redThenBlueDecodesToTheir8Bytes() {
        #expect(decoded(redBlue) == Decoded(width: 2, height: 1, pixels: [0xff, 0, 0, 0xff, 0, 0, 0xff, 0xff]))
    }

    @Test("a half-transparent and a faint pixel keep their straight alpha")
    func aHalfTransparentPixelKeepsItsStraightAlpha() {
        #expect(decoded(halfRed)?.pixels == [0xff, 0, 0, 0x80])
        #expect(decoded(faint)?.pixels == [0x40, 0x80, 0xc0, 0x10])
    }

    @Test("bytes that are no PNG and a PNG cut short are refused") func randomBytesAndATruncatedPngAreRefused() {
        #expect(decoded(Data((0..<70).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) })) == nil)
        // Into the pixels, and only into the IEND chunk's CRC, which ImageIO alone would take.
        #expect(decoded(redBlue.prefix(redBlue.count - 20)) == nil)
        #expect(decoded(redBlue.prefix(redBlue.count - 4)) == nil)
    }
}

/// One red pixel at alpha 0x80, RGBA.
private let halfRed = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DQAAAEgQGALFXOsAAAAABJRU5ErkJggg==")!
/// `40 80 c0` at alpha 0x10, which a round trip through premultiplied alpha would not give back.
private let faint = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNwaDggAAAEFQGRgRhtmAAAAABJRU5ErkJggg==")!

private struct Decoded: Equatable {
    let width: UInt32, height: UInt32, pixels: [UInt8]
}

private func decoded(_ png: Data) -> Decoded? {
    var out = GhosttySysImage()
    let ok = [UInt8](png).withUnsafeBufferPointer { decodePNG($0, allocator: nil, into: &out) }
    guard ok, let data = out.data else { return nil }
    defer { ghostty_free(nil, data, out.data_len) }
    #expect(out.data_len == Int(out.width * out.height * 4))
    return Decoded(width: out.width, height: out.height, pixels: Array(UnsafeBufferPointer(start: data,
                                                                                           count: out.data_len)))
}
