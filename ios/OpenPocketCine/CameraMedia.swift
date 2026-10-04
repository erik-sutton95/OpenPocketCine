import Foundation
import OpenCineAppKit
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore

/// Existing native goldens exercise the integration-owned finite return loop.
typealias MediaLiveResumeRunner = DjiAppleMediaLiveReturn

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
    var serviceTask: Task<Void, Never>?
    var serviceRequest = UUID()
    var resumeLiveTask: Task<Void, Never>?
    var resumeID = 0
    var actionCounter: UInt32 = 1
    var storageWinner: [String: Int] = [:]
    var thumbInFlight: [String: UUID] = [:]
    var downloadInFlight: [String: UUID] = [:]
    private var colorMapCache: (cameraID: String, generation: UInt64, map: [String: Int])?
    var progressOwner: [String: UUID] = [:]

    private let pump = MediaDownloadPump()
    private lazy var http: URLSession = {
        let cfg = httpConfiguration.copy() as! URLSessionConfiguration
        cfg.allowsCellularAccess = false
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()
    private lazy var downloadHTTP: URLSession = {
        let cfg = httpConfiguration.copy() as! URLSessionConfiguration
        cfg.allowsCellularAccess = false
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 600
        return URLSession(configuration: cfg, delegate: pump, delegateQueue: nil)
    }()

    func nextResumeID() -> Int {
        resumeID += 1
        return resumeID
    }

    func cancelResumeLive() {
        resumeLiveTask?.cancel()
        resumeLiveTask = nil
        resumeID += 1
    }

    func nextActionCounter() -> UInt32 {
        let value = actionCounter
        actionCounter &+= 1
        if actionCounter == 0 { actionCounter = 1 }
        return value
    }

    func resetSession() {
        serviceRequest = UUID()
        let old = serviceTask; serviceTask = nil; old?.cancel()
        cancelResumeLive()
        mediaService?.retire()
        mediaService = nil
        mediaPort = nil
        storageWinner.removeAll()
        thumbInFlight.removeAll()
        downloadInFlight.removeAll()
        progressOwner.removeAll()
        pump.cancelAll()
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
        MediaHTTP.resolvedStorage(
            stamped: file.storage,
            handle: file.handle != 0 ? file.handle : file.cmdHandle,
            winner: storageWinner[file.path],
            singleSdStorage: singleSd)
    }

    func rememberStorage(_ storage: Int, for path: String) {
        storageWinner[path] = storage
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

    /// Existence check that does not pull the body. HEAD first; ranged GET if the
    /// camera rejects HEAD. Cancels as soon as the status line is in.
    func probeExists(url: URL) async -> Bool {
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        head.timeoutInterval = 4
        if let (_, response) = try? await http.data(for: head),
            let http = response as? HTTPURLResponse
        {
            if (200...299).contains(http.statusCode) { return true }
            if http.statusCode == 404 || http.statusCode == 400 { return false }
        }
        var get = URLRequest(url: url)
        get.httpMethod = "GET"
        get.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        get.timeoutInterval = 4
        do {
            let (bytes, response) = try await http.bytes(for: get)
            bytes.task.cancel()
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    func downloadFile(
        from url: URL,
        to dest: URL,
        path: String,
        expectedSize: UInt64 = 0,
        onProgress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws {
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await pump.download(
            session: downloadHTTP, from: url, to: dest, path: path, expectedSize: expectedSize,
            onProgress: onProgress)
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
        pump.cancelAll()
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

enum MediaTransferError: Error {
    case badResponse
    case httpStatus(Int)
    case timeout
}

struct MediaPlaybackSource: Equatable {
    var url: URL
    var mimeType: String
    var isRemote: Bool
    var path: String
}

/// Streams `/v2` bodies to disk. A download-task wait-for-EOF hangs at 100% on
/// Pocket SoftAP (the camera often keeps the socket open after Content-Length).
final class MediaDownloadPump: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var task: URLSessionDataTask?

        func install(_ task: URLSessionDataTask) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            self.task = task
            return cancelled
        }

        func cancel() -> URLSessionDataTask? {
            lock.lock()
            defer { lock.unlock() }
            cancelled = true
            return task
        }
    }

    private struct Job {
        var task: URLSessionDataTask
        var dest: URL
        var tmp: URL
        var handle: FileHandle?
        var expected: UInt64
        var written: UInt64 = 0
        var onProgress: @MainActor @Sendable (Double) -> Void
        var continuation: CheckedContinuation<Void, Error>
        var finished = false
        var status: Int = 0
    }

    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]

    func download(
        session: URLSession,
        from url: URL,
        to dest: URL,
        path: String,
        expectedSize: UInt64,
        onProgress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws {
        _ = path
        var request = URLRequest(url: url)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let cancellation = Cancellation()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                let tmp = dest.deletingLastPathComponent()
                    .appendingPathComponent(UUID().uuidString + ".part")
                FileManager.default.createFile(atPath: tmp.path, contents: nil)
                let handle = try? FileHandle(forWritingTo: tmp)
                let task = session.dataTask(with: request)
                lock.lock()
                jobs[task.taskIdentifier] = Job(
                    task: task,
                    dest: dest,
                    tmp: tmp,
                    handle: handle,
                    expected: expectedSize,
                    onProgress: onProgress,
                    continuation: cont)
                lock.unlock()
                // Install only after registering the continuation. A cancellation
                // before installation is remembered; one after it removes the job.
                if cancellation.install(task) {
                    cancel(task: task)
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            if let task = cancellation.cancel() { self.cancel(task: task) }
        }
        try Task.checkCancellation()
    }

    private func cancel(task: URLSessionDataTask) {
        lock.lock()
        let job = jobs[task.taskIdentifier]
        if job?.finished == false { jobs[task.taskIdentifier] = nil }
        lock.unlock()
        task.cancel()
        guard let job, !job.finished else { return }
        try? job.handle?.close()
        try? FileManager.default.removeItem(at: job.tmp)
        job.continuation.resume(throwing: CancellationError())
    }

    func cancelAll() {
        lock.lock()
        let pending = jobs
        jobs.removeAll()
        lock.unlock()
        for job in pending.values {
            job.task.cancel()
            try? job.handle?.close()
            try? FileManager.default.removeItem(at: job.tmp)
            if !job.finished {
                job.continuation.resume(throwing: CancellationError())
            }
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let length = max(0, response.expectedContentLength)
        lock.lock()
        if var job = jobs[dataTask.taskIdentifier] {
            job.status = status
            if length > 0 { job.expected = UInt64(length) }
            jobs[dataTask.taskIdentifier] = job
        }
        lock.unlock()
        if status != 0, !(200...299).contains(status) {
            completionHandler(.cancel)
            finish(task: dataTask, error: MediaTransferError.httpStatus(status))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard var job = jobs[dataTask.taskIdentifier], !job.finished else {
            lock.unlock()
            return
        }
        do {
            try job.handle?.write(contentsOf: data)
            job.written += UInt64(data.count)
            jobs[dataTask.taskIdentifier] = job
            let written = job.written
            let expected = job.expected
            let progress = expected > 0 ? min(1, Double(written) / Double(expected)) : 0
            let taskID = dataTask.taskIdentifier
            let complete = expected > 0 && written >= expected
            lock.unlock()
            Task { @MainActor [weak self] in self?.publishProgress(progress, taskID: taskID) }
            if complete {
                dataTask.cancel()
                finish(task: dataTask, error: nil)
            }
        } catch {
            lock.unlock()
            finish(task: dataTask, error: error)
        }
    }

    @MainActor private func publishProgress(_ progress: Double, taskID: Int) {
        // Cancellation/completion may retire the transfer before this queued
        // publication runs. Never recreate the cleared progress entry afterward.
        lock.lock()
        let job = jobs[taskID]
        lock.unlock()
        guard let job, !job.finished else { return }
        job.onProgress(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
    {
        if let error, (error as NSError).code == NSURLErrorCancelled {
            lock.lock()
            let already = jobs[task.taskIdentifier]?.finished ?? true
            lock.unlock()
            if already { return }
        }
        finish(task: task, error: error)
    }

    private func finish(task: URLSessionTask, error: Error?) {
        lock.lock()
        guard var job = jobs[task.taskIdentifier], !job.finished else {
            lock.unlock()
            return
        }
        job.finished = true
        jobs[task.taskIdentifier] = job
        lock.unlock()

        try? job.handle?.close()

        if let error, (error as NSError).code != NSURLErrorCancelled {
            try? FileManager.default.removeItem(at: job.tmp)
            job.continuation.resume(throwing: error)
            lock.lock()
            jobs[task.taskIdentifier] = nil
            lock.unlock()
            return
        }

        do {
            guard job.written > 0, FileManager.default.fileExists(atPath: job.tmp.path) else {
                throw MediaTransferError.badResponse
            }
            if FileManager.default.fileExists(atPath: job.dest.path) {
                try FileManager.default.removeItem(at: job.dest)
            }
            try FileManager.default.moveItem(at: job.tmp, to: job.dest)
            lock.lock()
            jobs[task.taskIdentifier] = nil
            lock.unlock()
            job.continuation.resume()
        } catch {
            try? FileManager.default.removeItem(at: job.tmp)
            lock.lock()
            jobs[task.taskIdentifier] = nil
            lock.unlock()
            job.continuation.resume(throwing: error)
        }
    }
}

extension CameraSession {
    func beginMediaBrowse() {
        let library = mediaLibrary
        guard !library.browsing else { return }
        cameraMedia.cancelResumeLive()
        retireLivePictureRecoveryForMedia()
        mediaOperationNote = nil
        library.bind(nil)
        library.visibility = isLivePhase ? .allRecords : .cachedOnly
        library.begin()
        guard hasMediaDatalink, isLivePhase else {
            datalink?.setMediaBrowsing(false)
            mediaOperationNote = library.records.isEmpty ? MediaOperatorCopy.notConnected : nil
            return
        }
        let request = UUID(), lifetime = library.lifetimeToken
        cameraMedia.serviceRequest = request
        let old = cameraMedia.serviceTask; cameraMedia.serviceTask = nil; old?.cancel()
        guard cameraMedia.serviceRequest == request, library.lifetimeToken == lifetime else { return }
        cameraMedia.serviceTask = Task { [weak self] in
            guard let self else { return }
            let producer = await self.connectedMediaService()
            guard !Task.isCancelled, self.cameraMedia.serviceRequest == request,
                self.mediaLibraryOwner === library, library.lifetimeToken == lifetime, library.browsing else { return }
            self.cameraMedia.serviceTask = nil
            guard let producer else { self.mediaOperationNote = MediaOperatorCopy.notConnected; return }
            library.bind(producer)
        }
    }

    func endMediaBrowse() { endMediaBrowse(returning: nil) }

    /// The integration provides the loop; this host claims the existing genuine recovery slot.
    func endMediaBrowse(returning: (@MainActor (Int) async -> Void)?) {
        if returning == nil {
            cameraMedia.serviceRequest = UUID()
            let old = cameraMedia.serviceTask; cameraMedia.serviceTask = nil; old?.cancel()
            let hadBrowse = mediaLibraryOwner?.binding != nil
            mediaLibraryOwner?.close()
            mediaOperationNote = nil
            // The actual browse owns its same-session return. An offline/nil-driver opening
            // has no browse, so preserve the existing genuine recovery slot below.
            if hadBrowse { return }
        }
        cameraMedia.resumeLiveTask?.cancel()
        cameraMedia.resumeLiveTask = nil
        let token = cameraMedia.nextResumeID()
        // A full rejoin briefly has no driver while negotiating its replacement.
        // Preserve that owner and queue this return behind it, rather than lose
        // the only new picture/enable owner when the old generation retires.
        guard hasMediaDatalink || hasFeedRecoveryInFlight else {
            datalink?.setMediaBrowsing(false)
            return
        }
        cameraMedia.resumeLiveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if token == self.cameraMedia.resumeID {
                    self.cameraMedia.resumeLiveTask = nil
                    if !self.isBrowsingMedia { self.datalink?.setMediaBrowsing(false) }
                }
            }
            await self.claimMediaLiveRecovery(token: token) { [weak self] in
                guard let self else { return }
                if let returning {
                    await returning(token)
                } else {
                    await self.resumeLiveViewAfterMedia(token: token)
                }
            }
        }
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
        let result = await MediaLiveResumeRunner.run(
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
        if !mediaLibrary.canRefresh, cameraMedia.serviceTask == nil {
            mediaLibrary.close(); beginMediaBrowse(); return
        }
        guard !mediaLibrary.fetching else { return }
        mediaOperationNote = nil
        mediaLibrary.refresh()
    }

    func ensureThumbnail(for file: MediaFile) async {
        guard canReachCameraMedia, thumbnailURL(for: file) == nil else { return }
        let operation = PocketMediaLibraryOperation(session: self, file: file)
        guard operation.isCurrent, cameraMedia.thumbInFlight[file.path] == nil else { return }
        cameraMedia.thumbInFlight[file.path] = operation.id
        defer { if cameraMedia.thumbInFlight[file.path] == operation.id { cameraMedia.thumbInFlight[file.path] = nil } }
        do {
            let data = try await fetchMediaBytes(file: file, path: MediaHTTP.thumbnailPath(file), operation: operation)
            try operation.requireCurrent()
            guard !data.isEmpty else { throw MediaTransferError.badResponse }
            try cameraMedia.writeAtomically(data, to: cameraMedia.thumbnailCacheURL(cameraID: operation.cameraID, file: file))
            guard operation.isCurrent else { return }
            mediaIOCacheRevision &+= 1; mediaLibraryOwner?.refreshLocalCache()
        } catch {
            if operation.isCurrent, mediaNote == nil { mediaNote = MediaOperatorCopy.thumbFailed }
        }
    }

    func download(file: MediaFile) async {
        let operation = PocketMediaLibraryOperation(session: self, file: file)
        guard operation.isCurrent else { return }
        if isDownloaded(file) { finishDownloadProgress(file.path, operation: operation); return }
        guard canReachCameraMedia else { mediaNote = MediaOperatorCopy.clipNotCached; return }
        guard cameraMedia.downloadInFlight[file.path] == nil else { return }
        cameraMedia.downloadInFlight[file.path] = operation.id
        defer { if cameraMedia.downloadInFlight[file.path] == operation.id { cameraMedia.downloadInFlight[file.path] = nil } }
        cameraMedia.progressOwner[file.path] = operation.id
        mediaDownloadProgress[file.path] = 0
        let dest = cameraMedia.fileCacheURL(cameraID: operation.cameraID, file: file)
        do {
            _ = try await commitMediaDownload(file: file, path: MediaHTTP.deliveryPath(file), destination: dest,
                operation: operation) { incoming in
                try await self.fetchMediaFile(file: file, path: MediaHTTP.deliveryPath(file), to: incoming, operation: operation)
            }
            try operation.requireCurrent()
            if let mode = ClipColorProfileIO.shotColor(at: dest, path: file.path) {
                rememberShotColor(mode, for: file, operation: operation)
            }
            finishDownloadProgress(file.path, operation: operation)
        } catch {
            guard operation.isCurrent, cameraMedia.progressOwner[file.path] == operation.id else { return }
            mediaDownloadProgress[file.path] = nil
            mediaNote = MediaOperatorCopy.downloadFailed
            ControlLiveLog.line("media: download failed \(file.filename) \(error.localizedDescription)")
        }
    }

    /// A completion timer owns its exact progress operation, even when a successor reuses a path.
    private func finishDownloadProgress(_ path: String, operation: PocketMediaLibraryOperation) {
        guard operation.isCurrent else { return }
        cameraMedia.progressOwner[path] = operation.id
        mediaIOCacheRevision &+= 1; mediaLibraryOwner?.refreshLocalCache()
        guard operation.isCurrent, cameraMedia.progressOwner[path] == operation.id else { return }
        mediaDownloadProgress[path] = 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard operation.isCurrent, cameraMedia.progressOwner[path] == operation.id else { return }
            if mediaDownloadProgress[path] == 1 { mediaDownloadProgress[path] = nil }
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
            let mode = ClipColorProfileIO.shotColor(at: url, path: file.path)
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
        let dest = cameraMedia.playbackCacheURL(cameraID: operation.cameraID, file: file, path: path)
        if let existing = CameraMedia.existingFile(dest) { return existing }
        guard canReachCameraMedia else { throw MediaTransferError.timeout }
        cameraMedia.progressOwner[file.path] = operation.id
        mediaDownloadProgress[file.path] = 0
        do {
            let result = try await commitMediaDownload(file: file, path: path, destination: dest,
                operation: operation) { incoming in
                try await self.fetchMediaFile(file: file, path: path, to: incoming, operation: operation)
            }
            try operation.requireCurrent()
            if path == file.path {
                finishDownloadProgress(file.path, operation: operation)
            } else {
                mediaIOCacheRevision &+= 1; mediaLibraryOwner?.refreshLocalCache()
                if operation.isCurrent, cameraMedia.progressOwner[file.path] == operation.id { mediaDownloadProgress[file.path] = nil }
            }
            return result
        } catch {
            if operation.isCurrent, cameraMedia.progressOwner[file.path] == operation.id { mediaDownloadProgress[file.path] = nil }
            throw error
        }
    }

    /// The one existing HTTP/storage recipe supplies bytes; the shared player owns the
    /// canonical write and item readiness. Its private incoming file never becomes a cache row.
    func transferPlaybackFile(
        file: MediaFile, path: String, authority: PocketPlaybackAuthority,
        into sink: any MediaByteSink
    ) async throws -> MediaTransferReceipt {
        let operation = authority.operation
        try operation.requireCurrent()
        guard authority.admission.isCurrent(), canReachCameraMedia else {
            throw MediaTransferError.timeout
        }
        let incoming = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-player-" + operation.id.uuidString)
        defer { try? FileManager.default.removeItem(at: incoming) }
        cameraMedia.progressOwner[file.path] = operation.id
        mediaDownloadProgress[file.path] = 0
        do {
            try await fetchMediaFile(file: file, path: path, to: incoming, operation: operation)
            try operation.requireCurrent()
            guard authority.admission.isCurrent() else { throw MonitorPlaybackError.retired }
            let copy = Task.detached { try await PocketPlaybackStaging.copy(incoming, into: sink) }
            let count = try await withTaskCancellationHandler {
                try await copy.value
            } onCancel: {
                copy.cancel()
            }
            try Task.checkCancellation()
            try operation.requireCurrent()
            guard authority.admission.isCurrent() else { throw MonitorPlaybackError.retired }
            return .init(
                byteCount: count,
                expectedByteCount: path == file.path && file.sizeBytes > 0 ? file.sizeBytes : nil)
        } catch {
            if operation.isCurrent, cameraMedia.progressOwner[file.path] == operation.id {
                mediaDownloadProgress[file.path] = nil
            }
            throw error
        }
    }

    /// Invoked only after this shared cache writer commits under the captured content/root.
    func playbackTransferCommitted(
        file: MediaFile, path: String, authority: PocketPlaybackAuthority
    ) {
        let operation = authority.operation
        guard operation.isCurrent, authority.admission.isCurrent(),
            cameraMedia.progressOwner[file.path] == operation.id
        else { return }
        if path == file.path {
            finishDownloadProgress(file.path, operation: operation)
        } else {
            mediaIOCacheRevision &+= 1
            mediaLibraryOwner?.refreshLocalCache()
            if operation.isCurrent, cameraMedia.progressOwner[file.path] == operation.id {
                mediaDownloadProgress[file.path] = nil
            }
        }
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
        let handle = file.handle
        let counter = cameraMedia.nextActionCounter()
        let frame = Commands.deleteMedia(handle: handle, counter: counter)
        ControlLiveLog.line(
            "media: delete handle=\(String(format: "0x%08X", handle)) ctr=\(counter)")
        var acked = false
        do {
            let reply = try await awaitMediaOpcode(0x00, 0x28, timeout: .seconds(2)) {
                if operation.canWriteWire { self.sendMediaFrame(frame) }
            }
            acked =
                CameraReply.parse(reply.payload).isSuccess
                || reply.payload.starts(with: [0x00, 0x00])
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
        if library.isCurrent(token) { mediaDownloadProgress[file.path] = nil }
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
        let handle = file.favoriteHandle
        guard handle != 0, hasMediaDatalink, isBrowsingMedia else { return }
        let counter = cameraMedia.nextActionCounter()
        let frame = Commands.setMediaFavorite(
            handle: handle, on: on, counter: counter, model: connectedCamera?.model)
        ControlLiveLog.line("media: favorite handle=\(String(format: "0x%08X", handle)) on=\(on ? 1 : 0)")
        Task {
            guard operation.canWriteWire, library.isCurrent(token) else { return }
            _ = try? await self.awaitMediaOpcode(0x02, 0xBF, timeout: .milliseconds(900)) {
                if operation.canWriteWire { self.sendMediaFrame(frame) }
            }
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

    var mediaFavoritesAreSourceOwned: Bool { isNanoBody }

    private var isNanoBody: Bool {
        connectedCamera?.model.family == .nano
    }

    private var usesSingleSdStorage: Bool {
        if connectedCamera?.model.name.localizedCaseInsensitiveContains("Pocket 3") == true {
            return true
        }
        // Playback storage pushes are not topology evidence: Nano reports one zeroed block while
        // both internal and dock-SD manifests remain reachable.
        return !status.inPlayback && status.internalTotalMb == 0
    }

    private var isLivePhase: Bool {
        if case .live = phase { return true }
        return false
    }

    private func mediaThumbDest(_ file: MediaFile) -> URL {
        cameraMedia.thumbnailCacheURL(cameraID: mediaCameraID, file: file)
    }

    private func mediaFileDest(_ file: MediaFile) -> URL {
        cameraMedia.fileCacheURL(cameraID: mediaCameraID, file: file)
    }

    private func fetchMediaBytes(file: MediaFile, path: String, operation: PocketMediaLibraryOperation) async throws -> Data {
        let (data, _) = try await performMediaGET(file: file, path: path, operation: operation)
        return data
    }

    private func fetchMediaFile(file: MediaFile, path: String, to dest: URL, operation: PocketMediaLibraryOperation) async throws {
        let first = cameraMedia.resolvedStorage(for: file, singleSd: usesSingleSdStorage)
        let urls = storageURLs(path: path, first: first)
        var lastError: Error = MediaTransferError.badResponse
        for (storage, url) in urls {
            try Task.checkCancellation()
            try operation.requireCurrent()
            do {
                try await cameraMedia.downloadFile(
                    from: url, to: dest, path: file.path,
                    expectedSize: path == file.path ? file.sizeBytes : 0
                ) { [weak self] progress in
                    guard let self, operation.isCurrent, self.cameraMedia.progressOwner[file.path] == operation.id else { return }
                    self.mediaDownloadProgress[file.path] = progress
                }
                try operation.requireCurrent()
                cameraMedia.rememberStorage(storage, for: file.path)
                return
            } catch MediaTransferError.httpStatus(404) {
                lastError = MediaTransferError.httpStatus(404)
                continue
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw error
                }
                lastError = error
                // The buffered proxy path also tried the alternate storage on
                // transport/server errors. Preserve that fallback when streaming.
                if MediaHTTP.isProxyPath(path) { continue }
                if case MediaTransferError.httpStatus(let code) = error, (400...499).contains(code)
                {
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    private func performMediaGET(file: MediaFile, path: String, operation: PocketMediaLibraryOperation) async throws -> (Data, Int) {
        let first = cameraMedia.resolvedStorage(for: file, singleSd: usesSingleSdStorage)
        let urls = storageURLs(path: path, first: first)
        var lastError: Error = MediaTransferError.badResponse
        for (storage, url) in urls {
            do {
                try operation.requireCurrent()
                let (data, response) = try await cameraMedia.getData(url: url)
                try operation.requireCurrent()
                if (200...299).contains(response.statusCode) {
                    cameraMedia.rememberStorage(storage, for: file.path)
                    return (data, storage)
                }
                if response.statusCode == 404 {
                    lastError = MediaTransferError.httpStatus(404)
                    continue
                }
                lastError = MediaTransferError.httpStatus(response.statusCode)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func storageURLs(path: String, first: Int) -> [(Int, URL)] {
        let second = first == 0 ? 1 : 0
        var out: [(Int, URL)] = []
        if let url = MediaHTTP.pathURL(storage: first, path: path) {
            out.append((first, url))
        }
        if let url = MediaHTTP.pathURL(storage: second, path: path) {
            out.append((second, url))
        }
        return out
    }

    private func uniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}
