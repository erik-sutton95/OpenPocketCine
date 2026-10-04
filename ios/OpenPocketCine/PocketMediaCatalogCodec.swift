import Foundation
import OpenCineAppKit
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore

/// Existing camera namespace and preference schema; the shared owner keeps the local set.
@MainActor final class PocketMediaFavoritesStore: MonitorMediaFavoritesStore {
    private let preferences: UserDefaults
    private let key: String
    init(cameraID: String, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        key = "opc.media.fav." + cameraID
    }
    func favorites() -> Set<String> { Set(preferences.stringArray(forKey: key) ?? []) }
    func saveFavorites(_ keys: Set<String>) { preferences.set(keys.sorted(), forKey: key) }
}

/// Only Pocket's exact index.json payload/cache addresses/color interpretation belong here.
/// Query, catalog collection, cache entry scans, filtering and selection belong to the owner.
@MainActor final class PocketMediaCatalogCodec: MonitorMediaCatalogCodec {
    typealias Payload = MediaFile
    private let source: () -> DjiAppleMediaService?
    private let sourceOwnsFavorites: () -> Bool
    private let shotColor: (MediaFile) -> UInt8?
    init(source: @escaping () -> DjiAppleMediaService?, sourceOwnsFavorites: @escaping () -> Bool,
        shotColor: @escaping (MediaFile) -> UInt8?) {
        self.source = source; self.sourceOwnsFavorites = sourceOwnsFavorites; self.shotColor = shotColor
    }
    func decode(_ bytes: Data) throws -> [MonitorMediaRecord<MediaFile>] {
        try JSONDecoder().decode([MediaFile].self, from: bytes).map { record($0, includeDisplayFacts: false) }
    }
    func encode(_ records: [MonitorMediaRecord<MediaFile>]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let files = records.map { record in
            var file = record.payload; file.isStarred = record.favorite; return file
        }
        return try encoder.encode(files)
    }
    func record(_ file: MediaFile, includeDisplayFacts: Bool = true) -> MonitorMediaRecord<MediaFile> {
        let asset = DjiAppleMediaAssets.asset(for: file)
        var representations: [MediaRepresentationID: String] = [:]
        var alternatives: [MediaRepresentationID: [String]] = [:]
        for representation in asset.representations {
            switch representation.role {
            case .original:
                representations[representation.id] = "files/" + cacheName(file.path)
            case .proxy:
                let paths = MediaHTTP.proxyPaths(file).map { "play/" + MediaHTTP.playbackCacheFileName($0) }
                if let canonical = paths.first {
                    representations[representation.id] = canonical
                    alternatives[representation.id] = Array(paths.dropFirst())
                }
            default: break
            }
        }
        return .init(asset: asset, payload: file, address: .init(
            thumbnail: "thumbs/" + cacheName(file.thumbPath) + ".jpg",
            representations: representations, favoriteKey: file.path, readAlternatives: alternatives),
            favorite: file.isStarred, facts: facts(file, includeColor: includeDisplayFacts),
            favoriteAuthority: sourceOwnsFavorites() ? .source : .localOverlay,
            sourceFavorite: file.isStarred)
    }
    func facts(_ file: MediaFile, includeColor: Bool = true) -> MonitorMediaFilterFacts {
        .init(format: file.fileExtension.isEmpty ? nil : file.fileExtension, resolution: file.resolution,
            dateKey: file.dateKey.isEmpty ? nil : file.dateKey, orderKey: file.filenameTimestamp,
            color: includeColor ? shotColor(file).map { String($0) } : nil,
            presentationKind: file.kind == .photo ? .photo : .video)
    }
    func capture(_ asset: MediaAsset, binding: MediaBrowseBinding) throws -> MonitorMediaRecord<MediaFile> {
        guard let captured = source()?.mediaCatalogRecord(asset.id, binding: binding) else {
            throw MediaServiceError.retired
        }
        let value = record(captured.file)
        guard value.asset.id == asset.id else { throw MediaServiceError.retired }
        return value
    }
    func captureCatalog(_ delta: MediaCatalogDelta, binding: MediaBrowseBinding,
        existing: [MonitorMediaRecord<MediaFile>]) throws -> MonitorMediaCatalogCapture<MediaFile> {
        let incoming = try delta.upserts.map { try capture($0, binding: binding) }
        let removed = Set(delta.removed)
        var order = delta.reset ? [] : existing.filter { !removed.contains($0.asset.id) }.map(\.asset.id)
        // Actual newest-page rows appear first, without parsing their opaque asset identity.
        if !delta.reset {
            let incomingIDs = Set(incoming.map(\.asset.id))
            order = incoming.map(\.asset.id) + order.filter { !incomingIDs.contains($0) }
        }
        var favorites: Set<String>?
        if sourceOwnsFavorites() {
            let retained = delta.reset ? [] : existing.filter { !removed.contains($0.asset.id) }
            var values = Dictionary(retained.map { ($0.asset.id, $0) }, uniquingKeysWith: { _, newer in newer })
            for record in incoming { values[record.asset.id] = record }
            favorites = Set(values.values.filter { $0.sourceFavorite == true }.map { $0.address.favoriteKey })
        }
        return .init(resetLibrary: delta.reset, upserts: incoming, removed: delta.removed,
            order: delta.reset ? nil : order, sourceFavoriteKeys: favorites)
    }
    private func cacheName(_ path: String) -> String { path.replacingOccurrences(of: "/", with: "_") }
}
