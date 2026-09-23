import CoreImage
import CoreVideo
import Foundation
import MonitorPresentation

/// Inspector-only image work: at most one admitted source buffer, no pending
/// queue, and no display/decoder attachment. A busy job drops a request; the
/// view's next bounded tick reads the newest source instead of catching up.
final class AssistInspectorImageRenderer: @unchecked Sendable {
    typealias RenderOperation = @Sendable (CVPixelBuffer, LiveImageEffects) -> CGImage?
    typealias Clock = @Sendable () -> UInt64

    struct Result {
        let image: CGImage
        fileprivate let ticket: MonitorPreviewAdmission.Ticket
    }

    private let queue = DispatchQueue(label: "opv.assist-inspector", qos: .utility)
    private let lock = NSLock()
    private var admission = MonitorPreviewAdmission()
    private let now: Clock
    private let operation: RenderOperation?
    // These contexts are used only on queue, never by the live present worker.
    private var displayContext: CIContext?
    private var cubeContext: CIContext?

    init(
        now: @escaping Clock = { DispatchTime.now().uptimeNanoseconds },
        operation: RenderOperation? = nil
    ) {
        self.now = now
        self.operation = operation
    }

    func activate(owner: UUID) {
        lock.lock()
        defer { lock.unlock() }
        admission.activate(owner: owner)
    }

    func invalidate(owner: UUID) {
        lock.lock()
        defer { lock.unlock() }
        admission.invalidate(owner: owner)
    }

    func deactivate(owner: UUID) {
        lock.lock()
        defer { lock.unlock() }
        admission.deactivate(owner: owner)
    }

    func isCurrent(_ result: Result) -> Bool { isCurrent(result.ticket) }

    /// Admission remains occupied through native work and main-actor delivery.
    /// Cancelling an owner invalidates adoption but cannot free running CI work.
    @MainActor
    func render(
        owner: UUID, source: CVPixelBuffer, effects: @MainActor () -> LiveImageEffects
    ) async -> Result? {
        guard !Task.isCancelled, let ticket = reserve(owner: owner) else { return nil }
        defer { complete(ticket) }
        // LUT preview preparation belongs to the same admission as image work.
        // Rejected tab/option changes must not repeatedly build a color cube.
        let effects = effects()
        let work = InspectorImageWork()
        let image: CGImage? = await withTaskCancellationHandler {
            return await withCheckedContinuation { continuation in
                queue.async { [self] in
                    let image: CGImage?
                    if work.isCancelled || !isCurrent(ticket) {
                        image = nil
                    } else if let operation {
                        image = operation(source, effects)
                    } else {
                        image = renderImage(source: source, effects: effects)
                    }
                    continuation.resume(returning: work.isCancelled ? nil : image)
                }
            }
        } onCancel: {
            work.cancel()
            self.deactivate(owner: owner)
        }
        guard !Task.isCancelled, isCurrent(ticket), let image else { return nil }
        return Result(image: image, ticket: ticket)
    }

    private func reserve(owner: UUID) -> MonitorPreviewAdmission.Ticket? {
        lock.lock()
        defer { lock.unlock() }
        return admission.acquire(owner: owner, nowNanoseconds: now())
    }

    private func isCurrent(_ ticket: MonitorPreviewAdmission.Ticket) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return admission.isCurrent(ticket)
    }

    private func complete(_ ticket: MonitorPreviewAdmission.Ticket) {
        lock.lock()
        defer { lock.unlock() }
        admission.complete(ticket)
    }

    /// A caller with its own retained instance may reuse the production display
    /// look on a serial worker. It must not overlap this with `render` on that instance.
    func renderImage(source: CVPixelBuffer, effects: LiveImageEffects) -> CGImage? {
        autoreleasepool {
            guard let look = lookImage(source: source, effects: effects) else { return nil }
            return look.context.createCGImage(look.image, from: look.image.extent)
        }
    }

    /// The display look at most 320 px on its longest side, at the origin, and
    /// the context whose output encoding `renderImage` would produce. A caller
    /// may render it elsewhere with that context (and `outputColorSpace`) and get
    /// the same pixels without a CPU readback.
    func lookImage(source: CVPixelBuffer, effects: LiveImageEffects)
        -> (image: CIImage, context: CIContext, outputColorSpace: CGColorSpace?)?
    {
        let width = CGFloat(CVPixelBufferGetWidth(source))
        let height = CGFloat(CVPixelBufferGetHeight(source))
        guard width > 0, height > 0 else { return nil }
        let scale = min(
            1, AssistInspectorPreviewPolicy.maximumImageDimension / max(width, height))
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        // Downscale before every compositor graph. Preserve native source
        // codes for the tool and source attachments for its identity look.
        let identity = CIImage(cvPixelBuffer: source).transformed(by: transform)
        let codes = CIImage(
            cvPixelBuffer: source, options: LiveMonitorWorkingSpace.imageOptions
        )
        .transformed(by: transform)
        if effects.falseColor {
            PocketFalseColorMap.warm(
                scale: effects.falseColorScale, mode: effects.colorMode,
                hasLUT: effects.lutDimension >= 2)
        }
        let product = LiveMonitorCompositor.applyProduct(
            to: codes, effects: effects, display: identity)
        var result = product.image
        let outputScale = min(
            1,
            AssistInspectorPreviewPolicy.maximumImageDimension
                / max(result.extent.width, result.extent.height))
        if outputScale < 1 {
            result = result.transformed(
                by: CGAffineTransform(scaleX: outputScale, y: outputScale))
        }
        if effects.mirror {
            result = result.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        }
        let extent = result.extent
        guard extent.width.isFinite, extent.height.isFinite,
            extent.width > 0, extent.height > 0
        else { return nil }
        result = result.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        if product.unmanagedBake {
            if cubeContext == nil {
                cubeContext = CIContext(options: LiveMonitorWorkingSpace.contextOptions)
            }
            guard let cubeContext else { return nil }
            return (result, cubeContext, nil)
        }
        if displayContext == nil {
            displayContext = CIContext(options: LiveMonitorWorkingSpace.displayContextOptions)
        }
        guard let displayContext else { return nil }
        // Default output space: sRGB, as `createCGImage` encodes.
        return (result, displayContext, Self.sRGB)
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
}

private final class InspectorImageWork: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
