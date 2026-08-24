import Foundation
import OpenPocketViewCore

/// Operator-facing media notes. Never name a sister app or another camera brand.
enum MediaOperatorCopy {
    static let listing = "Listing camera clips…"
    static let notConnected = "Connect the camera to list clips."
    static let playbackFailed = "Camera did not enter playback."
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
    var assembler = MediaChunkAssembler()
    var browseTask: Task<Void, Never>?
    var resumeLiveTask: Task<Void, Never>?
    var browseID = 0
    var resumeID = 0
    var playbackHeld = false
    var actionCounter: UInt32 = 1
    var storageWinner: [String: Int] = [:]
    var favorites: Set<String> = []
    var favoritesCameraID: String?
    var thumbInFlight: Set<String> = []
    var downloadInFlight: Set<String> = []

    private let pump = MediaDownloadPump()
    private lazy var http: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.allowsCellularAccess = false
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()
    private lazy var downloadHTTP: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.allowsCellularAccess = false
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 600
        return URLSession(configuration: cfg, delegate: pump, delegateQueue: nil)
    }()

    func nextBrowseID() -> Int {
        browseID += 1
        return browseID
    }

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

    func loadFavorites(cameraID: String) -> Set<String> {
        if favoritesCameraID == cameraID { return favorites }
        favoritesCameraID = cameraID
        favorites = Set(
            UserDefaults.standard.stringArray(forKey: Self.favoritesKey(cameraID)) ?? [])
        return favorites
    }

    func persistFavorites() {
        guard let cameraID = favoritesCameraID else { return }
        UserDefaults.standard.set(Array(favorites).sorted(), forKey: Self.favoritesKey(cameraID))
    }

    func resetSession() {
        browseTask?.cancel()
        browseTask = nil
        cancelResumeLive()
        playbackHeld = false
        assembler.reset()
        storageWinner.removeAll()
        thumbInFlight.removeAll()
        downloadInFlight.removeAll()
        pump.cancelAll()
    }

    func cacheRoot(cameraID: String) -> URL {
        let app = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
            0]
        return app.appendingPathComponent("OpenPocketCine/media/\(cameraID)", isDirectory: true)
    }

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
        if let winner = storageWinner[file.path] { return winner }
        if file.storage == 0 || file.storage == 1 { return file.storage }
        let handle = file.handle != 0 ? file.handle : file.cmdHandle
        return MediaHTTP.storageGuess(handle: handle, singleSdStorage: singleSd)
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
        let url = colorStoreURL(cameraID: cameraID)
        guard let data = try? Data(contentsOf: url),
            let map = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return map
    }

    private func persistColorMap(_ map: [String: Int], cameraID: String) {
        let url = colorStoreURL(cameraID: cameraID)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(map)
            try data.write(to: url, options: .atomic)
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
        let url = catalogURL(cameraID: cameraID)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(files).write(to: url, options: .atomic)
        } catch {
            ControlLiveLog.line("media: catalog write failed \(error.localizedDescription)")
        }
    }

    func loadCatalog(cameraID: String) -> [MediaFile] {
        let url = catalogURL(cameraID: cameraID)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([MediaFile].self, from: data)) ?? []
    }

    func cacheByteCount(cameraID: String) -> UInt64 {
        let root = cacheRoot(cameraID: cameraID)
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])
        else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { continue }
            total += UInt64(values?.fileSize ?? 0)
        }
        return total
    }

    func clearCache(cameraID: String, preservingCatalog: Bool) {
        pump.cancelAll()
        let root = cacheRoot(cameraID: cameraID)
        let catalog = preservingCatalog ? loadCatalog(cameraID: cameraID) : []
        try? FileManager.default.removeItem(at: root)
        if preservingCatalog, !catalog.isEmpty {
            persistCatalog(catalog, cameraID: cameraID)
        }
    }

    func writeAtomically(_ data: Data, to dest: URL) throws {
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".part")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    static func existingFile(_ url: URL) -> URL? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
            !isDir.boolValue
        else { return nil }
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size]
            as? NSNumber,
            size.intValue <= 0
        {
            return nil
        }
        return url
    }

    private static func favoritesKey(_ cameraID: String) -> String {
        "opc.media.fav.\(cameraID)"
    }

    private static func cacheName(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "_")
    }
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
private final class MediaDownloadPump: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Job {
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
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let tmp = dest.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString + ".part")
            FileManager.default.createFile(atPath: tmp.path, contents: nil)
            let handle = try? FileHandle(forWritingTo: tmp)
            let task = session.dataTask(with: request)
            lock.lock()
            jobs[task.taskIdentifier] = Job(
                dest: dest,
                tmp: tmp,
                handle: handle,
                expected: expectedSize,
                onProgress: onProgress,
                continuation: cont)
            lock.unlock()
            task.resume()
        }
    }

    func cancelAll() {
        lock.lock()
        let pending = jobs
        jobs.removeAll()
        lock.unlock()
        for job in pending.values {
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
            let onProgress = job.onProgress
            let complete = expected > 0 && written >= expected
            lock.unlock()
            Task { @MainActor in onProgress(progress) }
            if complete {
                dataTask.cancel()
                finish(task: dataTask, error: nil)
            }
        } catch {
            lock.unlock()
            finish(task: dataTask, error: error)
        }
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
        cameraMedia.cancelResumeLive()
        cameraMedia.browseTask?.cancel()
        cameraMedia.browseTask = nil
        loadMediaFavorites()
        loadCachedCatalogIfNeeded()
        guard hasMediaDatalink, isLivePhase else {
            isBrowsingMedia = true
            mediaFetchInProgress = false
            mediaNote = mediaFiles.isEmpty ? MediaOperatorCopy.notConnected : nil
            return
        }
        isBrowsingMedia = true
        mediaFetchInProgress = true
        mediaFetchListedCount = mediaFiles.count
        mediaNote = MediaOperatorCopy.listing
        let id = cameraMedia.nextBrowseID()
        cameraMedia.browseTask = Task { [weak self] in
            await self?.runMediaBrowse(id: id)
        }
    }

    func endMediaBrowse() {
        cameraMedia.browseTask?.cancel()
        cameraMedia.browseTask = nil
        cameraMedia.browseID += 1
        mediaFetchInProgress = false
        cameraMedia.playbackHeld = false
        cameraMedia.assembler.reset()
        isBrowsingMedia = false
        mediaNote = nil
        guard hasMediaDatalink else { return }
        cameraMedia.resumeLiveTask?.cancel()
        let token = cameraMedia.nextResumeID()
        cameraMedia.resumeLiveTask = Task { [weak self] in
            await self?.resumeLiveViewAfterMedia(token: token)
        }
    }

    /// Mimo "Back to live view": keep sending `0x02/0x0c` exit until the camera
    /// drops the playback bit, then `0x09/0xa8`. Enable while still in playback
    /// ACKs `E0`/`D6` and the camera stays on "Playback in progress".
    func resumeLiveViewAfterMedia(token: Int) async {
        var exitAcked = false
        let started = Date()
        for attempt in 1...(MediaLiveResume.maxExitAttempts + 2) {
            guard !Task.isCancelled, token == cameraMedia.resumeID, !isBrowsingMedia else {
                return
            }
            switch MediaLiveResume.action(
                attempt: attempt,
                inPlayback: status.inPlayback,
                exitAcknowledged: exitAcked,
                pictureFresh: livePictureArrived(since: started)
            ) {
            case .done:
                ControlLiveLog.line("media: live resume done attempt=\(attempt)")
                return
            case .exitPlayback:
                ControlLiveLog.line(
                    "media: exit playback attempt=\(attempt) inPlayback=\(status.inPlayback ? 1 : 0)"
                )
                do {
                    let reply = try await awaitMediaOpcode(0x02, 0x0C, timeout: .milliseconds(450))
                    {
                        self.sendExitPlayback()
                    }
                    if CameraReply.parse(reply.payload).isSuccess { exitAcked = true }
                } catch {
                    sendExitPlayback()
                }
                try? await Task.sleep(for: .milliseconds(180))
            case .enableLiveView:
                ControlLiveLog.line("media: enable live after playback attempt=\(attempt)")
                restartLiveViewAfterMedia()
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    private func livePictureArrived(since start: Date) -> Bool {
        if let presented = decoder.lastPresentedAt, presented >= start { return true }
        if let packet = datalink?.lastVideoPacketAt, packet >= start { return true }
        return false
    }

    func refreshMedia() {
        Task { await self.refreshMedia() }
    }

    func refreshMedia() async {
        loadMediaFavorites()
        guard hasMediaDatalink, isLivePhase else {
            mediaNote = MediaOperatorCopy.notConnected
            return
        }
        if !isBrowsingMedia {
            beginMediaBrowse()
            return
        }
        if mediaFetchInProgress { return }
        mediaFetchInProgress = true
        mediaNote = MediaOperatorCopy.listing
        let id = cameraMedia.nextBrowseID()
        await listAllMediaPages(id: id)
    }

    func ingestMediaListFrame(_ frame: Duml.Frame) {
        _ = cameraMedia.assembler.ingest(frame)
    }

    func ensureThumbnail(for file: MediaFile) async {
        guard canReachCameraMedia else { return }
        guard thumbnailURL(for: file) == nil else { return }
        guard cameraMedia.thumbInFlight.insert(file.path).inserted else { return }
        defer { cameraMedia.thumbInFlight.remove(file.path) }
        do {
            let data = try await fetchMediaBytes(file: file, path: MediaHTTP.thumbnailPath(file))
            guard !data.isEmpty else { throw MediaTransferError.badResponse }
            try cameraMedia.writeAtomically(data, to: mediaThumbDest(file))
        } catch {
            if mediaNote == nil {
                mediaNote = MediaOperatorCopy.thumbFailed
            }
        }
    }

    func download(file: MediaFile) async {
        if isDownloaded(file) {
            finishDownloadProgress(file.path)
            return
        }
        guard canReachCameraMedia else {
            mediaNote = MediaOperatorCopy.clipNotCached
            return
        }
        guard cameraMedia.downloadInFlight.insert(file.path).inserted else { return }
        defer {
            cameraMedia.downloadInFlight.remove(file.path)
        }
        mediaDownloadProgress[file.path] = 0
        let dest = mediaFileDest(file)
        do {
            try await fetchMediaFile(file: file, path: MediaHTTP.deliveryPath(file), to: dest)
            guard CameraMedia.existingFile(dest) != nil else {
                throw MediaTransferError.badResponse
            }
            if let mode = ClipColorProfileIO.shotColor(at: dest, path: file.path) {
                rememberShotColor(mode, for: file)
            }
            finishDownloadProgress(file.path)
        } catch {
            mediaDownloadProgress[file.path] = nil
            mediaNote = MediaOperatorCopy.downloadFailed
            ControlLiveLog.line(
                "media: download failed \(file.filename) \(error.localizedDescription)")
        }
    }

    /// Progress `1` is "done", not in-flight. Clear it so the library header does
    /// not sit on CACHING 100% forever.
    private func finishDownloadProgress(_ path: String) {
        mediaDownloadProgress[path] = 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            if mediaDownloadProgress[path] == 1 {
                mediaDownloadProgress[path] = nil
            }
        }
    }

    func localURL(for file: MediaFile) -> URL? {
        CameraMedia.existingFile(mediaFileDest(file))
    }

    /// Shot color for Auto LUT. Never the LRF/XRF sidecar (Rec.709 even on D-Log2).
    func fetchOriginalShotColor(for file: MediaFile) async -> ColorMode? {
        if let url = localURL(for: file),
            let mode = ClipColorProfileIO.shotColor(at: url, path: file.path)
        {
            rememberShotColor(mode, for: file)
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
                let (data, response) = try await cameraMedia.getRange(url: url, range: range)
                guard (200...299).contains(response.statusCode) else { continue }
                if data.count > cap {
                    ControlLiveLog.line(
                        "media: clip color range ignored (\(data.count) bytes) \(file.path)")
                    continue
                }
                if let mode = ClipColorProfile.colorMode(fromMP4: data) {
                    cameraMedia.rememberStorage(storage, for: file.path)
                    rememberShotColor(mode, for: file)
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
        cameraMedia.rememberShotColor(color, path: file.path, cameraID: mediaCameraID)
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
        let dest = mediaPlaybackDest(file, path: path)
        if let existing = CameraMedia.existingFile(dest) { return existing }
        guard canReachCameraMedia else { throw MediaTransferError.timeout }
        mediaDownloadProgress[file.path] = 0
        do {
            if MediaHTTP.isProxyPath(path) {
                // Same GET as thumbnails — small sidecar, storage 0↔1 retry.
                let data = try await fetchMediaBytes(file: file, path: path)
                guard !data.isEmpty else { throw MediaTransferError.badResponse }
                try cameraMedia.writeAtomically(data, to: dest)
            } else {
                try await fetchMediaFile(file: file, path: path, to: dest)
            }
            if path == file.path {
                finishDownloadProgress(file.path)
            } else {
                mediaDownloadProgress[file.path] = nil
            }
            return dest
        } catch {
            mediaDownloadProgress[file.path] = nil
            throw error
        }
    }

    private func mediaPlaybackDest(_ file: MediaFile, path: String) -> URL {
        cameraMedia.playbackCacheURL(cameraID: mediaCameraID, file: file, path: path)
    }

    func deleteMedia(_ file: MediaFile) {
        Task { await self.deleteMedia(file) }
    }

    func deleteMedia(_ file: MediaFile) async {
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
                self.sendMediaFrame(frame)
            }
            acked =
                CameraReply.parse(reply.payload).isSuccess
                || reply.payload.starts(with: [0x00, 0x00])
        } catch {
            acked = false
        }
        if !acked {
            await listNewestMediaPage()
            if mediaFiles.contains(where: { $0.path == file.path }) {
                mediaNote = MediaOperatorCopy.deleteFailed
                return
            }
        }
        dropMediaFile(path: file.path)
    }

    func toggleMediaFavorite(_ file: MediaFile) {
        let on = !isMediaFavorite(file)
        applyLocalFavorite(path: file.path, on: on)
        if let idx = mediaFiles.firstIndex(where: { $0.path == file.path }) {
            mediaFiles[idx].isStarred = on
        }
        let handle = file.favoriteHandle
        guard handle != 0, hasMediaDatalink, isBrowsingMedia else { return }
        let counter = cameraMedia.nextActionCounter()
        let frame = Commands.setMediaFavorite(handle: handle, on: on, counter: counter)
        ControlLiveLog.line(
            "media: favorite handle=\(String(format: "0x%08X", handle)) on=\(on ? 1 : 0)")
        Task {
            _ = try? await self.awaitMediaOpcode(0x02, 0xBF, timeout: .milliseconds(900)) {
                self.sendMediaFrame(frame)
            }
        }
    }

    func isMediaFavorite(_ file: MediaFile) -> Bool {
        if isNanoBody { return file.isStarred }
        return file.isStarred || mediaLocalFavorites.contains(file.path)
    }

    func isFavorite(_ file: MediaFile) -> Bool { isMediaFavorite(file) }

    func toggleFavorite(_ file: MediaFile) { toggleMediaFavorite(file) }

    func deleteMediaFiles(_ files: [MediaFile]) async {
        for file in files {
            await deleteMedia(file)
        }
    }

    // MARK: - Browse

    private func runMediaBrowse(id: Int) async {
        guard id == cameraMedia.browseID else { return }
        let entered = await enterPlaybackForMedia()
        guard !Task.isCancelled, id == cameraMedia.browseID else { return }
        guard entered else {
            cameraMedia.playbackHeld = false
            mediaFetchInProgress = false
            mediaNote = MediaOperatorCopy.playbackFailed
            isBrowsingMedia = false
            return
        }
        cameraMedia.playbackHeld = true
        await listAllMediaPages(id: id)
    }

    private func enterPlaybackForMedia() async -> Bool {
        for attempt in 1...3 {
            if Task.isCancelled { return false }
            do {
                let reply = try await awaitMediaOpcode(0x02, 0x0C, timeout: .milliseconds(900)) {
                    self.sendEnterPlayback()
                }
                if CameraReply.parse(reply.payload).isSuccess || status.inPlayback {
                    ControlLiveLog.line("media: enter playback ok attempt=\(attempt)")
                    return true
                }
            } catch {
                if status.inPlayback { return true }
            }
            try? await Task.sleep(for: .milliseconds(120))
        }
        return status.inPlayback
    }

    private func listAllMediaPages(id: Int) async {
        defer {
            if id == cameraMedia.browseID {
                mediaFetchInProgress = false
            }
        }
        var collected: [MediaFile] = []
        var seen = Set<String>()
        var pageCursor: UInt32?
        var first = true
        while !Task.isCancelled, id == cameraMedia.browseID {
            let page: [MediaFile]
            if first {
                page = await queryMediaPage(internalCursor: MediaListCommand.newestInternal)
                first = false
            } else if let cursor = pageCursor {
                page = await queryMediaPage(internalCursor: cursor)
            } else {
                break
            }
            var added = 0
            for file in page {
                if seen.insert(file.path).inserted {
                    collected.append(applyFavoriteOverlay(file))
                    added += 1
                }
            }
            publishMediaFiles(collected)
            let handles = page.map(\.handle)
            let newest =
                handles.filter { $0 >= MediaListCommand.videoHandleBase }.max()
                ?? MediaListCommand.newestInternal
            pageCursor =
                MediaListCommand.nextCursor(handles: handles, current: newest)
                ?? handles.filter { $0 >= MediaListCommand.videoHandleBase }.min()
            if added == 0 || page.count < MediaListCommand.pageSize { break }
            if !MediaListCommand.hasOlderPage(recordCount: page.count, cursor: pageCursor) {
                break
            }
        }
        guard id == cameraMedia.browseID else { return }
        if collected.isEmpty {
            if cameraMedia.assembler.chunkCount == 0, !cameraMedia.assembler.sawEnd {
                mediaNote = MediaOperatorCopy.listFailed
            } else {
                mediaNote = MediaOperatorCopy.noClips
            }
        } else {
            mediaNote = nil
        }
    }

    private func listNewestMediaPage() async {
        let page = await queryMediaPage(internalCursor: MediaListCommand.newestInternal)
        var seen = Set<String>()
        var collected: [MediaFile] = []
        for file in page where seen.insert(file.path).inserted {
            collected.append(applyFavoriteOverlay(file))
        }
        for file in mediaFiles where seen.insert(file.path).inserted {
            collected.append(file)
        }
        publishMediaFiles(collected)
    }

    private func queryMediaPage(internalCursor: UInt32) async -> [MediaFile] {
        cameraMedia.assembler.reset()
        sendMediaFrame(
            Commands.mediaList(
                counter: MediaListCommand.sdCounter, cursor: MediaListCommand.newestSD))
        await collectMediaChunks(floor: .milliseconds(800), idle: .milliseconds(200))
        sendMediaFrame(Commands.mediaListTrigger())
        await collectMediaChunks(floor: .milliseconds(400), idle: .milliseconds(200))
        sendMediaFrame(
            Commands.mediaList(
                counter: MediaListCommand.internalCounter, cursor: internalCursor))
        await collectMediaChunks(floor: .milliseconds(800), idle: .milliseconds(800))
        return MediaManifest.decodeStores(assembler: cameraMedia.assembler)
    }

    private func collectMediaChunks(floor: Duration, idle: Duration, cap: Duration = .seconds(8))
        async
    {
        let clock = ContinuousClock()
        let start = clock.now
        var lastChange = start
        var lastCount = cameraMedia.assembler.chunkCount
        while !Task.isCancelled {
            let now = clock.now
            if now - start >= cap { break }
            if cameraMedia.assembler.sawEnd, now - start >= floor { break }
            try? await Task.sleep(for: .milliseconds(50))
            let count = cameraMedia.assembler.chunkCount
            if count != lastCount {
                lastCount = count
                lastChange = clock.now
            }
            if now - start >= floor, now - lastChange >= idle { break }
        }
    }

    private func publishMediaFiles(_ files: [MediaFile]) {
        var next = files
        if isNanoBody {
            syncNanoFavorites(&next)
        }
        mediaFiles = next
        mediaFetchListedCount = next.count
        persistMediaCatalog()
    }

    func persistMediaCatalog() {
        guard !mediaFiles.isEmpty else { return }
        cameraMedia.persistCatalog(mediaFiles, cameraID: mediaCameraID)
    }

    func loadCachedCatalogIfNeeded() {
        if mediaFiles.isEmpty {
            mediaFiles = cameraMedia.loadCatalog(cameraID: mediaCameraID)
        }
        mediaFetchListedCount = mediaFiles.count
    }

    private func applyFavoriteOverlay(_ file: MediaFile) -> MediaFile {
        var next = file
        if !isNanoBody, mediaLocalFavorites.contains(file.path) {
            next.isStarred = true
        }
        return next
    }

    private func syncNanoFavorites(_ files: inout [MediaFile]) {
        var next = Set<String>()
        for file in files where file.isStarred {
            next.insert(file.path)
        }
        cameraMedia.favorites = next
        mediaLocalFavorites = next
        cameraMedia.persistFavorites()
    }

    private func dropMediaFile(path: String) {
        mediaFiles.removeAll { $0.path == path }
        mediaFetchListedCount = mediaFiles.count
        mediaDownloadProgress[path] = nil
        cameraMedia.favorites.remove(path)
        mediaLocalFavorites = cameraMedia.favorites
        cameraMedia.persistFavorites()
    }

    private func applyLocalFavorite(path: String, on: Bool) {
        if on {
            cameraMedia.favorites.insert(path)
        } else {
            cameraMedia.favorites.remove(path)
        }
        mediaLocalFavorites = cameraMedia.favorites
        cameraMedia.persistFavorites()
    }

    func loadMediaFavorites() {
        let id = mediaCameraID
        mediaLocalFavorites = cameraMedia.loadFavorites(cameraID: id)
    }

    private static let lastMediaCameraKey = "opc.media.lastCameraID"

    /// Cache lives under the camera id. After disconnect `connectedCamera` is
    /// nil — keep the last id so cached clips stay findable offline.
    var mediaCameraID: String {
        if let id = connectedCamera?.id.uuidString {
            UserDefaults.standard.set(id, forKey: Self.lastMediaCameraKey)
            return id
        }
        return UserDefaults.standard.string(forKey: Self.lastMediaCameraKey) ?? "unknown"
    }

    private var isNanoBody: Bool {
        connectedCamera?.model.family == .nano
    }

    private var usesSingleSdStorage: Bool {
        if status.internalTotalMb == 0 { return true }
        return connectedCamera?.model.name.localizedCaseInsensitiveContains("Pocket 3") == true
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

    private func fetchMediaBytes(file: MediaFile, path: String) async throws -> Data {
        let (data, _) = try await performMediaGET(file: file, path: path)
        return data
    }

    private func fetchMediaFile(file: MediaFile, path: String, to dest: URL) async throws {
        let first = cameraMedia.resolvedStorage(for: file, singleSd: usesSingleSdStorage)
        let urls = storageURLs(path: path, first: first)
        var lastError: Error = MediaTransferError.badResponse
        for (storage, url) in urls {
            do {
                try await cameraMedia.downloadFile(
                    from: url, to: dest, path: file.path, expectedSize: file.sizeBytes
                ) { [weak self] progress in
                    self?.mediaDownloadProgress[file.path] = progress
                }
                cameraMedia.rememberStorage(storage, for: file.path)
                return
            } catch MediaTransferError.httpStatus(404) {
                lastError = MediaTransferError.httpStatus(404)
                continue
            } catch {
                lastError = error
                if case MediaTransferError.httpStatus(let code) = error, (400...499).contains(code)
                {
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    private func performMediaGET(file: MediaFile, path: String) async throws -> (Data, Int) {
        let first = cameraMedia.resolvedStorage(for: file, singleSd: usesSingleSdStorage)
        let urls = storageURLs(path: path, first: first)
        var lastError: Error = MediaTransferError.badResponse
        for (storage, url) in urls {
            do {
                let (data, response) = try await cameraMedia.getData(url: url)
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
