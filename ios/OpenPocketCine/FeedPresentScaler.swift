import Foundation
import Metal
import MetalPerformanceShaders
import os

#if canImport(MetalFX)
    import MetalFX
#endif

/// Bake→drawable upscale. OpenZCine `MetalLiveView.Coordinator.draw` present half.
final class FeedPresentScaler {
    private let device: MTLDevice
    private let bilinear: MPSImageBilinearScale
    private let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "feed-upscale")

    #if canImport(MetalFX)
        private struct SpatialScalerKey: Equatable {
            let inputWidth: Int
            let inputHeight: Int
            let outputWidth: Int
            let outputHeight: Int
            let pixelFormat: MTLPixelFormat
        }

        private var spatialScaler: MTLFXSpatialScaler?
        private var spatialScalerKey: SpatialScalerKey?
        private lazy var spatialScalingSupported = MTLFXSpatialScalerDescriptor.supportsDevice(
            device)
        private var spatialOutput: MTLTexture?
        private var supersampleTexture: MTLTexture?
    #endif

    #if !targetEnvironment(simulator)
        private var superResolver: AnyObject?
    #endif

    private var hdrScratch: MTLTexture?
    private var hdrPipeline: MTLRenderPipelineState?

    init(device: MTLDevice) {
        self.device = device
        bilinear = MPSImageBilinearScale(device: device)
    }

    /// Encodes the present-fit (and Super Res / MetalFX when selected) into `target`.
    func encode(
        from baked: MTLTexture,
        to target: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        overlay: Bool
    ) -> Bool {
        let gain = LiveHDRDisplay.presentGain
        if LiveHDRDisplay.isEnabled, target.pixelFormat == .rgba16Float {
            return encodeHDR(
                from: baked, to: target, commandBuffer: commandBuffer, overlay: overlay, gain: gain)
        }
        return encodeFitted(
            from: baked, to: target, commandBuffer: commandBuffer, overlay: overlay)
    }

    private func encodeHDR(
        from baked: MTLTexture, to target: MTLTexture, commandBuffer: MTLCommandBuffer,
        overlay: Bool, gain: Float
    ) -> Bool {
        guard let scratch = sdrScratch(matching: target) else { return false }
        guard
            encodeFitted(
                from: baked, to: scratch, commandBuffer: commandBuffer, overlay: overlay)
        else { return false }
        return encodeGain(
            from: scratch, to: target, commandBuffer: commandBuffer, gain: max(gain, 1))
    }

    private func sdrScratch(matching target: MTLTexture) -> MTLTexture? {
        if let existing = hdrScratch, existing.width == target.width,
            existing.height == target.height, existing.pixelFormat == LiveHDRDisplay.bakePixelFormat
        {
            return existing
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: LiveHDRDisplay.bakePixelFormat, width: target.width, height: target.height,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        hdrScratch = device.makeTexture(descriptor: descriptor)
        return hdrScratch
    }

    private func encodeGain(
        from source: MTLTexture, to target: MTLTexture, commandBuffer: MTLCommandBuffer, gain: Float
    ) -> Bool {
        guard let pipeline = hdrBlitPipeline(pixelFormat: target.pixelFormat) else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return false
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        var gain = gain
        encoder.setFragmentBytes(&gain, length: MemoryLayout<Float>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    private func hdrBlitPipeline(pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        if let hdrPipeline { return hdrPipeline }
        let source = """
            #include <metal_stdlib>
            using namespace metal;
            struct VOut { float4 position [[position]]; float2 uv; };
            vertex VOut hdr_v(uint vid [[vertex_id]]) {
                float2 p = float2((vid << 1) & 2, vid & 2);
                VOut o;
                o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
                // MPS writes y=0 at the bottom; Metal samples (0,0) at the top.
                o.uv = float2(p.x, 1.0 - p.y);
                return o;
            }
            fragment float4 hdr_f(VOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  constant float &gain [[buffer(0)]]) {
                constexpr sampler samp(filter::linear, address::clamp_to_edge);
                float4 c = src.sample(samp, in.uv);
                float3 linear = pow(max(c.rgb, 0.0), 2.2);
                return float4(linear * gain, c.a);
            }
            """
        guard let library = try? device.makeLibrary(source: source, options: nil),
            let vertex = library.makeFunction(name: "hdr_v"),
            let fragment = library.makeFunction(name: "hdr_f")
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        hdrPipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        return hdrPipeline
    }

    private func encodeFitted(
        from baked: MTLTexture,
        to target: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        overlay: Bool
    ) -> Bool {
        let superResolved = encodeSuperResolution(
            from: baked, to: target, commandBuffer: commandBuffer)
        let source =
            superResolved.map {
                encodeSupersample($0, to: target, commandBuffer: commandBuffer)
            } ?? baked

        let scale = min(
            Double(target.width) / Double(source.width),
            Double(target.height) / Double(source.height))
        let fittedWidth = Int((Double(source.width) * scale).rounded())
        let fittedHeight = Int((Double(source.height) * scale).rounded())
        let fillsDrawable = fittedWidth == target.width && fittedHeight == target.height
        if fillsDrawable,
            encodeSpatialUpscale(from: source, to: target, commandBuffer: commandBuffer)
        {
            return true
        }

        // Write straight into the drawable. A private-scratch + runtime-shader
        // flip returned false on device and left the opaque metal view black
        // over the working VT picture. Bake already flipped for MPS.
        // A 1:1 copy (source-sized drawable) writes every pixel, so it has no bars to clear.
        if source.width != target.width || source.height != target.height {
            Self.encodeClear(target, overlay: overlay, commandBuffer: commandBuffer)
        }
        var transform = Self.mpsFitTransform(
            sourceWidth: source.width, sourceHeight: source.height,
            targetWidth: target.width, targetHeight: target.height)
        // Identity HEVC uses the display layer's hardware scaler. LUT already
        // ran the cube at feed resolution — Lanczos on every replace frame is
        // why enabling a look hitchs a 720p proxy. Quality / AI return above.
        withUnsafePointer(to: &transform) { pointer in
            bilinear.scaleTransform = pointer
            bilinear.encode(
                commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: target)
            bilinear.scaleTransform = nil
        }
        return true
    }

    /// Aspect-fit into `target`. Positive scales only — OpenZCine `MetalLiveView`.
    static func mpsFitTransform(
        sourceWidth: Int, sourceHeight: Int, targetWidth: Int, targetHeight: Int
    ) -> MPSScaleTransform {
        let scale = min(
            Double(targetWidth) / Double(sourceWidth),
            Double(targetHeight) / Double(sourceHeight))
        return MPSScaleTransform(
            scaleX: scale,
            scaleY: scale,
            translateX: (Double(targetWidth) - Double(sourceWidth) * scale) / 2,
            translateY: (Double(targetHeight) - Double(sourceHeight) * scale) / 2)
    }

    private static func encodeClear(
        _ texture: MTLTexture, overlay: Bool, commandBuffer: MTLCommandBuffer
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: overlay ? 0 : 1)
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }

    #if canImport(MetalFX)
        private func spatialOutputTexture(matching target: MTLTexture) -> MTLTexture? {
            if let existing = spatialOutput, existing.width == target.width,
                existing.height == target.height, existing.pixelFormat == target.pixelFormat
            {
                return existing
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: target.pixelFormat, width: target.width, height: target.height,
                mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            descriptor.storageMode = .private
            spatialOutput = device.makeTexture(descriptor: descriptor)
            return spatialOutput
        }

        private func encodeSpatialUpscale(
            from source: MTLTexture, to target: MTLTexture, commandBuffer: MTLCommandBuffer,
            ignoringSelection: Bool = false
        ) -> Bool {
            guard ignoringSelection || FeedUpscaleSwitch.rendererReadsUpscaler == .spatial,
                spatialScalingSupported
            else { return false }
            guard target.width > source.width, target.height > source.height else { return false }

            let key = SpatialScalerKey(
                inputWidth: source.width, inputHeight: source.height,
                outputWidth: target.width, outputHeight: target.height,
                pixelFormat: target.pixelFormat)
            if key != spatialScalerKey {
                let descriptor = MTLFXSpatialScalerDescriptor()
                descriptor.inputWidth = source.width
                descriptor.inputHeight = source.height
                descriptor.outputWidth = target.width
                descriptor.outputHeight = target.height
                descriptor.colorTextureFormat = source.pixelFormat
                descriptor.outputTextureFormat = target.pixelFormat
                descriptor.colorProcessingMode = .perceptual
                guard let scaler = descriptor.makeSpatialScaler(device: device) else {
                    spatialScalingSupported = false
                    spatialScaler = nil
                    spatialScalerKey = nil
                    log.error("MetalFX spatial scaler unavailable — feed upscale uses Lanczos.")
                    return false
                }
                spatialScaler = scaler
                spatialScalerKey = key
                log.info(
                    """
                    Feed upscale: MetalFX Spatial \
                    \(source.width, privacy: .public)×\(source.height, privacy: .public) → \
                    \(target.width, privacy: .public)×\(target.height, privacy: .public)
                    """)
            }
            guard let spatialScaler, let output = spatialOutputTexture(matching: target)
            else { return false }
            spatialScaler.colorTexture = source
            spatialScaler.outputTexture = output
            spatialScaler.encode(commandBuffer: commandBuffer)
            // Bake is flipped for MPS. A blit would put that origin on CAMetalLayer
            // upside down; a 1:1 MPS copy uses the same Y as Fast.
            var copy = MPSScaleTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0)
            withUnsafePointer(to: &copy) { pointer in
                bilinear.scaleTransform = pointer
                bilinear.encode(
                    commandBuffer: commandBuffer, sourceTexture: output,
                    destinationTexture: target)
                bilinear.scaleTransform = nil
            }
            return true
        }

        private func encodeSupersample(
            _ source: MTLTexture, to target: MTLTexture, commandBuffer: MTLCommandBuffer
        ) -> MTLTexture {
            guard spatialScalingSupported else { return source }
            let wanted = min(max(target.width * 2, target.width), 3_840)
            let scale = Double(wanted) / Double(source.width)
            guard scale > 1.05 else { return source }
            let width = wanted
            let height = Int((Double(source.height) * scale).rounded())
            guard width > source.width, height > source.height else { return source }
            if supersampleTexture?.width != width || supersampleTexture?.height != height
                || supersampleTexture?.pixelFormat != target.pixelFormat
            {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: target.pixelFormat, width: width, height: height, mipmapped: false)
                descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
                descriptor.storageMode = .private
                supersampleTexture = device.makeTexture(descriptor: descriptor)
            }
            guard let supersampleTexture else { return source }
            guard
                encodeSpatialUpscale(
                    from: source, to: supersampleTexture, commandBuffer: commandBuffer,
                    ignoringSelection: true)
            else { return source }
            return supersampleTexture
        }
    #else
        private func encodeSpatialUpscale(
            from _: MTLTexture, to _: MTLTexture, commandBuffer _: MTLCommandBuffer,
            ignoringSelection _: Bool = false
        ) -> Bool { false }

        private func encodeSupersample(
            _ source: MTLTexture, to _: MTLTexture, commandBuffer _: MTLCommandBuffer
        ) -> MTLTexture { source }
    #endif

    #if !targetEnvironment(simulator)
        private func encodeSuperResolution(
            from source: MTLTexture, to target: MTLTexture, commandBuffer: MTLCommandBuffer
        ) -> MTLTexture? {
            guard FeedUpscaleSwitch.rendererReadsUpscaler == .superResolution,
                #available(iOS 26.0, *)
            else { return nil }
            let existing = superResolver as? FeedSuperResolutionScaler
            let scaler: FeedSuperResolutionScaler
            if let existing, existing.quality == .lowLatency {
                scaler = existing
            } else {
                scaler = FeedSuperResolutionScaler(device: device, quality: .lowLatency)
                superResolver = scaler
            }
            return scaler.encode(source: source, target: target, commandBuffer: commandBuffer)
        }
    #else
        private func encodeSuperResolution(
            from _: MTLTexture, to _: MTLTexture, commandBuffer _: MTLCommandBuffer
        ) -> MTLTexture? { nil }
    #endif
}
