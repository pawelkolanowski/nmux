import Foundation
import GhosttyVt

// The kitty images as the GPU draws them, read from libghostty-vt's render state and the terminal's image storage.
// Adapted from Ghostty's `src/renderer/image.zig` (`kittyUpdate`, `prepKittyImage`, the placement sort and the pixel
// conversion) and `src/renderer/generic.zig` (the animation tick) at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// Ghostty's `Image`, 40 bytes, laid out as `Image` in Shaders.metal: the top-left cell, the pixels from its corner, the
/// source rectangle in image pixels and the size it is drawn at.
struct ImageDraw: Equatable {
    var gridPos: SIMD2<Float>
    var cellOffset: SIMD2<Float>
    var sourceOrigin: SIMD2<Float>
    var sourceSize: SIMD2<Float>
    var destSize: SIMD2<Float>
}

/// Ghostty's three image layers, in the order they are drawn.
enum ImageLayer: Int {
    case belowBackground, belowText, aboveText
}

/// One placement of the render state's image list.
struct ImagePlacement: Equatable {
    var image: UInt32
    var layer: ImageLayer
    var z: Int32
    var draw: ImageDraw
}

/// The placements in drawing order: by layer, then z, then image id, then the order the render state listed them.
struct ImageDrawList: Equatable {
    let placements: [ImagePlacement]
    /// Where the layers below the text and above it start.
    let textStart: Int, aboveStart: Int

    init(_ listed: [ImagePlacement] = []) {
        placements = listed.enumerated().sorted {
            ($0.element.layer.rawValue, $0.element.z, $0.element.image, $0.offset)
                < ($1.element.layer.rawValue, $1.element.z, $1.element.image, $1.offset)
        }.map(\.element)
        textStart = placements.firstIndex { $0.layer != .belowBackground } ?? placements.count
        aboveStart = placements.firstIndex { $0.layer == .aboveText } ?? placements.count
    }

    func range(_ layer: ImageLayer) -> Range<Int> {
        switch layer {
        case .belowBackground: 0..<textStart
        case .belowText: textStart..<aboveStart
        case .aboveText: aboveStart..<placements.count
        }
    }
}

/// An image's pixels as RGBA, row by row from the top.
struct ImagePixels {
    var width: Int, height: Int
    var rgba: [UInt8]
}

/// An image as the storage holds it: its generation, its size and its bytes in their stored format.
private struct StoredImage {
    var generation: UInt64
    var width: Int, height: Int
    var format: GhosttyKittyImageFormat
    var bytes: [UInt8]
}

/// The stored pixels as RGBA: RGB takes an opaque alpha, gray is copied to the three channels, RGBA passes as it is.
/// Nil for PNG, which the storage never holds, or a format it does not know.
func rgbaPixels(_ bytes: [UInt8], _ format: GhosttyKittyImageFormat) -> [UInt8]? {
    // Each pixel's R, G, B and A, as offsets into its stored bytes or nil for opaque.
    let (depth, channels): (Int, [Int?])
    switch format {
    case GHOSTTY_KITTY_IMAGE_FORMAT_RGBA: return bytes
    case GHOSTTY_KITTY_IMAGE_FORMAT_RGB: (depth, channels) = (3, [0, 1, 2, nil])
    case GHOSTTY_KITTY_IMAGE_FORMAT_GRAY: (depth, channels) = (1, [0, 0, 0, nil])
    case GHOSTTY_KITTY_IMAGE_FORMAT_GRAY_ALPHA: (depth, channels) = (2, [0, 0, 0, 1])
    default: return nil
    }
    // One buffer filled in place: an image of millions of pixels converts on the main thread.
    return [UInt8](unsafeUninitializedCapacity: bytes.count / depth * 4) { out, count in
        for i in 0..<bytes.count / depth {
            for (c, offset) in channels.enumerated() { out[i * 4 + c] = offset.map { bytes[i * depth + $0] } ?? 255 }
        }
        count = bytes.count / depth * 4
    }
}

