import CoreImage
import CoreVideo
import Foundation

/// Inspector-only image work: at most one admitted source buffer, no pending
/// queue, and no display/decoder attachment. A busy job drops a request; the
/// view's next bounded tick reads the newest source instead of catching up.
final class AssistInspectorImageRenderer: @unchecked Sendable {
    typealias RenderOperation = @Sendable (CVPixelBuffer, LiveImageEffects) -> CGImage?

    private let queue = DispatchQueue(label: "opv.assist-inspector", qos: .utility)
    private let admission = NSLock()
    private var busy = false
    private let operation: RenderOperation?
    // These contexts are used only on queue, never by the live present worker.
    private var displayContext: CIContext?
    private var cubeContext: CIContext?

    init(operation: RenderOperation? = nil) {
        self.operation = operation
    }

    func render(source: CVPixelBuffer, effects: LiveImageEffects) async -> CGImage? {
        let work = InspectorImageWork()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return nil }
            return await withCheckedContinuation { continuation in
                guard reserve() else {
                    continuation.resume(returning: nil)
                    return
                }
                queue.async { [self] in
                    let image: CGImage?
                    if work.isCancelled {
                        image = nil
                    } else if let operation {
                        image = operation(source, effects)
                    } else {
                        image = renderImage(source: source, effects: effects)
                    }
                    release()
                    continuation.resume(returning: work.isCancelled ? nil : image)
                }
            }
        } onCancel: {
            work.cancel()
        }
    }

    private func reserve() -> Bool {
        admission.lock()
        defer { admission.unlock() }
        guard !busy else { return false }
        busy = true
        return true
    }

    private func release() {
        admission.lock()
        busy = false
        admission.unlock()
    }

    private func renderImage(source: CVPixelBuffer, effects: LiveImageEffects) -> CGImage? {
        autoreleasepool {
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
            let context: CIContext
            if product.unmanagedBake {
                if cubeContext == nil {
                    cubeContext = CIContext(options: LiveMonitorWorkingSpace.contextOptions)
                }
                guard let cubeContext else { return nil }
                context = cubeContext
            } else {
                if displayContext == nil {
                    displayContext = CIContext(
                        options: LiveMonitorWorkingSpace.displayContextOptions)
                }
                guard let displayContext else { return nil }
                context = displayContext
            }
            return context.createCGImage(result, from: result.extent)
        }
    }
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
