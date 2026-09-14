import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Only normalized pixels cross the manual-report boundary. Source metadata and
/// filenames are never copied into the outgoing attachment.
struct ProblemReportImage: Identifiable, Sendable, Transferable {
    static let maximumCount = 3
    static let maximumBytes = 1_024 * 1_024
    let id = UUID()
    let jpeg: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let url = received.file
            return try await Task.detached(priority: .utility) {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 60 * 1_024 * 1_024,
                    let source = CGImageSourceCreateWithURL(url as CFURL, nil)
                else { throw ImageFailure.unreadable }
                return try normalize(source)
            }.value
        }
    }

    static func prepare(_ data: Data) throws -> Self {
        guard data.count <= 60 * 1_024 * 1_024,
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { throw ImageFailure.unreadable }
        return try normalize(source)
    }

    private static func normalize(_ source: CGImageSource) throws -> Self {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_600,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw ImageFailure.unreadable }
        for quality in [0.8, 0.6, 0.4] {
            let bytes = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    bytes, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw ImageFailure.unreadable }
            // New destination from pixels: deliberately do not copy source properties.
            CGImageDestinationAddImage(
                destination, pixels,
                [
                    kCGImageDestinationLossyCompressionQuality: quality
                ] as CFDictionary)
            if CGImageDestinationFinalize(destination), bytes.length <= maximumBytes {
                return Self(jpeg: bytes as Data)
            }
        }
        throw ImageFailure.tooLarge
    }

    enum ImageFailure: LocalizedError {
        case unreadable, tooLarge
        var errorDescription: String? {
            switch self {
            case .unreadable: "Couldn't open this image. Please choose another photo or screenshot."
            case .tooLarge: "This image is too large to attach. Please choose a smaller image."
            }
        }
    }
}
