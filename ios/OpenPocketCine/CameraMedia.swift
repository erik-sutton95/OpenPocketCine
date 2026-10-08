import Foundation
import OpenCineAppKit
import OpenCineApple
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore

/// Operator-facing media notes. Never name a sister app or another camera brand.
enum MediaOperatorCopy {
    static let listing = "Listing camera clips…"
    static let notConnected = "Connect the camera to list clips."
    static let playbackFailed = "Camera did not enter playback."
    static let browsingOnCamera = "Playback is open on the camera. Close to return to live view."
    static let noClips = "No clips on the camera."
    static let listFailed = "Could not list camera clips."
    static let notDeletable = "That clip cannot be deleted from here."
    static let deleteFailed = "Could not delete that clip."
    static let downloadFailed = "Could not download that clip."
    static let thumbFailed = "Could not load that thumbnail."
    static let clipOpenFailed = "Could not open that clip."
    static let clipLoading = "Loading clip from camera…"
    static let clipNotCached = "This clip is not cached on the phone."
}

/// Playback-held media list + SoftAP HTTP cache. Owned by `CameraSession`.
@MainActor
final class CameraMedia {
    private let fileManager: FileManager
    private let httpConfiguration: URLSessionConfiguration
    // One declared canonical root shared by gallery, cache actions and retained native IO.
    private lazy var cacheOwner = MonitorMediaCacheRoot(
        root: applicationSupport.appendingPathComponent("OpenPocketCine/media", isDirectory: true),
        fileManager: fileManager, accountLegacyUnpreparedRoots: true)
    #if DEBUG && targetEnvironment(simulator)
        private lazy var reviewDirectory = MonitorMediaCacheDirectory(
            root: MonitorMediaReview.cacheRoot, fileManager: fileManager, accountLegacyUnpreparedRoots: true)
    #endif

