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
                if owner.isActive { return true }
                owner.close()
                return false
            }
        }
        return owner
    }

    func mediaPlaybackRecord(for file: MediaFile) -> MonitorMediaRecord<MediaFile>? {
        if let record = mediaRecord(for: file) { return record }
        #if targetEnvironment(simulator)
            if MonitorMediaReview.isActive, file.path.hasPrefix(MonitorMediaReview.pathPrefix) {
                // The explicit simulator review accepts its fixture files outside its catalog, with
                // or without supplied footage: the player's controls work without it, as on main.
                // A typed local value is not inserted into a camera catalog or local index.
                let codec = PocketMediaCatalogCodec(
                    source: { nil }, sourceOwnsFavorites: { false }, shotColor: { _ in nil })
                return codec.record(file)
            }
        #endif
        return nil
    }

    func playbackCandidates(_ record: MonitorMediaRecord<MediaFile>) -> [MonitorPlaybackCandidate] {
        let file = record.payload
        #if targetEnvironment(simulator)
            if let url = MonitorMediaReview.clipURL(for: file) {
                return [.cached(.init(url: url, mimeType: "video/mp4", sourceKey: file.path))]
            }
        #endif
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

/// Bounded IO only. It neither names a canonical destination nor changes catalog or playback state.
enum PocketPlaybackStaging {
    static func copy(_ source: URL, into sink: any MediaByteSink) async throws -> UInt64 {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var count: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let chunk = try input.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { return count }
            try await sink.write(chunk)
            count += UInt64(chunk.count)
        }
    }
}
