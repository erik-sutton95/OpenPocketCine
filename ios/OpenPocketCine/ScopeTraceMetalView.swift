import MetalKit
import MetalPerformanceShaders
import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine `ScopeTraceMetal` — GPU rasterizer for WAVE / PARADE. Push model:
/// `isPaused + enableSetNeedsDisplay`; a new bundle calls `setNeedsDisplay`.
enum ScopeTraceMetal {
    enum Mode: Equatable {
        case waveform(WaveformAssist.Mode)
        case parade(ParadeAssist.Mode)
    }

    struct Vertex {
        var position: SIMD2<Float>
        var size: Float
        var color: SIMD4<Float>
    }

    static let isAvailable: Bool = ScopeTraceRenderer.sharedPipeline != nil
    static let trailDecay: Double = 0.35

    /// UIKit-y `clip` → Metal scissor (drawable pixels, origin bottom-left).
    static func scissor(
        clip: CGRect, bounds: CGSize, drawable: CGSize
    ) -> MTLScissorRect? {
        guard bounds.width > 1, bounds.height > 1, drawable.width > 1, drawable.height > 1,
            clip.width > 0, clip.height > 0
        else { return nil }
        let sx = drawable.width / bounds.width
        let sy = drawable.height / bounds.height
        let x = max(0, Int(floor(clip.minX * sx)))
        let maxX = min(Int(drawable.width), Int(ceil(clip.maxX * sx)))
        let metalY = max(0, Int(floor(drawable.height - clip.maxY * sy)))
        let metalMaxY = min(Int(drawable.height), Int(ceil(drawable.height - clip.minY * sy)))
        let width = maxX - x
        let height = metalMaxY - metalY
        guard width > 0, height > 0 else { return nil }
        return MTLScissorRect(x: x, y: metalY, width: width, height: height)
    }

    /// Worst-case vertex count for `points` in `mode` (luma: ghost + core +
    /// hot every 4th sample; rgb / parade RGB: one per channel; YRGB: four).
    static func maxVertexCount(points: Int, mode: Mode) -> Int {
        switch mode {
        case .waveform(.luma): 2 * points + (points + 3) / 4
        case .waveform(.rgb): 3 * points
        case .parade(let paradeMode): paradeMode.laneCount * points
        }
    }

