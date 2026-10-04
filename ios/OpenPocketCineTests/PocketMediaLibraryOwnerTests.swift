import Foundation
import OpenCineAppKit
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

private final class LibraryOwnerFileManager: FileManager, @unchecked Sendable {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        directory == .applicationSupportDirectory ? [support] : super.urls(for: directory, in: domainMask)
    }
}

/// SIMULATED real adopter wiring. Original library/cache/recovery assertions remain unchanged.
@MainActor final class PocketMediaLibraryOwnerTests: XCTestCase {
    func testMalformedSavedOfflineRoutingUsesSharedUnknownDirectoryWithoutRewritingPreference() {
        let manager = LibraryOwnerFileManager()
        let media = CameraMedia(fileManager: manager)
        let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
        let key = "opc.media.lastCameraID"
        let preferences = UserDefaults.standard
        let previous = preferences.object(forKey: key)
        defer {
            if let previous {
                preferences.set(previous, forKey: key)
            } else {
                preferences.removeObject(forKey: key)
            }
            session.disconnect()
            session.decoder.close()
            try? FileManager.default.removeItem(at: manager.support)
        }
        let unknown = media.cacheDirectory(cameraID: "unknown")
        for saved in ["", ".", "..", "bad/namespace", "bad\\namespace"] {
            preferences.set(saved, forKey: key)
            XCTAssertEqual(session.mediaCameraID, "unknown")
            XCTAssertEqual(preferences.string(forKey: key), saved)
            XCTAssertTrue(media.cacheDirectory(cameraID: saved) === unknown)
            XCTAssertEqual(
                media.catalogURL(cameraID: saved), unknown.root.appendingPathComponent("index.json")
            )
            XCTAssertNil(session.mediaLibrary.binding)
            XCTAssertTrue(session.mediaLibrary.catalog.assets.isEmpty)
        }
    }

