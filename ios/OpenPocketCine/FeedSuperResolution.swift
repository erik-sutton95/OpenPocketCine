import CoreImage
import CoreVideo
import Foundation
import Metal
import MetalPerformanceShaders
import os
#if !targetEnvironment(simulator)
import VideoToolbox
#endif

enum SuperResolutionModel {
    /// High-quality VT model download is not offered — AI uses the low-latency processor.
    static var isReady: Bool { false }
}

#if !targetEnvironment(simulator)
/// VideoToolbox's low-latency super-resolution scaler as a feed upscaler, sitting between the
/// bake and the present's fit.
///
/// The model works on `CVPixelBuffer`s, not textures, so the bake is blitted into an
/// IOSurface-backed input surface and the model writes an output surface that is read back as a
/// texture — both allocated once per (bake size, scale factor). `processWithCommandBuffer`
/// keeps all of that inside the present's own command buffer: no CPU round-trip, no completion
/// handler, and the blit already queued ahead of it is ordered before the model by contract.
///
/// Unlike MetalFX this cannot take an arbitrary ratio — only the discrete factors the processor
/// reports for the source size — so it takes the smallest factor that *clears* the drawable and
/// lets the fit after it shrink. Enlarging a model's output with Lanczos would throw away the
/// thing being paid for.
@available(iOS 26.0, *)
final class FeedSuperResolutionScaler {
    /// Which of the two super-resolution processors this instance drives.
    ///
    /// They differ in more than quality. The low-latency one is stateless per frame and always
    /// present; the quality one is recurrent — it wants the previous source frame and its own
    /// previous output back — needs a downloaded model, computes optical flow per frame unless
    /// given it, and caps input at 1440×1080 on iOS.
    enum Quality {
        case lowLatency
        case high
    }

    /// Identifies the session a processor was started for; either half changing means a new one.
    private struct Key: Equatable {
        let width: Int
        let height: Int
        let scale: Float
    }

    /// A pixel buffer and the texture view of the same memory, kept together because the
    /// `CVMetalTexture` is what holds `texture` alive.
    private struct Surface {
        let buffer: CVPixelBuffer
        /// Held because a pool outlives the buffers it vends.
        let pool: CVPixelBufferPool
        /// Nil for planar formats: `420v` is two planes, so there is no one texture that is
        /// the image. Those surfaces are read and written through Core Image instead.
        let bridge: CVMetalTexture?
        let texture: MTLTexture?
    }

