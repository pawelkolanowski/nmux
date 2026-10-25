import Metal

/// The GPU state every terminal shares: the device, the queue, the library `make` compiles from Shaders.metal and the
/// three pipelines. Each view keeps its own layer, allocators, residency set and atlases.
@MainActor
public final class RenderContext {
    let device: MTLDevice
    let queue: MTL4CommandQueue
    let bgPipeline, cellBgPipeline, textPipeline: MTLRenderPipelineState

    /// `metallib` is the compiled shader library, which the app finds in its bundle.
    public init(metallib: URL) throws(RendererError) {
        // The offsets Shaders.metal's structs have; Swift lays them out the same way.
        precondition(MemoryLayout<Uniforms>.offset(of: \Uniforms.gridPadding) == 96
                     && MemoryLayout<Uniforms>.offset(of: \Uniforms.bgColor) == 128
                     && MemoryLayout<Uniforms>.size == 136 && MemoryLayout<CellText>.stride == 32)
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else { throw .noMetal4 }
        guard let queue = device.makeMTL4CommandQueue() else { throw .setup("a command queue") }
        (self.device, self.queue) = (device, queue)
        guard let library = try? device.makeLibrary(URL: metallib) else { throw .setup("the library \(metallib.path)") }
        func pipeline(_ vertex: String, _ fragment: String,
                      blend: Bool) throws(RendererError) -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let target = descriptor.colorAttachments[0]!
            target.pixelFormat = .bgra8Unorm
            if blend { // premultiplied alpha, as Ghostty's `src/renderer/metal/Pipeline.zig`
                target.isBlendingEnabled = true
                (target.rgbBlendOperation, target.alphaBlendOperation) = (.add, .add)
                (target.sourceRGBBlendFactor, target.sourceAlphaBlendFactor) = (.one, .one)
                (target.destinationRGBBlendFactor, target.destinationAlphaBlendFactor)
                    = (.oneMinusSourceAlpha, .oneMinusSourceAlpha)
            }
            guard let state = try? device.makeRenderPipelineState(descriptor: descriptor)
            else { throw .setup("the pipeline \(fragment)") }
            return state
        }
        bgPipeline = try pipeline("full_screen_vertex", "bg_color_fragment", blend: false)
        cellBgPipeline = try pipeline("full_screen_vertex", "cell_bg_fragment", blend: true)
        textPipeline = try pipeline("cell_text_vertex", "cell_text_fragment", blend: true)
    }
}
