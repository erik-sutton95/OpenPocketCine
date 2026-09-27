#if canImport(CoreVideo)
    import CoreVideo

    /// Mean encoded luma (0…1) of the decoded frame under the gimbal stick.
    /// Reads an 8×8 grid straight from the luma plane on the CPU: no GPU pass,
    /// no image copy, a few dozen memory reads per sample.
    public enum GimbalStickLuma {
        public static let grid = 8

        /// `region` is feed-normalised, top-left origin (`GimbalStick.chromeSampleRegion`).
        public static func mean(_ buffer: CVPixelBuffer, region: MonitorLayoutRegion) -> Double? {
            let format = CVPixelBufferGetPixelFormatType(buffer)
            let bgra = format == kCVPixelFormatType_32BGRA
            let tenBit =
                format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                || format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
            let videoRange =
                format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                || format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            guard
                bgra || tenBit
                    || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                    || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            else { return nil }

            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let base =
                bgra
                ? CVPixelBufferGetBaseAddress(buffer)
                : CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
            guard let base else { return nil }
            let width = bgra ? CVPixelBufferGetWidth(buffer) : CVPixelBufferGetWidthOfPlane(buffer, 0)
            let height =
                bgra ? CVPixelBufferGetHeight(buffer) : CVPixelBufferGetHeightOfPlane(buffer, 0)
            let rowBytes =
                bgra
                ? CVPixelBufferGetBytesPerRow(buffer)
                : CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            guard width > 0, height > 0 else { return nil }

            var sum = 0.0
            for row in 0..<grid {
                let fy = region.y + region.height * (Double(row) + 0.5) / Double(grid)
                let y = min(height - 1, max(0, Int(fy * Double(height))))
                let line = base.advanced(by: y * rowBytes)
                for column in 0..<grid {
                    let fx = region.x + region.width * (Double(column) + 0.5) / Double(grid)
                    let x = min(width - 1, max(0, Int(fx * Double(width))))
                    if bgra {
                        let px = line.advanced(by: x * 4).assumingMemoryBound(to: UInt8.self)
                        sum +=
                            (0.0722 * Double(px[0]) + 0.7152 * Double(px[1]) + 0.2126 * Double(px[2]))
                            / 255
                    } else if tenBit {
                        // 10 significant bits, MSB-aligned in 16.
                        let code = Double(line.load(fromByteOffset: x * 2, as: UInt16.self) >> 6)
                        sum += videoRange ? (code - 64) / 876 : code / 1023
                    } else {
                        let code = Double(line.load(fromByteOffset: x, as: UInt8.self))
                        sum += videoRange ? (code - 16) / 219 : code / 255
                    }
                }
            }
            return min(1, max(0, sum / Double(grid * grid)))
        }
    }
#endif
