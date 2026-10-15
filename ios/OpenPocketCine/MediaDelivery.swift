import OpenCineAppKit
import OpenCineApple
import OpenCineCameraControls
import OpenCineCore
import OpenCineFrameIO
import OpenCineFrameIOApple
import OpenPocketViewCore
import SwiftUI

/// Pocket's delivery over the shared clip delivery, delivery coordinator and Frame.io account.
/// Only the DJI session adapter, the curve copy and the saved namespaces live here.

extension FrameioHostNamespace {
    /// Pocket's saved sign-in, destination and upload history. Changing one signs every
    /// operator out or forgets their project.
    static let openPocketCine = FrameioHostNamespace(
        keychainService: "OpenPocketCine.frameio", destinationKey: "opc.frameio.destination.v1",
        historyKey: "opc.frameio.uploaded.v1")
}

extension MonitorClipDeliveryCopy {
    static let openPocketCine = MonitorClipDeliveryCopy(
        convertHelp: "Choose one output curve for every selected D-Log or D-Log2 clip. Camera originals stay untouched.",
        convertUnavailableHelp: "Needs a D-Log or D-Log2 clip. Rec.709 stays as-shot.",
        notLog: { "\($0) isn't D-Log or D-Log2." })
}

/// Where an internet hop leaves from and returns to.
struct PocketHopRoute {
    let session: CameraSession
    let sessionID: CameraSessionID
    let ssid: String?
}

extension AppModel {
    /// The captured session's clip library: a selection stays bound to the session, camera and
    /// cache generation it came from.
    func clipLibrary() -> MonitorClipLibrary {
        let session = session, library = session.mediaLibrary, directory = library.cache.directory
        let cameraID = session.mediaCameraID, generation = directory.generation
        return .init(
            isCurrent: { [weak self] in
                self?.session === session && session.mediaLibrary === library
                    && session.mediaCameraID == cameraID && directory.generation == generation
            },
            connected: { if case .live = session.phase { return true }; return false },
            cameraName: { session.connectedCamera?.model.name },
            isDownloaded: session.isDownloaded, download: { await session.download(file: $0) },
            downloadProgress: { session.mediaDownloadProgress[$0.path] },
            localURL: session.localURL(for:), shotColor: session.shotColor(for:),
            rememberShotColor: { session.rememberShotColor($0, for: $1) })
    }

    /// The delivery popup of one selection and the begin of its accepted request.
    func deliveryPopup(
        files: [MediaFile], preferred: MonitorDeliveryDestination? = nil
    ) -> MonitorOperatorDeliveryPopupHost<
        LogColorTransform, MonitorMediaExporter.Format, FrameioProject, FrameioProjectListing,
        MonitorInternetHop<PocketHopRoute>.Token, FrameioMark
    >.Made {
        let cameraID = session.mediaCameraID
        let hop = internetHop
        let internet = hop.deliveryService(route: { [weak self] in self?.hopRoute })
        return MonitorClipDelivery.popup(
            files: files, library: clipLibrary(), assist: { self.assist }, copy: .openPocketCine,
            coordinator: delivery,
            remote: frameio.remoteService(
                onCameraNetwork: { hop.onCameraNetwork }, internet: internet, transfer: { hop.transfer($0) }),
            remoteRun: { [frameio] request, admission in
                frameio.remoteRun(
                    request: request,
                    identity: { file in
                        FrameioUploadHistoryIndex.identity([cameraID, file.id, String(file.sizeBytes)])
                    }, admission: admission)
            }, preferredDestination: preferred)
    }
}

/// The delivery popup over a gallery, player or photo for one selection.
struct MediaDeliveryPopupOverlay: View {
    let files: [MediaFile]
    var preferredDestination: MonitorDeliveryDestination? = nil
    var onDismiss: () -> Void
    @Environment(AppModel.self) private var model
    var body: some View {
        MonitorOperatorDeliveryPopupHost(
            selectionID: files.map(\.id), make: { model.deliveryPopup(files: files, preferred: preferredDestination) },
            onDismiss: onDismiss, remoteArtwork: { FrameioMark() })
    }
}
