import MonitorUI
import OpenCineAppKit
import OpenCineFrameIO
import OpenPocketViewCore
import SwiftUI

struct MediaDeliveryOverlayState: Equatable, Sendable {
    let destination: MediaDeliveryDestination
    let totalClips: Int
    var clipIndex: Int
    var clipFraction: Double
    var isCaching = false
    var isSwitchingNetworks = false

    var overallFraction: Double {
        guard totalClips > 0 else { return 0 }
        let completed = Double(max(0, clipIndex - 1))
        return min(1, (completed + clipFraction) / Double(totalClips))
    }

    var isPreparingClip: Bool { clipFraction <= 0 }

    var percentText: String {
        guard !isPreparingClip else { return "" }
        return "\(Int((overallFraction * 100).rounded()))%"
    }

    var statusLine: String {
        if isSwitchingNetworks { return "Switching networks…" }
        let verb: String
        if isCaching {
            verb = isPreparingClip ? "Caching from camera…" : "Caching from camera"
        } else {
            switch destination {
            case .nativeShare:
                if clipFraction > 0, clipFraction < 0.95 {
                    verb = "Exporting"
                } else {
                    verb = isPreparingClip ? "Preparing…" : "Preparing to share"
                }
            case .frameio:
                if clipFraction > 0, clipFraction < 0.45 {
                    verb = "Exporting"
                } else {
                    verb = isPreparingClip ? "Preparing…" : "Uploading to Frame.io"
                }
            }
        }
        if isPreparingClip { return verb }
        return "\(verb) \(percentText)"
    }
}

@MainActor
@Observable
final class MediaDeliveryCoordinator {
    private let lifetime:
        MonitorDeliveryModel<
            MediaDeliveryOverlayState, MediaDeliveryRunOutcome, MediaDeliveryShareResources
        >
    private let execute:
        @MainActor (
            MediaDeliveryBeginRequest, AppModel,
            @escaping @MainActor (MediaDeliveryOverlayState) -> Void
        ) async -> MediaDeliveryRunOutcome