    private lazy var applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]

    init(
        fileManager: FileManager = .default,
        httpConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        self.fileManager = fileManager
        self.httpConfiguration = httpConfiguration
    }

    var mediaPort: PocketMediaPort?
    var mediaService: DjiAppleMediaService?
    let returnSession = MonitorMediaReturnSession()
    var resumeLiveTask: Task<Void, Never>? { returnSession.task }
    var resumeID: Int { returnSession.generation }
    let httpSource = DJIMediaHTTPSource()
    private var colorMapCache: (cameraID: String, generation: UInt64, map: [String: Int])?

    private lazy var http: URLSession = {
        let cfg = httpConfiguration.copy() as! URLSessionConfiguration
        cfg.allowsCellularAccess = false
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()
    private lazy var stream: MonitorMediaHTTPStream = {
        let cfg = httpConfiguration.copy() as! URLSessionConfiguration
        cfg.allowsCellularAccess = false
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 600
        return MonitorMediaHTTPStream(configuration: cfg)
    }()

    func cancelResumeLive() { returnSession.cancel() }

    func resetSession() {
        cancelResumeLive()
        mediaService?.retire()
        mediaService = nil
        mediaPort = nil
        httpSource.reset()
    }

    func sharedCache(cameraID: String, sourceOwnsFavorites: @escaping () -> Bool = { false },
        persistEmptyCatalog: Bool = false)
        -> (MonitorMediaCache<MediaFile>, PocketMediaCatalogCodec) {
        let directory = cacheDirectory(cameraID: cameraID)
        let codec = PocketMediaCatalogCodec(source: { [weak self] in self?.mediaService },
            sourceOwnsFavorites: sourceOwnsFavorites, shotColor: { [weak self] file in
                self?.shotColor(for: file.path, cameraID: cameraID)?.rawValue
            })
        return (MonitorMediaCache(directory: directory, codec: codec,
            eligibility: .minimumFraction(numerator: 9, denominator: 10), catalogAddress: "index.json",
            preservedMetadata: ["index.json", "color.json"], persistEmptyCatalog: persistEmptyCatalog), codec)
    }

    func cacheDirectory(cameraID: String) -> MonitorMediaCacheDirectory {
        #if DEBUG && targetEnvironment(simulator)
            if MonitorMediaReview.isActive { return reviewDirectory }
        #endif
        if let directory = try? cacheOwner.directory(namespace: cameraID) { return directory }
        // The factory performs only namespace validation. This fixed legacy fallback is valid,
        // so the second lookup returns the same shared directory without IO or another owner.
        return cacheDirectory(cameraID: "unknown")
    }

    /// Valid flat legacy namespaces keep their exact spelling. Invalid saved routing never grants
    /// source readiness and uses the existing unknown bucket without rewriting the saved value.
    func cacheNamespace(cameraID: String) -> String {
        (try? cacheOwner.directory(namespace: cameraID)) == nil ? "unknown" : cameraID
    }

    func cacheRoot(cameraID: String) -> URL { cacheDirectory(cameraID: cameraID).root }

    func thumbnailCacheURL(cameraID: String, file: MediaFile) -> URL {
        cacheRoot(cameraID: cameraID)
            .appendingPathComponent("thumbs", isDirectory: true)
            .appendingPathComponent(Self.cacheName(file.thumbPath) + ".jpg")
    }

    func fileCacheURL(cameraID: String, file: MediaFile) -> URL {
        cacheRoot(cameraID: cameraID)
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent(Self.cacheName(file.path))
    }

    /// Local copy used only for playback. Originals share the download cache so a
    /// play-to-open of the full file counts as downloaded.
    func playbackCacheURL(cameraID: String, file: MediaFile, path: String) -> URL {
        if path == file.path { return fileCacheURL(cameraID: cameraID, file: file) }
        return cacheRoot(cameraID: cameraID)
            .appendingPathComponent("play", isDirectory: true)
            .appendingPathComponent(MediaHTTP.playbackCacheFileName(path))
    }

    func resolvedStorage(for file: MediaFile, singleSd: Bool) -> Int {
        httpSource.resolvedStorage(for: file, singleSDStorage: singleSd)
    }

    func rememberStorage(_ storage: Int, for path: String) {
        httpSource.rememberStorage(storage, path: path)
    }

    func getData(url: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await http.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw MediaTransferError.badResponse }
        return (data, http)
    }

    /// Last 2 MiB of the original take — LRF Keys are Rec.709 even for log.
    func getRange(url: URL, range: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue(range, forHTTPHeaderField: "Range")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let (data, response) = try await http.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MediaTransferError.badResponse }
        return (data, http)
    }

    func streamFile(from url: URL, expected: UInt64?, into sink: any MediaByteSink)
        async throws -> MediaTransferReceipt {
        do { return try await stream.transfer(from: url, expectedByteCount: expected, into: sink) }
        catch MonitorMediaHTTPError.status(let status) { throw MediaTransferError.httpStatus(status) }
        catch MonitorMediaHTTPError.empty { throw MediaTransferError.badResponse }
    }

    func catalogURL(cameraID: String) -> URL {
        cacheRoot(cameraID: cameraID).appendingPathComponent("index.json")
    }

    func colorStoreURL(cameraID: String) -> URL {
        cacheRoot(cameraID: cameraID).appendingPathComponent("color.json")
    }

    func shotColor(for path: String, cameraID: String) -> ColorMode? {
        migrateLegacyShotColors(cameraID: cameraID)
        guard let raw = loadColorMap(cameraID: cameraID)[path],
            let mode = ColorMode(rawValue: UInt8(truncatingIfNeeded: raw))
        else { return nil }
        return mode
    }

    func rememberShotColor(_ color: ColorMode, path: String, cameraID: String) {
        migrateLegacyShotColors(cameraID: cameraID)
        var map = loadColorMap(cameraID: cameraID)
        map[path] = Int(color.rawValue)
        persistColorMap(map, cameraID: cameraID)
    }

    private func loadColorMap(cameraID: String) -> [String: Int] {
        let generation = cacheDirectory(cameraID: cameraID).generation
        if let cached = colorMapCache, cached.cameraID == cameraID, cached.generation == generation { return cached.map }
        let url = colorStoreURL(cameraID: cameraID)
        let map: [String: Int]
        if let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        {
            map = decoded
        } else {
            map = [:]
        }
        colorMapCache = (cameraID, cacheDirectory(cameraID: cameraID).generation, map)
        return map
    }

    private func persistColorMap(_ map: [String: Int], cameraID: String) {
        colorMapCache = (cameraID, cacheDirectory(cameraID: cameraID).generation, map)
        do {
            let data = try JSONEncoder().encode(map)
            try cacheDirectory(cameraID: cameraID).write(data, at: "color.json")
        } catch {
            ControlLiveLog.line("media: color store write failed \(error.localizedDescription)")
        }
    }

    private func migrateLegacyShotColors(cameraID: String) {
        let legacyKey = "OpenPocketCine.ClipShotColor"
        guard let raw = UserDefaults.standard.dictionary(forKey: legacyKey) as? [String: Int],
            !raw.isEmpty
        else { return }
        var map = loadColorMap(cameraID: cameraID)
        for (path, code) in raw where map[path] == nil {
            map[path] = code
        }
        persistColorMap(map, cameraID: cameraID)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    func persistCatalog(_ files: [MediaFile], cameraID: String) {
        let (cache, codec) = sharedCache(cameraID: cameraID, persistEmptyCatalog: true)
        do { try cache.save(files.map { codec.record($0, includeDisplayFacts: false) }) }
        catch { ControlLiveLog.line("media: catalog write failed \(error.localizedDescription)") }
    }

    func loadCatalog(cameraID: String) -> [MediaFile] {
        sharedCache(cameraID: cameraID).0.load().map(\.payload)
    }

    /// Snapshot disk state once per catalog/cache revision, away from SwiftUI body evaluation.
    /// Compatibility entry point for the original native goldens and retained actual HTTP IO.
    /// Immutable source facts and paths are captured here; all file stats run in the shared worker.
    func cacheEntries(cameraID: String, files: [MediaFile]) async -> [String: MediaCacheEntry] {
        let (cache, codec) = sharedCache(cameraID: cameraID)
        let records = files.map { codec.record($0, includeDisplayFacts: false) }
        guard let snapshot = try? await cache.snapshot(records) else { return [:] }
        return Dictionary(records.map { record in
            let entry = snapshot.entries[record.asset.id]
            return (record.payload.path, MediaCacheEntry(
                grade: .resolve(hasOriginal: entry?.originalURL != nil, hasProxy: entry?.proxyURL != nil),
                originalURL: entry?.originalURL, thumbnailURL: entry?.thumbnailURL))
        }, uniquingKeysWith: { _, newer in newer })
    }

    func cacheByteCount(cameraID: String) async -> UInt64 {
        await sharedCache(cameraID: cameraID).0.directory.totalByteCount()
    }

    func clearCache(cameraID: String, preservingCatalog: Bool) async throws {
        let directory = sharedCache(cameraID: cameraID).0.directory
        try await directory.clear(preserving: preservingCatalog ? ["index.json", "color.json"] : [])
    }

    func writeAtomically(_ data: Data, to dest: URL) throws {
        // Retained compatibility/native IO accepts only one of the actual composed cache roots.
        #if DEBUG && targetEnvironment(simulator)
            if MonitorMediaReview.isActive {
                let prefix = reviewDirectory.root.path + "/"
                guard dest.path.hasPrefix(prefix) else { throw MonitorMediaCacheError.invalidAddress }
                try reviewDirectory.write(data, at: String(dest.path.dropFirst(prefix.count)))
                return
            }
        #endif
        let root = cacheOwner.root.path + "/"
        guard dest.path.hasPrefix(root) else { throw MonitorMediaCacheError.invalidAddress }
        let relative = String(dest.path.dropFirst(root.count))
        guard let boundary = relative.firstIndex(of: "/") else { throw MonitorMediaCacheError.invalidAddress }
        let namespace = String(relative[..<boundary])
        let address = String(relative[relative.index(after: boundary)...])
        try cacheOwner.directory(namespace: namespace).write(data, at: address)
    }

    nonisolated static func existingFile(
        _ url: URL, fileManager: FileManager = .default
    ) -> URL? {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
            !isDir.boolValue
        else { return nil }
        if let size = try? fileManager.attributesOfItem(atPath: url.path)[.size]
            as? NSNumber,
            size.intValue <= 0
        {
            return nil
        }
        return url
    }

    private nonisolated static func cacheName(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "_")
    }
}

