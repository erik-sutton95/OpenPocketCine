import OpenCineFrameIO
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import AVFoundation
import Foundation
import OpenPocketViewCore
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MonitorUI

// Existing shared destination artwork, moved without changing its path.
struct FrameioMark: View {
    init() {}
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
    case nativeShare, frameio
    var id: String { rawValue }
    var shared: MonitorDeliveryDestination { self == .nativeShare ? .nativeShare : .remoteUpload }
    init(_ shared: MonitorDeliveryDestination) { self = shared == .nativeShare ? .nativeShare : .frameio }
    var title: String { shared.title(remoteDisplayName: "Frame.io") }
    var subtitle: String { shared.subtitle(remoteDisplayName: "Frame.io") }
    var actionTitle: String { shared.actionTitle }
}
typealias MediaDeliveryPostExportAction = MonitorDeliveryPostExportAction
typealias MediaDeliveryConfiguration = MonitorDeliveryExportConfiguration<LogColorTransform, MediaExportFormat>

extension MonitorDeliveryDestination {
    static var frameio: Self { .remoteUpload }
}
extension MonitorDeliveryBatchOutcome {
    static func frameio(summary: String) -> Self { .uploaded(summary: summary) }
}
extension MediaDeliveryDestination {
    var icon: MonitorIcon { self == .nativeShare ? .share : .upload }
}
extension MonitorDeliveryExportConfiguration where Curve == LogColorTransform, Format == MediaExportFormat {
    var forceFrameioReupload: Bool {
        get { forceReupload }
        set { forceReupload = newValue }
    }
    init() { self.init(logTransform: .dLogToDLog2, exportFormat: .mov) }
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
    var internetHopToken: FrameioInternetHop.Token? = nil
}

typealias MediaDeliveryRunOutcome = MonitorDeliveryBatchOutcome<URL>

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
        MonitorDeliveryFileNaming.filename(original: file.filename, configuration: configuration,
            formatExtension: configuration.exportFormat.rawValue, transformToken: transform?.filenameToken)
    }

    static func metadata(
        for file: MediaFile, configuration: MediaDeliveryConfiguration, lutName: String?,
        cameraName: String?, lutExposureStops: Double = 0,
        convertLog: LogColorTransform? = nil
    ) -> MediaClipDeliveryMetadata? {
        let selection = MonitorDeliveryMetadataSelection(configuration)
        guard selection.included else { return nil }
        let bakedStops = selection.bakedExposure ? LUTExposureCompensation.snap(lutExposureStops) : nil
        return MediaClipDeliveryMetadata(
            filename: file.filename,
            captureDate: file.filenameTimestamp ?? "",
            sizeBytes: file.sizeBytes,
            cameraName: cameraName,
            lutName: selection.bakedLook ? lutName : nil,
            lutExposureStops: bakedStops,
            convertLog: selection.convertedCurve ? convertLog?.label : nil,
            exportedAt: Date())
    }

    static func metadataSummary(for files: [MediaFile]) -> String {
        MonitorDeliveryMetadataSummary.text(files: files.map {
            .init(filename: $0.filename, captureDate: $0.filenameTimestamp, sizeBytes: $0.sizeBytes > 0 ? $0.sizeBytes : nil)
        }, formatBytes: { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .file) })
    }
}

typealias MediaPhotosSaver = MonitorDeliveryPhotosSaver
typealias MediaShareStaging = MonitorDeliveryShareStaging
