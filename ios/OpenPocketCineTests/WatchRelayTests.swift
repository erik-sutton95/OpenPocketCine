import CoreImage
import CoreVideo
import OpenPocketViewCore
import UIKit
import XCTest

@testable import OpenPocketCine

final class WatchRelayTests: XCTestCase {
    func testResumeKeepsOldAndNewFramesWithinThreeSlots() throws {
        var pump = WatchPreviewPump()
        let old = try (0..<3).map { _ in try XCTUnwrap(pump.reserve()) }
        XCTAssertNil(pump.reserve())

        pump.invalidate()
        XCTAssertTrue(old.allSatisfy { !pump.isCurrent($0) })
        XCTAssertNil(pump.reserve(), "Old encodes/transfers still occupy all three slots")

        XCTAssertTrue(pump.complete(old[0]))
        let current = try XCTUnwrap(pump.reserve())
        XCTAssertTrue(pump.isCurrent(current))
        XCTAssertEqual(pump.inFlightCount, 3)
        XCTAssertFalse(pump.complete(old[0]), "A duplicate ACK must not release another frame")
        XCTAssertNil(pump.reserve())

        pump.invalidate()
        XCTAssertFalse(pump.isCurrent(current))
        XCTAssertNil(pump.reserve(), "Repeated wrist wake must not create extra capacity")
        XCTAssertTrue(pump.complete(old[1]))
        let latest = try XCTUnwrap(pump.reserve())
        XCTAssertTrue(pump.isCurrent(latest))
        XCTAssertEqual(pump.inFlightCount, 3)

        XCTAssertTrue(pump.complete(old[2]))
        XCTAssertTrue(pump.complete(current))
        XCTAssertTrue(pump.complete(latest))
        XCTAssertEqual(pump.inFlightCount, 0)
    }

    func testIdentityThumbnailMirrorsPixelsExactlyOnce() throws {
        let buffer = Self.make420v(y: 32, rightY: 220, width: 64, height: 32)
        try assertMirroredPair(
            original: WatchRelay.thumbnailData(from: buffer, maxWidth: 32, quality: 0.95),
            mirrored: WatchRelay.thumbnailData(
                from: buffer, mirrored: true, maxWidth: 32, quality: 0.95))
    }