struct MediaCacheEntry: Sendable {
    var grade: MediaCacheGrade
    var originalURL: URL?
    var thumbnailURL: URL?
}

typealias MediaTransferError = DJIMediaHTTPError

struct MediaPlaybackSource: Equatable {
    var url: URL
    var mimeType: String
    var isRemote: Bool
    var path: String
}

extension CameraSession {
    func beginMediaBrowse() {
        let library = mediaLibrary
        guard !library.browsing else { return }
        cameraMedia.cancelResumeLive()
        retireLivePictureRecoveryForMedia()
        mediaOperationNote = nil
        library.visibility = isLivePhase ? .allRecords : .cachedOnly
        guard hasMediaDatalink, isLivePhase else {
            library.bind(nil)
            library.begin()
            datalink?.setMediaBrowsing(false)
            mediaOperationNote = library.records.isEmpty ? MediaOperatorCopy.notConnected : nil
            return
        }
        let seam = control, target = control.target, camera = connectedCamera?.id, driver = datalink
        library.begin(acquiring: { [weak self] in
            guard let self, self.control === seam, self.control.target == target,
                self.connectedCamera?.id == camera, self.datalink === driver else { return nil }
            let producer = await self.connectedMediaService()
            guard !Task.isCancelled, self.mediaLibraryOwner === library,
                self.control === seam, self.control.target == target,
                self.connectedCamera?.id == camera, self.datalink === driver else { return nil }
            return producer
        }, unavailableNote: MediaOperatorCopy.notConnected)
    }

    func endMediaBrowse() { endMediaBrowse(returning: nil) }

