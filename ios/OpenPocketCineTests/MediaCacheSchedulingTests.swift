import Foundation
import OpenPocketViewCore
import XCTest
import os

@testable import OpenPocketCine

@MainActor
final class MediaCacheSchedulingTests: XCTestCase {
    func testCancelledDownloadCannotPublishQueuedProgress() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pump = MediaDownloadPump()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingProxyProtocol.self]
        let http = URLSession(configuration: configuration, delegate: pump, delegateQueue: nil)
        defer { http.invalidateAndCancel() }
        let ready = expectation(description: "Transfer is awaiting more bytes")
        StreamingProxyProtocol.state.withLock { $0 = .init(firstChunk: ready) }
        defer { StreamingProxyProtocol.state.withLock { $0 = .init() } }
        var published: [Double] = []
        let download = Task {
            try await pump.download(
                session: http, from: MediaHTTP.pathURL(storage: 1, path: "proxy.LRF")!,
                to: root.appendingPathComponent("proxy.mov"), path: "proxy.LRF", expectedSize: 0,
                onProgress: { published.append($0) })
        }
        await fulfillment(of: [ready], timeout: 5)
        let tasks = await withCheckedContinuation { continuation in
            http.getAllTasks { continuation.resume(returning: $0) }
        }
        let networkTask = try XCTUnwrap(tasks.first as? URLSessionDataTask)
        published.removeAll()
        // Queue the actual delegate's progress publication while MainActor is
        // occupied by this test, then cancel before allowing the callback to run.
        pump.urlSession(http, dataTask: networkTask, didReceive: Data([7]))
        pump.cancelAll()
        _ = try? await download.value
        await Task.yield()
        XCTAssertTrue(published.isEmpty, "Cancelled work must not recreate a caching badge")
    }

    func testPlaybackProxyStreamsToDiskBeforeEOFAndRetriesStorage() async throws {
        try await assertStreamingProxy(firstStatus: 404)
    }

    func testPlaybackProxyRetriesOtherStorageAfterServerError() async throws {
        try await assertStreamingProxy(firstStatus: 500)
    }

    private func assertStreamingProxy(firstStatus: Int) async throws {
        let manager = ProbedCacheFileManager()
        defer { try? FileManager.default.removeItem(at: manager.support) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingProxyProtocol.self]
        let cache = CameraMedia(fileManager: manager, httpConfiguration: configuration)
        let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: cache)
        session.datalink = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "")
        session.phase = .live
        defer { session.disconnect() }
        var file = MediaFile(path: "DCIM/DJI_001/DJI_STREAM.MP4", thumbPath: "STREAM.scr")
        // The original's length must never truncate a differently sized proxy.
        file.sizeBytes = 1
        let proxy = try XCTUnwrap(MediaHTTP.proxyPaths(file).first)
        let dest = cache.playbackCacheURL(cameraID: session.mediaCameraID, file: file, path: proxy)
        let firstChunk = expectation(description: "Proxy prefix received after storage fallback")
        StreamingProxyProtocol.state.withLock {
            $0 = .init(firstChunk: firstChunk, firstStatus: firstStatus)
        }
        defer { StreamingProxyProtocol.state.withLock { $0 = .init() } }
        let download = Task { try await session.cachePlaybackFile(file: file, path: proxy) }
        await fulfillment(of: [firstChunk], timeout: 5)
        let directory = dest.deletingLastPathComponent()
        var bytesOnDisk = 0
        for _ in 0..<50 {
            let parts =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil)) ?? []
            bytesOnDisk = parts.reduce(0) { $0 + ((try? Data(contentsOf: $1).count) ?? 0) }
            if bytesOnDisk >= StreamingProxyProtocol.chunkSize { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let paused = StreamingProxyProtocol.state.withLock { $0.paused }
        paused?.finishBody()
        let result = try await download.value
        XCTAssertEqual(result, dest)
        XCTAssertEqual(
            bytesOnDisk, StreamingProxyProtocol.chunkSize,
            "A proxy must not accumulate its whole body for a MainActor write/release")
        XCTAssertEqual(
            try Data(contentsOf: result),
            Data(repeating: 7, count: 2 * StreamingProxyProtocol.chunkSize))
        XCTAssertEqual(StreamingProxyProtocol.state.withLock { $0.requests }, [0, 1])
    }

    func testCancellingPlaybackProxyStopsTransferAndRemovesPartialFile() async throws {
        let manager = ProbedCacheFileManager()
        defer { try? FileManager.default.removeItem(at: manager.support) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingProxyProtocol.self]
        let cache = CameraMedia(fileManager: manager, httpConfiguration: configuration)
        let session = CameraSession(borrowing: HevcDecoder(), cameraMedia: cache)
        session.datalink = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "")
        session.phase = .live
        defer { session.disconnect() }
        let file = MediaFile(path: "DCIM/DJI_001/DJI_CANCEL.MP4", thumbPath: "CANCEL.scr")
        let proxy = try XCTUnwrap(MediaHTTP.proxyPaths(file).first)
        let dest = cache.playbackCacheURL(cameraID: session.mediaCameraID, file: file, path: proxy)
        let firstChunk = expectation(description: "Paused proxy body")
        let completed = expectation(description: "Cancelled download returns without EOF")
        let stoppedTransfer = expectation(description: "Underlying camera request cancelled")
        StreamingProxyProtocol.state.withLock {
            $0 = .init(firstChunk: firstChunk, stoppedTransfer: stoppedTransfer)
        }
        defer { StreamingProxyProtocol.state.withLock { $0 = .init() } }
        let download = Task {
            defer { completed.fulfill() }
            do {
                _ = try await session.cachePlaybackFile(file: file, path: proxy)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return (error as? URLError)?.code == .cancelled
            }
        }
        await fulfillment(of: [firstChunk], timeout: 5)
        download.cancel()
        await fulfillment(of: [completed, stoppedTransfer], timeout: 1)
        let (stopped, paused) = StreamingProxyProtocol.state.withLock { ($0.stopped, $0.paused) }
        // Let the broken implementation finish in the red run.
        if !stopped { paused?.finishBody() }
        let cancelled = await download.value
        XCTAssertTrue(cancelled)
        XCTAssertTrue(stopped, "Cancellation must stop camera I/O, not only discard its result")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        let files = try FileManager.default.contentsOfDirectory(
            at: dest.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        XCTAssertTrue(files.isEmpty, "Cancelled transfers must remove their partial file")
    }

    func testCacheDeletionLeavesMainActorAvailableAndPreservesNewDownloads() async throws {
        let manager = ProbedCacheFileManager()
        defer { try? FileManager.default.removeItem(at: manager.support) }
        let cache = CameraMedia(fileManager: manager)
        let root = cache.cacheRoot(cameraID: "test")
        let file = MediaFile(path: "DCIM/DJI_001/DJI_TEST.MP4", thumbPath: "thumb.scr")
        cache.persistCatalog([file], cameraID: "test")
        cache.rememberShotColor(.dLog2, path: file.path, cameraID: "test")
        let oldDownload = root.appendingPathComponent("old.mp4")
        try Data([1]).write(to: oldDownload)
        let newDownload = root.appendingPathComponent("new.mp4")
        let wroteReplacement = expectation(
            description: "Main actor can write during recursive deletion")
        manager.beforeRemoval = {
            let heartbeat = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                do { try Data([2]).write(to: newDownload) } catch {
                    XCTFail("Replacement cache must remain writable: \(error)")
                }
                wroteReplacement.fulfill()
                heartbeat.signal()
            }
            _ = heartbeat.wait(timeout: .now() + 1)
        }
        try await cache.clearCache(cameraID: "test", preservingCatalog: true)
        await fulfillment(of: [wroteReplacement], timeout: 2)
        XCTAssertEqual(manager.removedOnMain, false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDownload.path))
        XCTAssertEqual(try Data(contentsOf: newDownload), Data([2]))
        let reloaded = CameraMedia(fileManager: manager)
        XCTAssertEqual(reloaded.loadCatalog(cameraID: "test"), [file])
        XCTAssertEqual(reloaded.shotColor(for: file.path, cameraID: "test"), .dLog2)
    }

    func testDeletionCannotSweepACacheAwaitingCatalogPreservation() async throws {
        let manager = ProbedCacheFileManager()
        defer { try? FileManager.default.removeItem(at: manager.support) }
        let cache = CameraMedia(fileManager: manager)
        let root = cache.cacheRoot(cameraID: "test")
        let preparing = root.deletingLastPathComponent()
            .appendingPathComponent(".retiring-test-unfinished")
        try FileManager.default.createDirectory(at: preparing, withIntermediateDirectories: true)
        let catalog = preparing.appendingPathComponent("index.json")
        try Data([1, 2, 3]).write(to: catalog)
        let file = MediaFile(path: "old.mp4", thumbPath: "old.scr")
        try cache.writeAtomically(Data([4]), to: cache.fileCacheURL(cameraID: "test", file: file))
        try await cache.clearCache(cameraID: "test", preservingCatalog: false)
        XCTAssertEqual(try Data(contentsOf: catalog), Data([1, 2, 3]))
        let bytes = await cache.cacheByteCount(cameraID: "test")
        XCTAssertEqual(bytes, 3, "Protected data is retained and counted")
    }

    func testFailedDeletionRemainsCountedAndCanBeRetried() async throws {
        let manager = ProbedCacheFileManager()
        defer { try? FileManager.default.removeItem(at: manager.support) }
        let cache = CameraMedia(fileManager: manager)
        let file = MediaFile(path: "retry.mp4", thumbPath: "retry.scr")
        try cache.writeAtomically(
            Data([1, 2, 3]), to: cache.fileCacheURL(cameraID: "test", file: file))
        manager.beforeRemoval = { throw CocoaError(.fileWriteNoPermission) }
        do {
            try await cache.clearCache(cameraID: "test", preservingCatalog: false)
            XCTFail("The failed deletion must be reported")
        } catch {}
        let retained = await cache.cacheByteCount(cameraID: "test")
        XCTAssertEqual(retained, 3)
        manager.beforeRemoval = nil
        try await cache.clearCache(cameraID: "test", preservingCatalog: false)
        let cleared = await cache.cacheByteCount(cameraID: "test")
        XCTAssertEqual(cleared, 0)
    }

    func testCacheSnapshotReadsOffMainAndRefreshesAfterDeletion() async throws {
        let manager = ProbedCacheFileManager()
        defer { try? FileManager.default.removeItem(at: manager.support) }
        let cache = CameraMedia(fileManager: manager)
        var original = MediaFile(path: "DCIM/DJI_001/DJI_ORIGINAL.MP4", thumbPath: "original.scr")
        original.sizeBytes = 100
        let proxy = MediaFile(path: "DCIM/DJI_001/DJI_PROXY.MP4", thumbPath: "proxy.scr")
        var short = MediaFile(path: "DCIM/DJI_001/DJI_SHORT.MP4", thumbPath: "short.scr")
        short.sizeBytes = 100
        try cache.writeAtomically(
            Data(repeating: 1, count: 100), to: cache.fileCacheURL(cameraID: "test", file: original)
        )
        try cache.writeAtomically(Data([1]), to: cache.fileCacheURL(cameraID: "test", file: short))
        try cache.writeAtomically(
            Data([1]), to: cache.thumbnailCacheURL(cameraID: "test", file: short))
        let proxyPath = try XCTUnwrap(MediaHTTP.proxyPaths(proxy).first)
        try cache.writeAtomically(
            Data([1]), to: cache.playbackCacheURL(cameraID: "test", file: proxy, path: proxyPath))
        let files = [original, proxy, short]
        let snapshot = await cache.cacheEntries(cameraID: "test", files: files)
        XCTAssertEqual(manager.attributesReadOnMain, false)
        XCTAssertEqual(snapshot[original.path]?.grade, .original)
        XCTAssertEqual(snapshot[proxy.path]?.grade, .proxy)
        XCTAssertEqual(snapshot[short.path]?.grade, MediaCacheGrade.none)
        XCTAssertNotNil(snapshot[short.path]?.thumbnailURL)
        XCTAssertNil(snapshot[short.path]?.originalURL)
        let bytes = await cache.cacheByteCount(cameraID: "test")
        XCTAssertEqual(bytes, 103)
        try await cache.clearCache(cameraID: "test", preservingCatalog: false)
        let empty = await cache.cacheEntries(cameraID: "test", files: files)
        XCTAssertTrue(empty.values.allSatisfy { $0.grade == .none && $0.thumbnailURL == nil })
    }
}