    /// Rasterize one point set straight into a mapped vertex buffer (DESIGN
    /// §2.4 — no intermediate array). WAVE `levelTable` is ``WaveformAxis``
    /// (0 / 50 / 100); PARADE keeps ``ScopeDisplayScale``. Returns the index
    /// one past the last vertex written; writes never pass `out.count` (size
    /// it with ``maxVertexCount(points:mode:)``).
    static func fillVertices(
        _ out: UnsafeMutableBufferPointer<Vertex>, from start: Int,
        points: [ScopePoint], mode: Mode, rect: CGRect, opacity: Double,
        levelTable: [Float]
    ) -> Int {
        guard !points.isEmpty, opacity > 0, levelTable.count >= 256 else { return start }
        var index = start

        func append(_ vertex: Vertex) {
            guard index < out.count else { return }
            out[index] = vertex
            index += 1
        }

        func paradeY(_ byte: UInt8) -> Float {
            WaveformAxis.vertexPositionY(
                ire: Double(levelTable[Int(byte)]), pointSize: 1, rect: rect)
        }

        func waveY(_ byte: UInt8, size: Float) -> Float {
            WaveformAxis.vertexPositionY(
                ire: Double(levelTable[Int(byte)]), pointSize: size, rect: rect)
        }

        switch mode {
        case .waveform(let waveformMode):
            switch waveformMode {
            case .luma:
                let ghost = ScopePalette.lumaGhost.premultiplied(opacity: opacity)
                let core = ScopePalette.luma.premultiplied(opacity: opacity)
                let hot = ScopePalette.lumaHot.premultiplied(opacity: opacity)
                for (offset, point) in points.enumerated() {
                    let x = Float(rect.minX + CGFloat(point.xRatio) * rect.width)
                    append(
                        Vertex(
                            position: SIMD2(x, waveY(point.luma, size: 2)), size: 2, color: ghost))
                    append(
                        Vertex(
                            position: SIMD2(x, waveY(point.luma, size: 1)), size: 1, color: core))
                    if offset % 4 == 0 {
                        append(
                            Vertex(
                                position: SIMD2(x, waveY(point.luma, size: 1)), size: 1, color: hot)
                        )
                    }
                }
            case .rgb:
                let channels: [(SIMD4<Float>, (ScopePoint) -> UInt8)] = [
                    (ScopePalette.overlayRed.premultiplied(opacity: opacity), { $0.red }),
                    (ScopePalette.overlayGreen.premultiplied(opacity: opacity), { $0.green }),
                    (ScopePalette.overlayBlue.premultiplied(opacity: opacity), { $0.blue }),
                ]
                for point in points {
                    let x = Float(rect.minX + CGFloat(point.xRatio) * rect.width)
                    for channel in channels {
                        append(
                            Vertex(
                                position: SIMD2(x, waveY(channel.1(point), size: 1)),
                                size: 1, color: channel.0))
                    }
                }
            }
        case .parade(let paradeMode):
            // YRGB prepends luma. Y rides the same WAVE IRE axis (0 / paper gray / 100).
            let lumaLane: [(SIMD4<Float>, (ScopePoint) -> UInt8)] =
                paradeMode == .yrgb
                ? [(ScopePalette.luma.premultiplied(opacity: opacity), { $0.luma })] : []
            let lanes: [(SIMD4<Float>, (ScopePoint) -> UInt8)] =
                lumaLane + [
                    (ScopePalette.paradeRed.premultiplied(opacity: opacity), { $0.red }),
                    (ScopePalette.paradeGreen.premultiplied(opacity: opacity), { $0.green }),
                    (ScopePalette.paradeBlue.premultiplied(opacity: opacity), { $0.blue }),
                ]
            for (offset, lane) in lanes.enumerated() {
                for point in points {
                    let x = Float(
                        ParadeAssist.laneX(
                            xRatio: point.xRatio, lane: offset, mode: paradeMode, plot: rect))
                    append(
                        Vertex(
                            position: SIMD2(x, paradeY(lane.1(point))),
                            size: 1, color: lane.0))
                }
            }
        }
        return index
    }
}

extension ScopePalette.TraceColor {
    func premultiplied(opacity: Double) -> SIMD4<Float> {
        let scale = Float(alpha * opacity)
        return SIMD4(
            Float(red / 255) * scale, Float(green / 255) * scale,
            Float(blue / 255) * scale, scale)
    }
}

/// SwiftUI face of the WAVE / PARADE rasterizer. WAVE passes `layoutSize` so
/// vertices share the Canvas guide coordinate space.
struct ScopeTraceMetalView: UIViewRepresentable {
    let samples: ScopeSamples
    var trail: ScopeSamples = .empty
    let mode: ScopeTraceMetal.Mode
    var transfer: MonitorTransfer = .rec709
    var revision: UInt64 = 0
    /// OpenZCine folds `waveformParadeBrightnessMultiplier` into vertex colour.
    var opacity: Double = 1
    /// WAVE chrome size. Vertices and the shader `bounds` must share this
    /// space — `view.bounds` during `updateUIView` often lags the Canvas size
    /// and floats a crushed floor above the drawn 0 line.
    var layoutSize: CGSize = .zero

    func makeCoordinator() -> ScopeTraceRenderer { ScopeTraceRenderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.colorPixelFormat = .bgra8Unorm
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.clipsToBounds = true
        view.layer.masksToBounds = true
        push(into: context.coordinator, view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        push(into: context.coordinator, view: uiView)
    }

    private func push(into renderer: ScopeTraceRenderer, view: MTKView) {
        let explicit = layoutSize.width > 1 && layoutSize.height > 1
        renderer.update(
            samples: samples, trail: trail, mode: mode, transfer: transfer,
            revision: revision, opacity: opacity,
            bounds: explicit ? layoutSize : view.bounds.size,
            lockLayout: explicit, view: view)
    }
}

@MainActor
final class ScopeTraceRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?