    init(
        sleep: @escaping @MainActor (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        execute:
            @escaping @MainActor (
                MediaDeliveryBeginRequest, AppModel,
                @escaping @MainActor (MediaDeliveryOverlayState) -> Void
            ) async -> MediaDeliveryRunOutcome = { request, model, progress in
                await MediaDeliveryRunner.execute(
                    request: request, model: model, onProgress: progress)
            }
    ) {
        self.execute = execute
        lifetime = .init(
            sleep: sleep,
            releaseShare: { resources in
                // Only an explicitly returned staging lease is disposable. Originals stay cached.
                if let root = resources.cleanupURL { try? FileManager.default.removeItem(at: root) }
            })
    }

    var overlayState: MediaDeliveryOverlayState? { lifetime.state.progress }
    var completionToast: String? { lifetime.state.toast }
    var isActive: Bool { lifetime.state.running }
    var sharePayload: MediaSharePayload? {
        lifetime.state.share.map { .init(id: $0.id, urls: $0.payload.urls) }
    }

    /// SwiftUI's delayed nil setter belongs to the sheet lease captured when built.
    var sharePresentation: Binding<MediaSharePayload?> {
        let presentedID = sharePayload?.id
        return Binding(
            get: { self.sharePayload },
            set: { value in
                if value == nil, let presentedID {
                    self.clearSharePresentation(id: presentedID)
                }
            })
    }

    func begin(
        _ request: MediaDeliveryBeginRequest, model: AppModel,
        onCancel: (() -> Void)? = nil,
        onComplete: ((MediaDeliveryRunOutcome) -> Void)? = nil
    ) {
        let completed: (MediaDeliveryRunOutcome) -> String? = { outcome in
            onComplete?(outcome)
            return nil
        }
        lifetime.begin(onCancel: onCancel, onComplete: completed) { progress in
            let outcome = await self.execute(request, model, progress)
            switch outcome {
            case .share(let urls, _, let cleanup):
                return .init(outcome, share: .init(urls: urls, cleanupURL: cleanup))
            case .savedToPhotos(let count):
                return .init(
                    outcome, toast: "Saved \(count) clip\(count == 1 ? "" : "s") to Photos")
            case .frameio(let summary): return .init(outcome, toast: summary)
            case .failed(let message): return .init(outcome, toast: message)
            }
        }
    }

    func cancel() { lifetime.cancel() }
    func close() { lifetime.close() }

    func clearSharePresentation(id: UUID? = nil) { lifetime.clearSharePresentation(id: id) }

    /// A matching UIKit completion acknowledges dismissal once, even if SwiftUI cleared first.
    @discardableResult
    func completeSharePresentation(id: UUID) -> Bool {
        lifetime.completeSharePresentation(id: id)
    }
}

private struct MediaDeliveryShareResources: Sendable {
    let urls: [URL]
    let cleanupURL: URL?
}

struct MediaSharePayload: Identifiable, Sendable {
    let id: UUID
    let urls: [URL]
}
struct MediaDeliveryOverlay: View {
    let state: MediaDeliveryOverlayState
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if state.isPreparingClip || state.isSwitchingNetworks {
                ProgressView().controlSize(.small).tint(LiveDesign.accent)
            } else {
                state.destination.icon.frame(width: 13, height: 13)
                    .foregroundStyle(LiveDesign.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.statusLine)
                    .font(MonitorTheme.font(12, weight: .semibold))
                    .foregroundStyle(LiveDesign.text)
                    .lineLimit(1)
                if state.totalClips > 1 {
                    Text("Clip \(min(state.clipIndex, state.totalClips)) of \(state.totalClips)")
                        .font(MonitorTheme.font(10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(LiveDesign.muted)
                }
            }
            Spacer(minLength: 4)
            if !state.isPreparingClip {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(LiveDesign.hairline.opacity(0.55))
                        Capsule()
                            .fill(LiveDesign.accent)
                            .frame(width: max(4, geo.size.width * state.overallFraction))
                    }
                }
                .frame(width: 44, height: 4)
            }
            Button("Cancel", action: onCancel)
                .font(MonitorTheme.font(11, weight: .semibold))
                .foregroundStyle(LiveDesign.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .monitorGlass(in: RoundedRectangle(cornerRadius: 12), density: .delivery)
    }
}

@MainActor
enum MediaDeliveryRunner {
    static func execute(
        request: MediaDeliveryBeginRequest,
        model: AppModel,
        onProgress: @escaping (MediaDeliveryOverlayState) -> Void
    ) async -> MediaDeliveryRunOutcome {
        // A popup may already have left camera Wi-Fi to choose an upload
        // project. Adopt that hop before caching so every exit restores it.
        var ownsInternetHop = request.destination == .frameio && model.internetHopActive
        defer {
            if ownsInternetHop { model.endInternetHop() }
        }
        let session = model.session
        let toCache = request.files.filter { !session.isDownloaded($0) }
        var uncached = 0
        if !toCache.isEmpty {
            var caching = MediaDeliveryOverlayState(
                destination: request.destination,
                totalClips: toCache.count,
                clipIndex: 1,
                clipFraction: 0,
                isCaching: true)
            onProgress(caching)
            for (index, file) in toCache.enumerated() {
                if Task.isCancelled { return .failed(message: "Cancelled.") }
                caching.clipIndex = index + 1
                caching.clipFraction = 0
                onProgress(caching)
                let mirror = Task { @MainActor in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(200))
                        if let fraction = session.mediaDownloadProgress[file.path] {
                            caching.clipFraction = fraction
                            onProgress(caching)
                        }
                    }
                }
                await session.download(file: file)
                mirror.cancel()
                if !session.isDownloaded(file) { uncached += 1 }
            }
        }

        let ready = request.files.filter { session.isDownloaded($0) }
        guard !ready.isEmpty else {
            return .failed(
                message: uncached > 0
                    ? "Couldn't cache \(uncached) clip(s) from the camera — check the connection and try again."
                    : MediaDeliveryError.emptySelection.localizedDescription)
        }

        var overlay = MediaDeliveryOverlayState(
            destination: request.destination,
            totalClips: ready.count,
            clipIndex: 1,
            clipFraction: 0)
        onProgress(overlay)

