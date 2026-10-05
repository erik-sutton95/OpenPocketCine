import Foundation
import OpenCineApple
import OpenPocketViewCore

/// Output storage and source-curve policy for the shared native exporter.
enum MediaLUT {
    enum ExportError: LocalizedError {
        case sessionSetupFailed
        case failed(String)
        case invalidFilename

        var errorDescription: String? {
            switch self {
            case .sessionSetupFailed: "Couldn't create the export session for this clip."
            case .failed(let reason): "Export failed: \(reason)"
            case .invalidFilename: "Enter a valid filename."
            }
        }
    }

    static func export(
        sourceURL: URL,
        outputFilename: String,
        format: MediaExportFormat,
        cube: CubeLUT?,
        logTransform: LogColorTransform? = nil,
        metadata: MediaClipDeliveryMetadata?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> MonitorMediaExporter.ExportResult {
        let outputURL = try makeExportURL(filename: outputFilename, format: format)
        progress(0.02)
        let look: MonitorMediaExporter.Look?
        if let logTransform {
            look = .init(
                cube: logTransform.cube(), preservingEncodedValues: true,
                metadataReplacement: .init(
                    key: ClipColorProfile.gammaKey, value: logTransform.destination.label))
        } else if let cube {
            look = .init(cube: cube)
        } else {
            look = nil
        }
        let nativeFormat: MonitorMediaExporter.Format
        switch format {
        case .mov: nativeFormat = .mov
        case .mp4: nativeFormat = .mp4
        }
        do {
            return try await MonitorMediaExporter.export(
                sourceURL: sourceURL, outputURL: outputURL, format: nativeFormat, look: look,
                metadata: metadata, progress: progress)
        } catch let error as MonitorMediaExporter.ExportError {
            switch error {
            case .sessionSetupFailed: throw ExportError.sessionSetupFailed
            case .failed(let reason): throw ExportError.failed(reason)
            }
        }
    }

    private static func makeExportURL(filename: String, format: MediaExportFormat) throws -> URL {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExportError.invalidFilename }
        let exports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        var name = trimmed
        if (name as NSString).pathExtension.isEmpty {
            name = "\(name).\(format.rawValue)"
        }
        let url = exports.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        return url
    }
}
