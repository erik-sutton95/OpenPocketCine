import Network
import XCTest

@testable import OpenPocketCine

final class WatcherConnectionTests: XCTestCase {
    @MainActor
    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool, timeout: Double = 5) async
        -> Bool
    {
        let end = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < end {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return predicate()
    }

    private func host(passcode: String = "") -> WatcherRelayTransport {
        let host = WatcherRelayTransport()
        host.queue.sync {
            host.start(
                hostName: "Loopback relay", cameraName: "Test camera", passcode: passcode,
                ceilingIndex: 3, allowsControl: true)
        }
        return host
    }

    @MainActor
    func testPasscodeDenialRetryAndExplicitHostStopReachRealClient() async throws {
        let host = host(passcode: "example-only")
        defer { host.queue.sync { host.stop() } }
        let ready = await waitUntil { host.queue.sync { host.listeningPort != nil } }
        XCTAssertTrue(ready)
        let port = try XCTUnwrap(host.queue.sync { host.listeningPort })
        let client = WatcherRelayClient()
        defer { client.leave() }
        client.join(
            endpoint: .hostPort(host: "127.0.0.1", port: port), hostName: "Loopback relay",
            passcode: "", watcherID: "test-watcher", deviceName: "Test watcher")
        let denied = await waitUntil { client.status == .needsPasscode }
        XCTAssertTrue(denied, "The host must flush the passcode refusal before closing")
        client.retryPasscode("example-only")
        let accepted = await waitUntil { client.status == .live }
        XCTAssertTrue(accepted)
        host.queue.sync { host.stop(reason: "The host ended this shared feed.") }
        let stopped = await waitUntil {
            client.status == .failed("The host ended this shared feed.")
        }
        XCTAssertTrue(stopped, "Explicit host stop is terminal, not a reconnect loop")
    }

    @MainActor
    func testIncomingFramePreservesLocalAssistsAndMirror() async throws {
        let host = host()
        defer { host.queue.sync { host.stop() } }
        let ready = await waitUntil { host.queue.sync { host.listeningPort != nil } }
        XCTAssertTrue(ready)
        let port = try XCTUnwrap(host.queue.sync { host.listeningPort })
        let client = WatcherRelayClient()
        defer { client.leave() }
        client.join(
            endpoint: .hostPort(host: "127.0.0.1", port: port), hostName: "Loopback relay",
            passcode: "", watcherID: "test-watcher", deviceName: "Test watcher")
        let accepted = await waitUntil { client.status == .live }
        XCTAssertTrue(accepted)
        client.decoder.effects.mirror = true
        let selected = client.decoder.effects
        client.decoder.assistMirror = true
        host.queue.sync {
            host.broadcast(
                hevc: Data([0, 0, 0, 1, 0x26, 1]), isKey: true, sets: nil, mirrored: true)
        }
        let arrived = await waitUntil { client.decoder.poseViewFlip }
        XCTAssertTrue(arrived)
        XCTAssertTrue(client.decoder.assistMirror)
        XCTAssertEqual(client.decoder.effects, selected)
    }

    @MainActor
    func testUnexpectedDisconnectResolvesFreshEndpointAndRejoins() async throws {
        let first = host()
        let second = host()
        defer {
            first.queue.sync { first.stop() }
            second.queue.sync { second.stop() }
        }
        let ready = await waitUntil {
            first.queue.sync { first.listeningPort != nil }
                && second.queue.sync { second.listeningPort != nil }
        }
        XCTAssertTrue(ready)
        let port = try XCTUnwrap(first.queue.sync { first.listeningPort })
        let secondPort = try XCTUnwrap(second.queue.sync { second.listeningPort })
        let client = WatcherRelayClient()
        defer { client.leave() }
        var resolutions = 0
        client.resolveEndpoint = { _ in
            resolutions += 1
            return .hostPort(host: "127.0.0.1", port: secondPort)
        }
        client.join(
            endpoint: .hostPort(host: "127.0.0.1", port: port), hostName: "Loopback relay",
            passcode: "", watcherID: "test-watcher", deviceName: "Test watcher")
        let firstJoin = await waitUntil { client.status == .live }
        XCTAssertTrue(firstJoin)
        first.queue.sync { first.stop() }
        let rejoined = await waitUntil { resolutions > 0 && client.status == .live }
        XCTAssertTrue(rejoined, "Retry must use the newly resolved host endpoint")
        XCTAssertFalse(client.token.holderIsRecipient)
    }

    @MainActor
    func testLeaveCancelsPendingReconnectAndNewHostClearsOldState() async {
        let client = WatcherRelayClient()
        var resolutions = 0
        client.resolveEndpoint = { _ in
            resolutions += 1
            return nil
        }
        client.state.cameraName = "Old camera"
        client.token.holderIsRecipient = true
        client.join(
            endpoint: .hostPort(host: "127.0.0.1", port: 9), hostName: "New relay",
            passcode: "", watcherID: "test-watcher", deviceName: "Test watcher")
        XCTAssertEqual(client.state.cameraName, "")
        XCTAssertFalse(client.token.holderIsRecipient)
        client.leave()
        try? await Task.sleep(for: .milliseconds(1300))
        XCTAssertEqual(client.status, .idle)
        XCTAssertEqual(resolutions, 0)
    }
}
