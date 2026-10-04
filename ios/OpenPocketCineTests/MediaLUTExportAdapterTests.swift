import Foundation
import XCTest
import os

@testable import OpenPocketCine

/// Filesystem adapter checks; movie decoding is covered by MediaLogExportTests.
final class MediaLUTExportAdapterTests: XCTestCase, @unchecked Sendable {
    func testOriginalCopyPreservesBytesNameMetadataAndProgress() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SIMULATED-export-adapter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("original.MOV")
        let original = Data([0, 1, 2, 3, 0xff, 0x80])
        try original.write(to: source)
        let stem = "SIMULATED-original-\(UUID().uuidString)"
        let exports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let expectedVideo = exports.appendingPathComponent("\(stem).mov")
        let expectedMetadata = exports.appendingPathComponent("\(stem).meta.json")
        defer {
            try? FileManager.default.removeItem(at: expectedVideo)
            try? FileManager.default.removeItem(at: expectedMetadata)
        }
        // Prove the existing output is replaced by this original, not retained.
        try Data([0x55]).write(to: expectedVideo)
        let metadata = MediaClipDeliveryMetadata(
            filename: "original.MOV", captureDate: "2026-10-04", sizeBytes: 6,
            cameraName: "SIMULATED", lutName: nil, lutExposureStops: nil,
            convertLog: nil, exportedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let progress = OSAllocatedUnfairLock<[Double]>(initialState: [])
        let result = try await MediaLUT.export(
            sourceURL: source, outputFilename: "  \(stem) \n", format: .mov,
            cube: nil, metadata: metadata,
            progress: { value in
                progress.withLock { $0.append(value) }
            })
        XCTAssertEqual(result.videoURL, expectedVideo)
        XCTAssertEqual(result.metadataURL, expectedMetadata)
        XCTAssertEqual(try Data(contentsOf: result.videoURL), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(progress.withLock { $0 }, [0.02, 0.9, 1])
        let decoded = try JSONDecoder().decode(
            [String: JSONValue].self, from: Data(contentsOf: expectedMetadata))
        XCTAssertEqual(decoded["filename"], .string("original.MOV"))
        XCTAssertEqual(decoded["captureDate"], .string("2026-10-04"))
        XCTAssertEqual(decoded["cameraName"], .string("SIMULATED"))
        XCTAssertEqual(decoded["sizeBytes"], .number(6))
        XCTAssertEqual(decoded["exportedAt"], .string("2023-11-14T22:13:20Z"))
        XCTAssertNil(decoded["lutName"])
        XCTAssertNil(decoded["lutExposureStops"])
        XCTAssertNil(decoded["convertLog"])
    }

    func testM4VOriginalCopiesToExplicitMP4NameWithoutSidecar() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SIMULATED-\(UUID().uuidString).m4v")
        defer { try? FileManager.default.removeItem(at: source) }
        let bytes = Data([0x66, 0x74, 0x79, 0x70, 0, 1, 2])
        try bytes.write(to: source)
        let filename = "SIMULATED-m4v-\(UUID().uuidString).mp4"
        let expected = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent(filename)
        defer { try? FileManager.default.removeItem(at: expected) }
        let progress = OSAllocatedUnfairLock<[Double]>(initialState: [])
        let result = try await MediaLUT.export(
            sourceURL: source, outputFilename: filename, format: .mp4, cube: nil,
            metadata: nil, progress: { value in progress.withLock { $0.append(value) } })
        XCTAssertEqual(result.videoURL, expected)
        XCTAssertEqual(try Data(contentsOf: result.videoURL), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertNil(result.metadataURL)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: expected.deletingPathExtension().appendingPathExtension("meta.json").path))
        XCTAssertEqual(progress.withLock { $0 }, [0.02, 0.9, 1])
    }

    func testBlankFilenameKeepsAppErrorAndReportsNoProgress() async throws {
        let progress = OSAllocatedUnfairLock<[Double]>(initialState: [])
        do {
            _ = try await MediaLUT.export(
                sourceURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "SIMULATED-nonexistent-\(UUID().uuidString).mov"),
                outputFilename: " \n\t ", format: .mov, cube: nil, metadata: nil,
                progress: { value in progress.withLock { $0.append(value) } })
            XCTFail("Blank filename must be rejected before source or native work")
        } catch MediaLUT.ExportError.invalidFilename {
            XCTAssertEqual(
                MediaLUT.ExportError.invalidFilename.errorDescription, "Enter a valid filename.")
        }
        XCTAssertTrue(progress.withLock { $0.isEmpty })
    }

    private enum JSONValue: Decodable, Equatable {
        case string(String)
        case number(Double)

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let string = try? value.decode(String.self) {
                self = .string(string)
            } else {
                self = .number(try value.decode(Double.self))
            }
        }
    }
}