    /// The integration provides the loop; this adapter claims the existing genuine recovery slot.
    func endMediaBrowse(returning: (@MainActor (Int) async -> Void)?) {
        if returning == nil {
            let hadBrowse = mediaLibraryOwner?.binding != nil
            mediaLibraryOwner?.close()
            mediaOperationNote = nil
            if hadBrowse { return }
        }
        let connection = control.id, camera = connectedCamera?.id
        let admitted = hasMediaDatalink || hasFeedRecoveryInFlight
        cameraMedia.returnSession.start(ifCurrent: { [weak self] token in
            guard let self else { return false }
            return admitted && self.control.id == connection && self.connectedCamera?.id == camera
                && self.isLivePictureRepairCurrent(token)
        }, operation: { [weak self] token in
            guard let self else { return }
            // A genuine rejoin may temporarily have no driver. Claiming its recovery slot waits
            // behind negotiation; presentation retirement never cancels that existing owner.
            await self.claimMediaLiveRecovery(token: token) { [weak self] in
                guard let self, self.control.id == connection,
                    self.connectedCamera?.id == camera, self.isLivePictureRepairCurrent(token) else { return }
                if let returning { await returning(token) }
                else { await self.resumeLiveViewAfterMedia(token: token) }
            }
        }, completed: { [weak self] _ in
            if let self, !self.isBrowsingMedia { self.datalink?.setMediaBrowsing(false) }
        })
        if !admitted { datalink?.setMediaBrowsing(false) }
    }

    /// Mimo "Back to live view": keep sending `0x02/0x0c` exit until the camera
    /// drops the playback bit, then `0x09/0xa8`. Enable while still in playback
    /// ACKs `E0`/`D6` and the camera stays on "Playback in progress".
    func mediaReturnAuthority(token: Int) -> DjiAppleMediaReturnAuthority {
        let started = Date()
        return .init(
            isCurrent: { self.isLivePictureRepairCurrent(token) },
            inPlayback: { self.status.inPlayback },
            pictureFresh: { self.hasFreshRecoveryPicture(since: started) },
            exitPlayback: {
                ControlLiveLog.line(
                    "media: exit playback inPlayback=\(self.status.inPlayback ? 1 : 0)")
                do {
                    let reply = try await self.awaitMediaOpcode(
                        0x02, 0x0C, timeout: .milliseconds(450)
                    ) {
                        self.sendExitPlayback()
                    }
                    return CameraReply.parse(reply.payload).isSuccess
                } catch {
                    return false
                }
            },
            enableLiveView: { self.restartLiveViewAfterMedia() },
            completed: { result in
                guard !Task.isCancelled, self.isLivePictureRepairCurrent(token) else { return }
                switch result {
                case .restored:
                    ControlLiveLog.line("media: live resume has fresh picture")
                case .exhausted:
                    ControlLiveLog.line("media: live resume picture deadline or exit budget expired")
                    self.beginSessionRecovery(
                        reason: "live picture did not return after media", trigger: .datalinkLost)
                case .superseded:
                    break
                }
            })
    }

    func resumeLiveViewAfterMedia(token: Int) async {
        let authority = mediaReturnAuthority(token: token)
        let result = await DjiAppleMediaLiveReturn.run(
            isCurrent: authority.isCurrent, inPlayback: authority.inPlayback,
            pictureFresh: authority.pictureFresh, exitPlayback: authority.exitPlayback,
            enableLiveView: authority.enableLiveView)
        authority.completed(result)
    }

    func refreshMedia() { Task { await self.refreshMedia() } }
    func refreshMedia() async {
        guard hasMediaDatalink, isLivePhase else {
            mediaOperationNote = MediaOperatorCopy.notConnected; return
        }
        if !isBrowsingMedia { beginMediaBrowse(); return }
        if !mediaLibrary.canRefresh, !mediaLibrary.acquiringSource {
            mediaLibrary.close(); beginMediaBrowse(); return
        }
        guard !mediaLibrary.fetching else { return }
        mediaOperationNote = nil
        mediaLibrary.refresh()
    }

    func ensureThumbnail(for file: MediaFile) async {
        guard canReachCameraMedia, thumbnailURL(for: file) == nil else { return }
        let operation = PocketMediaLibraryOperation(session: self, file: file)
        do {
            let destination = cameraMedia.thumbnailCacheURL(cameraID: operation.cameraID, file: file)
            try await operation.library.ensureHostThumbnail(operation.authority,
                at: try mediaCacheAddress(destination, operation: operation)) {
                try await self.fetchMediaBytes(file: file, path: MediaHTTP.thumbnailPath(file), operation: operation)
            }
        } catch {
            if operation.isCurrent, mediaNote == nil { mediaNote = MediaOperatorCopy.thumbFailed }
        }
    }

