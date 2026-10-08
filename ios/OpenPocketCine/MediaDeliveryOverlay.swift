import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineFrameIO
import OpenPocketViewCore
import SwiftUI

typealias MediaDeliveryOverlayState = MonitorDeliveryBatchProgress

extension MonitorDeliveryBatchProgress {
    var statusLine: String { statusLine(uploadCaption: "Uploading to Frame.io") }
}

@MainActor
@Observable
final class MediaDeliveryCoordinator {
    private let lifetime:
        MonitorDeliveryModel<
            MediaDeliveryOverlayState, MediaDeliveryRunOutcome, MonitorDeliveryShareFiles<URL>
        >
    private let execute:
        (@MainActor (
            MediaDeliveryBeginRequest, AppModel,
            @escaping @MainActor (MediaDeliveryOverlayState) -> Void
        ) async -> MediaDeliveryRunOutcome)?

    init(
        sleep: @escaping @MainActor (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        execute:
            (@MainActor (
                MediaDeliveryBeginRequest, AppModel,
                @escaping @MainActor (MediaDeliveryOverlayState) -> Void
            ) async -> MediaDeliveryRunOutcome)? = nil
    ) {
        self.execute = execute
        lifetime = .init(
            sleep: sleep,
            releaseShare: { resources in
                // Only an explicitly returned staging lease is disposable. Originals stay cached.
                if let root = resources.cleanup { try? FileManager.default.removeItem(at: root) }
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
        lifetime.beginAdmitted(onCancel: onCancel, onComplete: completed) { progress, admission in
            let outcome: MediaDeliveryRunOutcome
            if let execute = self.execute { outcome = await execute(request, model, progress) }
            else { outcome = await MediaDeliveryRunner.execute(request: request, model: model,
                admission: admission, onProgress: progress) }
            return outcome.completion()
        }
    }

    func failUnavailableExportSettings() {
        lifetime.begin { _ in .init(.failed(message: "Export settings are unavailable."), toast: "Export settings are unavailable.") }
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

struct MediaSharePayload: Identifiable, Sendable {
    let id: UUID
    let urls: [URL]
}
struct MediaDeliveryOverlay: View {
    let state: MediaDeliveryOverlayState
    var onCancel: () -> Void

    var body: some View { MonitorOperatorDeliveryProgress(state: state, onCancel: onCancel) }
}

@MainActor
enum MediaDeliveryRunner {
    static func execute(request: MediaDeliveryBeginRequest, model: AppModel,
        onProgress: @escaping @MainActor (MediaDeliveryOverlayState) -> Void) async -> MediaDeliveryRunOutcome {
        await execute(request: request, model: model, admission: .init { true }, onProgress: onProgress)
    }

    static func execute(request: MediaDeliveryBeginRequest, model: AppModel,
        admission: MonitorDeliveryAdmission,
        onProgress: @escaping @MainActor (MediaDeliveryOverlayState) -> Void) async -> MediaDeliveryRunOutcome {
        let session = model.session
        let cache = session.mediaLibrary.cache.directory
        let generation = cache.generation
        let cameraID = session.mediaCameraID
        let source = MonitorDeliveryAdmission {
            admission.isCurrent() && model.session === session && session.mediaCameraID == cameraID
                && cache.generation == generation && admission.isCurrent()
        }
        let internet = MonitorDeliveryInternetService<FrameioInternetHop.Token>(
            needsHop: { model.isOnCameraAccessPoint }, begin: { model.beginInternetHop() },
            owns: { model.internetHop.owns($0) }, wait: { await model.waitForInternetPath(timeoutSeconds: 30, token: $0) },
            restore: { model.endInternetHop($0) })
        return await MonitorDeliveryModel<MediaDeliveryOverlayState, MediaDeliveryRunOutcome, MonitorDeliveryShareFiles<URL>>.runBatch(
            records: request.files, destination: request.destination.shared, action: request.postExportAction, admission: source,
            originals: .init(available: session.isDownloaded, acquire: { file in
                guard source.isCurrent() else { return }
                await session.download(file: file)
            }, progress: { session.mediaDownloadProgress[$0.path] }),
            exporter: .init { file, progress in
                guard source.isCurrent() else { throw CancellationError() }
                do { return try await export(file: file, request: request, model: model,
                    session: session, admission: source, progress: progress) }
                catch { if isConvertLogSkip(error) { return nil }; throw error }
            }, share: { urls in
                let staged = try MediaShareStaging.prepareForShare(videoURLs: urls)
                return .init(urls: staged.urls, cleanup: staged.stagingCleanupURL)
            }, photos: .batch { try await MediaPhotosSaver.saveVideos(at: $0, ifCurrent: { source.isCurrent() }) },
            upload: .init(progressCaption: "Uploading to Frame.io") { url, progress in
                guard source.isCurrent() else { throw CancellationError() }
                try await model.uploadFileToFrameio(sourceURL: url, filename: url.lastPathComponent) { fraction in
                    Task { @MainActor in if source.isCurrent() { progress(fraction) } }
                }
            }, internet: internet, lease: request.internetHopToken,
            filename: { $0.filename }, metadata: { request.configuration.includeMetadata ? MediaDelivery.metadataSummary(for: $0) : nil },
            noPrepared: { files in request.configuration.convertLog ? files.first.map {
                MediaDeliveryError.convertLogNotLog($0.filename).localizedDescription
            } : nil }, progress: onProgress)
    }

    private static func export(
        file: MediaFile,
        request: MediaDeliveryBeginRequest,
        model: AppModel,
        session: CameraSession, admission: MonitorDeliveryAdmission,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> URL {
        guard admission.isCurrent(), let source = session.localURL(for: file), session.isDownloaded(file)
        else {
            throw MediaDeliveryError.clipNotCached(file.filename)
        }
        // `localURL` is the original camera file (`files/`), never the LRF proxy.
        let transform: LogColorTransform?
        let cube: CubeLUT?
        if request.configuration.convertLog {
            let color =
                ClipColorProfile.shotColor(at: source, path: file.path)
                ?? session.shotColor(for: file)
            guard admission.isCurrent() else { throw CancellationError() }
            if let color { session.rememberShotColor(color, for: file) }
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
        let filename = MediaDelivery.filename(
            for: file, configuration: request.configuration,
            transform: request.configuration.convertLog ? request.configuration.logTransform : nil)
        let metadata = MediaDelivery.metadata(
            for: file, configuration: request.configuration,
            lutName: model.assist.lutStatusLabel, cameraName: session.connectedCamera?.model.name,
            lutExposureStops: model.assist.lutExposureStops, convertLog: transform)
        guard admission.isCurrent() else { throw CancellationError() }
        let result = try await MediaLUT.export(
            sourceURL: source, outputFilename: filename, format: request.configuration.exportFormat,
            cube: cube, logTransform: transform, metadata: metadata
        ) { fraction in
            Task { @MainActor in if admission.isCurrent() { progress(fraction) } }
        }
        guard admission.isCurrent() else { throw CancellationError() }
        return result.videoURL
    }

    private static func isConvertLogSkip(_ error: Error) -> Bool {
        if let delivery = error as? MediaDeliveryError, case .convertLogNotLog = delivery {
            return true
        }
        return false
    }
}
