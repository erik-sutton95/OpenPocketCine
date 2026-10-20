import Network
import OpenCineHostedTestSupport
import OpenCineRelayApple
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class WatcherConnectionTests: XCTestCase {
    /// The loopback relay answers on its own network queue; wait for the state itself.
    @MainActor
    private func waitUntil(_ predicate: @MainActor @Sendable () -> Bool) async -> Bool {
        await HostedCondition.wait(until: predicate)
    }

    private func host(passcode: String = "") -> WatcherRelayTransport {
        let host = WatcherRelayTransport(
            versionMismatchReason: WatcherRelayJoin.versionMismatchReason)
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

    /// PIB-130: a host hello from another relay version must teach the baseline fix ("update on
    /// both devices"), not read as a property of this build alone.
    @MainActor
    func testWatcherVersionMismatchTeachesUpdatingBothDevices() async throws {
        let listener = try NWListener(using: WatcherRelayNetwork.parameters())
        let queue = DispatchQueue(label: "SIMULATED-version-mismatch-listener")
        // A newer host keeps the link open after its hello; closing at once races the hello
        // against the drop, and the watcher may read the drop first and reconnect.
        let held = VersionMismatchHostConnections()
        listener.newConnectionHandler = { connection in
            held.connections.append(connection)
            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                let hello = WatcherRelayHello(
                    version: WatcherRelayProtocol.version + 1, hostName: "Future relay")
                guard let payload = try? JSONEncoder().encode(hello) else { return }
                connection.send(
                    content: WatcherRelayFraming.encode(kind: .hello, payload: payload),
                    completion: .contentProcessed { _ in })
            }
            connection.start(queue: queue)
        }
        listener.start(queue: queue)
        defer {
            listener.cancel()
            queue.sync { held.connections.forEach { $0.cancel() } }
        }
        // Like the real host's listeningPort: a port is dialable only once the listener is ready
        // and has bound a nonzero port (port 0 fails with EADDRNOTAVAIL).
        let ready = await waitUntil {
            guard case .ready = listener.state, let port = listener.port else { return false }
            return port.rawValue != 0
        }
        XCTAssertTrue(ready)
        let port = try XCTUnwrap(listener.port)
        let client = WatcherRelayClient()
        defer { client.leave() }
        client.join(
            endpoint: .hostPort(host: "127.0.0.1", port: port), hostName: "Future relay",
            passcode: "", watcherID: "test-watcher", deviceName: "Test watcher")
        let failed = await waitUntil {
            client.status == .failed(
                "Update OpenPocketCine on both devices to watch this feed.")
        }
        XCTAssertTrue(failed, "unexpected watcher status \(client.status)")
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
        // Negative window past the first reconnect delay: a left client must not resolve again.
        try? await Task.sleep(for: .milliseconds(1300))
        XCTAssertEqual(client.status, .idle)
        XCTAssertEqual(resolutions, 0)
    }
}

/// The simulated newer host's open connections, touched only on its listener queue.
private final class VersionMismatchHostConnections: @unchecked Sendable {
    var connections: [NWConnection] = []
}