        switch request.destination {
        case .nativeShare:
            var prepared: [URL] = []
            for (index, file) in ready.enumerated() {
                overlay.clipIndex = index + 1
                overlay.clipFraction = 0
                onProgress(overlay)
                do {
                    let url = try await export(file: file, request: request, model: model) {
                        overlay.clipFraction = $0
                        onProgress(overlay)
                    }
                    prepared.append(url)
                } catch {
                    if isConvertLogSkip(error) { continue }
                    return .failed(message: error.localizedDescription)
                }
            }
            guard !prepared.isEmpty else {
                return .failed(
                    message: request.configuration.convertLog
                        ? MediaDeliveryError.convertLogNotLog(ready[0].filename)
                            .errorDescription
                            ?? "None of the clips are D-Log or D-Log2."
                        : MediaDeliveryError.emptySelection.localizedDescription)
            }
            switch request.postExportAction {
            case .saveToPhotos:
                do {
                    let count = try await MediaPhotosSaver.saveVideos(at: prepared)
                    return .savedToPhotos(count: count)
                } catch {
                    return .failed(message: error.localizedDescription)
                }
            case .systemShare:
                do {
                    let staged = try MediaShareStaging.prepareForShare(videoURLs: prepared)
                    let metadata =
                        request.configuration.includeMetadata
                        ? MediaDelivery.metadataSummary(for: ready) : nil
                    _ = metadata
                    return .share(
                        urls: staged.urls, metadataText: metadata,
                        stagingCleanupURL: staged.stagingCleanupURL)
                } catch {
                    return .failed(message: error.localizedDescription)
                }
            }

        case .frameio:
            if model.isOnCameraAccessPoint {
                model.beginInternetHop()
                ownsInternetHop = true
                overlay.isSwitchingNetworks = true
                onProgress(overlay)
                let online = await model.waitForInternetPath(timeoutSeconds: 30)
                overlay.isSwitchingNetworks = false
                onProgress(overlay)
                if !online {
                    return .failed(
                        message:
                            "Couldn't reach the internet after leaving the camera's Wi‑Fi. Check cellular or home Wi‑Fi and try again."
                    )
                }
            }
            // OpenCineFrameIO runs the batch and keeps the partial result; Pocket keeps
            // caching, export and the hop. No upload history: every selected clip uploads.
            let report: FrameioDeliveryReport
            do {
                report = try await FrameioDelivery.run(
                    Array(ready.enumerated()),
                    prepare: { item -> URL? in
                        overlay.clipIndex = item.offset + 1
                        overlay.clipFraction = 0
                        onProgress(overlay)
                        do {
                            return try await export(
                                file: item.element, request: request, model: model
                            ) {
                                overlay.clipFraction = $0 * 0.45
                                onProgress(overlay)
                            }
                        } catch {
                            if isConvertLogSkip(error) { return nil }
                            throw error
                        }
                    },
                    upload: { _, url in
                        try await model.uploadFileToFrameio(
                            sourceURL: url,
                            filename: url.lastPathComponent
                        ) { fraction in
                            overlay.clipFraction = 0.45 + fraction * 0.55
                            onProgress(overlay)
                        }
                        return .uploaded
                    })
            } catch {
                return .failed(message: "Cancelled.")
            }
            if ready.count == 1, report.failed == 1, let message = report.firstFailureMessage {
                return .failed(message: message)
            }
            let uploaded = report.uploaded
            let skipped = report.skipped
            let failed = report.failed
            var parts: [String] = []
            if uploaded > 0 { parts.append("\(uploaded) uploaded") }
            if skipped > 0 { parts.append("\(skipped) skipped") }
            if uncached > 0 { parts.append("\(uncached) not cached") }
            if failed > 0 { parts.append("\(failed) failed") }
            if failed > 0 {
                return .failed(message: parts.joined(separator: ", "))
            }
            if uploaded == 0 {
                return .failed(
                    message: skipped > 0
                        ? MediaDeliveryError.convertLogNotLog(ready[0].filename)
                            .errorDescription
                            ?? "None of the clips are D-Log or D-Log2."
                        : (parts.isEmpty ? "Nothing to upload." : parts.joined(separator: ", ")))
            }
            return .frameio(summary: parts.joined(separator: ", "))
        }
    }

    private static func export(
        file: MediaFile,
        request: MediaDeliveryBeginRequest,
        model: AppModel,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let source = model.session.localURL(for: file), model.session.isDownloaded(file)
        else {
            throw MediaDeliveryError.clipNotCached(file.filename)
        }
        // `localURL` is the original camera file (`files/`), never the LRF proxy.
        let transform: LogColorTransform?
        let cube: CubeLUT?
        if request.configuration.convertLog {
            let color =
                ClipColorProfileIO.shotColor(at: source, path: file.path)
                ?? model.session.shotColor(for: file)
            if let color { model.session.rememberShotColor(color, for: file) }
            guard let color, LogColorTransform.converting(from: color) != nil else {
                throw MediaDeliveryError.convertLogNotLog(file.filename)
            }
            transform = LogColorTransform.converting(
                from: color, to: request.configuration.logTransform.destination)
            cube = nil  // MediaLUT owns the encoded-value conversion path.
        } else if request.configuration.bakeLUT {
            transform = nil
            cube = model.assist.exportLUTCube(
                bakeExposure: request.configuration.bakeLUTExposure)
            if cube == nil { throw MediaDeliveryError.noLUTSelected }
        } else {
            transform = nil
            cube = nil
        }
        let result = try await MediaLUT.export(
            sourceURL: source,
            outputFilename: MediaDelivery.filename(
                for: file, configuration: request.configuration,
                transform: request.configuration.convertLog
                    ? request.configuration.logTransform : nil),
            format: request.configuration.exportFormat,
            cube: cube,
            logTransform: transform,
            metadata: MediaDelivery.metadata(
                for: file, configuration: request.configuration,
                lutName: model.assist.lutStatusLabel,
                cameraName: model.session.connectedCamera?.model.name,
                lutExposureStops: model.assist.lutExposureStops,
                convertLog: transform)
        ) { fraction in
            progress(fraction)
        }
        return result.videoURL
    }

    private static func isConvertLogSkip(_ error: Error) -> Bool {
        if let delivery = error as? MediaDeliveryError, case .convertLogNotLog = delivery {
            return true
        }
        return false
    }
}
