#if canImport(CoreVideo)
    import CoreVideo
    import Testing

    @testable import OpenPocketViewCore

    struct GimbalStickLumaTests {
        /// 64×64 video-range 420v frame: left half black (Y 16), right half white (Y 235).
        private func splitFrame() -> CVPixelBuffer {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(
                nil, 64, 64, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer)
            let frame = buffer!
            CVPixelBufferLockBaseAddress(frame, [])
            let base = CVPixelBufferGetBaseAddressOfPlane(frame, 0)!
            let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(frame, 0)
            for y in 0..<64 {
                for x in 0..<64 {
                    base.storeBytes(
                        of: UInt8(x < 32 ? 16 : 235), toByteOffset: y * rowBytes + x, as: UInt8.self)
                }
            }
            CVPixelBufferUnlockBaseAddress(frame, [])
            return frame
        }

        @Test func stickInkFollowsThePictureUnderIt() {
            let frame = splitFrame()
            let dark = GimbalStickLuma.mean(frame, region: .init(x: 0, y: 0, width: 0.4, height: 1))
            let bright = GimbalStickLuma.mean(
                frame, region: .init(x: 0.6, y: 0, width: 0.4, height: 1))
            #expect(dark == 0)
            #expect(bright == 1)
            #expect(!GimbalStick.prefersDarkChrome(luma: dark, previous: false))
            #expect(GimbalStick.prefersDarkChrome(luma: bright, previous: false))
            // Hysteresis: mid-grey keeps whichever ink is already showing.
            #expect(GimbalStick.prefersDarkChrome(luma: 0.4, previous: true))
            #expect(!GimbalStick.prefersDarkChrome(luma: 0.4, previous: false))
            #expect(GimbalStick.prefersDarkChrome(luma: nil, previous: true))
        }

        @Test func sampleRegionIsTheStickInsideTheFeed() {
            let region = GimbalStick.chromeSampleRegion(
                stick: .init(x: 150, y: 50, width: 100, height: 100),
                feed: .init(x: 0, y: 0, width: 200, height: 200))
            #expect(region == .init(x: 0.75, y: 0.25, width: 0.25, height: 0.5))
            #expect(
                GimbalStick.chromeSampleRegion(
                    stick: .init(x: 300, y: 0, width: 50, height: 50),
                    feed: .init(x: 0, y: 0, width: 200, height: 200)) == nil)
        }
    }
#endif