    private struct BuildInputs: Equatable {
        var revision: UInt64 = 0
        var mode: ScopeTraceMetal.Mode = .waveform(.rgb)
        var transfer: MonitorTransfer = .rec709
        var bounds: CGSize = .zero
        var pointCount = 0
        var opacity: Double = 1
    }

    /// DESIGN §2.4 in-flight vertex ring: the build queue writes vertices
    /// straight into a slot's `contents()`; `draw(in:)` only binds the
    /// published buffer. Depth 3 means a slot is not rewritten until two newer
    /// builds — each with its draw scheduled immediately on publish — landed.
    /// ponytail: no semaphore; builds are ≤25 Hz and draws complete within a
    /// frame. Add completion-handler slot tracking if draw cadence ever
    /// decouples from builds.
    private final class VertexRing: @unchecked Sendable {
        private var buffers: [MTLBuffer] = []
        private var index = 0

        /// Build-queue confined.
        func next(device: MTLDevice, byteCount: Int) -> MTLBuffer? {
            index = buffers.isEmpty ? 0 : (index + 1) % 3
            if index >= buffers.count {
                guard let buffer = Self.make(device: device, byteCount: byteCount) else {
                    return nil
                }
                buffers.append(buffer)
                return buffer
            }
            if buffers[index].length < byteCount {
                guard let buffer = Self.make(device: device, byteCount: byteCount) else {
                    return nil
                }
                buffers[index] = buffer
            }
            return buffers[index]
        }

        private static func make(device: MTLDevice, byteCount: Int) -> MTLBuffer? {
            device.makeBuffer(length: max(byteCount, 64 * 1024), options: .storageModeShared)
        }
    }

    private var inputs = BuildInputs()
    private var samples = ScopeSamples.empty
    private var trail = ScopeSamples.empty
    private var layoutLocked = false
    private var buildGeneration = 0
    private let buildQueue = DispatchQueue(label: "opv.scope-trace-vertices", qos: .userInitiated)
    private let ring = VertexRing()
    /// Latest finished build. Main-thread; `draw(in:)` binds and draws only.
    private var publishedBuffer: MTLBuffer?
    private var publishedVertexCount = 0
    private var publishedBounds = CGSize.zero

