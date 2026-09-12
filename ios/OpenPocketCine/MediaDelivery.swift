import AVFoundation
import Foundation
import OpenPocketViewCore
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// OpenZCine `IconFrameio` template mark.
struct FrameioMark: View {
    var body: some View {
        FrameioMarkShape()
            .fill(Color.primary)
            .aspectRatio(1, contentMode: .fit)
    }
}

private struct FrameioMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 7.5 * s, y: rect.minY + 4 * s))
        path.addArc(
            center: CGPoint(x: rect.minX + 7.5 * s, y: rect.minY + 6.5 * s),
            radius: 2.5 * s, startAngle: .degrees(-90), endAngle: .degrees(-180), clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + 5 * s, y: rect.minY + 17.5 * s))
        path.addArc(
            center: CGPoint(x: rect.minX + 7.5 * s, y: rect.minY + 17.5 * s),
            radius: 2.5 * s, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + 9.5 * s, y: rect.minY + 20 * s))
        path.addArc(
            center: CGPoint(x: rect.minX + 9.5 * s, y: rect.minY + 17.5 * s),
            radius: 2.5 * s, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + 12 * s, y: rect.minY + 14 * s))
        path.addLine(to: CGPoint(x: rect.minX + 15.5 * s, y: rect.minY + 14 * s))
        path.addArc(
            center: CGPoint(x: rect.minX + 15.5 * s, y: rect.minY + 11.5 * s),
            radius: 2.5 * s, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + 12 * s, y: rect.minY + 9 * s))
        path.addLine(to: CGPoint(x: rect.minX + 12 * s, y: rect.minY + 6.5 * s))
        path.addArc(
            center: CGPoint(x: rect.minX + 9.5 * s, y: rect.minY + 6.5 * s),
            radius: 2.5 * s, startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
        path.closeSubpath()
        return path
    }
}

enum MediaExportFormat: String, Sendable, CaseIterable, Identifiable {
    case mov
    case mp4
    var id: String { rawValue }
    var avFileType: AVFileType { self == .mov ? .mov : .mp4 }
    var label: String { rawValue.uppercased() }
}

enum MediaDeliveryDestination: String, CaseIterable, Identifiable, Sendable {
    case nativeShare
    case frameio
    var id: String { rawValue }
    var title: String {
        switch self {
        case .nativeShare: "Share"
        case .frameio: "Frame.io"
        }
    }
    var subtitle: String {
        switch self {
        case .nativeShare: "Convert log, Bake LUT, AirDrop, Files"
        case .frameio: "Upload to your Frame.io project"
        }
    }
    var icon: OpcIcon {
        switch self {
        case .nativeShare: .share
        case .frameio: .upload
        }
    }
    var actionTitle: String {
        switch self {
        case .nativeShare: "Share"
        case .frameio: "Upload"
        }
    }
}

enum MediaDeliveryPostExportAction: String, Sendable {
    case systemShare
    case saveToPhotos
}

struct MediaDeliveryConfiguration: Sendable {
    var bakeLUT = true
    /// When ``bakeLUT`` is on, write ``LUTExposureCompensation`` into the file.
    /// Off keeps the cube at 0.0. Default on so the export matches the monitor.
    var bakeLUTExposure = true
    /// Technical D-Log ↔ D-Log2 convert. Exclusive with ``bakeLUT``.
    var convertLog = false
    /// The destination applies to the whole selection, including mixed log clips.
    var logTransform: LogColorTransform = .dLogToDLog2
    var exportFormat: MediaExportFormat = .mov
    var includeMetadata = true
    var forceFrameioReupload = false
}

enum MediaDeliveryChrome {
    /// Hug the options. Cap matches Android `heightIn(max = 520.dp)` so portrait
    /// Back stays clear of the status bar.
    static let maxCardHeight: CGFloat = 520
}

enum MediaDeliveryCopy {
    static let bakeLUT = "Bake LUT"
    static let bakeLUTHelpUnavailable = "No LUT selected — pick one in view assists."
    static let bakeExposure = "Bake exposure"
    static let bakeExposureHelp =
        "Write the LUT exposure pull into the file so it matches the monitor. Off bakes the cube at 0.0."
    static let convertLog = "Convert log"
    static let convertLogHelp =
        "Choose one output curve for every selected D-Log or D-Log2 clip. Camera originals stay untouched."
    static let convertLogDestination = "Output curve"
    static let convertLogHelpUnavailable =
        "Needs a D-Log or D-Log2 clip — Rec.709 stays as-shot."

    static func bakeLUTHelp(statusLabel: String) -> String {
        "Apply \(statusLabel) to exports."
    }
}

