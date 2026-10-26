import Metal
import QuartzCore
import simd

// nmux's renderer on the Metal 4 command model: one MTL4CommandQueue, one reused command buffer, three allocators
// gated by a shared event, one argument table, one residency set. The frame and its uniforms are adapted from
// Ghostty's `src/renderer/generic.zig` (`drawFrame`) and `src/renderer/metal/shaders.zig` (`Uniforms`) at commit
// 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// Ghostty's `Uniforms`, laid out as `Uniforms` in Shaders.metal. The padding, the minimum contrast and the three
/// colour switches are never read yet; they keep Ghostty's layout, so its shaders port
/// without a change to the buffer.
struct Uniforms {
    var projection: simd_float4x4
    var screenSize: SIMD2<Float>
    var cellSize: SIMD2<Float>
    var gridSize: SIMD2<UInt16>
    var gridPadding = SIMD4<Float>.zero
    var paddingExtend: UInt8 = 0
    var minContrast: Float = 1
    var cursorPos: SIMD2<UInt16>
    var cursorColor: SIMD4<UInt8>
    var bgColor: SIMD4<UInt8>
    var cursorWide = false
    var useDisplayP3 = false
    var useLinearBlending = false
    var useLinearCorrection = false
}

#if NMUX_SELFTEST
/// The pixels of one drawn frame, BGRA, the first row the top.
struct Readback {
    let pixels: [UInt8]
    let width: Int, height: Int

    func bgra(_ x: Int, _ y: Int) -> SIMD4<UInt8>? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = (y * width + x) * 4
        return [pixels[i + 2], pixels[i + 1], pixels[i], pixels[i + 3]]
    }
}
#endif

public enum RendererError: Error, CustomStringConvertible {
    case noMetal4, setup(String)

    public var description: String {
        switch self {
        case .noMetal4: "no GPU with Metal 4"
        case .setup(let what): "Metal 4 cannot create \(what)"
        }
    }
}

@MainActor
final class MetalRenderer {
    static let framesInFlight = 3
    let layer = CAMetalLayer()
    /// Frames committed so far; frame n signals the event to n once it completes.
    private(set) var frames: UInt64 = 0
#if NMUX_SELFTEST
    /// Set for one frame: its pixels come back once it completed.
    var readback: ((Readback) -> Void)?
    /// A frame presented with the window's transaction that did not complete within 1000 ms.
    var onLate: () -> Void = {}
    private lazy var readbackAllocator = device.makeCommandAllocator()
#endif
    /// `background-opacity`; below 1 the layer is not opaque, so the window behind shows through.
    var opacity = 1.0 { didSet { layer.isOpaque = opacity >= 1 } }
    private let device: MTLDevice
    private let queue: MTL4CommandQueue
    private let commandBuffer: MTL4CommandBuffer
    private let allocators: [MTL4CommandAllocator]
    private let event: MTLSharedEvent
    private let table: MTL4ArgumentTable
    private let residency: MTLResidencySet
    private let bgPipeline, cellBgPipeline, textPipeline: MTLRenderPipelineState
    private var slots: [Slot] = []
    /// The alpha atlas and the colour one.
    private var atlasTexture: MTLTexture?
    private var colorAtlasTexture: MTLTexture?
    /// Textures and buffers replaced by larger ones, each kept until the last frame that read it completed.
    private var retired: [(resource: MTLAllocation, lastFrame: UInt64)] = []

    /// A frame in flight's own buffers, rewritten only once that frame completed.
    private struct Slot {
        var uniforms: MTLBuffer
        var bg: MTLBuffer
        var text: MTLBuffer
    }

    init(_ context: RenderContext) throws(RendererError) {
        let device = context.device
        (self.device, queue) = (device, context.queue)
        (bgPipeline, cellBgPipeline, textPipeline) = (context.bgPipeline, context.cellBgPipeline, context.textPipeline)
        guard let commandBuffer = device.makeCommandBuffer(), let event = device.makeSharedEvent() else {
            throw .setup("a command buffer")
        }
        (self.commandBuffer, self.event) = (commandBuffer, event)
        var allocators: [MTL4CommandAllocator] = []
        for _ in 0..<Self.framesInFlight {
            guard let allocator = device.makeCommandAllocator() else { throw .setup("a command allocator") }
            allocators.append(allocator)
        }
        self.allocators = allocators
        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 3
        tableDescriptor.maxTextureBindCount = 2
        do {
            table = try device.makeArgumentTable(descriptor: tableDescriptor)
            residency = try device.makeResidencySet(descriptor: MTLResidencySetDescriptor())
        } catch {
            throw .setup("an argument table or a residency set")
        }

        for _ in 0..<Self.framesInFlight {
            slots.append(Slot(uniforms: try buffer(MemoryLayout<Uniforms>.stride), bg: try buffer(4),
                              text: try buffer(32)))
        }
        residency.commit()

        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        // The shaders pass colours as they are, so the layer takes them as sRGB.
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.isOpaque = true
    }

