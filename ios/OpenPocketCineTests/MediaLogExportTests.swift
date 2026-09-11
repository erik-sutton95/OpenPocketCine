import AVFoundation
import CoreImage
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class MediaLogExportTests: XCTestCase, @unchecked Sendable {
    func testLogContextPreservesEncodedRec709TaggedSamples() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.itur_709))
        let value: Float = 0.3994
        let pixels: [Float] = [value, value, value, 1]
        let image = CIImage(
            bitmapData: pixels.withUnsafeBytes { Data($0) }, bytesPerRow: 16,
            size: CGSize(width: 1, height: 1), format: .RGBAf, colorSpace: space)
        for transform in LogColorTransform.allCases {
            let cube = transform.cube().colorCube
            let filter = try XCTUnwrap(
                CIFilter(
                    name: "CIColorCube",
                    parameters: [
                        kCIInputImageKey: image,
                        "inputCubeDimension": cube.size,
                        "inputCubeData": cube.rgbaComponents.withUnsafeBytes { Data($0) },
                    ]))
            var output = [Float](repeating: 0, count: 4)
            let result = try XCTUnwrap(filter.outputImage)
            output.withUnsafeMutableBytes {
                MediaLUT.colorContext(preservingEncodedValues: true).render(
                    result, toBitmap: $0.baseAddress!, rowBytes: 16,
                    bounds: image.extent, format: .RGBAf, colorSpace: space)
            }
            let expected = transform.apply(r: Double(value), g: Double(value), b: Double(value))
            XCTAssertEqual(Double(output[0]), expected.r, accuracy: 0.002)
            XCTAssertEqual(Double(output[1]), expected.g, accuracy: 0.002)
            XCTAssertEqual(Double(output[2]), expected.b, accuracy: 0.002)
        }
    }

    func testExportChangesEncodedPixelsAndEmbeddedGammaInBothDirections() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for transform in LogColorTransform.allCases {
            let source = folder.appendingPathComponent("\(transform.rawValue).mov")
            try await writeClip(to: source, gamma: transform.source.label)
            let before = try await readPixel(at: source)
            let result = try await MediaLUT.export(
                sourceURL: source, outputFilename: "log-regression-\(UUID().uuidString).mov",
                format: .mov, cube: nil, logTransform: transform, metadata: nil,
                progress: { _ in })
            defer { try? FileManager.default.removeItem(at: result.videoURL) }
            let after = try await readPixel(at: result.videoURL)
            let expected = transform.apply(r: before[0], g: before[1], b: before[2])
            // YUV conversion and lossy video quantization allow a few code values.
            XCTAssertEqual(after[0], expected.r, accuracy: 0.015)
            XCTAssertEqual(after[1], expected.g, accuracy: 0.015)
            XCTAssertEqual(after[2], expected.b, accuracy: 0.015)
            let metadata = try await AVURLAsset(url: result.videoURL).load(.metadata)
            let gamma = metadata.filter { ($0.key as? String) == ClipColorProfile.gammaKey }
            XCTAssertEqual(gamma.count, 1)
            XCTAssertEqual(gamma.first?.stringValue, transform.destination.label)
            XCTAssertTrue(metadata.contains { $0.stringValue == "Synthetic log fixture" })
            let original = try await AVURLAsset(url: source).load(.metadata)
            XCTAssertEqual(
                original.first { ($0.key as? String) == ClipColorProfile.gammaKey }?.stringValue,
                transform.source.label)
        }
    }

    private func writeClip(to url: URL, gamma: String) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let profile = AVMutableMetadataItem()
        profile.keySpace = .quickTimeMetadata
        profile.key = ClipColorProfile.gammaKey as NSString
        profile.value = gamma as NSString
        profile.dataType = kCMMetadataBaseDataType_UTF8 as String
        let title = AVMutableMetadataItem()
        title.identifier = .quickTimeMetadataTitle
        title.value = "Synthetic log fixture" as NSString
        writer.metadata = [profile, title]
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64, AVVideoHeightKey: 64,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ],
            ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
            ])
        writer.add(input)
        guard writer.startWriting() else { throw try XCTUnwrap(writer.error) }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer),
            kCVReturnSuccess)
        let pixel = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixel, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixel)).assumingMemoryBound(
            to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        for y in 0..<64 {
            for x in 0..<64 {
                let offset = y * stride + x * 4
                base[offset] = 102
                base[offset + 1] = 102
                base[offset + 2] = 102
                base[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        for frame in 0..<3 {
            for _ in 0..<200 where !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertTrue(input.isReadyForMoreMediaData)
            XCTAssertTrue(
                adaptor.append(
                    pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        writer.endSession(atSourceTime: CMTime(value: 3, timescale: 30))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    private func readPixel(at url: URL) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        defer { reader.cancelReading() }
        let sample = try XCTUnwrap(output.copyNextSampleBuffer())
        let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let data = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(
            to: UInt8.self)
        let center =
            (CVPixelBufferGetHeight(buffer) / 2) * CVPixelBufferGetBytesPerRow(buffer)
            + (CVPixelBufferGetWidth(buffer) / 2) * 4
        return [
            Double(data[center + 2]) / 255, Double(data[center + 1]) / 255,
            Double(data[center]) / 255,
        ]
    }
}