struct MediaClipDeliveryMetadata: Codable, Sendable {
    let filename: String
    let captureDate: String
    let sizeBytes: UInt64
    let cameraName: String?
    let lutName: String?
    let lutExposureStops: Double?
    let convertLog: String?
    let exportedAt: Date
}

struct MediaDeliveryPresentation: Identifiable {
    let id = UUID()
    let files: [MediaFile]
    var preferredDestination: MediaDeliveryDestination? = nil
}

enum MediaDeliveryError: LocalizedError {
    case clipNotCached(String)
    case noLUTSelected
    case convertLogNotLog(String)
    case photosDenied
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .clipNotCached(let name): "\(name) isn't fully cached yet."
        case .noLUTSelected: "Turn on a LUT before baking one into the file."
        case .convertLogNotLog(let name): "\(name) isn't D-Log or D-Log2."
        case .photosDenied: "Photos access is required to save the clip."
        case .emptySelection: "Select at least one clip."
        }
    }
}

struct MediaDeliveryBeginRequest: Sendable {
    let files: [MediaFile]
    let destination: MediaDeliveryDestination
    let configuration: MediaDeliveryConfiguration
    var postExportAction: MediaDeliveryPostExportAction = .systemShare
}

enum MediaDeliveryRunOutcome: Sendable {
    case share(urls: [URL], metadataText: String?, stagingCleanupURL: URL?)
    case savedToPhotos(count: Int)
    case frameio(summary: String)
    case failed(message: String)
}

struct MediaDeliveryBatchResult: Sendable {
    var exportedURLs: [URL] = []
    var metadataURLs: [URL] = []
    var uploadedCount: Int = 0
    var failed: [(MediaFile, String)] = []
}

enum MediaDelivery {
    /// Convert log is video-only. Unknown shot color stays available until export
    /// reads the original; Rec.709 / HLG / D-Log M disable the toggle.
    static func convertLogAvailable(files: [MediaFile], shotColors: [ColorMode?]) -> Bool {
        files.enumerated().contains { index, file in
            guard file.kind == .video else { return false }
            guard shotColors.indices.contains(index), let color = shotColors[index] else {
                return true
            }
            return LogColorTransform.converting(from: color) != nil
        }
    }

    static func filename(
        for file: MediaFile, configuration: MediaDeliveryConfiguration,
        transform: LogColorTransform? = nil
    ) -> String {
        let stem = (file.filename as NSString).deletingPathExtension
        if configuration.convertLog, let transform {
            return "\(stem).\(transform.filenameToken).\(configuration.exportFormat.rawValue)"
        }
        guard configuration.bakeLUT || configuration.convertLog else { return file.filename }
        return "\(stem).\(configuration.exportFormat.rawValue)"
    }

    static func metadata(
        for file: MediaFile, configuration: MediaDeliveryConfiguration, lutName: String?,
        cameraName: String?, lutExposureStops: Double = 0,
        convertLog: LogColorTransform? = nil
    ) -> MediaClipDeliveryMetadata? {
        guard configuration.includeMetadata else { return nil }
        let converting = configuration.convertLog
        let bakedStops: Double?
        if !converting, configuration.bakeLUT, configuration.bakeLUTExposure {
            bakedStops = LUTExposureCompensation.snap(lutExposureStops)
        } else {
            bakedStops = nil
        }
        return MediaClipDeliveryMetadata(
            filename: file.filename,
            captureDate: file.filenameTimestamp ?? "",
            sizeBytes: file.sizeBytes,
            cameraName: cameraName,
            lutName: !converting && configuration.bakeLUT ? lutName : nil,
            lutExposureStops: bakedStops,
            convertLog: converting ? convertLog?.label : nil,
            exportedAt: Date())
    }

    static func metadataSummary(for files: [MediaFile]) -> String {
        files.map { file in
            let size =
                file.sizeBytes > 0
                ? ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file)
                : "unknown size"
            let date = file.filenameTimestamp ?? "unknown date"
            return "\(file.filename) · \(date) · \(size)"
        }.joined(separator: "\n")
    }
}

enum MediaPhotosSaver {
    static func saveVideos(at urls: [URL]) async throws -> Int {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw MediaDeliveryError.photosDenied
        }
        var count = 0
        try await PHPhotoLibrary.shared().performChanges {
            for url in urls where ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                count += 1
            }
        }
        return count
    }
}

enum MediaShareStaging {
    static let shareableVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static func prepareForShare(videoURLs: [URL]) throws -> (urls: [URL], stagingCleanupURL: URL?) {
        let videos = videoURLs.filter {
            shareableVideoExtensions.contains($0.pathExtension.lowercased())
        }
        guard !videos.isEmpty else { throw MediaDeliveryError.emptySelection }
        return (videos, nil)
    }
}