private final class StreamingProxyProtocol: URLProtocol, @unchecked Sendable {
    static let chunkSize = 64 * 1024
    struct State {
        var firstChunk: XCTestExpectation?
        var firstStatus = 404
        var paused: StreamingProxyProtocol?
        var stopped = false
        var stoppedTransfer: XCTestExpectation?
        var requests: [Int] = []
    }
    static let state = OSAllocatedUnfairLock(initialState: State())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let storage = Int(
            URLComponents(url: url, resolvingAgainstBaseURL: false)!
                .queryItems!.first(where: { $0.name == "storage" })!.value!)!
        Self.state.withLock { $0.requests.append(storage) }
        let response = HTTPURLResponse(
            url: url, statusCode: storage == 0 ? Self.state.withLock { $0.firstStatus } : 200,
            httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if storage == 0 {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didLoad: Data(repeating: 7, count: Self.chunkSize))
        let ready = Self.state.withLock {
            $0.paused = self
            return $0.firstChunk
        }
        ready?.fulfill()
    }
    func finishBody() {
        client?.urlProtocol(self, didLoad: Data(repeating: 7, count: Self.chunkSize))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        let stopped = Self.state.withLock {
            guard $0.paused === self else { return Optional<XCTestExpectation>.none }
            $0.stopped = true
            return $0.stoppedTransfer
        }
        stopped?.fulfill()
    }
}

private final class ProbedCacheFileManager: FileManager, @unchecked Sendable {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let removal = OSAllocatedUnfairLock<Bool?>(initialState: nil)
    private let reads = OSAllocatedUnfairLock(initialState: false)
    var removedOnMain: Bool? { removal.withLock { $0 } }
    var attributesReadOnMain: Bool { reads.withLock { $0 } }
    // Configured before launching deletion and immutable until it completes.
    var beforeRemoval: (@Sendable () throws -> Void)?

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask)
        -> [URL]
    {
        [support]
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        reads.withLock { $0 = $0 || Thread.isMainThread }
        return try super.attributesOfItem(atPath: path)
    }

    override func removeItem(at URL: URL) throws {
        removal.withLock { $0 = Thread.isMainThread }
        try beforeRemoval?()
        try super.removeItem(at: URL)
    }
}