    let quality: Quality
    private let device: MTLDevice
    private let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "feed-upscale")
    private var textureCache: CVMetalTextureCache?
    private var processor: VTFrameProcessor?
    private var key: Key?
    /// The previous submission's frames, which the quality processor takes as references. Held
    /// as whole frames rather than indices so the round-robin can move underneath them.
    private var previousSource: VTFrameProcessorFrame?
    private var previousOutput: VTFrameProcessorFrame?
    /// One input/output pair per frame that can be in flight — see `encode`.
    private var surfaces: [(input: Surface, output: Surface)] = []
    private var nextSurface = 0
    /// Latched after a refusal so a device that cannot run the model stops paying for the
    /// attempt on every frame. Dimensions it merely does not serve are not a refusal — those
    /// return early without latching, since the next rotation may well be servable.
    private var unavailable = false
    private var frameCount: Int64 = 0
    /// Last decline logged, so a per-frame condition says its reason once rather than 30 times
    /// a second — and says it again if the reason changes.
    private var lastDecline: String?
    /// Shrinks a bake that out-sizes the processor into its input surface. Only ever a
    /// downscale, and only when the ceiling demands one — see `superResolutionInputSize`.
    private lazy var shrink = MPSImageLanczosScale(device: device)
    /// The format this session's surfaces are in. Not always BGRA: the quality processor takes
    /// only `RGhA` (64-bit RGBA half-float), and refusing to speak it is what latched that
    /// upscaler off before it ever ran a frame.
    private var surfaceFormat: (cv: OSType, metal: MTLPixelFormat?) = (
        kCVPixelFormatType_32BGRA, .bgra8Unorm
    )
    /// Carries the two colour conversions when the processor speaks a planar format. Core
    /// Image rather than a compute kernel because it converts `420v` in both directions
    /// natively, and because `render(_:to:commandBuffer:)` keeps the output leg on the
    /// present's own command buffer — the property that made this path cheap to begin with.
    private lazy var ciContext = CIContext(
        mtlDevice: device, options: [.cacheIntermediates: false])
    /// The model's own command buffers, so its work can be COMPLETED before Core Image reads
    /// the result — see `encode`. Separate from the present's queue on purpose: committing the
    /// model into the present's buffer is what produced a frame of flat green.
    private lazy var modelQueue = device.makeCommandQueue()

    /// The asynchronous model's state, shared with its completion handler.
    /// Which SLOT holds the finished result, not the buffer itself: `CVBuffer` carries no
    /// Sendable conformance, and an index crosses the lock without arguing about it.
    private struct AsyncModel {
        var inFlight = false
        /// The most recent output the model has actually FINISHED writing. Reading anything
        /// else is what produced flat green: Core Image resolves a `CVPixelBuffer` when the
        /// render is encoded, so it must only ever be handed a completed buffer.
        var readyIndex: Int?
        var failure: String?
    }

    private let asyncModel = OSAllocatedUnfairLock(initialState: AsyncModel())
    /// Where the model's planar output is converted back to, for the fit to present.
    private var rgbOutput: MTLTexture?
    private let workingColorSpace =
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init(device: MTLDevice, quality: Quality) {
        self.device = device
        self.quality = quality
    }

    deinit { processor?.endSession() }

    /// Encodes the super-resolution pass into `commandBuffer` and returns the enlarged texture,
    /// or `nil` when the model cannot take this frame and the caller should present the bake.
    func encode(source: MTLTexture, target: MTLTexture, commandBuffer: MTLCommandBuffer)
        -> MTLTexture?
    {
        guard !unavailable else { return nil }
        switch quality {
        case .lowLatency:
            guard VTLowLatencySuperResolutionScalerConfiguration.isSupported else {
                return decline("this device does not support it")
            }
        case .high:
            guard SuperResolutionModel.isReady else {
                return decline("its model has not been downloaded")
            }
            // The iOS cap for video input. A source past it is a configuration this processor
            // refuses to build, so it is a decline rather than a failure.
            guard source.width <= 1_440, source.height <= 1_080 else {
                return decline(
                    "\(source.width)×\(source.height) is past the 1440×1080 input limit")
            }
        }
        let ratio = min(
            Double(target.width) / Double(source.width),
            Double(target.height) / Double(source.height))
        guard ratio > 1 else {
            // `bakeSize` clamps a source that out-resolves the panel, so the present is a copy
            // and there is nothing to upscale — the demo-stills case. Worth saying out loud:
            // from the operator's side this looks exactly like the option doing nothing.
            return decline(
                "the \(source.width)×\(source.height) bake already fills the "
                    + "\(target.width)×\(target.height) panel — nothing to upscale")
        }

        // The bake can be bigger than the processor takes (1024×576 against a 960×960
        // ceiling). Shrinking to fit is what makes the model reachable at all; the fit after
        // it absorbs the difference either way.
        let ceiling: (width: Int, height: Int)
        switch quality {
        case .lowLatency:
            if let maximum = VTLowLatencySuperResolutionScalerConfiguration.maximumDimensions {
                ceiling = (Int(maximum.width), Int(maximum.height))
            } else {
                ceiling = (source.width, source.height)
            }
        case .high:
            ceiling = (1_440, 1_080)
        }
        // Sized against the ceiling first so the factor query asks about a frame the
        // processor will actually take; the panel-fit shrink lands once the factor is known.
        let ceilingInput = FeedUpscaler.superResolutionInputSize(
            source: (source.width, source.height), target: (target.width, target.height),
            scale: 0, maximum: ceiling)

        // No factors means the processor does not serve this source size — not a failure of the
        // model, so no latch: the next rotation may well be servable.
        let running = key.flatMap { $0.scale }
        // The quality processor's factors are whole numbers and do not depend on the source
        // size; the low-latency one's are fractional and asked per size.
        let offered: [Float] =
            switch quality {
            case .lowLatency:
                VTLowLatencySuperResolutionScalerConfiguration.supportedScaleFactors(
                    frameWidth: ceilingInput.width, frameHeight: ceilingInput.height)
            case .high:
                VTSuperResolutionScalerConfiguration.supportedScaleFactors.map(Float.init)
            }
        guard
            let scale = FeedUpscaler.superResolutionScale(
                offered: offered, ratio: ratio, held: running)
        else {
            // Say what the processor WILL take. An empty factor list is how it reports "not
            // this size", and without its own bounds beside them the number is unactionable —
            // a PTP live view is capped near 1024 wide, so if the floor is higher than that,
            // this upscaler can never serve the wireless feed and only HDMI capture qualifies.
            let bounds: String
            switch quality {
            case .lowLatency:
                let low = VTLowLatencySuperResolutionScalerConfiguration.minimumDimensions
                let high = VTLowLatencySuperResolutionScalerConfiguration.maximumDimensions
                if let low, let high {
                    bounds = "\(low.width)×\(low.height) to \(high.width)×\(high.height)"
                } else {
                    bounds = "sizes it does not report"
                }
            case .high:
                bounds = "up to 1440×1080"
            }
            return decline(
                "no scale factor is offered for \(source.width)×\(source.height) "
                    + "— it takes \(bounds)")
        }

        let modelInput = FeedUpscaler.superResolutionInputSize(
            source: (source.width, source.height), target: (target.width, target.height),
            scale: scale, maximum: ceiling)
        let wanted = Key(width: modelInput.width, height: modelInput.height, scale: scale)
        // Session startup happens OFF this thread and the frame is presented without it.
        //
        // The header is explicit: "ML model loading may take longer than a frame time. Avoid
        // blocking the UI thread or stalling frame rendering pipelines during this call." It
        // was being called from `draw(in:)`, with a frame submitted on the very next line —
        // which fits every symptom seen so far. `startSession` returns true because the
        // configuration is valid, while the pipeline behind it is still being built: submitting
        // then made the asynchronous entry point dereference an internal queue that did not
        // exist yet (EXC_BAD_ACCESS in VideoToolbox's own dispatch_async), and made the
        // command-buffer entry point encode nothing at all and report no error.
        if wanted != key {
            _ = startSession(for: wanted)
            // Present THIS frame on Lanczos and submit nothing. The session was previously
            // started and handed a frame in the same draw call, which is the one ordering the
            // header warns about — the load "may take longer than a frame time", and every
            // failure so far is consistent with a pipeline that had not finished coming up:
            // the async entry point crashed inside VideoToolbox's own dispatch_async, and the
            // command-buffer one encoded nothing and reported no error.
            return nil
        }
        guard let processor, !surfaces.isEmpty else { return nil }

        // Round-robin the surfaces rather than reusing one pair. Apple's contract is that
        // neither buffer may be touched until the work on it finishes — here that is command
        // buffer completion, and the drawable queue keeps two or three frames in flight, so
        // writing the next frame into last frame's input would corrupt work still running.
        let (input, output) = surfaces[nextSurface % surfaces.count]
        nextSurface += 1

        if let inputTexture = input.texture {
            // A blit copies bytes, so it can only take the case where nothing needs changing.
            // Any difference in size OR format goes through the resampler, which does both.
            if inputTexture.width == source.width, inputTexture.height == source.height,
                inputTexture.pixelFormat == source.pixelFormat
            {
                guard let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
                blit.copy(
                    from: source,
                    sourceSlice: 0,
                    sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
                    to: inputTexture,
                    destinationSlice: 0,
                    destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                blit.endEncoding()
            } else {
                // The one place this path shrinks the picture, and what makes the model legal
                // at all. Lanczos rather than the cheapest kernel: whatever detail survives
                // here is what the model has to work from.
                shrink.encode(
                    commandBuffer: commandBuffer, sourceTexture: source,
                    destinationTexture: inputTexture)
            }
        } else if !writePlanarInput(from: source, to: input, size: modelInput) {
            return decline("the frame could not be converted to the model's format")
        }

        // The feed carries no timestamps of its own, and a low-latency model is entitled to
        // read the previous frame — so the stamps at least have to advance monotonically.
        frameCount += 1
        let time = CMTime(value: frameCount, timescale: 600)
        guard
            let sourceFrame = VTFrameProcessorFrame(
                buffer: input.buffer, presentationTimeStamp: time),
            let destinationFrame = VTFrameProcessorFrame(
                buffer: output.buffer, presentationTimeStamp: time)
        else { return nil }
        let parameters: any VTFrameProcessorParameters
        switch quality {
        case .lowLatency:
            parameters = VTLowLatencySuperResolutionScalerParameters(
                sourceFrame: sourceFrame, destinationFrame: destinationFrame)
        case .high:
            // Recurrent: it refines against the previous source and its own previous output,
            // which is where the extra quality comes from. Both are nil on the first frame
            // after a session start, which the API allows. `sequential` tells it the stream has
            // not jumped — the mode that lets it keep its caches.
            guard
                let recurrent = VTSuperResolutionScalerParameters(
                    sourceFrame: sourceFrame,
                    previousFrame: previousSource,
                    previousOutputFrame: previousOutput,
                    opticalFlow: nil,
                    submissionMode: .sequential,
                    destinationFrame: destinationFrame)
            else { return decline("the frame pair was rejected") }
            parameters = recurrent
            previousSource = sourceFrame
            previousOutput = destinationFrame
        }
        // The model runs in ITS OWN command buffer, committed and awaited, whenever the
        // result has to be read back through Core Image.
        //
        // `processWithCommandBuffer` orders the model against other GPU work in the same
        // buffer, and that is enough when the output is a texture the fit samples directly.
        // It is NOT enough for the planar path: Core Image resolves a `CVPixelBuffer` source
        // when the render is ENCODED, not when it executes, so reading the output inside the
        // present's buffer captured the frame before the model had run — every pixel zero,
        // which in `420v` is the flat green this showed on device.
        //
        // Synchronous, which costs the draw thread the model's own latency. The input leg is
        // already synchronous, so this makes the whole stage so; if a device says that is too
        // expensive the answer is to present the PREVIOUS frame's output and drop the wait,
        // at the cost of one frame of lag.
        // A texture output can ride the present's own command buffer: the fit samples it
        // directly, and `processWithCommandBuffer` orders the model against the work around it.
        guard output.texture == nil else {
            processor.process(with: commandBuffer, parameters: parameters)
            lastDecline = nil
            return output.texture
        }

        // The planar path submits asynchronously and presents the previous completed result.
        //
        // Never the PRESENT's command buffer: Core Image resolves a `CVPixelBuffer` source
        // when the render is ENCODED, not when it executes, so reading the output there
        // captured the frame before the model ran — every pixel zero, which in `420v` is flat
        // green. Presenting only a buffer the model has FINISHED costs a frame of lag and buys
        // that guarantee outright.
        if FeedUpscaleSwitch.presentsSuperResolutionInput {
            // Diagnostic: read back the input, which needs no model at all.
            lastDecline = nil
            return readPlanarOutput(input, commandBuffer: commandBuffer)
        }

        let pending = asyncModel.withLock {
            state -> (start: Bool, readyIndex: Int?, failure: String?) in
            let start = !state.inFlight
            if start { state.inFlight = true }
            let failure = state.failure
            state.failure = nil
            return (start, state.readyIndex, failure)
        }
        if let failure = pending.failure {
            return decline("the model refused the frame — \(failure)")
        }
        if pending.start {
            let slot = (nextSurface - 1) % surfaces.count
            // The command-buffer entry point, which has never crashed. The asynchronous one
            // segfaults inside VideoToolbox for this configuration whether the buffers come
            // from `CVPixelBufferCreate` or from a pool, so it is not the buffers.
            //
            // Its own command buffer, not the present's: Core Image resolves a
            // `CVPixelBuffer` when the render is ENCODED, so only a buffer the model has
            // FINISHED is safe to read, and the completion handler is what proves that.
            if let modelQueue, let modelBuffer = modelQueue.makeCommandBuffer() {
                processor.process(with: modelBuffer, parameters: parameters)
                modelBuffer.addCompletedHandler { [weak self] buffer in
                    self?.asyncModel.withLock { state in
                        state.inFlight = false
                        if let error = buffer.error {
                            state.failure = error.localizedDescription
                        } else {
                            state.readyIndex = slot
                        }
                    }
                }
                modelBuffer.commit()
            } else {
                asyncModel.withLock { $0.inFlight = false }
            }
        }
        // Nothing finished yet — the first frame or two after a session starts. Present the
        // bake rather than an empty buffer, and say nothing: this is not a fault.
        guard let readyIndex = pending.readyIndex, readyIndex < surfaces.count else {
            return nil
        }
        lastDecline = nil  // A later decline is news again.
        return readPlanarOutput(
            surfaces[readyIndex].output.buffer, commandBuffer: commandBuffer)
        // Planar output: convert back to RGB for the fit. This render takes the present's own
        // command buffer, and `processWithCommandBuffer` documents that work inserted after it
        // runs after the effect — so this reads the model's result, not the frame before it.
        return readPlanarOutput(output, commandBuffer: commandBuffer)
    }

    /// Builds the processor and its surfaces for `wanted`, replacing whatever was there.
    ///
    /// This loads an ML model, which Apple documents as possibly taking longer than a frame —
    /// on the draw thread that is a visible hitch. It happens once per (bake size, scale), i.e.
    /// on selecting this upscaler and on a panel size the running factor no longer covers, not
    /// per frame.
    private func startSession(for wanted: Key) -> Bool {
        // `supportedPixelFormats` is refined onto each concrete configuration, not onto the
        // protocol, so the BGRA check has to happen before the type is erased.
        let configuration: any VTFrameProcessorConfiguration
        let takesBGRA: Bool
        var offeredFormats: [OSType] = []
        switch quality {
        case .lowLatency:
            let lowLatency = VTLowLatencySuperResolutionScalerConfiguration(
                frameWidth: wanted.width, frameHeight: wanted.height, scaleFactor: wanted.scale)
            offeredFormats = lowLatency.supportedPixelFormats
            takesBGRA = offeredFormats.contains(kCVPixelFormatType_32BGRA)
            configuration = lowLatency
        case .high:
            // `usePrecomputedFlow: false` — we have no optical flow to give it, so it computes
            // its own per frame. That is the bulk of what makes this one expensive, and the
            // reason it may not hold a live frame rate at all.
            guard
                let highQuality = VTSuperResolutionScalerConfiguration(
                    frameWidth: wanted.width, frameHeight: wanted.height,
                    scaleFactor: Int(wanted.scale), inputType: .video,
                    usePrecomputedFlow: false, qualityPrioritization: .normal,
                    revision: VTSuperResolutionScalerConfiguration.defaultRevision)
            else {
                return latchOff("the quality super-resolution configuration was refused")
            }
            offeredFormats = highQuality.supportedPixelFormats
            takesBGRA = offeredFormats.contains(kCVPixelFormatType_32BGRA)
            configuration = highQuality
        }
        // The first format on our preference list the processor actually offers. BGRA when it
        // is there costs nothing; `420v` costs two colour conversions but is the only format
        // the low-latency processor accepts, so refusing it is refusing the feature.
        _ = takesBGRA
        guard let chosen = Self.usableFormats.first(where: offeredFormats.contains) else {
            let offered = offeredFormats.map(Self.fourCC).joined(separator: ", ")
            return latchOff(
                "super resolution takes no format this pipeline can produce — it takes "
                    + "\(offered)")
        }
        surfaceFormat = (chosen, Self.metalFormat(for: chosen))
        if surfaceFormat.metal == nil {
            let name = Self.fourCC(chosen)
            log.info(
                "Feed upscale: super resolution runs in \(name, privacy: .public), colour converted on both sides."
            )
        }
        if textureCache == nil {
            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
            textureCache = cache
        }
        let outputWidth = Int((Double(wanted.width) * Double(wanted.scale)).rounded())
        let outputHeight = Int((Double(wanted.height) * Double(wanted.scale)).rounded())
        // One pair per frame that can be in flight at once — see `encode`. Three is the
        // drawable queue's own depth, which is what bounds how many frames are outstanding.
        let built = (0..<3).compactMap { _ -> (input: Surface, output: Surface)? in
            guard
                let input = makeSurface(
                    width: wanted.width, height: wanted.height,
                    attributes: configuration.sourcePixelBufferAttributes),
                let output = makeSurface(
                    width: outputWidth, height: outputHeight,
                    attributes: configuration.destinationPixelBufferAttributes)
            else { return nil }
            return (input, output)
        }
        guard built.count == 3 else {
            return latchOff("super resolution surfaces could not be allocated")
        }

        // End the OLD session only, and start on a FRESH processor — never endSession() on a
        // just-created one. That pattern was the root of the whole failure arc; the full
        // account lives in `FrameDecoder.LiveFeedSuperResolution.prepare`.
        self.processor?.endSession()
        self.processor = nil
        let processor = VTFrameProcessor()
        do {
            try processor.startSession(configuration: configuration)
        } catch {
            return latchOff("super resolution session refused: \(error.localizedDescription)")
        }
        self.processor = processor
        surfaces = built
        nextSurface = 0
        key = wanted
        // The references belong to the session that produced them; a restart invalidates both.
        previousSource = nil
        previousOutput = nil
        asyncModel.withLock { $0 = AsyncModel() }
        // Same reason MetalFX logs its selection: neither path exists in the simulator, so a
        // device log line is the only confirmation of which upscaler the feed actually chose.
        let name = quality == .high ? "VT Super Res+ (quality)" : "VT Super Res (low latency)"
        log.info(
            """
            Feed upscale: \(name, privacy: .public) \
            \(wanted.width, privacy: .public)×\(wanted.height, privacy: .public) → \
            \(outputWidth, privacy: .public)×\(outputHeight, privacy: .public) \
            (×\(wanted.scale, privacy: .public))
            """)
        return true
    }

    /// Writes the bake into a planar input surface, converting colour and size in one pass.
    ///
    /// Synchronous, and deliberately so: it runs at the MODEL's input size (a few hundred
    /// pixels a side), not the panel's, and the alternative — teaching the baker to produce
    /// this buffer on its own thread — couples the bake to the model's geometry. That trade is
    /// worth making only if a device says this costs real frame time.
    private func writePlanarInput(
        from source: MTLTexture, to surface: Surface, size: (width: Int, height: Int)
    ) -> Bool {
        guard
            let image = CIImage(
                mtlTexture: source, options: [.colorSpace: workingColorSpace])
        else { return false }
        let scaled = image.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(size.width) / image.extent.width,
                y: CGFloat(size.height) / image.extent.height))
        // No flip either way. Core Image's origin convention applies identically to the read
        // leg below, so the two cancel and the model simply sees the picture the same way
        // round on both sides — which a spatial upscaler is indifferent to.
        //
        // AWAITED, and that is the whole point of using a render task here rather than
        // `render(_:to:)`. That call is asynchronous: it returns before the GPU has written a
        // pixel. The model then read an input that was not there yet and dutifully upscaled
        // nothing, which in `420v` presents as flat green with no error anywhere — the buffer
        // was valid, the call succeeded, and the contents simply had not arrived.
        let destination = CIRenderDestination(pixelBuffer: surface.buffer)
        destination.colorSpace = workingColorSpace
        do {
            let task = try ciContext.startTask(
                toRender: scaled,
                from: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                to: destination,
                at: .zero)
            try task.waitUntilCompleted()
        } catch {
            log.error(
                "Feed upscale: input conversion failed — \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
        return true
    }

    /// Converts the model's planar output back to an RGB texture the fit can present.
    private func readPlanarOutput(_ surface: Surface, commandBuffer: MTLCommandBuffer)
        -> MTLTexture?
    {
        readPlanarOutput(surface.buffer, commandBuffer: commandBuffer)
    }

    private func readPlanarOutput(_ buffer: CVPixelBuffer, commandBuffer: MTLCommandBuffer)
        -> MTLTexture?
    {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        if rgbOutput?.width != width || rgbOutput?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            descriptor.storageMode = .private
            rgbOutput = device.makeTexture(descriptor: descriptor)
        }
        guard let rgbOutput else { return nil }
        ciContext.render(
            CIImage(cvPixelBuffer: buffer),
            to: rgbOutput,
            commandBuffer: commandBuffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: workingColorSpace)
        return rgbOutput
    }

    /// An IOSurface-backed BGRA buffer plus its texture view, meeting the processor's own
    /// attribute requirements for the side it is for.
    private func makeSurface(width: Int, height: Int, attributes: [String: Any]) -> Surface? {
        guard let textureCache else { return nil }
        // From a POOL built out of the processor's OWN attributes, which is what Apple's
        // guidance specifies — and the previous `CVPixelBufferCreate` did not do.
        //
        // That call took an explicit format argument, which OVERRIDES whatever the
        // configuration asked for, and a hand-merged dictionary that satisfied only the
        // requirements I happened to know about. The result was IOSurface-backed enough for
        // `VTFrameProcessorFrame` to accept it, so nothing ever errored — while apparently
        // missing something the processor needs, which is a silent no-op rather than a fault.
        //
        // Dimensions are ours; every other attribute, the pixel format included, is the
        // configuration's. The format is read back off the buffer rather than assumed.
        var resolved = attributes
        resolved[kCVPixelBufferWidthKey as String] = width
        resolved[kCVPixelBufferHeightKey as String] = height
        resolved[kCVPixelBufferMetalCompatibilityKey as String] = true
        if resolved[kCVPixelBufferIOSurfacePropertiesKey as String] == nil {
            resolved[kCVPixelBufferIOSurfacePropertiesKey as String] = [String: Any]()
        }
        var pool: CVPixelBufferPool?
        guard
            CVPixelBufferPoolCreate(
                kCFAllocatorDefault, nil, resolved as CFDictionary, &pool) == kCVReturnSuccess,
            let pool
        else { return nil }
        var buffer: CVPixelBuffer?
        guard
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
                == kCVReturnSuccess,
            let buffer
        else { return nil }
        // Pools outlive the buffers they vend, so the surface holds one alive.
        let format = CVPixelBufferGetPixelFormatType(buffer)
        // A planar format has no single texture to bridge to; those surfaces are driven
        // through Core Image and carry no Metal view at all.
        guard let metal = Self.metalFormat(for: format) else {
            return Surface(buffer: buffer, pool: pool, bridge: nil, texture: nil)
        }
        var bridge: CVMetalTexture?
        guard
            CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, textureCache, buffer, nil, metal,
                width, height, 0,
                &bridge) == kCVReturnSuccess,
            let bridge, let texture = CVMetalTextureGetTexture(bridge)
        else { return nil }
        return Surface(buffer: buffer, pool: pool, bridge: bridge, texture: texture)
    }

    /// The Metal format for a `CVPixelBuffer` format we can hand the model, or nil for one we
    /// cannot bridge.
    ///
    /// Both entries are plain RGBA orderings, so moving between them is a format change and
    /// nothing more — Metal samples a `bgra8Unorm` texture as `(r,g,b,a)` floats already, so
    /// an MPS pass into a half-float destination writes the right channels with no swizzle and
    /// no colour maths. A YUV-only processor would have been a different piece of work.
    private static func metalFormat(for format: OSType) -> MTLPixelFormat? {
        switch format {
        case kCVPixelFormatType_32BGRA: return .bgra8Unorm
        case kCVPixelFormatType_64RGBAHalf: return .rgba16Float
        default: return nil
        }
    }

    /// Formats this pipeline can hand the model, best first.
    ///
    /// The RGB pair need no conversion at all — Metal writes them directly. `420v` does, and
    /// it is last for that reason, but it is on the list because it is the ONLY format the
    /// low-latency processor accepts: refusing it is refusing the feature.
    private static let usableFormats: [OSType] = [
        kCVPixelFormatType_32BGRA,
        kCVPixelFormatType_64RGBAHalf,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ]

    /// A `CVPixelBufferPixelFormatType` as the four characters it actually is, because
    /// `875704422` in a log is unreadable and `420v` is the answer.
    private static func fourCC(_ format: OSType) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((format >> $0) & 0xFF) }
        let text = String(decoding: bytes, as: UTF8.self)
        return text.allSatisfy(\.isASCII) ? text : String(format)
    }

    private func latchOff(_ reason: String) -> Bool {
        unavailable = true
        log.error("\(reason, privacy: .public) — feed upscale falls back.")
        return false
    }

    /// Says why the selected upscaler is not the one on screen, once per reason.
    ///
    /// Every path out of `encode` is a silent fall back to Lanczos, which is indistinguishable
    /// from the setting not working — and neither this nor MetalFX can be exercised anywhere
    /// but a device, so a log line is the only way to tell those two apart.
    private func decline(_ reason: String) -> MTLTexture? {
        if reason != lastDecline {
            lastDecline = reason
            log.info(
                "Feed upscale: Super Res declined — \(reason, privacy: .public). Using Lanczos."
            )
        }
        return nil
    }
}
#endif
