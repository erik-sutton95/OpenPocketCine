import AVFoundation
import CoreImage
import Foundation
import OpenPocketViewCore
import UIKit

/// LUT bake for export. Clip playback grades through `PlaybackFeedSession`
/// (player identity + `CIFeedView`), not `AVVideoComposition`.
enum MediaLUT {
    private static let displayColorSpace =
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let exportContext = CIContext(options: [
        .workingFormat: CIFormat.RGBAh,
        .workingColorSpace: displayColorSpace,
        .highQualityDownsample: true,
    ])

    /// Export bake stays at the source raster. Preview LUT does not use this
    /// composition — it grades `AVPlayerItemVideoOutput` at `maxWorkingWidth`.
    /// Fitting a downscaled CI output into the composition buffer without this
    /// transform parks the picture in the bottom-left and fills the rest green.
    static func transformFitting(_ source: CGRect, to target: CGRect) -> CGAffineTransform {
        guard source.width > 1, source.height > 1, target.width > 1, target.height > 1 else {
            return .identity
        }
        let scaleX = target.width / source.width
        let scaleY = target.height / source.height
        let scale = CGAffineTransform(scaleX: scaleX, y: scaleY)
        let scaledOrigin = CGPoint(x: source.minX, y: source.minY).applying(scale)
        return scale.concatenating(
            CGAffineTransform(
                translationX: target.minX - scaledOrigin.x,
                y: target.minY - scaledOrigin.y))
    }

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

    struct ExportResult: Sendable {
        let videoURL: URL
        let metadataURL: URL?
    }

