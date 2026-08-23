import CoreVideo
import Foundation
import OpenPocketViewCore

/// Shared synthetic-buffer factories for the scope-pipeline tests.
///
/// Everything is **legal-scaled**: the camera writes `container10 = 64 + curve × 876`
/// in a tv-range container, and `LiveFrameTap` expands that back to curve
/// fractions. So D-Log2 black is Y10 119 (→ tap byte 16), 18% grey is Y10 331
/// (→ 78), clip is Y10 940 (→ 255). Neutral chroma is 512 (10-bit) / 128 (8-bit).
/// BGRA buffers carry tap-domain curve bytes directly.
enum ScopeTestBuffers {
    /// Legal-scaled 10-bit container code for a curve fraction.
    static func legal10(_ curveFraction: Double) -> Int {
        Int((64 + curveFraction * 876).rounded())
    }

    /// D-Log2 wire anchors (legal-scaled): black 119, grey 331, clip 940.
    static let dlog2Black10 = 119
    static let dlog2Grey10 = 331
    static let clip10 = 940

    // MARK: - BGRA (tap-domain curve bytes)

    static func makeBGRA(
        width: Int = 128, height: Int = 72, code: (Int, Int) -> UInt8
    ) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            fatalError("CVPixelBufferCreate failed: \(status)")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let value = code(x, y)
                let p = base.advanced(by: y * stride + x * 4)
                p[0] = value
                p[1] = value
                p[2] = value
                p[3] = 255
            }
        }
        return buffer
    }

    static func makeFlatBuffer(code: UInt8, width: Int = 128, height: Int = 72) -> CVPixelBuffer {
        makeBGRA(width: width, height: height) { _, _ in code }
    }

    static func makeEdgeBuffer(width: Int = 128, height: Int = 72) -> CVPixelBuffer {
        makeBGRA(width: width, height: height) { x, _ in x > width / 2 ? 255 : 16 }
    }

    /// Metal-compatible IOSurface BGRA. `filled == false` when the host cannot
    /// CPU-write the surface (skip hardware-dependent asserts there).
    static func makeIOSurfaceBGRA(width: Int, height: Int, left: UInt8, right: UInt8)
        -> (buffer: CVPixelBuffer, filled: Bool)
    {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attrs as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            fatalError("IOSurface BGRA create failed: \(status)")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            return (buffer, false)
        }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let src = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let on = x < width / 2 ? left : right
                let p = src.advanced(by: y * stride + x * 4)
                p[0] = on
                p[1] = on
                p[2] = on
                p[3] = 255
            }
        }
        return (buffer, true)
    }

    // MARK: - 10-bit x420 (legal-scaled wire codes, MSB-aligned words)

    /// `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` with per-column 10-bit
    /// luma codes and neutral chroma 512. Stores `value << 6` (MSB alignment).
    /// `nil` when the host cannot create the format.
    static func makeX420(
        width: Int, height: Int, ioSurface: Bool = false, luma10: (Int, Int) -> Int
    ) -> CVPixelBuffer? {
        var attrs: [String: Any] = [:]
        if ioSurface {
            attrs[kCVPixelBufferIOSurfacePropertiesKey as String] = [:] as [String: Any]
        }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            attrs.isEmpty ? nil : attrs as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
            let chromaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)
        else { return nil }
        let lumaBPR = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let chromaBPR = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        for y in 0..<height {
            for x in 0..<width {
                lumaBase.storeBytes(
                    of: UInt16(luma10(x, y) << 6),
                    toByteOffset: y * lumaBPR + x * 2, as: UInt16.self)
            }
        }
        let chromaH = CVPixelBufferGetHeightOfPlane(buffer, 1)
        let chromaW = CVPixelBufferGetWidthOfPlane(buffer, 1)
        for y in 0..<chromaH {
            for x in 0..<chromaW {
                chromaBase.storeBytes(
                    of: UInt16(512 << 6), toByteOffset: y * chromaBPR + x * 4, as: UInt16.self)
                chromaBase.storeBytes(
                    of: UInt16(512 << 6), toByteOffset: y * chromaBPR + x * 4 + 2, as: UInt16.self)
            }
        }
        return buffer
    }

    // MARK: - 8-bit 420v (video-range luma, neutral chroma 128)

    static func make420v(width: Int, height: Int, leftY: UInt8, rightY: UInt8) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            fatalError("420v create failed: \(status)")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(
            to: UInt8.self)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        for y in 0..<height {
            for x in 0..<width {
                yBase[y * yStride + x] = x < width / 2 ? leftY : rightY
            }
        }
        let uv = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!.assumingMemoryBound(to: UInt8.self)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let uvH = CVPixelBufferGetHeightOfPlane(buffer, 1)
        let uvW = CVPixelBufferGetWidthOfPlane(buffer, 1)
        for y in 0..<uvH {
            for x in 0..<uvW {
                uv[y * uvStride + x * 2] = 128
                uv[y * uvStride + x * 2 + 1] = 128
            }
        }
        return buffer
    }
}
