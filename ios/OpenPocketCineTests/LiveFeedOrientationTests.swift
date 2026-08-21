import CoreImage
import Metal
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// LUT / peaking / false colour / zebra share `needsGPUFeed` → `FeedFrameBaker` →
/// texel-for-texel blit. A leftover `scaleY: -1` anywhere in that chain inverted
/// all four versus the clean HEVC layer. `LiveFeedPresent` is gone — the present
/// is now a plain blit — so the testable seam is the baker's texture orientation.
final class LiveFeedOrientationTests: XCTestCase {
    func testGPUAssistsShareOneFeedFlag() {
        XCTAssertTrue(Self.peaking.needsGPUFeed)
        XCTAssertTrue(Self.zebra.needsGPUFeed)
        XCTAssertTrue(Self.falseColor.needsGPUFeed)
        XCTAssertTrue(Self.lut.needsGPUFeed)
        XCTAssertFalse(LiveImageEffects().needsGPUFeed)
        XCTAssertFalse(LiveImageEffects().needsSample)
        var face = LiveImageEffects()
        face.faceAF = true
        XCTAssertTrue(face.needsSample)
        XCTAssertFalse(face.needsGPUFeed)
        XCTAssertTrue(Self.peaking.needsOverlayFeed)
        XCTAssertTrue(Self.zebra.needsOverlayFeed)
        XCTAssertTrue(Self.falseColor.needsOverlayFeed)
        XCTAssertFalse(Self.lut.needsOverlayFeed)
        XCTAssertFalse(Self.falseColor.replacesIdentityFeed)
        XCTAssertTrue(Self.lut.replacesIdentityFeed)
    }

    func testCompositorKeepsVerticalMarkerForEveryGPUAssist() {
        Self.warmFalseColorCubes()
        let source = Self.verticalMarker()
        XCTAssertTrue(Self.bandEdgeIsOnCITop(source))
        for (name, fx) in [
            ("peaking", Self.peaking),
            ("zebra", Self.zebra),
            ("false color", Self.falseColor),
            ("LUT", Self.lut),
        ] {
            let output = LiveMonitorCompositor.apply(to: source, effects: fx)
            XCTAssertEqual(output.extent, source.extent, "\(name) must not change extent")
            // Luma is the wrong proxy here: IRE false colour remaps paper white/black
            // onto WAVE bands whose luma can invert while the raster stays upright.
            // The white-band *edge* is the orientation signal.
            XCTAssertTrue(
                Self.bandEdgeIsOnCITop(output),
                "\(name) must not invert the raster — colour science stays, orientation stays")
        }
        for (name, fx) in [
            ("peaking overlay", Self.peaking),
            ("zebra overlay", Self.zebra),
            ("false color overlay", Self.falseColor),
        ] {
            let overlay = LiveMonitorCompositor.assistOverlay(from: source, effects: fx)
            XCTAssertEqual(overlay.extent, source.extent, "\(name) must not change extent")
        }
    }

