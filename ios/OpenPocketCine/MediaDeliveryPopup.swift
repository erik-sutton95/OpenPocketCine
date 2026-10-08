import MonitorUI
import OpenCineAppKit
import OpenCineApple
import OpenCineCameraControls
import OpenCineFrameIO
import OpenPocketViewCore
import SwiftUI

struct MediaDeliveryPopupOverlay: View {
    let files: [MediaFile]
    var preferredDestination: MediaDeliveryDestination? = nil
    var onDismiss: () -> Void
    @Environment(AppModel.self) private var model
    var body: some View {
        CapturedMediaDeliveryPopup(model: model, files: files, preferredDestination: preferredDestination,
            maxCardHeight: nil, onClose: onDismiss)
    }
}

struct MediaDeliveryPopup: View {
    let files: [MediaFile]
    var preferredDestination: MediaDeliveryDestination? = nil
    var maxCardHeight: CGFloat = MediaDeliveryChrome.maxCardHeight
    let onClose: () -> Void
    @Environment(AppModel.self) private var model
    var body: some View {
        CapturedMediaDeliveryPopup(model: model, files: files, preferredDestination: preferredDestination,
            maxCardHeight: maxCardHeight, onClose: onClose)
    }
}

private struct CapturedMediaDeliveryPopup: View {
    @State private var source: MediaDeliveryPreparationSource
    let maxCardHeight: CGFloat?
    let onClose: () -> Void
    init(model: AppModel, files: [MediaFile], preferredDestination: MediaDeliveryDestination?,
        maxCardHeight: CGFloat?, onClose: @escaping () -> Void) {
        _source = State(initialValue: .init(model: model, files: files, preferredDestination: preferredDestination))
        self.maxCardHeight = maxCardHeight; self.onClose = onClose
    }
    var body: some View {
        if let maxCardHeight {
            MonitorOperatorDeliveryScreen(model: source.preparation, maxCardHeight: maxCardHeight,
                onClose: onClose, onBegin: source.begin, remoteArtwork: { FrameioMark() })
        } else {
            MonitorOperatorDeliveryPopupOverlay(model: source.preparation, onDismiss: onClose, onBegin: source.begin, remoteArtwork: { FrameioMark() })
        }
    }
}

/// Immutable selection/source and actual SDK account/export facts only.
@MainActor private struct MediaDeliveryPreparationSource {
    let model: AppModel
    let files: [MediaFile]
    let preparation: MonitorDeliveryPreparationModel<LogColorTransform, MediaExportFormat,
        FrameioProject, FrameioProjectListing, FrameioInternetHop.Token>
    private let isCurrent: () -> Bool
    init(model: AppModel, files: [MediaFile], preferredDestination: MediaDeliveryDestination?) {
        self.model = model; self.files = files
        let session = model.session, library = session.mediaLibrary, directory = library.cache.directory
        let cameraID = session.mediaCameraID, generation = directory.generation
        let current: () -> Bool = {
            model.session === session && session.mediaLibrary === library && session.mediaCameraID == cameraID && directory.generation == generation
        }
        isCurrent = current
        var configuration = MediaDeliveryConfiguration()
        if let first = files.filter({ $0.kind == .video }).compactMap({ session.shotColor(for: $0) })
            .compactMap({ LogColorTransform.converting(from: $0) }).first { configuration.logTransform = first }
        let remote = MonitorDeliveryRemoteService<FrameioProject, FrameioProjectListing, FrameioInternetHop.Token>(
            presentation: .init(displayName: "Frame.io", progressCaption: "Uploading to Frame.io"), observe: {
                let saved = FrameioDestination.loaded
                return .init(configured: model.isFrameioConfigured, connected: model.isFrameioConnected,
                    onCameraNetwork: model.isOnCameraAccessPoint, savedProjectID: saved?.projectID, savedProjectName: saved?.projectName)
            }, load: {
                let listing = try await model.loadFrameioProjectListing()
                return .init(context: listing, projects: listing.projects.map {
                    .init(id: $0.id, name: $0.name, uploadable: $0.rootFolderID.map { _ in true }, payload: $0)
                })
            }, create: { name, context in
                let project = try await model.createFrameioProject(name: name, accountID: context.accountID, workspaceID: context.workspaceID)
                return .init(id: project.id, name: project.name, uploadable: project.rootFolderID.map { _ in true }, payload: project)
            }, persist: { project, context in
                model.persistFrameioDestination(project: project.payload, accountID: context.accountID, workspaceID: context.workspaceID)
            }, internet: .init(needsHop: { model.isOnCameraAccessPoint }, begin: { model.beginInternetHop() },
                owns: { model.internetHop.owns($0) }, wait: { await model.waitForInternetPath(timeoutSeconds: 30, token: $0) },
                restore: { model.endInternetHop($0) }), transfer: { model.transferInternetHop($0) })
        preparation = .init(selection: {
            .init(files: files.map { .init(filename: $0.filename, sizeBytes: $0.sizeBytes > 0 ? $0.sizeBytes : nil) },
                cachedCount: files.filter { session.isDownloaded($0) }.count,
                connected: { if case .live = session.phase { return true }; return false }())
        }, configuration: configuration, exportOptions: .init(
            curves: LogColorTransform.allCases.map { .init(id: $0.rawValue, label: $0.destination.label, value: $0) },
            formats: MediaExportFormat.allCases.map { .init(id: $0.rawValue, label: $0.label, value: $0) },
            lutAvailable: { model.assist.playbackEffects.lutDimension >= 2 || model.assist.effects.lutDimension >= 2 },
            convertLogAvailable: { MediaDelivery.convertLogAvailable(files: files, shotColors: files.map { session.shotColor(for: $0) }) },
            lutLabel: { model.assist.lutStatusLabel }, convertHelp: MediaDeliveryCopy.convertLogHelp,
            convertUnavailableHelp: MediaDeliveryCopy.convertLogHelpUnavailable,
            filename: { configuration in files.count == 1 ? files.first.map {
                MediaDelivery.filename(for: $0, configuration: configuration,
                    transform: configuration.convertLog ? configuration.logTransform : nil)
            } : nil }), remote: remote, preferredDestination: preferredDestination?.shared, sourceCurrent: current)
    }
    func begin(_ request: MonitorDeliveryPreparedRequest<LogColorTransform, MediaExportFormat, FrameioInternetHop.Token>) {
        guard isCurrent() else { if let token = request.internetLease { model.endInternetHop(token) }; return }
        guard let configuration = request.configuration else {
            if let token = request.internetLease { model.endInternetHop(token) }
            model.delivery.failUnavailableExportSettings()
            return
        }
        model.delivery.begin(.init(files: files, destination: .init(request.destination), configuration: configuration,
            postExportAction: request.action, internetHopToken: request.internetLease), model: model)
    }
}