    /// A shared buffer in the residency set; the caller commits the set.
    private func buffer(_ length: Int) throws(RendererError) -> MTLBuffer {
        guard let b = device.makeBuffer(length: length, options: [.storageModeShared, .cpuCacheModeWriteCombined])
        else {
            throw .setup("a \(length)-byte buffer")
        }
        residency.addAllocation(b)
        return b
    }

    /// Draws `cells` into the drawable `next` hands out. False when no frame could be encoded, so the caller draws
    /// the cells again.
    func draw(_ cells: Cells, next: () -> CAMetalDrawable?) -> Bool {
        // Frame n reuses the allocator and buffers of frame n - 3, so it waits for that one. Its cells are taken from
        // the terminal already, so it never drops them; a GPU that completes nothing in 10 s is gone, and nmux ends
        // with that rather than hang.
        let inFlight = UInt64(Self.framesInFlight)
        if frames >= inFlight, !event.wait(untilSignaledValue: frames - inFlight + 1, timeoutMS: 10_000) {
            fatalError("the GPU completed no frame in 10 s")
        }
        release()
        let i = Int(frames % inFlight)
        syncAtlas(cells)
        let count = cells.textCount
        grow(&slots[i].bg, cells.bg.count * 4)
        grow(&slots[i].text, count * MemoryLayout<CellText>.stride)
        residency.commit()
        let slot = slots[i]
        cells.bg.withUnsafeBytes {
            if let b = $0.baseAddress { slot.bg.contents().copyMemory(from: b, byteCount: $0.count) }
        }
        cells.writeText(slot.text.contents().bindMemory(to: CellText.self, capacity: max(count, 1)))
        let size = layer.drawableSize
        let cell = cells.font.cell
        // The default background at `background-opacity`; a cell with its own background stays opaque.
        var background = cells.background
        background.w = UInt8((opacity * 255).rounded())
        // Text under a block cursor takes the theme's cursor-text, else the background's colour; no other cursor covers
        // its text.
        let block = cells.cursorShape == .block ? cells.cursorCell.map { SIMD2(UInt16($0.x), UInt16($0.y)) } : nil
        var uniforms = Uniforms(projection: ortho(width: Float(size.width), height: Float(size.height)),
                                screenSize: [Float(size.width), Float(size.height)],
                                cellSize: [Float(cell.width), Float(cell.height)],
                                gridSize: [UInt16(cells.cols), UInt16(cells.rows)],
                                cursorPos: block ?? SIMD2(repeating: .max),
                                cursorColor: cells.cursorText ?? cells.background,
                                bgColor: background, cursorWide: block != nil && cells.cursorWide)
        slot.uniforms.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.size)

        guard let drawable = next() else { return false }
        let allocator = allocators[i]
        allocator.reset()
        commandBuffer.beginCommandBuffer(allocator: allocator)
        // The queue is every view's, so each frame names its own residency.
        commandBuffer.useResidencySets([residency, layer.residencySet])
        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            commandBuffer.endCommandBuffer()
            return false
        }
        table.setAddress(slot.text.gpuAddress, index: 0)
        table.setAddress(slot.uniforms.gpuAddress, index: 1)
        table.setAddress(slot.bg.gpuAddress, index: 2)
        table.setTexture(atlasTexture!.gpuResourceID, index: 0)
        table.setTexture(colorAtlasTexture!.gpuResourceID, index: 1)
        enc.setArgumentTable(table, stages: [.vertex, .fragment])
        enc.setRenderPipelineState(bgPipeline)
        enc.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        if cells.cols > 0 && cells.rows > 0 {
            enc.setRenderPipelineState(cellBgPipeline)
            enc.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        }
        if count > 0 {
            enc.setRenderPipelineState(textPipeline)
            enc.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }
        enc.endEncoding()
        commandBuffer.endCommandBuffer()

        queue.waitForDrawable(drawable)
        queue.commit([commandBuffer])
        frames += 1
        queue.signalEvent(event, value: frames)
#if NMUX_SELFTEST
        if let readback {
            self.readback = nil
            if let pixels = read(drawable.texture) { readback(pixels) }
        }
#endif
        queue.signalDrawable(drawable)
        // Metal 4 has no `waitUntilScheduled`: a frame presented with the transaction waits until it completed, so
        // the window never shows the new size around the old frame.
        if layer.presentsWithTransaction, !event.wait(untilSignaledValue: frames, timeoutMS: 1000) {
#if NMUX_SELFTEST
            onLate()
#endif
        }
        drawable.present()
        return true
    }

    /// Replaces the atlas textures by the next frame's: a new scale starts empty atlases. The old textures live until
    /// the frames that read them completed.
    func dropAtlas() {
        retire(atlasTexture)
        retire(colorAtlasTexture)
        (atlasTexture, colorAtlasTexture) = (nil, nil)
    }

    private func retire(_ texture: MTLTexture?) {
        if let texture { retired.append((texture, frames)) }
    }