/// Seconds from `now` until the frame due at `next`, both in milliseconds, never under 8 ms, as Ghostty paces them.
func animationDelay(now: UInt64, next: UInt64) -> Double {
    Double(next > now ? max(next - now, 8) : 8) / 1000
}

/// The render state's image list and the pixels the renderer still has to upload. The list is read again only when
/// the placements or the storage changed; pixels only for an image whose generation differs from the one handed out.
final class Images {
    private(set) var list = ImageDrawList()
    /// Pixels the renderer uploads, and the images whose textures go, both cleared once it did.
    private(set) var uploads: [UInt32: ImagePixels] = [:]
    private(set) var gone: Set<UInt32> = []
    /// The milliseconds of the last tick and of the next animation frame, while one plays.
    private(set) var animation: (now: UInt64, next: UInt64)?
    /// The generation each image's pixels were handed out at.
    private var generations: [UInt32: UInt64] = [:]
    private var storageGeneration: UInt64 = 0
    private var built: (placements: UInt64, storage: UInt64)?
    private var iterator: GhosttyRenderStateImageIterator?

    init() { ghostty_render_state_image_iterator_new(nil, &iterator) }

    deinit { ghostty_render_state_image_iterator_free(iterator) }

    /// Reads the storage's generation and, while images are drawn, plays their animations one frame on; inside the
    /// host's lock, before `begin_update`, as Ghostty ticks.
    func tick(_ terminal: GhosttyTerminal) {
        guard let graphics = graphics(terminal) else { return }
        ghostty_kitty_graphics_get(graphics, GHOSTTY_KITTY_GRAPHICS_DATA_GENERATION, &storageGeneration)
        animation = nil
        guard !generations.isEmpty else { return }
        let now = DispatchTime.now().uptimeNanoseconds / 1_000_000
        var next: UInt64 = 0
        if ghostty_kitty_graphics_animation_tick(graphics, now, &next) == GHOSTTY_SUCCESS { animation = (now, next) }
    }

