import Foundation
import OpenCineDJIApple
import OpenPocketViewCore
import XCTest
import os

@testable import OpenPocketCine

/// SIMULATED native HTTP, through the actual source facade and captured Library owner.
@MainActor final class PocketMediaThumbnailOwnerTests: XCTestCase {
    func testRawThumbnailKeepsStampedStoragePathBytesAndExistingCache() async throws {
        let fixture = ThumbnailOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "DCIM/ORIGINAL.MP4", thumbPath: "MISC/THM/RAW.scr", storage: 1, storageKnown: true)
        fixture.media.rememberStorage(0, for: file.path)
        let expected = try XCTUnwrap(MediaHTTP.pathURL(storage: 1, path: file.thumbPath))
        let bytes = Data([0, 1, 255, 9])
        ThumbnailOwnerURLProtocol.state.withLock { $0 = .init(payload: bytes) }
        defer { ThumbnailOwnerURLProtocol.state.withLock { $0 = .init() } }
        let first = await fixture.session.thumbnailBytes(for: file)
        XCTAssertEqual(first, bytes)
        let cached = fixture.media.thumbnailCacheURL(cameraID: fixture.session.mediaCameraID, file: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cached.path))
        try fixture.media.writeAtomically(Data([7]), to: cached)
        let second = await fixture.session.thumbnailBytes(for: file)
        XCTAssertEqual(second, bytes)
        XCTAssertEqual(try Data(contentsOf: cached), Data([7]))
        XCTAssertEqual(ThumbnailOwnerURLProtocol.state.withLock { $0.requests }, [expected, expected])
        XCTAssertTrue(fixture.session.mediaLibrary.hostProgress.isEmpty)
        XCTAssertTrue(fixture.session.mediaLibrary.records.isEmpty)
        XCTAssertTrue(fixture.session.mediaLibrary.catalog.assets.isEmpty)
    }

    func testLibraryCloseCancelsActualRawThumbnailRequest() async {
        let fixture = ThumbnailOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "DCIM/CLOSE.MP4", thumbPath: "CLOSE.scr")
        let ready = expectation(description: "Actual raw thumbnail HTTP is pending")
        let stopped = expectation(description: "Library close stops native HTTP")
        let completed = expectation(description: "Retired facade returns without waiting for body")
        ThumbnailOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready, stopped: stopped) }
        defer { ThumbnailOwnerURLProtocol.state.withLock { $0 = .init() } }
        let request = Task {
            let bytes = await fixture.session.thumbnailBytes(for: file)
            completed.fulfill()
            return bytes
        }
        await fulfillment(of: [ready], timeout: 5)
        fixture.session.mediaLibrary.close()
        await fulfillment(of: [stopped, completed], timeout: 5)
        let cancelled = ThumbnailOwnerURLProtocol.state.withLock { $0.didStop }
        // Bound a failed cancellation implementation as well as the repaired one.
        if !cancelled { ThumbnailOwnerURLProtocol.state.withLock { $0.pending }?.finishBody() }
        let bytes = await request.value
        XCTAssertTrue(cancelled, "Retirement must cancel camera HTTP, not just discard its eventual bytes")
        XCTAssertNil(bytes)
        XCTAssertTrue(fixture.session.mediaLibrary.hostProgress.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.media.thumbnailCacheURL(cameraID: fixture.session.mediaCameraID, file: file).path))
    }

    func testCallerCancellationStopsActualRawThumbnailRequest() async {
        let fixture = ThumbnailOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "DCIM/CANCEL.MP4", thumbPath: "CANCEL.scr")
        let ready = expectation(description: "Actual raw thumbnail HTTP is pending")
        let stopped = expectation(description: "Caller cancellation stops native HTTP")
        let completed = expectation(description: "Cancelled facade returns without a body")
        ThumbnailOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready, stopped: stopped) }
        defer { ThumbnailOwnerURLProtocol.state.withLock { $0 = .init() } }
        let request = Task {
            let bytes = await fixture.session.thumbnailBytes(for: file)
            completed.fulfill()
            return bytes
        }
        await fulfillment(of: [ready], timeout: 5)
        request.cancel()
        await fulfillment(of: [stopped, completed], timeout: 5)
        let cancelled = ThumbnailOwnerURLProtocol.state.withLock { $0.didStop }
        if !cancelled { ThumbnailOwnerURLProtocol.state.withLock { $0.pending }?.finishBody() }
        let bytes = await request.value
        XCTAssertTrue(cancelled)
        XCTAssertNil(bytes)
        XCTAssertTrue(fixture.session.mediaLibrary.hostProgress.isEmpty)
    }

    func testDriverReplacementRejectsRawThumbnailBytesFromOldSource() async throws {
        let fixture = ThumbnailOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "DCIM/REPLACED.MP4", thumbPath: "REPLACED.scr")
        let ready = expectation(description: "Old source thumbnail is pending")
        ThumbnailOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready) }
        defer { ThumbnailOwnerURLProtocol.state.withLock { $0 = .init() } }
        let request = Task { await fixture.session.thumbnailBytes(for: file) }
        await fulfillment(of: [ready], timeout: 5)
        let oldDriver = fixture.session.datalink
        fixture.session.datalink = DjiAppleDatalink(port: 9005, tcpPoke: false, pairingToken: "")
        let pending = try XCTUnwrap(ThumbnailOwnerURLProtocol.state.withLock { $0.pending })
        pending.finishBody()
        let bytes = await request.value
        XCTAssertNil(bytes)
        XCTAssertTrue(fixture.session.mediaLibrary.hostProgress.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.media.thumbnailCacheURL(cameraID: fixture.session.mediaCameraID, file: file).path))
        withExtendedLifetime(oldDriver) {}
    }

    func testCanonicalClearRejectsDelayedRawThumbnailWithoutWritingCache() async throws {
        let fixture = ThumbnailOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "DCIM/CLEAR.MP4", thumbPath: "CLEAR.scr")
        let ready = expectation(description: "Raw thumbnail precedes canonical clear")
        ThumbnailOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready) }
        defer { ThumbnailOwnerURLProtocol.state.withLock { $0 = .init() } }
        let request = Task { await fixture.session.thumbnailBytes(for: file) }
        await fulfillment(of: [ready], timeout: 5)
        try await fixture.media.clearCache(cameraID: fixture.session.mediaCameraID, preservingCatalog: false)
        let pending = try XCTUnwrap(ThumbnailOwnerURLProtocol.state.withLock { $0.pending })
        pending.finishBody()
        let bytes = await request.value
        XCTAssertNil(bytes)
        XCTAssertTrue(fixture.session.mediaLibrary.hostProgress.isEmpty)
        XCTAssertTrue(fixture.session.mediaLibrary.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.media.thumbnailCacheURL(cameraID: fixture.session.mediaCameraID, file: file).path))
    }
}

