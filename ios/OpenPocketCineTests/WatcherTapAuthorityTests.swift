import Foundation
import MonitorPresentation
import OpenCineRelay
import XCTest

@testable import OpenPocketCine

@MainActor
private final class WatcherTapWireLog {
    var packets: [Data] = []
    var onCommand: (@MainActor () -> Void)?

    func accept(_ data: Data) {
        packets.append(data)
        let callback = onCommand
        onCommand = nil
        callback?()
    }
}

final class WatcherTapAuthorityTests: XCTestCase {
    @MainActor
    private func makeClient(_ log: WatcherTapWireLog) -> WatcherRelayClient {
        let result = WatcherRelayClient(commandWire: { log.accept($0) })
        grant(result)
        return result
    }

    @MainActor
    private func grant(_ client: WatcherRelayClient) {
        client.status = .live
        client.token = .init(holderName: "Watcher", holderIsRecipient: true)
        client.hostTitle = "Same camera"
    }

    @MainActor
    private func tap(
        _ client: WatcherRelayClient, mirrored: Bool = false, flipped: Bool = false
    ) -> @MainActor (CGPoint) -> MonitorWatcherFocus? {
        WatcherLiveView.capturedTapAction(
            client: client, feed: CGSize(width: 400, height: 200),
            mirrored: { mirrored }, flippedVertically: { flipped })
    }

    private func command(_ wire: Data) throws -> WatcherRelayCommand {
        let message = try XCTUnwrap(WatcherRelayFraming.decode(from: wire))
        XCTAssertEqual(message.kind, .command)
        XCTAssertEqual(message.consumedBytes, wire.count)
        return try JSONDecoder().decode(WatcherRelayCommand.self, from: message.payload)
    }

    @MainActor
    func testCurrentTapPreservesMirroredFlippedCoordinatesAndExactWireFrame() throws {
        let log = WatcherTapWireLog()
        let client = makeClient(log)
        let action = tap(client, mirrored: true, flipped: true)
        let mark = try XCTUnwrap(action(CGPoint(x: 100, y: 50)))
        XCTAssertEqual(mark, .init(source: client.tapSource, x: 0.75, y: 0.75))
        XCTAssertEqual(log.packets.count, 1)
        XCTAssertEqual(
            try command(log.packets[0]),
            .tapFocus(cameraX: 750, cameraY: 750, coordinateWidth: 1000, coordinateHeight: 1000))
    }

    @MainActor
    func testSourceReplacementRetiresOldFocusAndRenderedTap() throws {
        let log = WatcherTapWireLog()
        let client = makeClient(log)
        let oldAction = tap(client)
        let first = try XCTUnwrap(oldAction(CGPoint(x: 100, y: 50)))
        var interaction = MonitorWatcherInteraction()
        let admitted = interaction.applyFocus(first, current: client.tapSource)
        XCTAssertTrue(admitted)
        log.packets.removeAll()
        client.leave()
        grant(client)
        interaction.retireFocus(current: client.tapSource)
        XCTAssertNil(interaction.focus)
        XCTAssertNil(oldAction(CGPoint(x: 200, y: 100)))
        XCTAssertTrue(log.packets.isEmpty)
        let current = try XCTUnwrap(tap(client)(CGPoint(x: 200, y: 100)))
        let accepted = interaction.applyFocus(current, current: client.tapSource)
        XCTAssertTrue(accepted)
        XCTAssertEqual(interaction.focus, current)
        XCTAssertEqual(log.packets.count, 1)
    }

    @MainActor
    func testSourceABARejectsOldCompletionEvenWhenHostAndControlReturn() {
        let log = WatcherTapWireLog()
        let client = makeClient(log)
        let oldSource = client.tapSource
        let oldAction = tap(client)
        client.leave()
        grant(client)
        client.leave()
        grant(client)
        XCTAssertEqual(client.hostTitle, "Same camera")
        XCTAssertTrue(client.canControl)
        XCTAssertNotEqual(client.tapSource.revision, oldSource.revision)
        XCTAssertNil(oldAction(CGPoint(x: 100, y: 50)))
        XCTAssertTrue(log.packets.isEmpty)
    }

    @MainActor
    func testControlLossRefusesWithoutGrantingNewAuthority() {
        let log = WatcherTapWireLog()
        let client = makeClient(log)
        let oldAction = tap(client)
        client.token = .init(holderName: "Host", holderIsRecipient: false)
        XCTAssertNil(oldAction(CGPoint(x: 100, y: 50)))
        XCTAssertTrue(log.packets.isEmpty)
    }

