import CoreImage
import CoreVideo
import OpenPocketViewCore
import UIKit
import XCTest

@testable import OpenPocketCine

final class WatchRelayTests: XCTestCase {
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

    private static func make420v(y: UInt8, width: Int, height: Int) -> CVPixelBuffer {
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
                yPlane[row * yStride + col] = y
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