    func testBakerRoundTripKeepsVerticalMarker() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal required")
        }
        let baker = FeedFrameBaker(device: device)
        let source = Self.verticalMarker()
        let drawable = CGSize(width: 64, height: 64)
        let done = expectation(description: "bake")
        baker.scheduleBake(
            image: source, drawableSize: drawable, pixelFormat: .bgra8Unorm
        ) {
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        guard let texture = baker.bakedTexture(for: drawable, pixelFormat: .bgra8Unorm) else {
            XCTFail("baker must publish a texture")
            return
        }
        defer { baker.releaseBakedTexture(texture) }
        // The present path blits this texture. CIImage(mtlTexture:) origin has
        // moved across Xcode versions, so orientation is read from Metal rows.
        XCTAssertTrue(
            Self.metalTopIsBrighter(texture: texture, device: device),
            "bake must land in drawable orientation — a leftover flip inverts the feed")
    }

    private static var peaking: LiveImageEffects {
        var fx = LiveImageEffects()
        fx.peaking = true
        return fx
    }

    private static var zebra: LiveImageEffects {
        var fx = LiveImageEffects()
        fx.zebra = true
        fx.zebraHighlight = true
        fx.zebraMidtone = false
        return fx
    }

    private static var falseColor: LiveImageEffects {
        var fx = LiveImageEffects()
        fx.falseColor = true
        fx.falseColorScale = .ire
        return fx
    }

    private static var lut: LiveImageEffects {
        let cube = BuiltInLook.mono.cube()
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        return fx
    }

    /// White band on the CI top (high y), black below — a vertical flip moves the energy down.
    private static func verticalMarker(width: CGFloat = 32, height: CGFloat = 32) -> CIImage {
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let band = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
            .cropped(to: CGRect(x: 0, y: height * 0.75, width: width, height: height * 0.25))
        return band.composited(over: black)
    }

    /// False colour cubes are async. Earlier tests in a full suite already warm
    /// them; isolation still needs a short wait so IRE paint actually runs.
    private static func warmFalseColorCubes() {
        PocketFalseColorMap.warm(scale: .ire, mode: .normal)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if PocketFalseColorMap.overlayPaintData(scale: .ire, mode: .normal) != nil,
                PocketFalseColorMap.overlayWeightData(scale: .ire, mode: .normal) != nil
            {
                return
            }
            usleep(20_000)
        }
    }

    /// White band is the CI top quarter, so the luma/chroma step sits above mid-Y.
    /// A vertical flip moves that step into the bottom half.
    private static func bandEdgeIsOnCITop(_ image: CIImage) -> Bool {
        let context = CIContext(options: [.cacheIntermediates: false])
        let e = image.extent
        let height = Int(e.height.rounded(.down))
        guard height > 4, e.width > 2 else { return false }
        var means: [Float] = []
        means.reserveCapacity(height)
        for row in 0..<height {
            let y = e.minY + CGFloat(row)
            means.append(
                meanRGB(
                    image,
                    rect: CGRect(x: e.minX, y: y, width: e.width, height: 1),
                    context: context))
        }
        var bestRow = 0
        var bestMag: Float = 0
        for i in 1..<height {
            let mag = abs(means[i] - means[i - 1])
            if mag > bestMag {
                bestMag = mag
                bestRow = i
            }
        }
        guard bestMag > 0.04 else { return false }
        return CGFloat(bestRow) > e.height / 2
    }

    /// CI top-center maps to Metal y = 0 (`FeedFrameBaker.metalOriginTransform`).
    private static func metalTopIsBrighter(texture: MTLTexture, device: MTLDevice) -> Bool {
        guard let queue = device.makeCommandQueue(),
            let commandBuffer = queue.makeCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            XCTFail("Metal blit readback unavailable")
            return false
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let readable = device.makeTexture(descriptor: descriptor) else {
            XCTFail("shared Metal texture unavailable")
            return false
        }
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
            to: readable,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            XCTFail("Metal blit failed: \(error.localizedDescription)")
            return false
        }
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        readable.getBytes(
            &bytes, bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        func rowMean(_ rows: Range<Int>) -> Float {
            var sum: Float = 0
            var count = 0
            for row in rows {
                for x in 0..<width {
                    let i = (row * width + x) * 4
                    let b = Float(bytes[i])
                    let g = Float(bytes[i + 1])
                    let r = Float(bytes[i + 2])
                    sum += (r + g + b) / 3
                    count += 1
                }
            }
            return sum / Float(max(count, 1)) / 255
        }
        return rowMean(0..<(height / 2)) > rowMean((height / 2)..<height) + 0.08
    }

    private static func meanRGB(_ image: CIImage, rect: CGRect, context: CIContext) -> Float {
        let w = max(1, Int(rect.width.rounded(.down)))
        let h = max(1, Int(rect.height.rounded(.down)))
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        context.render(
            image, toBitmap: &bytes, rowBytes: w * 4,
            bounds: CGRect(x: rect.minX, y: rect.minY, width: CGFloat(w), height: CGFloat(h)),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var sum: Float = 0
        let pixels = w * h
        for i in 0..<pixels {
            let r = Float(bytes[i * 4])
            let g = Float(bytes[i * 4 + 1])
            let b = Float(bytes[i * 4 + 2])
            sum += (r + g + b) / 3
        }
        return sum / Float(max(pixels, 1)) / 255
    }
}
