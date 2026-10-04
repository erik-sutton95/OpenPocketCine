import Foundation
import OpenCineAppKit
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore

/// Host IO admission, separate from source query/return admission. No captured absence grants
/// camera readiness. An unindexed playback request retains its original native test contract.
@MainActor struct PocketMediaLibraryOperation {
    let id = UUID()
    let cameraID: String
    let directory: MonitorMediaCacheDirectory
    let generation: UInt64
    private let admit: @MainActor (Bool) -> Bool
    private let wire: @MainActor () -> Bool

    init(session: CameraSession, file: MediaFile) {
        cameraID = session.mediaCameraID
        directory = session.cameraMedia.cacheDirectory(cameraID: cameraID)
        generation = directory.generation
        let namespace = cameraID, directory = directory, generation = generation
        let owner = session.mediaLibrary, token = owner.actionToken
        let asset = DjiAppleMediaAssets.asset(for: file).id
        let hadRecord = owner.records.contains(where: { $0.payload.id == file.id }) == true
        let connection = session.control.id, camera = session.connectedCamera?.id
        let driver = session.datalink, target = session.control.target
        let source = session.cameraMedia.mediaPort?.mediaFacts?.identity
        admit = { [weak session] allowingRemoval in
            guard let session, !Task.isCancelled, directory.generation == generation,
                session.mediaCameraID == namespace, session.control.id == connection,
                session.connectedCamera?.id == camera, session.datalink === driver else { return false }
            guard session.mediaLibraryOwner === owner, owner.isCurrent(token) else { return false }
            let current = owner.records.first { $0.payload.id == file.id }
            return hadRecord && !allowingRemoval ? current?.asset.id == asset : (current == nil || current?.asset.id == asset)
        }
        wire = { [weak session] in
            guard let session, session.control.target == target else { return false }
            return session.cameraMedia.mediaPort?.mediaFacts?.identity == source
        }
    }
    var isCurrent: Bool { admit(false) }
    var canWriteWire: Bool { admit(false) && wire() }
    var canRetireDeletedContent: Bool { admit(true) && wire() }
    func requireCurrent() throws { guard isCurrent else { throw MediaServiceError.retired } }
}

/// Bounded disk-to-disk handoff. The original URLSession pump still streams before EOF;
/// this helper never materializes a movie in RAM and the shared lease alone commits its name.
private enum PocketMediaStaging {
    static func copy(_ source: URL, to writer: MonitorMediaCacheWrite) async throws -> UInt64 {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var count: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let chunk = try input.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { return count }
            try await writer.write(chunk)
            count += UInt64(chunk.count)
        }
    }
}

extension CameraSession {
    func commitMediaDownload(file: MediaFile, path: String, destination: URL,
        operation: PocketMediaLibraryOperation,
        fetch: (URL) async throws -> Void) async throws -> URL {
        try operation.requireCurrent()
        let prefix = operation.directory.root.path + "/"
        guard destination.path.hasPrefix(prefix) else { throw MonitorMediaCacheError.invalidAddress }
        let writer = try operation.directory.beginWrite(at: String(destination.path.dropFirst(prefix.count)))
        // The incoming name stays in the original destination directory. Existing native tests
        // inspect that directory while the HTTP pump is paused before its final body chunk.
        let incoming = destination.deletingLastPathComponent().appendingPathComponent(".incoming-" + operation.id.uuidString)
        defer { writer.abort(); try? FileManager.default.removeItem(at: incoming) }
        try await fetch(incoming)
        try operation.requireCurrent()
        let copy = Task.detached { try await PocketMediaStaging.copy(incoming, to: writer) }
        let count = try await withTaskCancellationHandler { try await copy.value } onCancel: { copy.cancel() }
        try Task.checkCancellation()
        try operation.requireCurrent()
        let expected = path == file.path && file.sizeBytes > 0 ? file.sizeBytes : nil
        return try writer.commit(.init(byteCount: count, expectedByteCount: expected))
    }
}
