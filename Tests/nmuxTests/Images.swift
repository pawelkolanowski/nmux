import GhosttyVt
import Testing
@testable import Terminal

// A placement of `image` in `layer` at `z`; its place on the grid tells the placements apart.
private func placed(_ image: UInt32, _ layer: ImageLayer, _ z: Int32, at col: Float = 0) -> ImagePlacement {
    ImagePlacement(image: image, layer: layer, z: z,
                   draw: ImageDraw(gridPos: [col, 0], cellOffset: .zero, sourceOrigin: .zero, sourceSize: [1, 1],
                                   destSize: [1, 1]))
}

struct ImageTests {
    @Test("each stored format becomes RGBA byte for byte, and PNG never does",
          arguments: [(GHOSTTY_KITTY_IMAGE_FORMAT_RGB, [1, 2, 3, 4, 5, 6], [1, 2, 3, 255, 4, 5, 6, 255]),
                      (GHOSTTY_KITTY_IMAGE_FORMAT_GRAY, [7, 8], [7, 7, 7, 255, 8, 8, 8, 255]),
                      (GHOSTTY_KITTY_IMAGE_FORMAT_GRAY_ALPHA, [7, 9, 8, 0], [7, 7, 7, 9, 8, 8, 8, 0]),
                      (GHOSTTY_KITTY_IMAGE_FORMAT_RGBA, [1, 2, 3, 4], [1, 2, 3, 4]),
                      (GHOSTTY_KITTY_IMAGE_FORMAT_PNG, [1, 2, 3, 4], nil)] as
            [(GhosttyKittyImageFormat, [UInt8], [UInt8]?)])
    func eachStoredFormatBecomesRgba(format: GhosttyKittyImageFormat, stored: [UInt8], rgba: [UInt8]?) {
        #expect(rgbaPixels(stored, format) == rgba)
    }

    @Test("the draw list orders by layer, then z, then image id, then the order listed")
    func theDrawListOrdersByLayerThenZThenImageId() {
        let list = ImageDrawList([placed(1, .aboveText, 0), placed(5, .belowText, -1), placed(2, .belowBackground, 0),
                                  placed(3, .belowText, -5), placed(1, .belowText, -1, at: 1),
                                  placed(1, .belowText, -1, at: 2), placed(4, .aboveText, -1)])
        #expect(list.placements == [placed(2, .belowBackground, 0), placed(3, .belowText, -5),
                                    placed(1, .belowText, -1, at: 1), placed(1, .belowText, -1, at: 2),
                                    placed(5, .belowText, -1), placed(4, .aboveText, -1), placed(1, .aboveText, 0)])
        #expect(list.range(.belowBackground) == 0..<1)
        #expect(list.range(.belowText) == 1..<5)
        #expect(list.range(.aboveText) == 5..<7)
    }

    @Test("a layer with no placements is an empty range") func aLayerWithNoPlacementsIsAnEmptyRange() {
        let list = ImageDrawList([placed(1, .aboveText, 0)])
        #expect(list.range(.belowBackground).isEmpty && list.range(.belowText).isEmpty)
        #expect(list.range(.aboveText) == 0..<1)
        #expect(ImageDrawList().range(.aboveText).isEmpty)
    }

    @Test("the next animation frame is waited for, never under 8 ms",
          arguments: [(1000, 1040, 0.04), (1000, 1003, 0.008), (1000, 900, 0.008), (1000, 1000, 0.008)] as
            [(UInt64, UInt64, Double)])
    func theNextAnimationFrameIsWaitedFor(now: UInt64, next: UInt64, delay: Double) {
        #expect(animationDelay(now: now, next: next) == delay)
    }
}