    /// Retained native image fallback: the raw catalog thumbnail path and stamped storage,
    /// without a second cache writer or any image decoding in the source adapter.
    func thumbnailBytes(for file: MediaFile) async -> Data? {
        let operation = PocketMediaLibraryOperation(session: self, file: file)
        guard canReachCameraMedia, operation.canWriteWire,
            let url = MediaHTTP.pathURL(storage: file.storage, path: file.thumbPath) else { return nil }
        let source = cameraMedia
        do {
            return try await operation.library.readHostThumbnail(operation.authority) {
                try operation.requireCurrent()
                guard operation.canWriteWire else { throw MediaServiceError.retired }
                let (bytes, _) = try await source.getData(url: url)
                try operation.requireCurrent()
                guard operation.canWriteWire else { throw MediaServiceError.retired }
                return bytes
            }
        } catch { return nil }
    }

    /// One uncached photo read at the original stamped address. The Library owns its task;
    /// the captured SDK source and exact record must still admit the requesting picture.
    func originalImageBytes(for file: MediaFile,
        ifCurrent: @escaping @MainActor () -> Bool) async -> Data? {
        let content: MediaFile = { var value = file; value.isStarred = false; return value }()
        let library = mediaLibrary
        guard file.kind == .photo, canReachCameraMedia,
            let record = library.records.first(where: {
                var candidate = $0.payload; candidate.isStarred = false
                return candidate == content
            }), let url = MediaHTTP.pathURL(storage: file.storage, path: file.path) else { return nil }
        let operation = PocketMediaLibraryOperation(session: self, file: file)
        let source = cameraMedia
        let current: @MainActor () -> Bool = { [weak self] in
            guard let self, self.canReachCameraMedia, operation.isCurrent, operation.canWriteWire,
                self.mediaLibraryOwner === library,
                let present = library.record(record.asset.id) else { return false }
            var candidate = present.payload; candidate.isStarred = false
            return candidate == content
        }
        let authority = library.captureIO(key: operation.authority.key, asset: record.asset.id) {
            guard current() else { return false }
            let allowed = ifCurrent()
            return allowed && current()
        }
        do {
            return try await library.readHostOriginalImage(authority) {
                try authority.requireCurrent()
                let (bytes, _) = try await source.getData(url: url)
                try authority.requireCurrent()
                return bytes
            }
        } catch { return nil }
    }

    func download(file: MediaFile) async {
        let operation = PocketMediaLibraryOperation(session: self, file: file)
        guard operation.isCurrent else { return }
        if isDownloaded(file) {
            operation.library.completeHostTransfer(operation.authority, role: .original)
            return
        }
        guard canReachCameraMedia else { mediaNote = MediaOperatorCopy.clipNotCached; return }
        let destination = cameraMedia.fileCacheURL(cameraID: operation.cameraID, file: file)
        do {
            guard let location = try await operation.library.cacheHostFile(operation.authority,
                purpose: .download, at: try mediaCacheAddress(destination, operation: operation),
                plan: mediaTransferPlan(file: file, path: MediaHTTP.deliveryPath(file), operation: operation)) else { return }
            try operation.requireCurrent()
            if let mode = ClipColorProfile.shotColor(at: location, path: file.path) {
                rememberShotColor(mode, for: file, operation: operation)
            }
            operation.library.completeHostTransfer(operation.authority, role: .original)
        } catch {
            guard operation.isCurrent else { return }
            operation.library.clearHostProgress(operation.authority)
            mediaNote = MediaOperatorCopy.downloadFailed
            ControlLiveLog.line("media: download failed \(file.filename) \(error.localizedDescription)")
        }
    }

    func localURL(for file: MediaFile) -> URL? {
        CameraMedia.existingFile(mediaFileDest(file))
    }

    /// Shot color for Auto LUT. Never the LRF/XRF sidecar (Rec.709 even on D-Log2).
    func fetchOriginalShotColor(for file: MediaFile) async -> ColorMode? {
        let operation = PocketMediaLibraryOperation(session: self, file: file)
        guard operation.isCurrent else { return nil }
        if let url = localURL(for: file),
            let mode = ClipColorProfile.shotColor(at: url, path: file.path)
        {
            rememberShotColor(mode, for: file, operation: operation)
            return mode
        }
        if let cached = shotColor(for: file) { return cached }
        guard canReachCameraMedia else { return nil }
        let range = ClipColorProfile.httpRange(fileSize: file.sizeBytes)
        let first = cameraMedia.resolvedStorage(for: file, singleSd: usesSingleSdStorage)
        let second = first == 0 ? 1 : 0
        let cap = ClipColorProfile.fileTailBytes * 3
        for storage in [first, second] {
            guard let url = MediaHTTP.pathURL(storage: storage, path: file.path) else { continue }
            do {
                try operation.requireCurrent()
                let (data, response) = try await cameraMedia.getRange(url: url, range: range)
                try operation.requireCurrent()
                guard (200...299).contains(response.statusCode) else { continue }
                if data.count > cap {
                    ControlLiveLog.line(
                        "media: clip color range ignored (\(data.count) bytes) \(file.path)")
                    continue
                }
                if let mode = ClipColorProfile.colorMode(fromMP4: data) {
                    cameraMedia.rememberStorage(storage, for: file.path)
                    rememberShotColor(mode, for: file, operation: operation)
                    return mode
                }
            } catch {
                continue
            }
        }
        return nil
    }

