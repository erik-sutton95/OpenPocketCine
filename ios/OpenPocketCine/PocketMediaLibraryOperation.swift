import Foundation
import OpenCineAppKit
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore

/// Host IO admission, separate from source query/return admission. No captured absence grants
/// camera readiness. An unindexed playback request retains its original native test contract.
@MainActor struct PocketMediaLibraryOperation {
    let cameraID: String
    let library: MonitorMediaLibraryModel<MediaFile>
    let authority: MonitorMediaLibraryIOAuthority
    var id: UUID { authority.id }
    var directory: MonitorMediaCacheDirectory { authority.directory }
    var generation: UInt64 { authority.generation }
    private let admit: @MainActor (Bool) -> Bool
    private let wire: @MainActor () -> Bool

    init(session: CameraSession, file: MediaFile) {
        cameraID = session.mediaCameraID
        let owner = session.mediaLibrary, token = owner.actionToken
        library = owner
        let namespace = cameraID, directory = owner.cache.directory, generation = directory.generation
        let asset = DjiAppleMediaAssets.asset(for: file).id
        let hadRecord = owner.records.contains(where: { $0.payload.id == file.id }) == true
        let connection = session.control.id, camera = session.connectedCamera?.id
        let driver = session.datalink, target = session.control.target
        let source = session.cameraMedia.mediaPort?.mediaFacts?.identity
        let admitted: @MainActor (Bool) -> Bool = { [weak session] allowingRemoval in
            guard let session, !Task.isCancelled, directory.generation == generation,
                session.mediaCameraID == namespace, session.control.id == connection,
                session.connectedCamera?.id == camera, session.datalink === driver else { return false }
            guard session.mediaLibraryOwner === owner, owner.isCurrent(token) else { return false }
            let current = owner.records.first { $0.payload.id == file.id }
            return hadRecord && !allowingRemoval ? current?.asset.id == asset : (current == nil || current?.asset.id == asset)
        }
        admit = admitted
        authority = owner.captureIO(key: .init(file.path), asset: hadRecord ? asset : nil,
            ifCurrent: { admitted(false) })
        wire = { [weak session] in
            guard let session, session.control.target == target else { return false }
            return session.cameraMedia.mediaPort?.mediaFacts?.identity == source
        }
    }
    var isCurrent: Bool { authority.isCurrent }
    var canWriteWire: Bool { admit(false) && wire() }
    var canRetireDeletedContent: Bool { admit(true) && wire() }
    func requireCurrent() throws { try authority.requireCurrent() }
}

extension CameraSession {
    func commitMediaDownload(file: MediaFile, path: String, destination: URL,
        operation: PocketMediaLibraryOperation,
        fetch: @escaping @MainActor (URL) async throws -> Void) async throws -> URL {
        try operation.requireCurrent()
        let prefix = operation.directory.root.path + "/"
        guard destination.path.hasPrefix(prefix) else { throw MonitorMediaCacheError.invalidAddress }
        let expected = path == file.path && file.sizeBytes > 0 ? file.sizeBytes : nil
        guard let location = try await operation.library.cacheHostStagedFile(operation.authority,
            purpose: .playback, at: String(destination.path.dropFirst(prefix.count)),
            expectedByteCount: expected, staging: fetch) else { throw MediaServiceError.unavailable }
        return location
    }
}
