import OpenCineCameraControls
import OpenCineAppKitApple
import AVFoundation
import Foundation
import OpenCineAppKit
import OpenCineApple
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore

typealias PocketPlaybackModel = MonitorMediaPlaybackModel<MediaFile, PocketPlaybackLook>

/// The host retains actual camera IO policy separately from local gallery/frame admission.
@MainActor final class PocketPlaybackAuthority {
    nonisolated let id = UUID()
    let operation: PocketMediaLibraryOperation
    let admission: MonitorPlaybackAdmission
    init(session: CameraSession, file: MediaFile) {
        operation = .init(session: session, file: file)
        let owner = session.mediaLibrary
        let token = owner.actionToken
        let cameraID = session.mediaCameraID
        let directory = owner.cache.directory
        let generation = directory.generation
        let asset = DjiAppleMediaAssets.asset(for: file).id
        let indexed = owner.records.contains { $0.payload.id == file.id }
        admission = .init { [weak session] in
            guard let session, session.mediaLibraryOwner === owner,
                owner.lifetimeToken == token.lifetime,
                session.mediaCameraID == cameraID, directory.generation == generation
            else { return false }
            let current = owner.records.first { $0.payload.id == file.id }
            return indexed
                ? current?.asset.id == asset : (current == nil || current?.asset.id == asset)
        }
    }
}

struct PocketPlaybackLook: Equatable, Sendable {
    let color: ColorMode
    let shotColor: ColorMode?
    let family: CameraBodyFamily
    let cameraName: String?
    let file: MediaFile
    let cameraID: String
    let authority: PocketPlaybackAuthority
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.color == rhs.color && lhs.shotColor == rhs.shotColor && lhs.family == rhs.family
            && lhs.cameraName == rhs.cameraName && lhs.file == rhs.file
            && lhs.cameraID == rhs.cameraID
            && lhs.authority.id == rhs.authority.id
    }
}

@MainActor extension CameraSession {
    func makeMediaPlayback(
        native: any MonitorPlaybackPort, previousColor: @escaping @MainActor () -> ColorMode?
    ) -> PocketPlaybackModel {
        let owner = PocketPlaybackModel(
            library: mediaLibrary, native: native,
            candidates: { [weak self] record in self?.playbackCandidates(record) ?? [] },
            resolveLook: { [weak self] record, item in
                guard let self else { return nil }
                return await self.resolvePlaybackLook(
                    record: record, item: item, previousColor: previousColor())
            })
        owner.setItemAdmission { [weak self] record in
            guard let self else { return .init(isCurrent: { false }) }
            return PocketPlaybackAuthority(session: self, file: record.payload).admission
        }
        if let apple = native as? MonitorApplePlaybackOwner {
            apple.sourceAdmission = { [weak owner] in
                guard let owner else { return false }
                let captured = owner.token, accepted = owner.isActive
                guard owner.token == captured, !owner.closed else { return false }
                if accepted { return true }
                owner.close()
                return false
            }
        }
        return owner
    }

    func mediaPlaybackRecord(for file: MediaFile) -> MonitorMediaRecord<MediaFile>? {
        mediaRecord(for: file)
    }

    func playbackCandidates(_ record: MonitorMediaRecord<MediaFile>) -> [MonitorPlaybackCandidate] {
        let file = record.payload
        var choices: [MonitorPlaybackCandidate] = []
        func cached(_ source: MediaPlaybackSource) -> MonitorPlaybackCandidate {
            .cached(
                .init(
                    url: source.url, mimeType: source.mimeType, sourceKey: source.path,
                    role: MediaHTTP.isProxyPath(source.path) ? .proxy : .original,
                    isRemote: source.isRemote))
        }
        func remote(_ path: String) -> MonitorPlaybackCandidate {
            let authority = PocketPlaybackAuthority(session: self, file: file)
            let destination = cameraMedia.playbackCacheURL(
                cameraID: authority.operation.cameraID, file: file, path: path)
            let prefix = authority.operation.directory.root.path + "/"
            let address = String(destination.path.dropFirst(prefix.count))
            return .hostDownload(
                address: address, mimeType: MediaHTTP.playbackMIMEType(for: path),
                sourceKey: path, role: path == file.path ? .original : .proxy,
                admission: .init { [weak self] in
                    authority.admission.isCurrent() && authority.operation.isCurrent
                        && self?.canReachCameraMedia == true
                },
                didCommit: { [weak self] in
                    self?.playbackTransferCommitted(file: file, path: path, authority: authority)
                },
                transfer: { [weak self] sink in
                    guard let self else { throw MonitorPlaybackError.retired }
                    return try await self.transferPlaybackFile(
                        file: file, path: path, authority: authority, into: sink)
                })
        }
        // Monitor-grade proxy first, even when export has cached the high-resolution original.
        // The shared owner retries each native candidate with the original eight-second deadline.
        if let proxy = localProxySource(for: file) { choices.append(cached(proxy)) }
        if canReachCameraMedia { choices += MediaHTTP.proxyPaths(file).map(remote) }
        if let local = localPlaybackSource(for: file) { choices.append(cached(local)) }
        if canReachCameraMedia { choices.append(remote(MediaHTTP.deliveryPath(file))) }
        return choices
    }