    func shotColor(for file: MediaFile) -> ColorMode? {
        cameraMedia.shotColor(for: file.path, cameraID: mediaCameraID)
    }

    func rememberShotColor(_ color: ColorMode, for file: MediaFile) {
        rememberShotColor(color, for: file, operation: .init(session: self, file: file))
    }

    func rememberShotColor(_ color: ColorMode, for file: MediaFile, operation: PocketMediaLibraryOperation) {
        guard operation.isCurrent else { return }
        cameraMedia.rememberShotColor(color, path: file.path, cameraID: operation.cameraID)
        guard operation.isCurrent, let owner = mediaLibraryOwner,
            let record = mediaRecord(for: file) else { return }
        let previous = record.facts
        let facts = MonitorMediaFilterFacts(format: previous.format, resolution: previous.resolution,
            dateKey: previous.dateKey, orderKey: previous.orderKey, color: String(color.rawValue),
            presentationKind: previous.presentationKind)
        try? owner.updateLocalFacts([record.asset.id: facts], token: owner.actionToken)
    }

    func cacheGrade(for file: MediaFile) -> MediaCacheGrade {
        MediaCacheGrade.resolve(
            hasOriginal: isDownloaded(file),
            hasProxy: localProxySource(for: file) != nil)
    }

    func thumbnailURL(for file: MediaFile) -> URL? {
        CameraMedia.existingFile(mediaThumbDest(file))
    }

    func isDownloaded(_ file: MediaFile) -> Bool {
        guard let url = localURL(for: file) else { return false }
        guard file.sizeBytes > 0 else { return true }
        let onDisk =
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .uint64Value ?? 0
        // Manifest size is the original. A short write (error page, cut transfer)
        // must not count as cached.
        return onDisk >= file.sizeBytes * 9 / 10
    }

    func remotePlaybackURL(for file: MediaFile) -> URL? {
        let storage = cameraMedia.resolvedStorage(for: file, singleSd: usesSingleSdStorage)
        for path in MediaHTTP.previewPaths(file) {
            if let url = MediaHTTP.pathURL(storage: storage, path: path) {
                return url
            }
        }
        return nil
    }

    /// Cached file if we already pulled this clip. Does not touch the camera.
    /// A thumbnail or a short/failed original write is not a playback source.
    func localPlaybackSource(for file: MediaFile) -> MediaPlaybackSource? {
        if let proxy = localProxySource(for: file) { return proxy }
        if isDownloaded(file), let local = localURL(for: file) {
            return MediaPlaybackSource(
                url: local,
                mimeType: MediaHTTP.playbackMIMEType(for: file.path),
                isRemote: false,
                path: file.path)
        }
        return nil
    }

    /// 720p LRF/XRF sidecar, never the 4K original.
    func localProxySource(for file: MediaFile) -> MediaPlaybackSource? {
        for path in MediaHTTP.proxyPaths(file) {
            let dest = mediaPlaybackDest(file, path: path)
            if let existing = CameraMedia.existingFile(dest) {
                return MediaPlaybackSource(
                    url: existing,
                    mimeType: MediaHTTP.playbackMIMEType(for: path),
                    isRemote: false,
                    path: path)
            }
        }
        return nil
    }

    /// Original or playable proxy on disk. A `.scr` thumb does not count.
    func isAvailableOffline(_ file: MediaFile) -> Bool {
        localPlaybackSource(for: file) != nil
    }

    var canReachCameraMedia: Bool { hasMediaDatalink && isLivePhase }

    /// Local cache, then the first `/v2` URL that actually answers 2xx.
    /// Does not HEAD-probe — camera HEAD on `/v2` can sit until the session
    /// resource timeout and leave the player on "Buffering from camera…".
    func resolvePlaybackSource(for file: MediaFile) async -> MediaPlaybackSource? {
        localPlaybackSource(for: file)
    }

    /// Remaining `/v2` URLs after `source`, same storage-first order.
    func remainingPlaybackSources(
        for file: MediaFile, after source: MediaPlaybackSource
    ) -> [MediaPlaybackSource] {
        let first = cameraMedia.resolvedStorage(for: file, singleSd: usesSingleSdStorage)
        let all = MediaHTTP.playbackCandidates(file: file, firstStorage: first)
        var seenSource = false
        var out: [MediaPlaybackSource] = []
        for candidate in all {
            if !seenSource {
                if candidate.path == source.path { seenSource = true }
                continue
            }
            if candidate.path == source.path { continue }
            if out.contains(where: { $0.path == candidate.path }) { continue }
            guard let url = MediaHTTP.pathURL(storage: candidate.storage, path: candidate.path)
            else { continue }
            out.append(
                MediaPlaybackSource(
                    url: url,
                    mimeType: MediaHTTP.playbackMIMEType(for: candidate.path),
                    isRemote: true,
                    path: candidate.path))
        }
        return out
    }