    func testValidFlatOfflineRoutingPreservesExactNamespaceIndexAndFavoriteKeys() throws {
        let manager = LibraryOwnerFileManager()
        let media = CameraMedia(fileManager: manager)
        let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
        let key = "opc.media.lastCameraID"
        let preferences = UserDefaults.standard
        let previous = preferences.object(forKey: key)
        let suite = "SIMULATED.routing." + UUID().uuidString
        let local = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            if let previous {
                preferences.set(previous, forKey: key)
            } else {
                preferences.removeObject(forKey: key)
            }
            local.removePersistentDomain(forName: suite)
            session.disconnect()
            session.decoder.close()
            try? FileManager.default.removeItem(at: manager.support)
        }
        for saved in [
            "SIMULATED-flat", "test.camera_ID-1", "unknown", "12345678-1234-1234-1234-123456789abc",
        ] {
            preferences.set(saved, forKey: key)
            XCTAssertEqual(session.mediaCameraID, saved)
            XCTAssertEqual(preferences.string(forKey: key), saved)
            let expected = manager.support.appendingPathComponent(
                "OpenPocketCine/media", isDirectory: true
            )
            .appendingPathComponent(saved, isDirectory: true)
            XCTAssertEqual(media.cacheRoot(cameraID: saved), expected)
            XCTAssertEqual(
                media.catalogURL(cameraID: saved), expected.appendingPathComponent("index.json"))
            XCTAssertTrue(
                media.cacheDirectory(cameraID: saved) === media.cacheDirectory(cameraID: saved))
            let favorites = PocketMediaFavoritesStore(
                cameraID: session.mediaCameraID, preferences: local)
            favorites.saveFavorites(["DCIM/ORIGINAL.MP4"])
            XCTAssertEqual(
                local.stringArray(forKey: "opc.media.fav." + saved), ["DCIM/ORIGINAL.MP4"])
            XCTAssertEqual(favorites.favorites(), ["DCIM/ORIGINAL.MP4"])
        }
    }

    func testActualHostKeepsOneGalleryLifetimeAcrossRepeatedNestedReads() {
        let manager = LibraryOwnerFileManager(), media = CameraMedia(fileManager: manager)
        let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
        defer { session.disconnect(); session.decoder.close(); try? FileManager.default.removeItem(at: manager.support) }
        let library = session.mediaLibrary
        session.beginMediaBrowse()
        let captured = library.actionToken
        XCTAssertTrue(session.isBrowsingMedia)
        session.beginMediaBrowse()
        XCTAssertTrue(session.mediaLibrary === library)
        XCTAssertEqual(session.mediaLibrary.actionToken, captured)
        XCTAssertNil(library.binding)
        XCTAssertTrue(library.catalog.assets.isEmpty)
        session.endMediaBrowse()
        XCTAssertFalse(library.browsing)
        XCTAssertFalse(library.isCurrent(captured))
        session.beginMediaBrowse()
        XCTAssertTrue(session.mediaLibrary === library)
        XCTAssertNotEqual(library.actionToken, captured)
    }

    func testLegacyCodecPreservesExactIndexBytesAndProxyAddressOrder() throws {
        let codec = PocketMediaCatalogCodec(source: { nil }, sourceOwnsFavorites: { false }, shotColor: { _ in nil })
        let file = MediaFile(path: "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4",
            thumbPath: "MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr", handle: 0x40100880,
            cmdHandle: 0x40100880, sizeBytes: 2048, durationSeconds: 209, isStarred: true,
            resolution: "3840x2160", fps: 25, storage: 1, storageKnown: true,
            group: 4, handleShared: false, handleCandidate: 0x40100880)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let record = codec.record(file)
        XCTAssertEqual(try codec.encode([record]), try encoder.encode([file]))
        XCTAssertEqual(try codec.decode(encoder.encode([file])).map(\.payload), [file])
        XCTAssertEqual(record.asset, DjiAppleMediaAssets.asset(for: file))
        XCTAssertEqual(record.address.thumbnail, "thumbs/MISC_THM_DJI_001_DJI_20260814125250_0034_D.scr.jpg")
        let proxy = try XCTUnwrap(record.asset.representations.first { $0.role == .proxy })
        let paths = MediaHTTP.proxyPaths(file).map { "play/" + MediaHTTP.playbackCacheFileName($0) }
        XCTAssertEqual(record.address.representations[proxy.id], paths.first)
        XCTAssertEqual(record.address.readAlternatives[proxy.id], Array(paths.dropFirst()))
        XCTAssertEqual(record.favoriteAuthority, .localOverlay)
    }

    func testActualSharedOwnerMatchesOriginalFilterSortAndRetiresCapturedHostMetadata() throws {
        let manager = LibraryOwnerFileManager(), media = CameraMedia(fileManager: manager)
        defer { try? FileManager.default.removeItem(at: manager.support) }
        let (cache, codec) = media.sharedCache(cameraID: "SIMULATED-library-golden")
        let files = [
            MediaFile(path: "DJI_20260814125250_0034_D.MP4", thumbPath: "A.scr", resolution: "3840x2160"),
            MediaFile(path: "DJI_20260404103742_0001_D.MP4", thumbPath: "B.scr", isStarred: true, resolution: "1920x1080"),
            MediaFile(path: "DJI_20260801000000_0002_D.JPG", thumbPath: "C.scr")]
        let suite = "SIMULATED.library-owner." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let owner = MonitorMediaLibraryModel(cache: cache, favorites: PocketMediaFavoritesStore(cameraID: suite, preferences: preferences),
            initialCatalog: .init(), initialRecords: files.map { codec.record($0) })
        defer { owner.close() }
        owner.visibility = .allRecords; owner.category = .videos; owner.sort = .newest
        XCTAssertEqual(owner.displayedRecords.map(\.payload), MediaLibraryQuery.sorted(MediaLibraryQuery.filtered(files, tab: .videos), by: .newest))
        owner.category = .all; owner.formats = ["MP4"]; owner.dateStart = "20260801"
        XCTAssertEqual(owner.displayedRecords.map(\.payload), MediaLibraryQuery.filtered(files, tab: .all, formats: ["MP4"], dateStart: "20260801"))
        owner.resetFilters(); owner.category = .favorites
        XCTAssertEqual(owner.displayedRecords.map(\.payload), MediaLibraryQuery.filtered(files, tab: .favorites))
        owner.category = .all; owner.selectAll()
        XCTAssertEqual(owner.selectedRecords.count, 3)
        XCTAssertTrue(owner.catalog.assets.isEmpty, "Local cache does not manufacture a camera catalog")
        let token = owner.actionToken; owner.close()
        XCTAssertThrowsError(try owner.applyLocalRecords(.init(resetLibrary: true, upserts: []), token: token))
        XCTAssertEqual(owner.records.count, 3)
    }
    func testActualCodecAndSharedOwnerPreserveOriginalManifestFilterExpectedValues() throws {
        let manager = LibraryOwnerFileManager(), media = CameraMedia(fileManager: manager)
        defer { try? FileManager.default.removeItem(at: manager.support) }
        let (cache, codec) = media.sharedCache(cameraID: "SIMULATED-filter")
        let files = [
            MediaFile(path: "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4", thumbPath: "new.scr", resolution: "3840x2160"),
            MediaFile(path: "DCIM/DJI_001/DJI_20260404103742_0001_D.MP4", thumbPath: "old.scr", isStarred: true, resolution: "1920x1080"),
            MediaFile(path: "DCIM/DJI_001/DJI_20260801000000_0002_D.JPG", thumbPath: "photo.scr")]
        let suite = "SIMULATED.filter." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let owner = MonitorMediaLibraryModel(cache: cache,
            favorites: PocketMediaFavoritesStore(cameraID: suite, preferences: preferences),
            initialCatalog: .init(), initialRecords: files.map { codec.record($0) })
        defer { owner.close() }
        owner.visibility = .allRecords
        owner.category = .favorites; XCTAssertEqual(owner.displayedRecords.count, 1)
        owner.category = .all; owner.formats = ["MP4"]; XCTAssertEqual(owner.displayedRecords.count, 2)
        owner.formats = []; owner.resolutions = ["3840x2160"]; XCTAssertEqual(owner.displayedRecords.count, 1)
        owner.resolutions = []; owner.dateStart = "20260801"
        XCTAssertEqual(owner.displayedRecords.map(\.payload.filename), ["DJI_20260814125250_0034_D.MP4", "DJI_20260801000000_0002_D.JPG"])
        owner.dateStart = nil; owner.dateEnd = "20260501"
        XCTAssertEqual(owner.displayedRecords.map(\.payload.filename), ["DJI_20260404103742_0001_D.MP4"])
        owner.dateStart = "20260801"; owner.dateEnd = "20260801"
        XCTAssertEqual(owner.displayedRecords.map(\.payload.filename), ["DJI_20260801000000_0002_D.JPG"])
        owner.resetFilters(); owner.category = .videos; owner.sort = .newest
        XCTAssertEqual(owner.displayedRecords.first?.payload.filename, "DJI_20260814125250_0034_D.MP4")
    }

    func testActualCodecAndSharedOfflineVisibilityHideThumbnailOnlyRows() throws {
        let manager = LibraryOwnerFileManager(), media = CameraMedia(fileManager: manager)
        defer { try? FileManager.default.removeItem(at: manager.support) }
        let (cache, codec) = media.sharedCache(cameraID: "SIMULATED-offline")
        let cached = MediaFile(path: "DCIM/DJI_001/CACHED.MP4", thumbPath: "MISC/THM/CACHED.scr")
        let thumb = MediaFile(path: "DCIM/DJI_001/THUMB_ONLY.MP4", thumbPath: "MISC/THM/THUMB_ONLY.scr")
        let records = [cached, thumb].map { codec.record($0) }
        let original = try XCTUnwrap(records[0].asset.representations.first { $0.role == .original })
        try cache.directory.write(Data([1]), at: try XCTUnwrap(records[0].address.representations[original.id]))
        try cache.directory.write(Data([2]), at: try XCTUnwrap(records[1].address.thumbnail))
        let owner = MonitorMediaLibraryModel(cache: cache, favorites: PocketMediaFavoritesStore(cameraID: "SIMULATED-offline"),
            initialCatalog: .init(), initialRecords: records)
        defer { owner.close() }
        owner.visibility = .cachedOnly
        XCTAssertEqual(owner.displayedRecords.map(\.payload.filename), ["CACHED.MP4"])
        XCTAssertEqual(owner.entries[records[1].asset.id]?.thumbnailURL?.lastPathComponent, "MISC_THM_THUMB_ONLY.scr.jpg")
        XCTAssertTrue(owner.catalog.assets.isEmpty)
    }

    func testRenderedSelectionRejectsRecycledPageKeyAndReadsCurrentSameFrameSelection() throws {
        let manager = LibraryOwnerFileManager(), media = CameraMedia(fileManager: manager)
        let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
        defer { session.disconnect(); session.decoder.close(); try? FileManager.default.removeItem(at: manager.support) }
        let owner = session.mediaLibrary
        let (_, codec) = media.sharedCache(cameraID: session.mediaCameraID)
        let first = MediaFile(path: "DCIM/REUSED.MP4", thumbPath: "same.scr", handle: 1, sizeBytes: 10)
        var successor = first; successor.handle = 2; successor.sizeBytes = 20
        let old = codec.record(first), next = codec.record(successor)
        XCTAssertEqual(first.id, successor.id); XCTAssertNotEqual(old.asset.id, next.asset.id)
        try owner.applyLocalRecords(.init(resetLibrary: true, upserts: [old]), token: owner.actionToken)
        let captured = PocketMediaLibraryPresentation(owner: owner)
        XCTAssertTrue(captured.select([first.id])); XCTAssertEqual(captured.selectedIDs, [first.id])
        XCTAssertTrue(captured.select([])); XCTAssertTrue(captured.selectedIDs.isEmpty)
        try owner.applyLocalRecords(.init(resetLibrary: true, upserts: [next]), token: owner.actionToken)
        XCTAssertNil(captured.file(first.id)); XCTAssertFalse(captured.select([first.id]))
        XCTAssertTrue(owner.selectedIDs.isEmpty)
        let current = PocketMediaLibraryPresentation(owner: owner)
        XCTAssertTrue(current.select([successor.id])); XCTAssertEqual(owner.selectedIDs, [next.asset.id])
        owner.close(); XCTAssertFalse(current.select([]))
    }

    func testCapturedHostCompletionRejectsReplacementAndCanonicalClear() async throws {
        let manager = LibraryOwnerFileManager(), media = CameraMedia(fileManager: manager)
        let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
        defer { session.disconnect(); session.decoder.close(); try? FileManager.default.removeItem(at: manager.support) }
        let owner = session.mediaLibrary
        let (_, codec) = media.sharedCache(cameraID: session.mediaCameraID)
        let first = MediaFile(path: "DCIM/REUSED.MP4", thumbPath: "same.scr", handle: 1, sizeBytes: 10)
        var successor = first; successor.handle = 2; successor.sizeBytes = 20
        try owner.applyLocalRecords(.init(resetLibrary: true, upserts: [codec.record(first)]), token: owner.actionToken)
        let old = PocketMediaLibraryOperation(session: session, file: first)
        XCTAssertTrue(old.isCurrent)
        try owner.applyLocalRecords(.init(resetLibrary: true, upserts: [codec.record(successor)]), token: owner.actionToken)
        XCTAssertFalse(old.isCurrent)
        session.rememberShotColor(.dLog, for: first, operation: old)
        XCTAssertNil(media.shotColor(for: first.path, cameraID: session.mediaCameraID))
        let current = PocketMediaLibraryOperation(session: session, file: successor)
        XCTAssertTrue(current.isCurrent)
        try await media.clearCache(cameraID: session.mediaCameraID, preservingCatalog: true)
        XCTAssertFalse(current.isCurrent)
        session.rememberShotColor(.dLog2, for: successor, operation: current)
        XCTAssertNil(media.shotColor(for: successor.path, cameraID: session.mediaCameraID))
    }

    func testAcceptedMetadataPublishesSharedColorFactAndClearRetiresWarmMap() async throws {
        let manager = LibraryOwnerFileManager(), media = CameraMedia(fileManager: manager)
        let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
        defer { session.disconnect(); session.decoder.close(); try? FileManager.default.removeItem(at: manager.support) }
        let owner = session.mediaLibrary
        let (_, codec) = media.sharedCache(cameraID: session.mediaCameraID)
        let file = MediaFile(path: "DCIM/COLOR.MP4", thumbPath: "color.scr")
        let record = codec.record(file)
        try owner.applyLocalRecords(.init(resetLibrary: true, upserts: [record]), token: owner.actionToken)
        session.rememberShotColor(.dLog2, for: file)
        XCTAssertEqual(owner.record(record.asset.id)?.facts.color, String(ColorMode.dLog2.rawValue))
        XCTAssertEqual(media.shotColor(for: file.path, cameraID: session.mediaCameraID), .dLog2)
        XCTAssertTrue(owner.catalog.assets.isEmpty); XCTAssertEqual(owner.catalogPageCount, 0)
        try await media.clearCache(cameraID: session.mediaCameraID, preservingCatalog: false)
        XCTAssertNil(media.shotColor(for: file.path, cameraID: session.mediaCameraID))
    }

    func testActualFavoriteActionPreservesFirstPathRowPreferencesAndDeferredIndexWrite() throws {
        let manager = LibraryOwnerFileManager(), media = CameraMedia(fileManager: manager)
        let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
        defer { session.disconnect(); session.decoder.close(); try? FileManager.default.removeItem(at: manager.support) }
        let first = MediaFile(path: "DCIM/FAVORITE.MP4", thumbPath: "favorite.scr", storage: 0, storageKnown: true)
        let second = MediaFile(path: first.path, thumbPath: first.thumbPath, storage: 1, storageKnown: true)
        let prefs = PocketMediaFavoritesStore(cameraID: session.mediaCameraID)
        let previousFavorites = prefs.favorites(); defer { prefs.saveFavorites(previousFavorites) }
        prefs.saveFavorites([])
        media.persistCatalog([first, second], cameraID: session.mediaCameraID)
        let index = media.catalogURL(cameraID: session.mediaCameraID), originalBytes = try Data(contentsOf: index)
        let owner = session.mediaLibrary
        session.toggleMediaFavorite(second)
        XCTAssertEqual(owner.records.map(\.payload.isStarred), [true, false])
        XCTAssertTrue(owner.records.allSatisfy(\.favorite))
        XCTAssertEqual(prefs.favorites(), [first.path])
        XCTAssertEqual(try Data(contentsOf: index), originalBytes)
        XCTAssertTrue(owner.catalog.assets.isEmpty)
        session.toggleMediaFavorite(second)
        XCTAssertEqual(owner.records.map(\.payload.isStarred), [false, false])
        XCTAssertTrue(owner.records.allSatisfy { !$0.favorite }); XCTAssertTrue(prefs.favorites().isEmpty)
        XCTAssertEqual(try Data(contentsOf: index), originalBytes)
    }

    func testDelayedActualHostDownloadCannotCommitOverAcceptedSuccessorWriter() async throws {
        let manager = LibraryOwnerFileManager(), media = CameraMedia(fileManager: manager)
        let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
        defer { session.disconnect(); session.decoder.close(); try? FileManager.default.removeItem(at: manager.support) }
        let owner = session.mediaLibrary
        let file = MediaFile(path: "DCIM/STAGED.MP4", thumbPath: "staged.scr")
        let operation = PocketMediaLibraryOperation(session: session, file: file)
        let destination = media.fileCacheURL(cameraID: session.mediaCameraID, file: file)
        let gate = LibraryOwnerDownloadGate()
        let old = Task { () -> Bool in
            do {
                _ = try await session.commitMediaDownload(file: file, path: file.path,
                    destination: destination, operation: operation) { incoming in
                    try Data([1, 2]).write(to: incoming)
                    await gate.hold()
                }
                return true
            } catch { return false }
        }
        for _ in 0..<2000 { if gate.pending != nil { break }; await Task.yield() }
        guard gate.pending != nil else { old.cancel(); XCTFail("Actual host download did not reach manual gate"); return }
        owner.begin()
        let prefix = operation.directory.root.path + "/"
        try operation.directory.write(Data([9]), at: String(destination.path.dropFirst(prefix.count)))
        gate.release()
        let accepted = await old.value
        XCTAssertFalse(accepted)
        XCTAssertEqual(try Data(contentsOf: destination), Data([9]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path), [destination.lastPathComponent])
    }
}

@MainActor private final class LibraryOwnerDownloadGate {
    var pending: CheckedContinuation<Void, Never>?
    func hold() async { await withCheckedContinuation { pending = $0 } }
    func release() { let captured = pending; pending = nil; captured?.resume() }
}