#if NMUX_SELFTEST
    /// The drawn frame, once it completed, copied into a shared texture by a second commit. The CPU waits on both,
    /// which only the self-test's one readback can afford.
    private func read(_ texture: MTLTexture) -> Readback? {
        guard event.wait(untilSignaledValue: frames, timeoutMS: 1000), let readbackAllocator else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat,
                                                                  width: texture.width, height: texture.height,
                                                                  mipmapped: false)
        descriptor.storageMode = .shared
        guard let copy = device.makeTexture(descriptor: descriptor) else { return nil }
        residency.addAllocation(copy)
        residency.commit()
        defer {
            residency.removeAllocation(copy)
            residency.commit()
        }
        guard let done = device.makeSharedEvent() else { return nil }
        readbackAllocator.reset()
        commandBuffer.beginCommandBuffer(allocator: readbackAllocator)
        commandBuffer.useResidencySets([residency, layer.residencySet])
        guard let blit = commandBuffer.makeComputeCommandEncoder() else {
            commandBuffer.endCommandBuffer()
            return nil
        }
        blit.copy(sourceTexture: texture, destinationTexture: copy)
        blit.endEncoding()
        commandBuffer.endCommandBuffer()
        queue.commit([commandBuffer])
        queue.signalEvent(done, value: 1)
        guard done.wait(untilSignaledValue: 1, timeoutMS: 1000) else { return nil }
        var pixels = [UInt8](repeating: 0, count: copy.width * copy.height * 4)
        copy.getBytes(&pixels, bytesPerRow: copy.width * 4, from: MTLRegionMake2D(0, 0, copy.width, copy.height),
                      mipmapLevel: 0)
        return Readback(pixels: pixels, width: copy.width, height: copy.height)
    }
#endif

    /// Uploads what each atlas gained since the last frame, the colour one as `bgra8Unorm_srgb` as Ghostty's. A grown
    /// atlas gets a new texture, and the old one lives until the frames that read it completed. Frames in flight read
    /// only places already filled, so the partial upload never races them.
    private func syncAtlas(_ cells: Cells) {
        sync(cells.atlas, &atlasTexture, .r8Unorm)
        sync(cells.colorAtlas, &colorAtlasTexture, .bgra8Unorm_srgb)
        cells.atlasUploaded()
    }

    private func sync(_ atlas: Atlas, _ current: inout MTLTexture?, _ format: MTLPixelFormat) {
        if current == nil || atlas.grew {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: atlas.size,
                                                                      height: atlas.size, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = .shaderRead
            guard let texture = device.makeTexture(descriptor: descriptor)
            else { fatalError("no memory for a \(atlas.size)² atlas") }
            residency.addAllocation(texture)
            retire(current)
            current = texture
            upload(atlas, texture, (0, 0, atlas.size, atlas.size))
        } else if let region = atlas.dirty {
            upload(atlas, current!, region)
        }
    }

    private func upload(_ atlas: Atlas, _ texture: MTLTexture, _ r: (x: Int, y: Int, maxX: Int, maxY: Int)) {
        let line = atlas.size * atlas.depth
        atlas.pixels.withUnsafeBytes { pixels in
            texture.replace(region: MTLRegionMake2D(r.x, r.y, r.maxX - r.x, r.maxY - r.y), mipmapLevel: 0,
                            withBytes: pixels.baseAddress! + r.y * line + r.x * atlas.depth, bytesPerRow: line)
        }
    }

    /// Drops what was retired once the frames that read it completed.
    private func release() {
        let done = event.signaledValue
        retired.removeAll { r in
            guard r.lastFrame <= done else { return false }
            residency.removeAllocation(r.resource)
            return true
        }
    }

    /// A slot's buffer at twice what is needed when it is too small. Its frame completed, so the old one may go at
    /// once; the new one joins the residency set before the frame's commit.
    private func grow(_ slotBuffer: inout MTLBuffer, _ length: Int) {
        guard slotBuffer.length < length else { return }
        // Going on with the old buffer would write past its end.
        guard let next = try? buffer(length * 2) else { fatalError("no memory for a \(length * 2)-byte buffer") }
        residency.removeAllocation(slotBuffer)
        slotBuffer = next
    }
}

/// Maps pixels, origin at the top left, to clip space.
private func ortho(width: Float, height: Float) -> simd_float4x4 {
    simd_float4x4(columns: ([2 / width, 0, 0, 0], [0, -2 / height, 0, 0], [0, 0, 1, 0], [-1, 1, 0, 1]))
}
