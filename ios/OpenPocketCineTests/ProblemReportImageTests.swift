import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest

@testable import OpenPocketCine

final class ProblemReportImageTests: XCTestCase {
    func testNormalizationRemovesMetadataAndBoundsPixels() throws {
        let raw = try fixture()
        let originalSource = try XCTUnwrap(CGImageSourceCreateWithData(raw as CFData, nil))
        let originalProperties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [String: Any])
        XCTAssertNotNil(originalProperties[kCGImagePropertyGPSDictionary as String])
        let normalized = try ProblemReportImage.prepare(raw)
        XCTAssertLessThanOrEqual(normalized.jpeg.count, ProblemReportImage.maximumBytes)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(normalized.jpeg as CFData, nil))
        let props = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertNil(props[kCGImagePropertyGPSDictionary as String])
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        XCTAssertTrue(
            Set(exif.keys).isSubset(of: ["ColorSpace", "PixelXDimension", "PixelYDimension"]))
        XCTAssertNil(exif[kCGImagePropertyExifUserComment as String])
        XCTAssertLessThanOrEqual(
            props[kCGImagePropertyPixelWidth as String] as? Int ?? Int.max, 1600)
        XCTAssertLessThanOrEqual(
            props[kCGImagePropertyPixelHeight as String] as? Int ?? Int.max, 1600)
    }

    func testCorruptImageIsRejected() {
        XCTAssertThrowsError(try ProblemReportImage.prepare(Data("not an image".utf8)))
    }

    @MainActor func testImagesPersistInManualEnvelopeAndDiscardTogether() throws {
        let image = try ProblemReportImage.prepare(fixture())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reporter = ProblemReporting(
            directory: root,
            dsnProvider: { "https://public@sentry.invalid/42" }, isForeground: { false })
        try reporter.submit(message: "Image test", email: "", diagnostics: nil, images: [image])
        let queued = try XCTUnwrap(reporter.pending?.envelope)
        XCTAssertNotNil(queued.range(of: Data("image-1.jpg".utf8)))
        XCTAssertNotNil(queued.range(of: image.jpeg))
        let restored = ProblemReporting(directory: root, isForeground: { false })
        XCTAssertEqual(restored.pending?.envelope, queued)
        try restored.discard()
        XCTAssertNil(ProblemReporting(directory: root).pending)
        XCTAssertThrowsError(
            try ProblemReporting.envelope(
                id: "test", message: "test", email: "",
                diagnostics: nil, date: Date(), images: Array(repeating: image, count: 4)))
    }

    private func fixture() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1200), format: format)
            .image { context in
                UIColor.blue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1200))
            }
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, try XCTUnwrap(image.cgImage),
            [
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 12.0, kCGImagePropertyGPSLatitudeRef: "N",
                ],
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifUserComment: "Synthetic private metadata"
                ],
            ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