    static func videoComposition(
        for asset: AVAsset, cube: CubeLUT, renderSize: CGSize? = nil
    ) -> AVVideoComposition {
        let prepared = cube.colorCube
        let dimension = prepared.size
        let cubeData = prepared.rgbaComponents.withUnsafeBytes { Data($0) }
        let built = AVVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            let extent = source.extent
            guard
                let filter = CIFilter(
                    name: "CIColorCube",
                    parameters: [
                        "inputCubeDimension": dimension,
                        "inputCubeData": cubeData,
                    ])
            else {
                request.finish(with: source, context: exportContext)
                return
            }
            filter.setValue(source.clampedToExtent(), forKey: kCIInputImageKey)
            let output = (filter.outputImage ?? source).cropped(to: extent)
            request.finish(with: output, context: exportContext)
        }
        guard let renderSize, renderSize.width > 1, renderSize.height > 1,
            let mutable = built.mutableCopy() as? AVMutableVideoComposition
        else {
            return built
        }
        mutable.renderSize = renderSize
        mutable.renderScale = 1
        return mutable
    }

    static func export(
        sourceURL: URL,
        outputFilename: String,
        format: MediaExportFormat,
        cube: CubeLUT?,
        metadata: MediaClipDeliveryMetadata?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportResult {
        let outputURL = try makeExportURL(filename: outputFilename, format: format)
        progress(0.02)
        let sourceExt = sourceURL.pathExtension.lowercased()
        let passthrough =
            cube == nil
            && (sourceExt == format.rawValue || (sourceExt == "m4v" && format == .mp4))
        if passthrough {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: outputURL)
            progress(0.9)
        } else {
            try await transcode(
                sourceURL: sourceURL, outputURL: outputURL, format: format, cube: cube,
                progress: progress)
        }
        try await ensureFileReady(at: outputURL)
        let metadataURL = try writeMetadataSidecar(metadata, nextTo: outputURL)
        progress(1)
        return ExportResult(videoURL: outputURL, metadataURL: metadataURL)
    }

    /// Maps `AVAssetExportSession.progress` (0…1) onto the overlay's export band (5%…90%).
    static func mappedExportProgress(_ sessionProgress: Float) -> Double {
        0.05 + Double(max(0, min(1, sessionProgress))) * 0.85
    }

    /// LUT bake must stay at the source raster. `HighestQuality` is an H.264
    /// preset that caps at 720p/1080p; HEVC highest keeps 4K.
    static func exportPreset(bakingLUT: Bool, compatible: [String]) -> String {
        if !bakingLUT { return AVAssetExportPresetPassthrough }
        let preferred = [
            AVAssetExportPresetHEVCHighestQuality,
            AVAssetExportPresetHEVC3840x2160,
            AVAssetExportPreset3840x2160,
            AVAssetExportPresetHEVC1920x1080,
            AVAssetExportPreset1920x1080,
            AVAssetExportPresetHighestQuality,
        ]
        return preferred.first { compatible.contains($0) } ?? AVAssetExportPresetHighestQuality
    }

    private static func transcode(
        sourceURL: URL,
        outputURL: URL,
        format: MediaExportFormat,
        cube: CubeLUT?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        _ = try? await asset.loadTracks(withMediaType: .video)
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preferred = exportPreset(bakingLUT: cube != nil, compatible: compatible)
        let renderSize = await videoDisplaySize(of: asset)
        do {
            try await runExport(
                asset: asset, outputURL: outputURL, format: format, cube: cube,
                presetName: preferred, renderSize: renderSize, progress: progress)
        } catch {
            guard cube == nil, preferred == AVAssetExportPresetPassthrough else { throw error }
            let fallback = exportPreset(bakingLUT: true, compatible: compatible)
            try await runExport(
                asset: asset, outputURL: outputURL, format: format, cube: cube,
                presetName: fallback, renderSize: renderSize, progress: progress)
        }
    }

    private static func videoDisplaySize(of asset: AVAsset) async -> CGSize? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        guard let size = try? await track.load(.naturalSize) else { return nil }
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        let fitted = CGSize(width: abs(rect.width), height: abs(rect.height))
        guard fitted.width > 1, fitted.height > 1 else { return nil }
        return fitted
    }

    private static func runExport(
        asset: AVAsset,
        outputURL: URL,
        format: MediaExportFormat,
        cube: CubeLUT?,
        presetName: String,
        renderSize: CGSize?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw ExportError.sessionSetupFailed
        }
        if let cube {
            session.videoComposition = videoComposition(
                for: asset, cube: cube, renderSize: renderSize)
        }
        progress(0.05)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        let reporter = ExportProgressReporter(session: session, report: progress)
        let progressTask = Task { await reporter.poll() }
        defer { progressTask.cancel() }
        if #available(iOS 18, *) {
            try await session.export(to: outputURL, as: format.avFileType)
        } else {
            session.outputURL = outputURL
            session.outputFileType = format.avFileType
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                nonisolated(unsafe) let exportSession = session
                exportSession.exportAsynchronously {
                    if exportSession.status == .completed {
                        cont.resume()
                    } else {
                        cont.resume(throwing: exportSession.error ?? ExportError.failed("export"))
                    }
                }
            }
        }
        progress(0.95)
    }

    /// Polls `AVAssetExportSession.progress` during transcode without crossing Swift 6 sendability.
    private final class ExportProgressReporter: @unchecked Sendable {
        private let session: AVAssetExportSession
        private let report: @Sendable (Double) -> Void

        init(session: AVAssetExportSession, report: @escaping @Sendable (Double) -> Void) {
            self.session = session
            self.report = report
        }

        func poll() async {
            while !Task.isCancelled {
                let exportProgress = session.progress
                if exportProgress > 0 {
                    report(MediaLUT.mappedExportProgress(exportProgress))
                }
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
    }

    private static func ensureFileReady(at url: URL) async throws {
        for _ in 0..<20 {
            if FileManager.default.isReadableFile(atPath: url.path) { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ExportError.failed("export file never became readable")
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

    private static func writeMetadataSidecar(
        _ metadata: MediaClipDeliveryMetadata?, nextTo videoURL: URL
    ) throws -> URL? {
        guard let metadata else { return nil }
        let url = videoURL.deletingPathExtension().appendingPathExtension("meta.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: url, options: .atomic)
        return url
    }
}