@MainActor private final class ThumbnailOwnerFixture {
    let manager = ThumbnailOwnerFileManager()
    let media: CameraMedia
    let session: CameraSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ThumbnailOwnerURLProtocol.self]
        media = CameraMedia(fileManager: manager, httpConfiguration: configuration)
        session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
        session.datalink = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
        session.phase = .live
    }
    func close() {
        session.disconnect()
        session.decoder.close()
        try? FileManager.default.removeItem(at: manager.support)
    }
}

private final class ThumbnailOwnerFileManager: FileManager, @unchecked Sendable {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] { [support] }
}

private final class ThumbnailOwnerURLProtocol: URLProtocol, @unchecked Sendable {
    struct State {
        var payload = Data([1, 2, 3])
        var hold = false
        var ready: XCTestExpectation?
        var stopped: XCTestExpectation?
        var requests: [URL] = []
        var pending: ThumbnailOwnerURLProtocol?
        var didStop = false
    }
    static let state = OSAllocatedUnfairLock(initialState: State())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let captured = Self.state.withLock {
            $0.requests.append(url)
            $0.pending = self
            $0.didStop = false
            return ($0.hold, $0.ready)
        }
        captured.1?.fulfill()
        if !captured.0 { finishBody() }
    }
    func finishBody() {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else { return }
        let bytes = Self.state.withLock { $0.pending === self && !$0.didStop ? $0.payload : nil }
        guard let bytes else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        let stopped = Self.state.withLock {
            guard $0.pending === self, !$0.didStop else { return Optional<XCTestExpectation>.none }
            $0.didStop = true
            return $0.stopped
        }
        stopped?.fulfill()
    }
}
