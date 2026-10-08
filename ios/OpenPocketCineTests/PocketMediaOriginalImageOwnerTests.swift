import Foundation
import OpenCineAppKit
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore
import XCTest
import os

@testable import OpenPocketCine

/// SIMULATED native original-image IO through the actual app source facade and Library task.
@MainActor final class PocketMediaOriginalImageOwnerTests: XCTestCase {
    func testActualOriginalKeepsStampedPathBytesCacheAndShotColor() async throws {
        let fixture = OriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "DCIM/ORIGINAL.JPG", thumbPath: "MISC/THM/RAW.scr", sizeBytes: 4, storage: 1, storageKnown: true)
        try fixture.seed(file)
        fixture.media.rememberStorage(0, for: file.path)
        fixture.session.rememberShotColor(.normal, for: file)
        let expected = try XCTUnwrap(MediaHTTP.pathURL(storage: 1, path: file.path))
        let bytes = Data([0, 1, 255, 9])
        OriginalImageOwnerURLProtocol.state.withLock { $0 = .init(payload: bytes) }
        defer { OriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        let original = fixture.media.fileCacheURL(cameraID: fixture.session.mediaCameraID, file: file)
        let thumbnail = fixture.media.thumbnailCacheURL(cameraID: fixture.session.mediaCameraID, file: file)
        try fixture.media.writeAtomically(Data([7]), to: original)
        try fixture.media.writeAtomically(Data([8]), to: thumbnail)
        let value = await fixture.session.originalImageBytes(for: file, ifCurrent: { true })
        XCTAssertEqual(value, bytes)
        XCTAssertEqual(OriginalImageOwnerURLProtocol.state.withLock { $0.requests }, [expected])
        XCTAssertEqual(try Data(contentsOf: original), Data([7]))
        XCTAssertEqual(try Data(contentsOf: thumbnail), Data([8]))
        XCTAssertEqual(fixture.session.shotColor(for: file), .normal)
        XCTAssertEqual(fixture.session.mediaLibrary.records.map(\.payload), [file])
        XCTAssertTrue(fixture.session.mediaLibrary.hostProgress.isEmpty)
    }

    func testMissingRecordAndRetiredPictureNeverDispatchOriginalHTTP() async throws {
        let fixture = OriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "DCIM/UNKNOWN.JPG", thumbPath: "THM.scr")
        OriginalImageOwnerURLProtocol.state.withLock { $0 = .init() }
        defer { OriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        let unknown = await fixture.session.originalImageBytes(for: file, ifCurrent: { true })
        XCTAssertNil(unknown)
        try fixture.seed(file)
        let retired = await fixture.session.originalImageBytes(for: file, ifCurrent: { false })
        XCTAssertNil(retired)
        let reentered = await fixture.session.originalImageBytes(for: file, ifCurrent: {
            fixture.session.phase = .idle
            return true
        })
        XCTAssertNil(reentered)
        XCTAssertTrue(OriginalImageOwnerURLProtocol.state.withLock { $0.requests.isEmpty })
        XCTAssertTrue(fixture.session.mediaLibrary.hostProgress.isEmpty)
    }

