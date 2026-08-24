import CoreImage
import CoreVideo
import Metal
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// Tight loop for "LUT on a 720p proxy should be cheap." Times the real baker
/// graph, not a stub. Numbers are logged; the assertions catch regressions that
/// would make a 3D cube feel like a 4K grade.
final class LUTPresentPerfTests: XCTestCase {
    func testWorkingRasterCapsFourKBeforeTheCube() {
        XCTAssertEqual(FeedPresentPolicy.maxWorkingWidth, 1440)
        XCTAssertEqual(
            FeedWorkingRaster.targetSize(width: 1280, height: 720).width, 1280,
            "720p proxy must not be rescaled")
        XCTAssertEqual(FeedWorkingRaster.targetSize(width: 3840, height: 2160).width, 1440)
        XCTAssertEqual(FeedWorkingRaster.targetSize(width: 1920, height: 1080).width, 1440)
    }

    func testBakeStaysAtSourceWhenDrawableIsRetinaPanel() throws {
        let source = CGSize(width: 1280, height: 720)
        let panel = CGSize(width: 2796, height: 1290)
        let baked = FeedFrameBaker.bakeSize(source: source, drawable: panel)
        XCTAssertEqual(Int(baked.width.rounded()), 1280)
        XCTAssertEqual(Int(baked.height.rounded()), 720)
    }

    func testLUTBakeOf720pProxyIsCheapRelativeToFourK() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal required")
        }
        let cube = BuiltInLook.mono.cube()
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }

        let baker = FeedFrameBaker(device: device)
        let drawable = CGSize(width: 1920, height: 1080)
        // First GPU compiles the cube pipeline — discard that hitch.
        _ = measureBake(
            baker: baker, drawable: drawable, width: 1280, height: 720, effects: fx, frames: 2,
            skip: 2)
        let proxy = measureBake(
            baker: baker, drawable: drawable, width: 1280, height: 720, effects: fx, frames: 6,
            skip: 0)
        let fourK = measureBake(
            baker: baker, drawable: drawable, width: 3840, height: 2160, effects: fx, frames: 4,
            skip: 0)
        let identity = measureBake(
            baker: baker, drawable: drawable, width: 1280, height: 720,
            effects: LiveImageEffects(), frames: 4, skip: 0)

        print(
            "LUT present ms proxy=\(String(format: "%.2f", proxy)) 4K=\(String(format: "%.2f", fourK)) identity=\(String(format: "%.2f", identity))"
        )
        XCTAssertLessThan(
            proxy, 16,
            "720p LUT bake+GPU must stay inside one 60 Hz frame after warmup (was \(proxy) ms)")
        // Size tests pin the 1440 cap. This timing is a disaster tripwire for CI
        // GPU, not the physical SLO (docs/PERFORMANCE.md). A GitHub macOS runner
        // measured ~48 ms here; 24 ms is a phone, not a shared VM.
        XCTAssertLessThan(
            fourK, 80,
            "4K must cap at 1440 before the cube; bake was \(fourK) ms")
    }

    private func measureBake(
        baker: FeedFrameBaker, drawable: CGSize, width: Int, height: Int,
        effects: LiveImageEffects, frames: Int, skip: Int
    ) -> Double {
        let buffer = ScopeTestBuffers.makeFlatBuffer(code: 78, width: width, height: height)
        let source = CIImage(cvPixelBuffer: buffer, options: LiveMonitorWorkingSpace.imageOptions)
        let display = CIImage(cvPixelBuffer: buffer)
        var total: Double = 0
        var counted = 0
        for i in 0..<(frames + skip) {
            let image =
                effects.lutDimension >= 2
                ? LiveMonitorCompositor.applyProduct(to: source, effects: effects, display: display)
                    .image
                : display
            let done = expectation(description: "bake \(width)x\(height) #\(i)")
            let start = CFAbsoluteTimeGetCurrent()
            baker.scheduleBake(
                image: image, drawableSize: drawable, pixelFormat: .bgra8Unorm, unmanaged: false
            ) {
                if i >= skip {
                    total += CFAbsoluteTimeGetCurrent() - start
                    counted += 1
                }
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
            if let texture = baker.bakedTexture(for: drawable, pixelFormat: .bgra8Unorm) {
                baker.releaseBakedTexture(texture)
            }
        }
        return counted == 0 ? 0 : total / Double(counted) * 1000
    }
}