    override init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        pipeline = Self.sharedPipeline
        super.init()
    }

    func update(
        samples: ScopeSamples, trail: ScopeSamples, mode: ScopeTraceMetal.Mode,
        transfer: MonitorTransfer, revision: UInt64, opacity: Double = 1,
        bounds: CGSize, lockLayout: Bool = false, view: MTKView
    ) {
        layoutLocked = lockLayout
        let settled = bounds.width > 1 ? bounds : view.bounds.size
        let next = BuildInputs(
            revision: revision, mode: mode, transfer: transfer, bounds: settled,
            pointCount: samples.points.count + trail.points.count, opacity: opacity)
        // Identical bundles (same revision) never rebuild.
        guard next != inputs else { return }
        inputs = next
        self.samples = samples
        self.trail = trail
        scheduleBuild(view: view)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if layoutLocked {
            view.setNeedsDisplay()
            return
        }
        let bounds = view.bounds.size
        if bounds.width > 1 { inputs.bounds = bounds }
        scheduleBuild(view: view)
    }

    private func scheduleBuild(view: MTKView) {
        if !layoutLocked, view.bounds.width > 1 { inputs.bounds = view.bounds.size }
        guard let device else { return }
        buildGeneration += 1
        let generation = buildGeneration
        let inputs = inputs
        let samples = samples
        let trail = trail
        let ring = ring
        buildQueue.async { [weak self, weak view] in
            let built = Self.build(
                inputs, samples: samples, trail: trail, ring: ring, device: device)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.buildGeneration == generation else { return }
                    self.publishedBuffer = built?.buffer
                    self.publishedVertexCount = built?.count ?? 0
                    self.publishedBounds = inputs.bounds
                    view?.setNeedsDisplay()
                }
            }
        }
    }

    nonisolated private static func plotRect(
        mode: ScopeTraceMetal.Mode, bounds: CGSize
    ) -> CGRect {
        switch mode {
        case .waveform, .parade:
            // `bounds` is already the plot size — do not apply title/chrome again.
            CGRect(origin: .zero, size: bounds)
        }
    }

    nonisolated private static func build(
        _ inputs: BuildInputs, samples: ScopeSamples, trail: ScopeSamples,
        ring: VertexRing, device: MTLDevice
    ) -> (buffer: MTLBuffer, count: Int)? {
        let bounds = inputs.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let capacity = ScopeTraceMetal.maxVertexCount(
            points: samples.points.count + trail.points.count, mode: inputs.mode)
        guard capacity > 0,
            let buffer = ring.next(
                device: device,
                byteCount: capacity * MemoryLayout<ScopeTraceMetal.Vertex>.stride)
        else { return nil }
        let rect = plotRect(mode: inputs.mode, bounds: bounds)
        let table: [Float]
        switch inputs.mode {
        case .waveform, .parade:
            table = WaveformAxis.levelTable(for: inputs.transfer)
        }
        let out = UnsafeMutableBufferPointer(
            start: buffer.contents().bindMemory(
                to: ScopeTraceMetal.Vertex.self, capacity: capacity),
            count: capacity)
        var count = ScopeTraceMetal.fillVertices(
            out, from: 0, points: trail.points, mode: inputs.mode, rect: rect,
            opacity: inputs.opacity * ScopeTraceMetal.trailDecay, levelTable: table)
        count = ScopeTraceMetal.fillVertices(
            out, from: count, points: samples.points, mode: inputs.mode, rect: rect,
            opacity: inputs.opacity, levelTable: table)
        return (buffer, count)
    }

    func draw(in view: MTKView) {
        guard let pipeline, let queue,
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let command = queue.makeCommandBuffer()
        else { return }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        if publishedVertexCount > 0, let vertexBuffer = publishedBuffer {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            let layout = publishedBounds.width > 1 ? publishedBounds : view.bounds.size
            var viewSize = SIMD2<Float>(
                Float(view.drawableSize.width), Float(view.drawableSize.height))
            encoder.setVertexBytes(&viewSize, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            var bounds = SIMD2<Float>(
                Float(max(layout.width, 1)), Float(max(layout.height, 1)))
            encoder.setVertexBytes(&bounds, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
            if let scissor = ScopeTraceMetal.scissor(
                clip: scopeTraceClipRect(Self.plotRect(mode: inputs.mode, bounds: layout)),
                bounds: layout,
                drawable: view.drawableSize)
            {
                encoder.setScissorRect(scissor)
            }
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: publishedVertexCount)
        }
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }

    nonisolated static let sharedPipeline: MTLRenderPipelineState? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let source = """
            #include <metal_stdlib>
            using namespace metal;
            struct TraceVertex { float2 position; float size; float4 color; };
            struct VOut { float4 position [[position]]; float size [[point_size]]; float4 color; };
            vertex VOut trace_v(uint vid [[vertex_id]],
                                const device TraceVertex *vertices [[buffer(0)]],
                                constant float2 &viewSize [[buffer(1)]],
                                constant float2 &bounds [[buffer(2)]]) {
                TraceVertex v = vertices[vid];
                float2 center = v.position + v.size * 0.5;
                float2 scale = viewSize / max(bounds, float2(1.0, 1.0));
                VOut o;
                o.position = float4(
                    center.x / bounds.x * 2.0 - 1.0,
                    1.0 - center.y / bounds.y * 2.0, 0.0, 1.0);
                o.size = v.size * min(scale.x, scale.y);
                o.color = v.color;
                return o;
            }
            fragment float4 trace_f(VOut in [[stage_in]]) { return in.color; }
            """
        guard let library = try? device.makeLibrary(source: source, options: nil),
            let vertexFunction = library.makeFunction(name: "trace_v"),
            let fragmentFunction = library.makeFunction(name: "trace_f")
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = .bgra8Unorm
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .one
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }()
}

