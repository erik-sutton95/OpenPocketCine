#if canImport(CoreVideo)
    import CoreVideo
    import Testing
    @testable import OpenPocketViewCore

    @Suite struct LiveFrameTapTests {
        // MARK: - Buffer factories

        private func makeBiPlanar(
            width: Int, height: Int, tenBit: Bool, fullRange: Bool = false, ioSurface: Bool = false,
            luma: (Int, Int) -> Int, cb: Int, cr: Int
        ) throws -> CVPixelBuffer {
            let format: OSType =
                tenBit
                ? (fullRange
                    ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
                    : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
                : (fullRange
                    ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                    : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
            var attrs: [String: Any] = [:]
            if ioSurface { attrs[kCVPixelBufferIOSurfacePropertiesKey as String] = [:] }
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault, width, height, format, attrs as CFDictionary, &buffer)
            let pixelBuffer = try #require(status == kCVReturnSuccess ? buffer : nil)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
            let lumaBase = try #require(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0))
            let chromaBase = try #require(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1))
            let lumaBPR = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let chromaBPR = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            for y in 0..<height {
                for x in 0..<width {
                    let value = luma(x, y)
                    if tenBit {
                        // 10 bits in the MSBs of 16-bit words.
                        lumaBase.storeBytes(
                            of: UInt16(value << 6), toByteOffset: y * lumaBPR + x * 2,
                            as: UInt16.self)
                    } else {
                        lumaBase.storeBytes(
                            of: UInt8(value), toByteOffset: y * lumaBPR + x, as: UInt8.self)
                    }
                }
            }
            for y in 0..<(height / 2) {
                for x in 0..<(width / 2) {
                    if tenBit {
                        chromaBase.storeBytes(
                            of: UInt16(cb << 6), toByteOffset: y * chromaBPR + x * 4,
                            as: UInt16.self)
                        chromaBase.storeBytes(
                            of: UInt16(cr << 6), toByteOffset: y * chromaBPR + x * 4 + 2,
                            as: UInt16.self)
                    } else {
                        chromaBase.storeBytes(
                            of: UInt8(cb), toByteOffset: y * chromaBPR + x * 2, as: UInt8.self)
                        chromaBase.storeBytes(
                            of: UInt8(cr), toByteOffset: y * chromaBPR + x * 2 + 1, as: UInt8.self)
                    }
                }
            }
            return pixelBuffer
        }

        private func makePacked(
            width: Int, height: Int, rgba: Bool = false, b: UInt8, g: UInt8, r: UInt8
        ) throws -> CVPixelBuffer {
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault, width, height,
                rgba ? kCVPixelFormatType_32RGBA : kCVPixelFormatType_32BGRA,
                nil, &buffer)
            let pixelBuffer = try #require(status == kCVReturnSuccess ? buffer : nil)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
            let base = try #require(CVPixelBufferGetBaseAddress(pixelBuffer))
            let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * bpr + x * 4
                    if rgba {
                        bytes[i] = r
                        bytes[i + 1] = g
                        bytes[i + 2] = b
                        bytes[i + 3] = 255
                    } else {
                        bytes[i] = b
                        bytes[i + 1] = g
                        bytes[i + 2] = r
                        bytes[i + 3] = 255
                    }
                }
            }
            return pixelBuffer
        }

        private func lumaBytes(_ tap: (bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int))
            -> [UInt8]
        {
            // Neutral-chroma taps have r == g == b; green channel stands in for luma.
            stride(from: 1, to: tap.bytes.count, by: 4).map { tap.bytes[$0] }
        }

        // MARK: - Range expansion (the axis contract)

        @Test func planar420LegalBlackExpandsToCurveZero() throws {
            // The camera writes legal-scaled curve codes; the tap recovers the
            // curve fraction: video-range Y 16 → byte 0.
            let buffer = try makeBiPlanar(
                width: 32, height: 16, tenBit: false, luma: { _, _ in 16 }, cb: 128, cr: 128)
            let tap = try #require(LiveFrameTap.copyBGRA8(buffer, maxWidth: 32))
            for value in lumaBytes(tap) {
                #expect(value == 0, "legal floor is curve 0")
            }
        }

        @Test func tenBitLegalAnchorsExpandToPaperBytes() throws {
            // Legal-scaled D-Log2 anchors on the wire: black 119, grey 331, clip 940.
            // Expanded curve bytes: (C−64)×255/876 → 16, 78, 255 — the papers' own axis.
            let buffer = try makeBiPlanar(
                width: 48, height: 16, tenBit: true,
                luma: { x, _ in x < 16 ? 119 : (x < 32 ? 331 : 940) }, cb: 512, cr: 512)
            let tap = try #require(LiveFrameTap.copyBGRA8(buffer, maxWidth: 48))
            let values = Set(lumaBytes(tap))
            #expect(values.contains(16), "D-Log2 black anchor byte (encode(0)×255 ≈ 15.95)")
            #expect(values.contains(78), "D-Log2 grey anchor byte (encode(0.18)×255 ≈ 77.77)")
            #expect(values.contains(255), "curve top")
            #expect(values.count == 3)
        }

        @Test func tenBitIOSurfaceReadsRealPlanes() throws {
            // The historical bug: IOSurface-backed VT output tapping to zeros.
            let buffer = try makeBiPlanar(
                width: 64, height: 32, tenBit: true, ioSurface: true,
                luma: { _, _ in 331 }, cb: 512, cr: 512)
            #expect(LiveFrameTap.isIOSurfaceBacked(buffer))
            let tap = try #require(LiveFrameTap.copyBGRA8(buffer, maxWidth: 64))
            #expect(LiveFrameTap.maxRGB(tap.bytes) > 0)
            for value in lumaBytes(tap) {
                #expect(value == 78)
            }
        }

        @Test func fullRangeChromaAppliesBT709() throws {
            // Full-range 8-bit passes through: Y 128, Cb +50 → B ≈ 221, G ≈ 119, R = 128.
            let buffer = try makeBiPlanar(
                width: 16, height: 16, tenBit: false, fullRange: true,
                luma: { _, _ in 128 }, cb: 178, cr: 128)
            let tap = try #require(LiveFrameTap.copyBGRA8(buffer, maxWidth: 16))
            #expect(abs(Int(tap.bytes[0]) - 221) <= 1)
            #expect(abs(Int(tap.bytes[1]) - 119) <= 1)
            #expect(abs(Int(tap.bytes[2]) - 128) <= 1)
        }

        @Test func videoRangeChromaExpands() throws {
            // Video-range 8-bit: Y' = (128−16)×255/219 ≈ 130.4, Cb' = (178−128)×255/224 ≈ 56.9
            // → B ≈ 236, G ≈ 120, R ≈ 130.
            let buffer = try makeBiPlanar(
                width: 16, height: 16, tenBit: false,
                luma: { _, _ in 128 }, cb: 178, cr: 128)
            let tap = try #require(LiveFrameTap.copyBGRA8(buffer, maxWidth: 16))
            #expect(abs(Int(tap.bytes[0]) - 236) <= 1)
            #expect(abs(Int(tap.bytes[1]) - 120) <= 1)
            #expect(abs(Int(tap.bytes[2]) - 130) <= 1)
        }

        @Test func tenBitGradientOccupiesManyLevels() throws {
            let buffer = try makeBiPlanar(
                width: 256, height: 16, tenBit: true,
                luma: { x, _ in 64 + (940 - 64) * x / 255 }, cb: 512, cr: 512)
            let tap = try #require(LiveFrameTap.copyBGRA8(buffer, maxWidth: 256))
            let distinct = Set(lumaBytes(tap))
            #expect(distinct.count > 100, "gradient must not collapse")
            #expect(distinct.min() == 0)
            #expect(distinct.max() == 255)
        }

        // MARK: - Geometry

        @Test func largeFrameScalesToTapWidth() throws {
            let buffer = try makeBiPlanar(
                width: 3840, height: 2160, tenBit: true,
                luma: { x, _ in 64 + x % 800 }, cb: 512, cr: 512)
            let tap = try #require(LiveFrameTap.copyBGRA8(buffer, maxWidth: 200))
            #expect(tap.width <= 208)
            #expect(tap.height <= 120)
            #expect(tap.bytesPerRow == tap.width * 4)
            #expect(tap.bytes.count == tap.width * tap.height * 4)
        }

        // MARK: - Packed formats

        @Test func packedBGRAStillWorks() throws {
            let buffer = try makePacked(width: 32, height: 16, b: 10, g: 20, r: 30)
            let tap = try #require(LiveFrameTap.copyBGRA8(buffer, maxWidth: 32))
            #expect(tap.bytes[0] == 10)
            #expect(tap.bytes[1] == 20)
            #expect(tap.bytes[2] == 30)
            #expect(LiveFrameTap.minRGB(tap.bytes) == 10)
            #expect(LiveFrameTap.maxRGB(tap.bytes) == 30)
        }

        // MARK: - Diagnostics helpers

        @Test func fourCCNamesTheFormat() throws {
            let buffer = try makeBiPlanar(
                width: 16, height: 16, tenBit: true, luma: { _, _ in 512 }, cb: 512, cr: 512)
            #expect(LiveFrameTap.fourCC(buffer) == "x420")
        }
    }
#endif