    func cachePlaybackFile(file: MediaFile, path: String) async throws -> URL {
        let operation = PocketMediaLibraryOperation(session: self, file: file)
        try operation.requireCurrent()
        let destination = cameraMedia.playbackCacheURL(cameraID: operation.cameraID, file: file, path: path)
        if let existing = CameraMedia.existingFile(destination) { return existing }
        guard canReachCameraMedia else { throw MediaTransferError.timeout }
        guard let location = try await operation.library.cacheHostFile(operation.authority,
            purpose: .playback, at: try mediaCacheAddress(destination, operation: operation),
            plan: mediaTransferPlan(file: file, path: path, operation: operation)) else {
            throw MediaServiceError.unavailable
        }
        try operation.requireCurrent()
        operation.library.completeHostTransfer(operation.authority, role: path == file.path ? .original : .proxy)
        return location
    }

    /// Actual source routing supplies the stream. The library stages each real attempt before
    /// handing its accepted body to the shared player's borrowed canonical writer.
    func transferPlaybackFile(
        file: MediaFile, path: String, authority: PocketPlaybackAuthority,
        into sink: any MediaByteSink
    ) async throws -> MediaTransferReceipt {
        let operation = authority.operation
        try operation.requireCurrent()
        guard authority.admission.isCurrent(), canReachCameraMedia else { throw MediaTransferError.timeout }
        let receipt = try await operation.library.transferHostFile(operation.authority, into: sink,
            plan: mediaTransferPlan(file: file, path: path, operation: operation,
                ifCurrent: authority.admission.isCurrent), stagingRoot: FileManager.default.temporaryDirectory)
        try operation.requireCurrent()
        guard authority.admission.isCurrent() else { throw MonitorPlaybackError.retired }
        return receipt
    }

    func playbackTransferCommitted(file: MediaFile, path: String, authority: PocketPlaybackAuthority) {
        let operation = authority.operation
        guard operation.isCurrent, authority.admission.isCurrent() else { return }
        operation.library.completeHostTransfer(operation.authority, role: path == file.path ? .original : .proxy)
    }

    private func mediaPlaybackDest(_ file: MediaFile, path: String) -> URL {
        cameraMedia.playbackCacheURL(cameraID: mediaCameraID, file: file, path: path)
    }

    func deleteMedia(_ file: MediaFile) {
        Task { await self.deleteMedia(file) }
    }

    func deleteMedia(_ file: MediaFile) async {
        let operation = PocketMediaLibraryOperation(session: self, file: file)
        guard operation.canWriteWire else { return }
        let library = mediaLibrary, token = mediaLibrary.actionToken
        guard file.isDeletable else {
            mediaNote = MediaOperatorCopy.notDeletable
            return
        }
        guard isBrowsingMedia, hasMediaDatalink else {
            mediaNote = MediaOperatorCopy.notConnected
            return
        }
        guard let producer = cameraMedia.mediaService, let binding = token.binding,
            let asset = mediaRecord(for: file)?.asset.id else { return }
        var acked = false
        do {
            acked = try await producer.deleteAsset(asset, binding: binding)
        } catch {
            acked = false
        }
        guard operation.canWriteWire, library.isCurrent(token), !Task.isCancelled else { return }
        if !acked {
            await listNewestMediaPage(token: token)
            guard operation.canRetireDeletedContent, library.isCurrent(token), !Task.isCancelled else { return }
            if mediaFiles.contains(where: { $0.path == file.path }) {
                mediaNote = MediaOperatorCopy.deleteFailed
                return
            }
        }
        let ids = Set(library.records.filter { $0.payload.path == file.path }.map(\.asset.id))
        try? library.applyLocalRemoval(ids, token: token)
        if library.isCurrent(token) { library.clearHostProgress(operation.authority) }
    }