/// Fixed-size texture ring (FeedFrameBaker pool pattern): rotate `depth`
/// textures keyed by size / format instead of allocating per update. Confine
/// each instance to one queue.
final class ScopeTexturePool: @unchecked Sendable {
    private var textures: [MTLTexture] = []
    private var index = 0
    private let depth: Int

    init(depth: Int) {
        self.depth = max(1, depth)
    }

    func texture(
        device: MTLDevice, width: Int, height: Int, pixelFormat: MTLPixelFormat
    ) -> MTLTexture? {
        if let first = textures.first,
            first.width != width || first.height != height || first.pixelFormat != pixelFormat
        {
            textures.removeAll()
            index = 0
        }
        if textures.count < depth {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            textures.append(texture)
            return texture
        }
        let texture = textures[index]
        index = (index + 1) % depth
        return texture
    }
}

struct VectorscopeMetalView: UIViewRepresentable {
    let points: [ScopePoint]
    var trailPoints: [ScopePoint] = []
    var zoom: VectorscopeAssist.Zoom = .x1
    var brightness: Int = VectorscopeAssist.defaultBrightness
    var revision: UInt64 = 0

    func makeCoordinator() -> VectorscopeMetalRenderer { VectorscopeMetalRenderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.colorPixelFormat = .bgra8Unorm
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.framebufferOnly = false
        push(into: context.coordinator, view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        push(into: context.coordinator, view: uiView)
    }

    private func push(into renderer: VectorscopeMetalRenderer, view: MTKView) {
        renderer.update(
            points: points, trailPoints: trailPoints, zoom: zoom, brightness: brightness,
            revision: revision, view: view)
    }
}

@MainActor
final class VectorscopeMetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?

    private struct BuildInputs: Equatable {
        var revision: UInt64 = 0
        var zoom: VectorscopeAssist.Zoom = .x1
        var brightness: Int = VectorscopeAssist.defaultBrightness
        var pointCount = 0
    }

    private var inputs = BuildInputs()
    private var buildGeneration = 0
    private let buildQueue = DispatchQueue(label: "opv.vectorscope-density", qos: .userInitiated)
    /// 2 roles × 2 generations — a texture the GPU sampled last draw is not
    /// CPU-rewritten on the very next update. Build-queue confined.
    private let densityPool = ScopeTexturePool(depth: 4)
    /// Blur outputs, reused across draws. Main-thread confined; same-queue
    /// command ordering makes GPU-side reuse safe.
    private let blurPool = ScopeTexturePool(depth: 2)
    private var mainTexture: MTLTexture?
    private var trailTexture: MTLTexture?
    private var blurredMain: MTLTexture?
    private var blurredTrail: MTLTexture?