    /// Reads the list again when a generation changed, after `end_update`, and copies the pixels it needs with the
    /// host locked once more. True when the list was read.
    func update(_ state: GhosttyRenderState?, _ host: VTHost) -> Bool {
        var placements: UInt64 = 0
        ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_IMAGE_PLACEMENTS_GENERATION, &placements)
        if let built, built == (placements, storageGeneration) { return false }
        built = (placements, storageGeneration)
        ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_IMAGE_ITERATOR, &iterator)
        var listed: [ImagePlacement] = []
        var wanted = Set<UInt32>()
        while ghostty_render_state_image_iterator_next(iterator) {
            func get<T: BitwiseCopyable>(_ key: GhosttyRenderStateImageData, _ value: T) -> T {
                var v = value
                ghostty_render_state_image_get(iterator, key, &v)
                return v
            }
            guard get(GHOSTTY_RENDER_STATE_IMAGE_DATA_PROTOCOL, GhosttyImageProtocol(rawValue: .max))
                    == GHOSTTY_IMAGE_PROTOCOL_KITTY,
                  let layer = ImageLayer(rawValue: Int(get(GHOSTTY_RENDER_STATE_IMAGE_DATA_LAYER,
                                                           GhosttyRenderStateImageLayer(rawValue: .max)).rawValue))
            else { continue }
            func float(_ key: GhosttyRenderStateImageData) -> Float { Float(get(key, UInt32(0))) }
            let id = get(GHOSTTY_RENDER_STATE_IMAGE_DATA_IMAGE_ID, UInt32(0))
            let draw = ImageDraw(
                gridPos: [Float(get(GHOSTTY_RENDER_STATE_IMAGE_DATA_VIEWPORT_COL, Int32(0))),
                          Float(get(GHOSTTY_RENDER_STATE_IMAGE_DATA_VIEWPORT_ROW, Int32(0)))],
                cellOffset: [float(GHOSTTY_RENDER_STATE_IMAGE_DATA_CELL_OFFSET_X),
                             float(GHOSTTY_RENDER_STATE_IMAGE_DATA_CELL_OFFSET_Y)],
                sourceOrigin: [float(GHOSTTY_RENDER_STATE_IMAGE_DATA_SOURCE_X),
                               float(GHOSTTY_RENDER_STATE_IMAGE_DATA_SOURCE_Y)],
                sourceSize: [float(GHOSTTY_RENDER_STATE_IMAGE_DATA_SOURCE_WIDTH),
                             float(GHOSTTY_RENDER_STATE_IMAGE_DATA_SOURCE_HEIGHT)],
                destSize: [float(GHOSTTY_RENDER_STATE_IMAGE_DATA_PIXEL_WIDTH),
                           float(GHOSTTY_RENDER_STATE_IMAGE_DATA_PIXEL_HEIGHT)])
            listed.append(ImagePlacement(image: id, layer: layer, z: get(GHOSTTY_RENDER_STATE_IMAGE_DATA_Z, Int32(0)),
                                         draw: draw))
            if generations[id] != get(GHOSTTY_RENDER_STATE_IMAGE_DATA_IMAGE_GENERATION, UInt64(0)) { wanted.insert(id) }
        }
        list = ImageDrawList(listed)
        // The storage may have moved on since `end_update`; the pixels then come at the generation it holds now.
        let stored: [(id: UInt32, image: StoredImage)] = host.locked { t in
            guard let graphics = graphics(t) else { return [] }
            // An image that left the storage, or waits for its pixels again, gives up its texture.
            for id in generations.keys where !stored(graphics, id) {
                (generations[id], uploads[id]) = (nil, nil)
                gone.insert(id)
            }
            return wanted.compactMap { id in pixels(graphics, id).map { (id, $0) } }
        }
        for (id, image) in stored {
            guard let rgba = rgbaPixels(image.bytes, image.format), rgba.count == image.width * image.height * 4
            else { continue }
            generations[id] = image.generation
            uploads[id] = ImagePixels(width: image.width, height: image.height, rgba: rgba)
            gone.remove(id)
        }
        return true
    }

    /// Called once the renderer took the uploads and dropped what went.
    func uploaded() {
        uploads.removeAll()
        gone.removeAll()
    }

    private func graphics(_ terminal: GhosttyTerminal) -> GhosttyKittyGraphics? {
        var graphics: GhosttyKittyGraphics?
        return ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_KITTY_GRAPHICS, &graphics) == GHOSTTY_SUCCESS
            ? graphics : nil
    }

    /// Whether the storage holds the image with its pixels, none of them pending.
    private func stored(_ graphics: GhosttyKittyGraphics, _ id: UInt32) -> Bool {
        var data: UnsafePointer<UInt8>?
        guard let image = ghostty_kitty_graphics_image(graphics, id) else { return false }
        return ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_DATA_PTR, &data) == GHOSTTY_SUCCESS
            && data != nil
    }

    /// The image as stored; nil when it is gone or its pixels are pending.
    private func pixels(_ graphics: GhosttyKittyGraphics, _ id: UInt32) -> StoredImage? {
        guard let image = ghostty_kitty_graphics_image(graphics, id) else { return nil }
        var data: UnsafePointer<UInt8>?
        var length = 0, width: UInt32 = 0, height: UInt32 = 0, generation: UInt64 = 0
        var format = GHOSTTY_KITTY_IMAGE_FORMAT_PNG
        guard ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_DATA_PTR, &data) == GHOSTTY_SUCCESS,
              let data else { return nil }
        ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_DATA_LEN, &length)
        ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_WIDTH, &width)
        ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_HEIGHT, &height)
        ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_FORMAT, &format)
        ghostty_kitty_graphics_image_get(image, GHOSTTY_KITTY_IMAGE_DATA_GENERATION, &generation)
        return StoredImage(generation: generation, width: Int(width), height: Int(height), format: format,
                           bytes: Array(UnsafeBufferPointer(start: data, count: length)))
    }
}