    func testCIThumbnailMirrorsDisplayAndLUTPixelsExactlyOnce() throws {
        let extent = CGRect(x: 12, y: 8, width: 64, height: 32)
        let image = CIImage(color: CIColor(red: 0.9, green: 0.9, blue: 0.9))
            .cropped(to: CGRect(x: 44, y: 8, width: 32, height: 32))
            .composited(over: CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)))
            .cropped(to: extent)
        for unmanaged in [false, true] {
            try assertMirroredPair(
                original: WatchRelay.thumbnailData(
                    from: image, unmanaged: unmanaged, maxWidth: 32, quality: 0.95),
                mirrored: WatchRelay.thumbnailData(
                    from: image, unmanaged: unmanaged, mirrored: true,
                    maxWidth: 32, quality: 0.95))
        }
    }

    func testThumbnailFromSolidImageIsNonEmpty() {
        let color = CIColor(red: 0.2, green: 0.4, blue: 0.6)
        let image = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
        let data = WatchRelay.thumbnailData(from: image, maxWidth: 512, quality: 0.5)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 32)
        XCTAssertNotNil(data.flatMap { UIImage(data: $0) })
    }

    func testIdentityThumbnailFromRec709GreyIsNotBlown() {
        // Rec.709 18% grey in video-range 420v (Y = 16 + 0.409×219 ≈ 106).
        // A DeviceRGB CI bake of this buffer was the overexposed wrist preview.
        let buffer = Self.make420v(y: 106, width: 64, height: 32)
        let data = WatchRelay.thumbnailData(from: buffer, maxWidth: 64, quality: 0.95)
        XCTAssertNotNil(data)
        let image = data.flatMap { UIImage(data: $0) }
        XCTAssertNotNil(image)
        let luma = Self.meanLuma(image!)
        XCTAssertGreaterThan(luma, 70, "crushed identity JPEG luma=\(luma)")
        XCTAssertLessThan(luma, 170, "overexposed identity JPEG luma=\(luma)")
    }

    func testWatchShutterCopyIsOperatorFacing() {
        for text in [
            WatchRelayCopy.openOnIPhone,
            WatchRelayCopy.connectFirst,
            WatchRelayCopy.switchToVideo,
            WatchRelayCopy.switchToPhoto,
            WatchRelayCopy.busy,
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("OpenZCine"))
            XCTAssertFalse(text.localizedCaseInsensitiveContains("Nikon"))
        }
    }

    private func assertMirroredPair(
        original: Data?, mirrored: Data?, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let originalCG = try XCTUnwrap(
            original.flatMap { UIImage(data: $0)?.cgImage }, file: file, line: line)
        let mirroredCG = try XCTUnwrap(
            mirrored.flatMap { UIImage(data: $0)?.cgImage }, file: file, line: line)
        XCTAssertEqual(originalCG.width, mirroredCG.width, file: file, line: line)
        XCTAssertEqual(originalCG.height, mirroredCG.height, file: file, line: line)
        let left = CGRect(
            x: 0, y: 0, width: originalCG.width / 2, height: originalCG.height)
        let right = left.offsetBy(dx: CGFloat(originalCG.width / 2), dy: 0)
        let originalLeft = Self.meanLuma(
            UIImage(cgImage: try XCTUnwrap(originalCG.cropping(to: left))))
        let originalRight = Self.meanLuma(
            UIImage(cgImage: try XCTUnwrap(originalCG.cropping(to: right))))
        let mirroredLeft = Self.meanLuma(
            UIImage(cgImage: try XCTUnwrap(mirroredCG.cropping(to: left))))
        let mirroredRight = Self.meanLuma(
            UIImage(cgImage: try XCTUnwrap(mirroredCG.cropping(to: right))))
        XCTAssertGreaterThan(originalRight - originalLeft, 100, file: file, line: line)
        XCTAssertGreaterThan(mirroredLeft - mirroredRight, 100, file: file, line: line)
        XCTAssertEqual(originalLeft, mirroredRight, accuracy: 5, file: file, line: line)
        XCTAssertEqual(originalRight, mirroredLeft, accuracy: 5, file: file, line: line)
    }

    private static func make420v(
        y: UInt8, rightY: UInt8? = nil, width: Int, height: Int
    ) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer)
        precondition(status == kCVReturnSuccess, "CVPixelBufferCreate failed: \(status)")
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!
            .assumingMemoryBound(to: UInt8.self)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        for row in 0..<height {
            for col in 0..<width {
                yPlane[row * yStride + col] = col >= width / 2 ? (rightY ?? y) : y
            }
        }
        let uv = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)!
            .assumingMemoryBound(to: UInt8.self)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        for row in 0..<(height / 2) {
            for col in 0..<(width / 2) {
                uv[row * uvStride + col * 2] = 128
                uv[row * uvStride + col * 2 + 1] = 128
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        CVBufferSetAttachment(
            pixelBuffer, kCVImageBufferColorPrimariesKey,
            kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(
            pixelBuffer, kCVImageBufferTransferFunctionKey,
            kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(
            pixelBuffer, kCVImageBufferYCbCrMatrixKey,
            kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        return pixelBuffer
    }

    private static func meanLuma(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return -1 }
        let width = cg.width
        let height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard
            let ctx = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return -1 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var sum = 0
        let count = width * height
        for i in 0..<count {
            let r = Int(pixels[i * 4])
            let g = Int(pixels[i * 4 + 1])
            let b = Int(pixels[i * 4 + 2])
            sum += (r + g + b) / 3
        }
        return Double(sum) / Double(max(count, 1))
    }
}
