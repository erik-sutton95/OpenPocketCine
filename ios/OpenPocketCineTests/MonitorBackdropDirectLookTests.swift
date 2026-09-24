import CoreImage
import CoreVideo
import MonitorPresentation
import OpenPocketViewCore
import XCTest

@testable import MonitorUI
@testable import OpenPocketCine

/// The single-source fast path renders the look straight into the blur canvas.
/// It must match the CGImage path (look readback, then canvas) for managed and
/// unmanaged looks, apart from the old path's 8-bit look intermediate.
final class MonitorBackdropDirectLookTests: XCTestCase {
    func testDirectLookMatchesTheCGImagePathForIdentityAndLUT() throws {
        let cube = BuiltInLook.mono.cube()
        var lut = LiveImageEffects()
        lut.lutDimension = cube.size
        lut.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        for effects in [LiveImageEffects(), lut] {
            let source = Self.colorBars()
            let looks = AssistInspectorImageRenderer()
            let renderer = MonitorBackdropRenderer()
            let canvas = CGSize(width: 440, height: 300)
            let frame = CGRect(x: 20, y: 40, width: 400, height: 225)
            let clip = CGRect(x: 0, y: 30, width: 440, height: 240)
            let look = try XCTUnwrap(looks.lookImage(source: source, effects: effects))
            let direct = try XCTUnwrap(
                renderer.render(
                    canvasSize: canvas, look: look.image, frame: frame, clip: clip,
                    lookContext: look.context, outputColorSpace: look.outputColorSpace,
                    surroundRGB: 0x224466))
            let image = try XCTUnwrap(looks.renderImage(source: source, effects: effects))
            let reference = try XCTUnwrap(
                renderer.render(
                    canvasSize: canvas,
                    layers: [MonitorBackdropLayer(image: image, frame: frame, clip: clip)],
                    surroundRGB: 0x224466))
            for role in MonitorGlassDensity.allCases {
                let a = try Self.pixels(XCTUnwrap(direct.image(for: role)))
                let b = try Self.pixels(XCTUnwrap(reference.image(for: role)))
                XCTAssertEqual(a.count, b.count)
                let worst = zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0
                XCTAssertLessThanOrEqual(worst, 3, "\(role) lut=\(effects.lutDimension)")
            }
        }
    }

    private static func colorBars() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixels = buffer!
        CVPixelBufferLockBaseAddress(pixels, [])
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
        let bars: [(UInt8, UInt8, UInt8)] = [
            (230, 40, 40), (40, 200, 60), (50, 80, 220), (220, 200, 40), (30, 30, 30),
        ]
        for y in 0..<180 {
            for x in 0..<320 {
                let (r, g, b) = bars[min(bars.count - 1, x * bars.count / 320)]
                let p = base.advanced(by: y * stride + x * 4)
                p[0] = y < 90 ? b : b / 2
                p[1] = y < 90 ? g : g / 2
                p[2] = y < 90 ? r : r / 2
                p[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return pixels
    }

    private static func pixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
}