    func toggleMediaFavorite(_ file: MediaFile) {
        let operation = PocketMediaLibraryOperation(session: self, file: file)
        guard operation.isCurrent else { return }
        let library = mediaLibrary, token = library.actionToken
        guard let current = mediaRecord(for: file) else { return }
        let on = !current.favorite
        var local = PocketMediaFavoritesStore(cameraID: operation.cameraID).favorites()
        if on { local.insert(file.path) } else { local.remove(file.path) }
        // The original Apple action changes the first actual path row only, writes the local
        // preferences immediately, and leaves index.json persistence to the next real listing.
        var amendments: [MonitorMediaRecord<MediaFile>] = []
        if let first = library.records.first(where: { $0.payload.path == file.path }) {
            var changed = first.payload; changed.isStarred = on
            amendments = [cameraMedia.sharedCache(cameraID: operation.cameraID,
                sourceOwnsFavorites: { self.mediaFavoritesAreSourceOwned }).1.record(changed)]
        }
        do { try library.applyLocalRecords(.init(resetLibrary: false, upserts: [],
            amendments: amendments, sourceFavoriteKeys: local), token: token, persist: false) }
        catch { return }
        guard operation.canWriteWire else { return }
        guard hasMediaDatalink, isBrowsingMedia, let producer = cameraMedia.mediaService,
            let binding = token.binding else { return }
        Task {
            guard operation.canWriteWire, library.isCurrent(token) else { return }
            try? await producer.setFavorite(current.asset.id, on: on, binding: binding)
        }
    }

    func isMediaFavorite(_ file: MediaFile) -> Bool {
        mediaRecord(for: file)?.favorite ?? file.isStarred
    }

    func isFavorite(_ file: MediaFile) -> Bool { isMediaFavorite(file) }

    func toggleFavorite(_ file: MediaFile) { toggleMediaFavorite(file) }

    func deleteMediaFiles(_ files: [MediaFile]) async {
        for file in files {
            await deleteMedia(file)
        }
    }

    // Actual newest cursor is collected by the same gallery owner and captured browse lease.
    private func listNewestMediaPage(token: MonitorMediaLibraryActionToken) async {
        guard let binding = token.binding, let producer = cameraMedia.mediaService,
            mediaLibrary.isCurrent(token) else { return }
        do { try await mediaLibrary.reconcileCatalog(producer.newestCatalog(binding: binding),
            binding: binding, token: token) }
        catch { if mediaLibrary.isCurrent(token) { mediaOperationNote = MediaOperatorCopy.listFailed } }
    }

    private static let lastMediaCameraKey = "opc.media.lastCameraID"

    /// Cache lives under the camera id. After disconnect `connectedCamera` is
    /// nil — keep the last id so cached clips stay findable offline.
    var mediaCameraID: String {
        if let id = connectedCamera?.id.uuidString {
            if UserDefaults.standard.string(forKey: Self.lastMediaCameraKey) != id {
                UserDefaults.standard.set(id, forKey: Self.lastMediaCameraKey)
            }
            return id
        }
        return cameraMedia.cacheNamespace(
            cameraID: UserDefaults.standard.string(forKey: Self.lastMediaCameraKey) ?? "unknown")
    }

    var mediaFavoritesAreSourceOwned: Bool { cameraMedia.mediaService?.sourcePolicy?.sourceOwnsFavorites == true }

    private var usesSingleSdStorage: Bool { cameraMedia.mediaService?.sourcePolicy?.singleSDStorage == true }

    private func mediaThumbDest(_ file: MediaFile) -> URL {
        cameraMedia.thumbnailCacheURL(cameraID: mediaCameraID, file: file)
    }

    private func mediaFileDest(_ file: MediaFile) -> URL {
        cameraMedia.fileCacheURL(cameraID: mediaCameraID, file: file)
    }

    private func mediaCacheAddress(_ destination: URL, operation: PocketMediaLibraryOperation) throws -> String {
        let prefix = operation.directory.root.path + "/"
        guard destination.path.hasPrefix(prefix) else { throw MonitorMediaCacheError.invalidAddress }
        return String(destination.path.dropFirst(prefix.count))
    }

    private func mediaTransferPlan(file: MediaFile, path: String, operation: PocketMediaLibraryOperation,
        ifCurrent: @escaping @MainActor () -> Bool = { true }) -> MediaTransferPlan {
        let source = cameraMedia, singleSD = usesSingleSdStorage
        return source.httpSource.transferPlan(file: file, path: path, singleSDStorage: singleSD) { resource, expected, sink in
            try operation.requireCurrent()
            guard ifCurrent() else { throw MonitorPlaybackError.retired }
            let receipt = try await source.streamFile(from: resource.url, expected: expected, into: sink)
            try operation.requireCurrent()
            guard ifCurrent() else { throw MonitorPlaybackError.retired }
            return receipt
        }
    }

    private func fetchMediaBytes(file: MediaFile, path: String, operation: PocketMediaLibraryOperation) async throws -> Data {
        let source = cameraMedia
        return try await source.httpSource.read(file: file, path: path, singleSDStorage: usesSingleSdStorage,
            ifCurrent: { operation.isCurrent }) { resource in
            let (data, response) = try await source.getData(url: resource.url)
            return .init(data: data, status: response.statusCode)
        }
    }

    private func uniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}
