import CoreImage
import CoreVideo
import Metal
import OpenPocketViewCore

/// Cap the raster the LUT cube sees. 720p proxies pass through. A 4K original
/// is export-only — memcpy + CIColorCube at 3840 is why a "trivial" cube hitch.
enum FeedWorkingRaster {
    private static let lock = NSLock()
    private static var pool: [PoolKey: CVPixelBuffer] = [:]
    private static let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(
                mtlDevice: device, options: LiveMonitorWorkingSpace.displayContextOptions)
        }
        return CIContext(options: LiveMonitorWorkingSpace.displayContextOptions)
    }()

    private struct PoolKey: Hashable {
        var width: Int
        var height: Int
    }

    static func targetSize(
        width: Int, height: Int, maxWidth: Int = FeedPresentPolicy.maxWorkingWidth
    ) -> (width: Int, height: Int) {
        guard width > maxWidth, width > 1, height > 1 else { return (width, height) }
        let scale = Double(maxWidth) / Double(width)
        return (maxWidth, max(1, Int((Double(height) * scale).rounded())))
    }

    /// Same buffer when already at or under the working width.
    static func prepared(_ buffer: CVPixelBuffer) -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let target = targetSize(width: width, height: height)
        guard target.width != width else { return buffer }
        return scale(buffer, width: target.width, height: target.height) ?? buffer
    }

    private static func scale(_ buffer: CVPixelBuffer, width: Int, height: Int) -> CVPixelBuffer? {
        lock.lock()
        let key = PoolKey(width: width, height: height)
        let dest = pool[key] ?? makeBuffer(width: width, height: height)
        if pool[key] == nil, let dest { pool[key] = dest }
        lock.unlock()
        guard let dest else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        let scaled = image.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(width) / max(image.extent.width, 1),
                y: CGFloat(height) / max(image.extent.height, 1)))
        context.render(
            scaled, to: dest,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: nil)
        return dest
    }

    private static func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attrs as CFDictionary, &buffer)
        guard status == kCVReturnSuccess else { return nil }
        return buffer
    }
}