    private func resolvePlaybackLook(
        record: MonitorMediaRecord<MediaFile>, item: MonitorPlaybackItem, previousColor: ColorMode?
    ) async -> MonitorPlaybackLook<PocketPlaybackLook>? {
        let file = record.payload
        let authority = PocketPlaybackAuthority(session: self, file: file)
        guard authority.admission.isCurrent() else { return nil }
        let clip: ColorMode?
        if let original = localURL(for: file),
            let mode = ClipColorProfile.shotColor(at: original, path: file.path)
        {
            clip = mode
        } else if let mode = ClipColorProfile.shotColor(at: item.url, path: item.sourceKey) {
            clip = mode
        } else if let cached = shotColor(for: file) {
            clip = cached
        } else {
            clip = await fetchOriginalShotColor(for: file)
        }
        guard authority.admission.isCurrent(), !Task.isCancelled,
            let color = PlaybackLUTColor.resolve(
                clip: clip, live: status.colorMode,
                last: LUTPreferences.app.lastMonitorColorMode ?? previousColor)
        else { return nil }
        return .init(
            transfer: MonitorTransfer(color),
            source: .init(
                color: color, shotColor: clip,
                family: bodyFamily, cameraName: connectedCamera?.model.name, file: file,
                cameraID: authority.operation.cameraID, authority: authority))
    }
}

/// Pocket's camera source for the shared playback host: the page runtime over Pocket's feed,
/// its authority admission, operations and per-record values.
@MainActor final class PocketPlaybackPresentationSource: MonitorPlaybackPresentationSource {
    let presentation: MonitorApplePlaybackPresentation<MediaFile, PocketPlaybackLook>
    private let model: AppModel
    init(model: AppModel) {
        self.model = model
        presentation = .init(makeFeed: {
            let feed = PlaybackFeedSession()
            feed.referenceCaptureEnabled = model.referenceStore != nil
            return feed
        }, audioSession: model.playbackAudioSession,
            samples: { model.frameSamples }, projectEffects: { $0.playbackFrameEffects },
            onTapFailure: MediaPlaybackAudioSession.tapFailure,
            onAudioFailure: MediaPlaybackAudioSession.audioFailure)
    }
    func makeOwner() -> MonitorOperatorMediaModel<MediaFile, PocketPlaybackLook> {
        let model = model
        return presentation.makeOwner(library: model.session.mediaLibrary,
            recordAdmission: { record in PocketPlaybackAuthority(session: model.session, file: record.payload).admission },
            makePlayback: { native in
                model.session.makeMediaPlayback(native: native, previousColor: { model.assist.monitorColorMode })
            })
    }
    func operations(
        owner: MonitorOperatorMediaModel<MediaFile, PocketPlaybackLook>) -> MonitorOperatorPlaybackOperations<MediaFile, PocketPlaybackLook> {
        let model = model
        let cache: (@MainActor (MonitorMediaRecord<MediaFile>) async -> Void)?
        let delete: (@MainActor (MonitorMediaRecord<MediaFile>) async -> Bool)?
        if model.session.canReachCameraMedia {
            cache = { record in await model.session.download(file: record.payload) }
            delete = { record in
                await model.session.deleteMediaFiles([record.payload])
                return model.session.mediaLibrary.record(record.asset.id) == nil
            }
        } else { cache = nil; delete = nil }
        return .init(cacheOriginal: cache, delete: delete,
            favorite: { record in model.session.toggleFavorite(record.payload) }, adoptLook: { _, look in
            let value = look.source
            guard let player = owner.playback else { return }
            let token = player.token
            guard owner.isCurrent(token), value.authority.admission.isCurrent(), owner.isCurrent(token) else { return }
            if let shot = value.shotColor {
                model.session.rememberShotColor(shot, for: value.file, operation: value.authority.operation)
            }
            guard owner.isCurrent(token) else { return }
            let family = value.family != .other ? value.family : model.assist.monitorFamily
            model.assist.adoptPlaybackColor(value.color, family: family, cameraName: value.cameraName,
                lookProfile: DJICameraLUTProfile.make(family: family,
                    cameraName: value.cameraName ?? model.assist.monitorCameraName))
        })
    }
    func values(record: MonitorMediaRecord<MediaFile>,
        owner: MonitorOperatorMediaModel<MediaFile, PocketPlaybackLook>) -> MonitorPlaybackSourceValues {
        let file = record.payload
        let grade = model.session.cacheGrade(for: file)
        let availability: MonitorPlaybackAvailability =
            grade == .original ? .original : grade.isProxyOnly ? .proxy : .camera
        let transfer = model.monitorTransfer ?? model.assist.monitorColorMode.map(MonitorTransfer.init)
        return .init(availability: availability,
            progress: model.session.mediaDownloadProgress[file.path],
            colorLabel: model.session.shotColor(for: file)?.label,
            transfer: transfer,
            clipByte: transfer.map { model.frameSamples.exposureCeiling.clipByte(transfer: $0) },
            bufferedThroughSeconds: presentation.bufferedThroughSeconds(record: record, owner: owner))
    }
}
