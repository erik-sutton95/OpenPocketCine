import Foundation
import OpenCineCore
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore

/// Native source facts, primitive exchange/driver IO and existing recovery authority.
/// It contains no catalog, assembler, retry, pagination or return loop.
@MainActor final class PocketMediaPort: DjiAppleMediaMutationPort {
    private weak var session: CameraSession?
    private var identity: DjiAppleMediaIdentity
    private var target: ControlTarget

    init(session: CameraSession, snapshot: CameraSnapshot, target: ControlTarget, cameraID: String)
    {
        self.session = session
        self.target = target
        identity = .init(session: snapshot.session, epoch: snapshot.epoch, cameraID: cameraID)
    }

    func bind(snapshot: CameraSnapshot, target: ControlTarget, cameraID: String) {
        self.target = target
        identity = .init(session: snapshot.session, epoch: snapshot.epoch, cameraID: cameraID)
    }

    var mediaFacts: DjiAppleMediaFacts? {
        guard let session, session.control.id == identity.session else { return nil }
        if let camera = session.connectedCamera, camera.id.uuidString != identity.cameraID {
            return nil
        }
        // Keep actual captured connection identity through the driver's full-rejoin gap.
        if session.connectedCamera == nil, !session.hasFeedRecoveryInFlight { return nil }
        return .init(
            identity: identity,
            canQuery: session.canReachCameraMedia && session.control.target == target,
            bodyGalleryOpen: session.cameraGalleryOpen, inPlayback: session.status.inPlayback,
            model: session.connectedCamera?.model,
            sourcePolicy: .init(model: session.connectedCamera?.model,
                inPlayback: session.status.inPlayback, internalTotalMB: session.status.internalTotalMb))
    }

    func mediaBrowseChanged(
        _ active: Bool, binding: MediaBrowseBinding, source: DjiAppleMediaIdentity
    ) {
        guard let session, mediaFacts?.identity.session == source.session else { return }
        if active {
            if !session.isBrowsingMedia {
                session.cameraMedia.cancelResumeLive()
                session.retireLivePictureRecoveryForMedia()
            }
            session.isBrowsingMedia = true
            if session.cameraGalleryOpen {
                session.mediaNote = MediaOperatorCopy.browsingOnCamera
            }
        } else if !session.isBrowsingMedia {
            session.datalink?.setMediaBrowsing(false)
        }
    }

    func setMediaWireHeld(_ held: Bool, source: DjiAppleMediaIdentity) {
        guard let session, mediaFacts?.identity.session == source.session,
            mediaFacts?.identity.cameraID == source.cameraID
        else { return }
        session.datalink?.setMediaBrowsing(held)
    }

    func writeMedia(_ frame: Duml.Frame, source: DjiAppleMediaIdentity) throws {
        guard let session, let facts = mediaFacts, facts.identity == source, facts.canQuery else {
            throw MediaServiceError.retired
        }
        session.sendMediaFrame(frame)
    }

    func enterMediaPlayback(source: DjiAppleMediaIdentity, timeout: Duration) async throws
        -> Duml.Frame
    {
        guard let session, let facts = mediaFacts, facts.identity == source, facts.canQuery else {
            throw MediaServiceError.retired
        }
        let reply = try await session.awaitMediaOpcode(0x02, 0x0c, timeout: timeout) {
            if self.mediaFacts?.identity == source, self.mediaFacts?.canQuery == true {
                session.sendEnterPlayback()
            }
        }
        guard mediaFacts?.identity == source, mediaFacts?.canQuery == true else {
            throw MediaServiceError.retired
        }
        return reply
    }

    func requestMedia(_ frame: Duml.Frame, source: DjiAppleMediaIdentity, timeout: Duration)
        async throws -> Duml.Frame {
        guard let session, mediaFacts?.identity == source, mediaFacts?.canQuery == true
        else { throw MediaServiceError.retired }
        let reply = try await session.awaitMediaOpcode(frame.cmdSet, frame.cmdId, timeout: timeout) {
            if self.mediaFacts?.identity == source, self.mediaFacts?.canQuery == true {
                session.sendMediaFrame(frame)
            }
        }
        guard mediaFacts?.identity == source, mediaFacts?.canQuery == true
        else { throw MediaServiceError.retired }
        return reply
    }

    func claimMediaReturn(
        binding: MediaBrowseBinding, source: DjiAppleMediaIdentity,
        operation: @escaping @MainActor (DjiAppleMediaReturnAuthority) async -> Void
    ) async {
        guard let session, mediaFacts?.identity.session == source.session,
            mediaFacts?.identity.cameraID == source.cameraID
        else { return }
        session.endMediaBrowse(returning: { token in
            guard self.mediaFacts?.identity.session == source.session else { return }
            await operation(session.mediaReturnAuthority(token: token))
        })
        // The existing recovery slot transfers the task into its genuine owner when ready.
        // This wait does not cancel or replace negotiation and never polls picture readiness.
        let task = session.cameraMedia.resumeLiveTask
        await task?.value
    }
}

extension CameraSession {
    /// The published epoch comes from the real common adapter, not a fabricated media state.
    func connectedMediaService() async -> DjiAppleMediaService? {
        guard let camera = connectedCamera else { return nil }
        let seam = control
        let target = seam.target
        guard let snapshot = await seam.currentSnapshot(), control === seam,
            control.target == target, connectedCamera?.id == camera.id
        else { return nil }
        if cameraMedia.mediaService?.sessionID != seam.id {
            cameraMedia.mediaService?.retire()
            let port = PocketMediaPort(
                session: self, snapshot: snapshot,
                target: target, cameraID: camera.id.uuidString)
            cameraMedia.mediaPort = port
            cameraMedia.mediaService = DjiAppleMediaService(
                session: seam.id, port: port,
                ingress: datalink?.mediaIngress ?? .init(), journal: ControlLiveLog.line)
        } else {
            cameraMedia.mediaPort?.bind(
                snapshot: snapshot, target: target, cameraID: camera.id.uuidString)
            if let datalink { cameraMedia.mediaService?.attachIngress(datalink.mediaIngress) }
        }
        return cameraMedia.mediaService
    }
}
