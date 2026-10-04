import Foundation
import OpenCineAppKit
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore

extension CameraSession {
    /// One actual gallery owner per persisted camera namespace. Nested player/photo covers
    /// read this owner; only the gallery's parent closes it.
    var mediaLibrary: MonitorMediaLibraryModel<MediaFile> {
        let cameraID = mediaCameraID
        if let current = mediaLibraryOwner, mediaLibraryCameraID == cameraID { return current }
        let old = mediaLibraryOwner
        let (cache, codec) = cameraMedia.sharedCache(cameraID: cameraID,
            sourceOwnsFavorites: { [weak self] in self?.mediaFavoritesAreSourceOwned == true })
        let next = MonitorMediaLibraryModel(cache: cache,
            favorites: PocketMediaFavoritesStore(cameraID: cameraID), cacheScanning: .background, catalogBase: .freshListing,
            initialCatalog: .init(), initialRecords: cache.load().map { codec.record($0.payload) },
            copy: .init(openFailed: MediaOperatorCopy.listFailed,
                listFailed: MediaOperatorCopy.listFailed, downloadFailed: MediaOperatorCopy.downloadFailed,
                listing: MediaOperatorCopy.listing, empty: MediaOperatorCopy.noClips))
        mediaLibraryCameraID = cameraID
        mediaLibraryOwner = next
        old?.close()
        return next
    }

    func mediaRecord(for file: MediaFile) -> MonitorMediaRecord<MediaFile>? {
        mediaLibrary.record(DjiAppleMediaAssets.asset(for: file).id)
    }

    func libraryFile(_ record: MonitorMediaRecord<MediaFile>) -> MediaFile {
        var file = record.payload; file.isStarred = record.favorite; return file
    }

    func libraryEntry(for file: MediaFile) -> MediaCacheEntry? {
        guard let record = mediaRecord(for: file), let entry = mediaLibrary.entries[record.asset.id] else { return nil }
        return .init(grade: .resolve(hasOriginal: entry.originalURL != nil, hasProxy: entry.proxyURL != nil),
            originalURL: entry.originalURL, thumbnailURL: entry.thumbnailURL)
    }
}
