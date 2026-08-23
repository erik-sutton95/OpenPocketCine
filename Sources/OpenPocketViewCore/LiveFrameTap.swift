#if canImport(CoreVideo)
    import CoreVideo
    import Foundation
    #if canImport(CoreImage)
        import CoreGraphics
        // Xcode 16.4 treats CIContext as non-Sendable; 6.2 does not. Preconcurrency
        // keeps the static fallback compiling on both without a spurious annotation.
        @preconcurrency import CoreImage
    #endif

    /// The scope tap: CVPixelBuffer → tightly packed BGRA8 analysis buffer,
    /// ≤ `maxWidth` wide, nearest-neighbour.
    ///
    /// Direct CPU plane reads — no CoreImage, no GPU round-trip, no implicit
    /// colour management. `CVPixelBufferLockBaseAddress` syncs IOSurface-backed VT
    /// output; planar formats are read via `GetBaseAddressOfPlane` (plain
    /// `GetBaseAddress` on a planar buffer is a header, not pixels — the source of
    /// the historical "IOSurface taps to zeros" bug).
    ///
    /// Output bytes are **curve fractions** (`byte/255` = normalized log/OETF
    /// code). The camera writes legal-range scaled codes (`container10 =
    /// 64 + curve × 876`, measured on Pocket 4P recordings), so video-range
    /// buffers are expanded back here — the ONLY place container knowledge lives.
    /// D-Log2 black → byte 16, 18% grey → 78, clip → 255; official DJI `.cube`
    /// LUTs receive exactly the domain they are authored for.
    public enum LiveFrameTap {
        public static func copyBGRA8(_ buffer: CVPixelBuffer, maxWidth: Int) -> (
            bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int
        )? {
            let srcW = CVPixelBufferGetWidth(buffer)
            let srcH = CVPixelBufferGetHeight(buffer)
            guard srcW >= 8, srcH >= 8 else { return nil }
            let step = max(1, srcW / max(8, maxWidth))
            let width = max(8, srcW / step)
            let height = max(8, srcH / step)

            guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
                return nil
            }

            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let format = CVPixelBufferGetPixelFormatType(buffer)
            let ok: Bool
            switch format {
            case kCVPixelFormatType_32BGRA, kCVPixelFormatType_32RGBA:
                ok = readPacked32(
                    buffer, into: &bytes, width: width, height: height, step: step,
                    bgra: format == kCVPixelFormatType_32BGRA)
            case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
                ok = readBiPlanar(
                    buffer, into: &bytes, width: width, height: height, step: step,
                    tenBit: false, videoRange: true)
            case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
                ok = readBiPlanar(
                    buffer, into: &bytes, width: width, height: height, step: step,
                    tenBit: false, videoRange: false)
            case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
                ok = readBiPlanar(
                    buffer, into: &bytes, width: width, height: height, step: step,
                    tenBit: true, videoRange: true)
            case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
                ok = readBiPlanar(
                    buffer, into: &bytes, width: width, height: height, step: step,
                    tenBit: true, videoRange: false)
            default:
                ok = false
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            if ok { return (bytes, width, height, width * 4) }
            // Packed / compressed VT formats, or a planar buffer whose CPU
            // planes did not map. Unlock first — Core Image cannot attach
            // while the buffer is still locked.
            return ciFallback(buffer, maxWidth: maxWidth)
        }

        public static func fourCC(_ buffer: CVPixelBuffer) -> String {
            let format = CVPixelBufferGetPixelFormatType(buffer)
            let chars = [
                UInt8((format >> 24) & 0xFF), UInt8((format >> 16) & 0xFF),
                UInt8((format >> 8) & 0xFF), UInt8(format & 0xFF),
            ]
            return String(bytes: chars, encoding: .ascii) ?? String(format)
        }

        public static func maxRGB(_ bytes: [UInt8]) -> UInt8 {
            var maxC: UInt8 = 0
            var i = 0
            while i + 2 < bytes.count {
                maxC = max(maxC, bytes[i], bytes[i + 1], bytes[i + 2])
                i += 4
            }
            return maxC
        }

        public static func minRGB(_ bytes: [UInt8]) -> UInt8 {
            var minC: UInt8 = 255
            var i = 0
            while i + 2 < bytes.count {
                minC = min(minC, bytes[i], bytes[i + 1], bytes[i + 2])
                i += 4
            }
            return minC
        }

        public static func isIOSurfaceBacked(_ buffer: CVPixelBuffer) -> Bool {
            CVPixelBufferGetIOSurface(buffer) != nil
        }

        // MARK: - Readers

        private static func readPacked32(
            _ buffer: CVPixelBuffer, into bytes: inout [UInt8],
            width: Int, height: Int, step: Int, bgra: Bool
        ) -> Bool {
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
            let srcW = CVPixelBufferGetWidth(buffer)
            let srcH = CVPixelBufferGetHeight(buffer)
            let srcBPR = CVPixelBufferGetBytesPerRow(buffer)
            let src = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                let sy = min(srcH - 1, y * step)
                let row = sy * srcBPR
                for x in 0..<width {
                    let sx = min(srcW - 1, x * step)
                    let s = row + sx * 4
                    let d = (y * width + x) * 4
                    if bgra {
                        bytes[d] = src[s]
                        bytes[d + 1] = src[s + 1]
                        bytes[d + 2] = src[s + 2]
                    } else {
                        bytes[d] = src[s + 2]
                        bytes[d + 1] = src[s + 1]
                        bytes[d + 2] = src[s]
                    }
                    bytes[d + 3] = 255
                }
            }
            return true
        }

        private static func readBiPlanar(
            _ buffer: CVPixelBuffer, into bytes: inout [UInt8],
            width: Int, height: Int, step: Int, tenBit: Bool, videoRange: Bool
        ) -> Bool {
            guard CVPixelBufferGetPlaneCount(buffer) >= 2,
                let lumaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
                let chromaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)
            else { return false }
            let srcW = CVPixelBufferGetWidth(buffer)
            let srcH = CVPixelBufferGetHeight(buffer)
            let lumaBPR = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let chromaBPR = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            let chromaW = CVPixelBufferGetWidthOfPlane(buffer, 1)
            let chromaH = CVPixelBufferGetHeightOfPlane(buffer, 1)
            guard chromaW > 0, chromaH > 0 else { return false }

            // Expansion back to curve fractions (8-bit scale, chroma centred on 0):
            //   10-bit video: (Y−64)×255/876,  (C−512)×255/896
            //   10-bit full:   Y×255/1023,     (C−512)×255/1023
            //    8-bit video: (Y−16)×255/219,  (C−128)×255/224
            //    8-bit full:   Y,              C−128
            let lumaOffset: Double = videoRange ? (tenBit ? 64 : 16) : 0
            let lumaScale: Double =
                tenBit
                ? (videoRange ? 255.0 / 876.0 : 255.0 / 1023.0) : (videoRange ? 255.0 / 219.0 : 1)
            let chromaCenter: Double = tenBit ? 512 : 128
            let chromaScale: Double =
                tenBit
                ? (videoRange ? 255.0 / 896.0 : 255.0 / 1023.0) : (videoRange ? 255.0 / 224.0 : 1)

            for y in 0..<height {
                let sy = min(srcH - 1, y * step)
                let cy = min(chromaH - 1, sy / 2)
                for x in 0..<width {
                    let sx = min(srcW - 1, x * step)
                    let cx = min(chromaW - 1, sx / 2)
                    let luma: Double
                    let cb: Double
                    let cr: Double
                    if tenBit {
                        // 10 bits in the MSBs of 16-bit words (x420/xf20): value = word >> 6.
                        let lWord = lumaBase.load(
                            fromByteOffset: sy * lumaBPR + sx * 2, as: UInt16.self)
                        let cbWord = chromaBase.load(
                            fromByteOffset: cy * chromaBPR + cx * 4, as: UInt16.self)
                        let crWord = chromaBase.load(
                            fromByteOffset: cy * chromaBPR + cx * 4 + 2, as: UInt16.self)
                        luma = Double(lWord >> 6)
                        cb = Double(cbWord >> 6)
                        cr = Double(crWord >> 6)
                    } else {
                        luma = Double(
                            lumaBase.load(fromByteOffset: sy * lumaBPR + sx, as: UInt8.self))
                        cb = Double(
                            chromaBase.load(fromByteOffset: cy * chromaBPR + cx * 2, as: UInt8.self)
                        )
                        cr = Double(
                            chromaBase.load(
                                fromByteOffset: cy * chromaBPR + cx * 2 + 1, as: UInt8.self))
                    }
                    let yd = max(0, (luma - lumaOffset)) * lumaScale
                    let cbc = (cb - chromaCenter) * chromaScale
                    let crc = (cr - chromaCenter) * chromaScale
                    // BT.709 full-excursion relations on the expanded signal.
                    let d = (y * width + x) * 4
                    bytes[d] = clampByte(yd + 1.8556 * cbc)
                    bytes[d + 1] = clampByte(yd - 0.187324 * cbc - 0.468124 * crc)
                    bytes[d + 2] = clampByte(yd + 1.5748 * crc)
                    bytes[d + 3] = 255
                }
            }
            return true
        }

        private static func clampByte(_ v: Double) -> UInt8 {
            UInt8(min(255, max(0, v.rounded())))
        }

        // MARK: - Core Image safety net (unknown pixel formats only)

        #if canImport(CoreImage)
            private static let fallbackContext = CIContext(options: [
                .cacheIntermediates: false,
                .workingFormat: CIFormat.BGRA8,
                .workingColorSpace: NSNull(),
                .outputColorSpace: NSNull(),
            ])

            private static func ciFallback(_ buffer: CVPixelBuffer, maxWidth: Int) -> (
                bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int
            )? {
                let srcW = CVPixelBufferGetWidth(buffer)
                let srcH = CVPixelBufferGetHeight(buffer)
                let scale = min(1, CGFloat(maxWidth) / CGFloat(srcW))
                let width = max(8, Int((CGFloat(srcW) * scale).rounded()))
                let height = max(8, Int((CGFloat(srcH) * scale).rounded()))
                var cpu: CVPixelBuffer?
                guard
                    CVPixelBufferCreate(
                        kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &cpu)
                        == kCVReturnSuccess, let cpu
                else { return nil }
                let image = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
                    .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                fallbackContext.render(
                    image, to: cpu,
                    bounds: CGRect(x: 0, y: 0, width: width, height: height),
                    colorSpace: CGColorSpaceCreateDeviceRGB())
                guard CVPixelBufferLockBaseAddress(cpu, .readOnly) == kCVReturnSuccess else {
                    return nil
                }
                defer { CVPixelBufferUnlockBaseAddress(cpu, .readOnly) }
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                let ok = readPacked32(
                    cpu, into: &bytes, width: width, height: height, step: 1, bgra: true)
                return ok ? (bytes, width, height, width * 4) : nil
            }
        #else
            private static func ciFallback(_ buffer: CVPixelBuffer, maxWidth: Int) -> (
                bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int
            )? {
                nil
            }
        #endif
    }
#endif