    func testLibraryCloseCancelsActualOriginalHTTPRequest() async throws {
        let fixture = OriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "DCIM/CLOSE.JPG", thumbPath: "CLOSE.scr")
        try fixture.seed(file)
        let ready = expectation(description: "Actual original HTTP is pending")
        let stopped = expectation(description: "Library close stops original HTTP")
        let completed = expectation(description: "Retired facade does not wait for image body")
        OriginalImageOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready, stopped: stopped) }
        defer { OriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        let request = Task {
            let bytes = await fixture.session.originalImageBytes(for: file, ifCurrent: { true })
            completed.fulfill(); return bytes
        }
        await fulfillment(of: [ready], timeout: 5)
        fixture.session.mediaLibrary.close()
        await fulfillment(of: [stopped, completed], timeout: 5)
        let cancelled = OriginalImageOwnerURLProtocol.state.withLock { $0.didStop }
        if !cancelled { OriginalImageOwnerURLProtocol.state.withLock { $0.pending }?.finishBody() }
        let bytes = await request.value
        XCTAssertTrue(cancelled, "Retirement must cancel underlying camera HTTP")
        XCTAssertNil(bytes)
        XCTAssertTrue(fixture.session.mediaLibrary.hostProgress.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.media.fileCacheURL(cameraID: fixture.session.mediaCameraID, file: file).path))
    }

    func testCallerCancellationStopsActualOriginalHTTPRequest() async throws {
        let fixture = OriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "DCIM/CANCEL.JPG", thumbPath: "CANCEL.scr")
        try fixture.seed(file)
        let ready = expectation(description: "Actual original HTTP is pending")
        let stopped = expectation(description: "Caller cancellation stops original HTTP")
        let completed = expectation(description: "Cancelled facade does not wait for image body")
        OriginalImageOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready, stopped: stopped) }
        defer { OriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        let request = Task {
            let bytes = await fixture.session.originalImageBytes(for: file, ifCurrent: { true })
            completed.fulfill(); return bytes
        }
        await fulfillment(of: [ready], timeout: 5)
        request.cancel()
        await fulfillment(of: [stopped, completed], timeout: 5)
        let cancelled = OriginalImageOwnerURLProtocol.state.withLock { $0.didStop }
        if !cancelled { OriginalImageOwnerURLProtocol.state.withLock { $0.pending }?.finishBody() }
        let bytes = await request.value
        XCTAssertTrue(cancelled); XCTAssertNil(bytes)
        XCTAssertTrue(fixture.session.mediaLibrary.hostProgress.isEmpty)
    }

    func testDriverReplacementRejectsOldOriginalAndAdmitsCurrentRead() async throws {
        let fixture = OriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "DCIM/REPLACED.JPG", thumbPath: "REPLACED.scr")
        try fixture.seed(file)
        let ready = expectation(description: "Old source original is pending")
        OriginalImageOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready) }
        defer { OriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        let request = Task { await fixture.session.originalImageBytes(for: file, ifCurrent: { true }) }
        await fulfillment(of: [ready], timeout: 5)
        let oldDriver = fixture.session.datalink
        fixture.session.datalink = DjiAppleDatalink(port: 9005, tcpPoke: false, pairingToken: "")
        let pending = try XCTUnwrap(OriginalImageOwnerURLProtocol.state.withLock { $0.pending })
        pending.finishBody(); let oldBytes = await request.value
        XCTAssertNil(oldBytes)
        OriginalImageOwnerURLProtocol.state.withLock { $0 = .init(payload: Data([9])) }
        let current = await fixture.session.originalImageBytes(for: file, ifCurrent: { true })
        XCTAssertEqual(current, Data([9]))
        XCTAssertTrue(fixture.session.mediaLibrary.hostProgress.isEmpty)
        withExtendedLifetime(oldDriver) {}
    }

    func testSameAssetRecordReplacementRejectsDelayedOriginalContent() async throws {
        let fixture = OriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "DCIM/RECYCLED.JPG", thumbPath: "FIRST.scr", sizeBytes: 4)
        var next = file; next.thumbPath = "SECOND.scr"
        XCTAssertEqual(DjiAppleMediaAssets.asset(for: file).id, DjiAppleMediaAssets.asset(for: next).id)
        try fixture.seed(file)
        let ready = expectation(description: "Original precedes same-ID content replacement")
        OriginalImageOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready) }
        defer { OriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        let request = Task { await fixture.session.originalImageBytes(for: file, ifCurrent: { true }) }
        await fulfillment(of: [ready], timeout: 5)
        try fixture.seed(next)
        let pending = try XCTUnwrap(OriginalImageOwnerURLProtocol.state.withLock { $0.pending })
        pending.finishBody(); let bytes = await request.value
        XCTAssertNil(bytes)
        XCTAssertEqual(fixture.session.mediaLibrary.records.map(\.payload), [next])
        XCTAssertTrue(fixture.session.mediaLibrary.hostProgress.isEmpty)
    }

    func testPictureRetirementRejectsDelayedBytesWithoutCacheMutation() async throws {
        let fixture = OriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "DCIM/PICTURE.JPG", thumbPath: "PICTURE.scr")
        try fixture.seed(file)
        let ready = expectation(description: "Captured picture original is pending")
        OriginalImageOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready) }
        defer { OriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        var current = true
        let request = Task { await fixture.session.originalImageBytes(for: file, ifCurrent: { current }) }
        await fulfillment(of: [ready], timeout: 5)
        current = false
        let pending = try XCTUnwrap(OriginalImageOwnerURLProtocol.state.withLock { $0.pending })
        pending.finishBody(); let bytes = await request.value
        XCTAssertNil(bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.media.fileCacheURL(cameraID: fixture.session.mediaCameraID, file: file).path))
        XCTAssertTrue(fixture.session.mediaLibrary.hostProgress.isEmpty)
    }
}

@MainActor private final class OriginalImageOwnerFixture {
    let manager = OriginalImageOwnerFileManager()
    let media: CameraMedia
    let session: CameraSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OriginalImageOwnerURLProtocol.self]
        media = CameraMedia(fileManager: manager, httpConfiguration: configuration)
        session = CameraSession(borrowing: HevcDecoder(), cameraMedia: media)
        session.datalink = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
        session.phase = .live
    }
    func seed(_ file: MediaFile) throws {
        let owner = session.mediaLibrary
        let (_, codec) = media.sharedCache(cameraID: session.mediaCameraID)
        try owner.applyLocalRecords(.init(resetLibrary: true, upserts: [codec.record(file)]), token: owner.actionToken)
    }
    func close() {
        session.disconnect()
        session.decoder.close()
        try? FileManager.default.removeItem(at: manager.support)
    }
}

private final class OriginalImageOwnerFileManager: FileManager, @unchecked Sendable {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] { [support] }
}

private final class OriginalImageOwnerURLProtocol: URLProtocol, @unchecked Sendable {
    struct State {
        var payload = Data([1, 2, 3])
        var hold = false
        var ready: XCTestExpectation?
        var stopped: XCTestExpectation?
        var requests: [URL] = []
        var pending: OriginalImageOwnerURLProtocol?
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
