import XCTest

@testable import OpenPocketCine

final class FeedUpscaleTests: XCTestCase {
    func testOfferedUpscalersAreRunnableAndTheDefaultIsTheFastFloor() {
        let offered = FeedUpscaler.supportedOnThisDevice
        XCTAssertTrue(offered.contains(.off))
        XCTAssertTrue(offered.contains(.lanczos))
        #if targetEnvironment(simulator)
            XCTAssertEqual(offered, [.off, .lanczos])
        #endif
        // The fast floor is the default even where better upscalers exist.
        XCTAssertEqual(FeedUpscaler.supported(or: nil), .lanczos)
        XCTAssertTrue(FeedUpscaler.supported(or: nil).isSupportedOnThisDevice)
        XCTAssertEqual(FeedUpscaler.supported(or: .lanczos), .lanczos)
        XCTAssertEqual(FeedUpscaler.lanczos.rawValue, "Fast")
        for upscaler in offered {
            XCTAssertTrue(
                upscaler.isSupportedOnThisDevice, "\(upscaler) is offered but not runnable")
            XCTAssertEqual(
                FeedUpscaler.supported(or: upscaler), upscaler,
                "\(upscaler) is runnable, so a stored choice keeps it")
        }
        for upscaler in FeedUpscaler.allCases {
            XCTAssertTrue(
                FeedUpscaler.supported(or: upscaler).isSupportedOnThisDevice,
                "a stored \(upscaler) this device cannot run resolves to one it can")
        }
    }

    func testSuperResolutionShrinksABakeThatOutsizesTheProcessor() {
        let input = FeedUpscaler.superResolutionInputSize(
            source: (1_024, 576), target: (2_347, 1_320), scale: 0, maximum: (960, 960))
        XCTAssertEqual(input.width, 960)
        XCTAssertEqual(input.height, 540)
        XCTAssertEqual(
            Double(input.width) / Double(input.height), 1_024.0 / 576.0, accuracy: 0.01)
    }

    func testSuperResolutionLeavesASourceInsideTheLimitAlone() {
        let input = FeedUpscaler.superResolutionInputSize(
            source: (640, 480), target: (1_280, 960), scale: 2, maximum: (960, 960))
        XCTAssertEqual(input.width, 640)
        XCTAssertEqual(input.height, 480)
    }

    func testSuperResolutionShrinksToWhicheverDimensionBindsFirst() {
        let input = FeedUpscaler.superResolutionInputSize(
            source: (1_000, 2_000), target: (4_000, 8_000), scale: 0, maximum: (1_440, 1_080))
        XCTAssertEqual(input.height, 1_080)
        XCTAssertEqual(input.width, 540)
    }

    func testMpsFitTransformMatchesOpenZCinePositiveScale() {
        let fill = FeedPresentScaler.mpsFitTransform(
            sourceWidth: 1280, sourceHeight: 720, targetWidth: 2560, targetHeight: 1440)
        XCTAssertEqual(fill.scaleX, 2, accuracy: 0.0001)
        XCTAssertEqual(fill.scaleY, 2, accuracy: 0.0001)
        XCTAssertEqual(fill.translateX, 0, accuracy: 0.0001)
        XCTAssertEqual(fill.translateY, 0, accuracy: 0.0001)

        let letterbox = FeedPresentScaler.mpsFitTransform(
            sourceWidth: 1280, sourceHeight: 720, targetWidth: 2560, targetHeight: 1600)
        XCTAssertEqual(letterbox.scaleX, 2, accuracy: 0.0001)
        XCTAssertGreaterThan(letterbox.scaleY, 0)
        XCTAssertEqual(letterbox.scaleY, letterbox.scaleX, accuracy: 0.0001)
        XCTAssertEqual(letterbox.translateX, 0, accuracy: 0.0001)
        XCTAssertEqual(letterbox.translateY, 80, accuracy: 0.0001)
    }

    func testMetalBakeFlipPutsCITopOnMetalRowZero() {
        let extent = CGRect(x: 0, y: 0, width: 100, height: 80)
        let t = FeedFrameBaker.metalOriginTransform(extent: extent, bakeWidth: 100, bakeHeight: 80)
        // CI top-center (y = height) lands at Metal y = 0.
        let top = CGPoint(x: 50, y: 80).applying(t)
        XCTAssertEqual(top.x, 50, accuracy: 0.001)
        XCTAssertEqual(top.y, 0, accuracy: 0.001)
        let bottom = CGPoint(x: 50, y: 0).applying(t)
        XCTAssertEqual(bottom.y, 80, accuracy: 0.001)
    }
}