    @MainActor
    func testRecordingOnlyReportPreservesCurrentTap() throws {
        let log = WatcherTapWireLog()
        let client = makeClient(log)
        let source = client.tapSource
        let action = tap(client)
        client.state.isRecording = true
        XCTAssertEqual(client.tapSource, source)
        let mark = try XCTUnwrap(action(CGPoint(x: 100, y: 50)))
        XCTAssertEqual(mark.source, source)
        XCTAssertEqual(log.packets.count, 1)
        XCTAssertEqual(
            try command(log.packets[0]),
            .tapFocus(cameraX: 250, cameraY: 250, coordinateWidth: 1000, coordinateHeight: 1000))
    }

    @MainActor
    func testMappingCallbackReplacementSendsNoSuccessorCommand() {
        let log = WatcherTapWireLog()
        let client = makeClient(log)
        let action = WatcherLiveView.capturedTapAction(
            client: client,
            feed: CGSize(width: 400, height: 200),
            mirrored: {
                client.leave()
                self.grant(client)
                return true
            }, flippedVertically: { false })
        XCTAssertNil(action(CGPoint(x: 100, y: 50)))
        XCTAssertTrue(log.packets.isEmpty)
        XCTAssertTrue(client.canControl)
    }

    @MainActor
    func testEnteredWireReplacementWithoutControlSuppressesOldFocusPublication() throws {
        let log = WatcherTapWireLog()
        let client = makeClient(log)
        let action = tap(client)
        let source = client.tapSource
        var interaction = MonitorWatcherInteraction()
        let admitted = interaction.applyFocus(
            .init(source: source, x: 0.3, y: 0.7), current: source)
        XCTAssertTrue(admitted)
        log.onCommand = { client.leave() }
        let result = action(CGPoint(x: 100, y: 50))
        if let result { interaction.applyFocus(result, current: client.tapSource) }
        interaction.retireFocus(current: client.tapSource)
        XCTAssertNil(result)
        XCTAssertNil(interaction.focus)
        XCTAssertFalse(client.canControl)
        XCTAssertEqual(log.packets.count, 1)
        XCTAssertEqual(
            try command(log.packets[0]),
            .tapFocus(cameraX: 250, cameraY: 250, coordinateWidth: 1000, coordinateHeight: 1000))
    }

    @MainActor
    func testEnteredWireReplacementWithControlKeepsSuccessorFocus() throws {
        let log = WatcherTapWireLog()
        let client = makeClient(log)
        let action = tap(client)
        let oldSource = client.tapSource
        var interaction = MonitorWatcherInteraction()
        log.onCommand = {
            client.leave()
            self.grant(client)
            interaction.applyFocus(
                .init(source: client.tapSource, x: 0.8, y: 0.2), current: client.tapSource)
        }
        let result = action(CGPoint(x: 100, y: 50))
        if let result { interaction.applyFocus(result, current: client.tapSource) }
        interaction.retireFocus(current: client.tapSource)
        let refused = interaction.applyFocus(
            .init(source: oldSource, x: 0.1, y: 0.9), current: client.tapSource)
        XCTAssertNil(result)
        XCTAssertFalse(refused)
        XCTAssertEqual(
            interaction.focus, MonitorWatcherFocus(source: client.tapSource, x: 0.8, y: 0.2))
        XCTAssertTrue(client.canControl)
        XCTAssertEqual(log.packets.count, 1)
        XCTAssertEqual(
            try command(log.packets[0]),
            .tapFocus(cameraX: 250, cameraY: 250, coordinateWidth: 1000, coordinateHeight: 1000))
    }

    @MainActor
    func testExpiredCapturedCommandRefusesWhileDirectCommandRemainsAvailable() throws {
        let log = WatcherTapWireLog()
        let client = makeClient(log)
        let oldSource = client.tapSource
        client.leave()
        grant(client)
        let refused = client.sendCommand(.setISO(4), captured: oldSource)
        XCTAssertFalse(refused)
        XCTAssertTrue(log.packets.isEmpty)
        client.sendCommand(.setISO(4))
        XCTAssertEqual(log.packets.count, 1)
        XCTAssertEqual(try command(log.packets[0]), .setISO(4))
    }
}
