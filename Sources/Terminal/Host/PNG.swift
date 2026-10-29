import Accelerate
import GhosttyVt
import ImageIO

/// The PNG decoder libghostty-vt calls for a kitty image sent as `f=100`, installed once per process; every host's
/// init reads it before its terminal starts. Ghostty decodes with wuffs, which is not in the library; nmux reads the
/// file with ImageIO and writes it with vImage. A refusal stops the app: every PNG would get EINVAL without a word.
let pngDecoderInstalled: Bool = {
    let decode: GhosttySysDecodePngFn = { _, allocator, data, len, out in
        guard let data, let out else { return false }
        return decodePNG(UnsafeBufferPointer(start: data, count: len), allocator: allocator, into: out)
    }
    return ghostty_sys_set(GHOSTTY_SYS_OPT_DECODE_PNG, unsafeBitCast(decode, to: UnsafeRawPointer.self))
        == GHOSTTY_SUCCESS
}()

/// The PNG as 8-bit RGBA with straight alpha, top row first and no row padding, in a buffer from `allocator`, as
/// `GhosttySysDecodePngFn` asks. False for anything not a whole PNG, an image no storage can hold (over 4294967295
/// bytes, the largest `image-storage-limit`), or a failed allocation; `out` then holds no buffer.
func decodePNG(_ png: UnsafeBufferPointer<UInt8>, allocator: UnsafePointer<GhosttyAllocator>?,
               into out: UnsafeMutablePointer<GhosttySysImage>) -> Bool {
    // ImageIO decodes a file cut short as long as its pixels arrived, so a whole PNG must end in its IEND chunk.
    guard png.count > iend.count, png.suffix(iend.count).elementsEqual(iend), let base = png.baseAddress,
          let source = CGImageSourceCreateWithData(Data(bytes: base, count: png.count) as CFData, nil),
          CGImageSourceGetType(source) as String? == "public.png",
          CGImageSourceGetStatus(source) == .statusComplete,
          let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return false }
    // limitation: the decoder cannot see the screen's limit, so a small file of up to 4 GB of pixels is decoded before
    // the storage refuses it, as Ghostty's wuffs decodes it; upgrade to a cap the host passes when that spike shows.
    let (width, height) = (image.width, image.height)
    let (len, overflow) = width.multipliedReportingOverflow(by: height * 4)
    guard width > 0, height > 0, !overflow, len <= Int(UInt32.max),
          let pixels = ghostty_alloc(allocator, len) else { return false }
    // An RGB file keeps its own colour space, so its bytes come out unconverted; grey and indexed ones go to sRGB.
    let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
    var buffer = vImage_Buffer(data: pixels, height: vImagePixelCount(height), width: vImagePixelCount(width),
                               rowBytes: width * 4)
    guard var format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32,
                                            colorSpace: space ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)),
          vImageBuffer_InitWithCGImage(&buffer, &format, nil, image, vImage_Flags(kvImageNoAllocate))
            == kvImageNoError
    else {
        ghostty_free(allocator, pixels, len)
        return false
    }
    out.pointee = GhosttySysImage(width: UInt32(width), height: UInt32(height), data: pixels, data_len: len)
    return true
}

private let iend: [UInt8] = [0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]