    override init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        pipeline = Self.quadPipeline
        super.init()
    }

    func update(
        points: [ScopePoint], trailPoints: [ScopePoint],
        zoom: VectorscopeAssist.Zoom, brightness: Int, revision: UInt64, view: MTKView
    ) {
        let next = BuildInputs(
            revision: revision, zoom: zoom, brightness: brightness,
            pointCount: points.count + trailPoints.count)
        guard next != inputs else { return }
        inputs = next
        buildGeneration += 1
        let generation = buildGeneration
        guard let device else { return }
        let zoom = next.zoom
        let brightness = next.brightness
        let pool = densityPool
        buildQueue.async { [weak self, weak view] in
            let main = Self.densityTexture(
                device: device, points: points, zoom: zoom, brightness: brightness, pool: pool)
            let trail = Self.densityTexture(
                device: device, points: trailPoints, zoom: zoom, brightness: brightness, pool: pool)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.buildGeneration == generation else { return }
                    self.mainTexture = main
                    self.trailTexture = trail
                    self.blurredMain = nil
                    self.blurredTrail = nil
                    view?.setNeedsDisplay()
                }
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay()
    }

    func draw(in view: MTKView) {
        guard let device, let queue, let pipeline,
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let command = queue.makeCommandBuffer()
        else { return }
        if blurredMain == nil, let mainTexture {
            blurredMain = Self.blurred(
                mainTexture, device: device, command: command, pool: blurPool)
        }
        if blurredTrail == nil, let trailTexture {
            blurredTrail = Self.blurred(
                trailTexture, device: device, command: command, pool: blurPool)
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipeline)
        let bounds = view.bounds.size
        let rect = vectorscopePlotSquare(in: bounds)
        var quad = SIMD4<Float>(
            Float(rect.minX / max(bounds.width, 1)), Float(rect.minY / max(bounds.height, 1)),
            Float(rect.width / max(bounds.width, 1)), Float(rect.height / max(bounds.height, 1)))
        encoder.setVertexBytes(&quad, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        func drawQuad(_ texture: MTLTexture?, opacity: Float) {
            guard let texture else { return }
            var opacity = opacity
            encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        drawQuad(blurredTrail, opacity: Float(ScopeTraceMetal.trailDecay))
        drawQuad(blurredMain, opacity: 1)
        drawQuad(mainTexture, opacity: 0.35)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }

    /// Upload the shared 128-bin raster into a pooled texture — the same
    /// ``VectorscopeRaster`` pixels the Canvas fallback draws.
    nonisolated private static func densityTexture(
        device: MTLDevice, points: [ScopePoint],
        zoom: VectorscopeAssist.Zoom, brightness: Int, pool: ScopeTexturePool
    ) -> MTLTexture? {
        guard
            let pixels = VectorscopeRaster.pixels(
                from: points, gain: zoom.gain,
                intensity: VectorscopeAssist.intensity(brightness))
        else { return nil }
        let n = VectorscopeRaster.bins
        guard
            let texture = pool.texture(
                device: device, width: n, height: n, pixelFormat: .rgba8Unorm)
        else { return nil }
        pixels.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0,
                    withBytes: base, bytesPerRow: n * 4)
            }
        }
        return texture
    }

    nonisolated private static func blurred(
        _ texture: MTLTexture, device: MTLDevice, command: MTLCommandBuffer,
        pool: ScopeTexturePool
    ) -> MTLTexture? {
        guard
            let output = pool.texture(
                device: device, width: texture.width, height: texture.height,
                pixelFormat: texture.pixelFormat)
        else { return nil }
        let blur = MPSImageGaussianBlur(device: device, sigma: 1.1)
        blur.encode(commandBuffer: command, sourceTexture: texture, destinationTexture: output)
        return output
    }

    nonisolated static let quadPipeline: MTLRenderPipelineState? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let source = """
            #include <metal_stdlib>
            using namespace metal;
            struct VOut { float4 position [[position]]; float2 uv; };
            vertex VOut vector_v(uint vid [[vertex_id]],
                                 constant float4 &quad [[buffer(0)]]) {
                float2 corners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };
                float2 c = corners[vid];
                float2 pos01 = float2(quad.x + c.x * quad.z, quad.y + c.y * quad.w);
                VOut o;
                o.position = float4(pos01.x * 2.0 - 1.0, 1.0 - pos01.y * 2.0, 0.0, 1.0);
                o.uv = c;
                return o;
            }
            fragment float4 vector_f(VOut in [[stage_in]],
                                     texture2d<float> density [[texture(0)]],
                                     constant float &opacity [[buffer(0)]]) {
                constexpr sampler linearSampler(filter::linear, address::clamp_to_zero);
                return density.sample(linearSampler, in.uv) * opacity;
            }
            """
        guard let library = try? device.makeLibrary(source: source, options: nil),
            let vertexFunction = library.makeFunction(name: "vector_v"),
            let fragmentFunction = library.makeFunction(name: "vector_f")
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = .bgra8Unorm
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .one
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }()
}
