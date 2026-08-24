import OpenPocketViewCore
import SwiftUI

struct MediaDeliveryOverlayState: Equatable {
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
    private(set) var overlayState: MediaDeliveryOverlayState?
    var sharePayload: MediaSharePayload?
    private(set) var completionToast: String?
    private var deliveryTask: Task<Void, Never>?
    private var cancelHandler: (() -> Void)?
    private var activeDeliveryToken = UUID()

    var isActive: Bool { overlayState != nil }

    func begin(
        _ request: MediaDeliveryBeginRequest,
        model: AppModel,
        onCancel: (() -> Void)? = nil,
        onComplete: ((MediaDeliveryRunOutcome) -> Void)? = nil
    ) {
        deliveryTask?.cancel()
        let token = UUID()
        activeDeliveryToken = token
        cancelHandler = onCancel
        deliveryTask = Task { @MainActor in
            let outcome = await MediaDeliveryRunner.execute(
                request: request, model: model
            ) { [weak self] state in
                guard let self, self.activeDeliveryToken == token else { return }
                self.overlayState = state
            }
            guard activeDeliveryToken == token else { return }
            finish(token: token, outcome: outcome, onComplete: onComplete)
        }
    }

    func cancel() {
        activeDeliveryToken = UUID()
        deliveryTask?.cancel()
        deliveryTask = nil
        cancelHandler?()
        cancelHandler = nil
        overlayState = nil
    }

    private func finish(
        token: UUID,
        outcome: MediaDeliveryRunOutcome,
        onComplete: ((MediaDeliveryRunOutcome) -> Void)?
    ) {
        guard activeDeliveryToken == token else { return }
        deliveryTask = nil
        overlayState = nil
        cancelHandler = nil
        onComplete?(outcome)
        switch outcome {
        case .share(let urls, _, _):
            sharePayload = MediaSharePayload(urls: urls)
        case .savedToPhotos(let count):
            showToast("Saved \(count) clip\(count == 1 ? "" : "s") to Photos")
        case .frameio(let summary):
            showToast(summary)
        case .failed(let message):
            showToast(message)
        }
    }

    func clearSharePresentation() {
        sharePayload = nil
    }

    private func showToast(_ message: String) {
        completionToast = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if completionToast == message { completionToast = nil }
        }
    }
}

struct MediaSharePayload: Identifiable {
    let id = UUID()
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
                Image(systemName: state.destination.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LiveDesign.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.statusLine)
                    .font(LiveType.ui(size: 12, weight: .semibold))
                    .foregroundStyle(LiveDesign.text)
                    .lineLimit(1)
                if state.totalClips > 1 {
                    Text("Clip \(min(state.clipIndex, state.totalClips)) of \(state.totalClips)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
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
                .font(LiveType.ui(size: 11, weight: .semibold))
                .foregroundStyle(LiveDesign.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous),
            interactive: false)
    }
}

@MainActor
enum MediaDeliveryRunner {
    static func execute(
        request: MediaDeliveryBeginRequest,
        model: AppModel,
        onProgress: @escaping (MediaDeliveryOverlayState) -> Void
    ) async -> MediaDeliveryRunOutcome {
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
                    return .failed(message: error.localizedDescription)
                }
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
            var hopped = false
            if model.isOnCameraAccessPoint {
                model.beginInternetHop()
                hopped = true
                overlay.isSwitchingNetworks = true
                onProgress(overlay)
                let online = await model.waitForInternetPath(timeoutSeconds: 30)
                overlay.isSwitchingNetworks = false
                onProgress(overlay)
                if !online {
                    model.endInternetHop()
                    return .failed(
                        message:
                            "Couldn't reach the internet after leaving the camera's Wi‑Fi. Check cellular or home Wi‑Fi and try again."
                    )
                }
            }
            defer {
                if hopped || model.internetHopActive { model.endInternetHop() }
            }
            var uploaded = 0
            var failed = 0
            for (index, file) in ready.enumerated() {
                overlay.clipIndex = index + 1
                overlay.clipFraction = 0
                onProgress(overlay)
                do {
                    let url = try await export(file: file, request: request, model: model) {
                        overlay.clipFraction = $0 * 0.45
                        onProgress(overlay)
                    }
                    try await model.uploadFileToFrameio(
                        sourceURL: url,
                        filename: MediaDelivery.filename(
                            for: file, configuration: request.configuration)
                    ) { fraction in
                        overlay.clipFraction = 0.45 + fraction * 0.55
                        onProgress(overlay)
                    }
                    uploaded += 1
                } catch {
                    failed += 1
                    if ready.count == 1 {
                        return .failed(message: error.localizedDescription)
                    }
                }
            }
            var parts: [String] = []
            if uploaded > 0 { parts.append("\(uploaded) uploaded") }
            if uncached > 0 { parts.append("\(uncached) not cached") }
            if failed > 0 { parts.append("\(failed) failed") }
            if failed > 0 {
                return .failed(message: parts.joined(separator: ", "))
            }
            return .frameio(
                summary: parts.isEmpty ? "Nothing to upload." : parts.joined(separator: ", "))
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
        let cube: CubeLUT? = {
            guard request.configuration.bakeLUT else { return nil }
            return model.assist.exportLUTCube(
                bakeExposure: request.configuration.bakeLUTExposure)
        }()
        if request.configuration.bakeLUT, cube == nil {
            throw MediaDeliveryError.noLUTSelected
        }
        let result = try await MediaLUT.export(
            sourceURL: source,
            outputFilename: MediaDelivery.filename(for: file, configuration: request.configuration),
            format: request.configuration.exportFormat,
            cube: cube,
            metadata: MediaDelivery.metadata(
                for: file, configuration: request.configuration,
                lutName: model.assist.lutStatusLabel,
                cameraName: model.session.connectedCamera?.model.name,
                lutExposureStops: model.assist.lutExposureStops)
        ) { fraction in
            progress(fraction)
        }
        return result.videoURL
    }
}
