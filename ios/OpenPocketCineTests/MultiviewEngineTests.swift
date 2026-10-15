import OpenCineAppKit
import OpenCineCore
import OpenCineMulticam
import OpenPocketViewCore
import SwiftUI
import XCTest
import OpenCineDJIApple

@testable import OpenPocketCine

/// The Multi View rows of plan 11.3 that need no hardware, on Pocket's own tiles driving the
/// OpenCineMulticam engine through each tile's `DJICameraSessionAdapter`.
@MainActor final class MultiviewEngineTests: XCTestCase {
    func testSelectionLayoutAndRotationKeepFeedsSessionsAndLinks() async throws {
        let session = linked(MultiviewUIReview.makeSession(count: 4))
        func identities() -> [String] {
            session.tiles.map { tile in
                let driver = tile.driver.map { "\(ObjectIdentifier($0))" } ?? "-"
                return
                    "\(tile.id) \(ObjectIdentifier(tile.decoder)) \(driver) \(tile.control.id) \(tile.control.current.epoch)"
            }
        }
        let before = identities()
        let group = session.multicamGroup
        let controller = UIHostingController(
            rootView: MultiviewView(session: session, startsSession: false, reviewPictures: true)
                .environment(AppModel()))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        for step in 0..<8 {
            window.frame.size =
                step.isMultiple(of: 2)
                ? CGSize(width: 852, height: 393) : CGSize(width: 393, height: 852)
            controller.view.frame = window.bounds
            session.focusedIndex = step % 4
            session.layout = step % 3 == 0 ? .grid : .centerStage
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(identities(), before, "step \(step)")
            XCTAssertEqual(session.multicamGroup, group, "step \(step)")
        }
    }

    func testSwitchingCameraRetiresTheEditorLeaseAndItsQueuedSets() {
        let session = linked(MultiviewUIReview.makeSession(count: 2))
        defer { session.closeCameraSettings() }
        let a = session.tiles[0]
        let b = session.tiles[1]
        let first = session.openCameraSettings(a)!
        let lease = try! XCTUnwrap(session.editorLeases.leases.first)
        XCTAssertEqual(lease.entry, a.entryID)
        XCTAssertEqual(lease.session, a.control.id)
        XCTAssertTrue(first.session.admitsMultiviewControl)

        let second = session.openCameraSettings(b)!
        XCTAssertEqual(
            session.editorLeases.refusal(
                for: lease, in: session.multicamGroup, at: session.multicamSnapshot()),
            .retired)
        XCTAssertFalse(first.session.admitsMultiviewControl)
        XCTAssertTrue(second.session.admitsMultiviewControl)
        first.session.setWhiteBalanceCustom(kelvin: 6000, tint: 0)
        XCTAssertEqual(first.session.controlNote, "not live")
        XCTAssertNil(second.session.pendingWhiteBalance, "The old editor's SET never reaches b")

        // A replaced link retires the lease through the control epoch alone.
        let current = try! XCTUnwrap(session.editorLeases.leases.first)
        b.driver = DjiAppleDatalink(port: 9049, tcpPoke: false, pairingToken: "")
        b.controlHost = "192.0.2.49"
        XCTAssertEqual(
            session.editorLeases.refusal(
                for: current, in: session.multicamGroup, at: session.multicamSnapshot()),
            .retired)
    }

    func testReconnectDuringConfirmationInvalidatesTheApprovedPlan() async {
        let session = linked(MultiviewUIReview.makeSession(count: 2))
        var sent = 0
        for tile in session.tiles {
            tile.controlPort.transmit = { _, _ in
                sent += 1
                return 1
            }
        }
        let approved = MultiviewRecordContext(session: session)
        XCTAssertTrue(approved.canConfirm)
        // Same camera, replacement link: the dialog's plan must not reach it.
        session.tiles[1].driver = DjiAppleDatalink(port: 9048, tcpPoke: false, pairingToken: "")
        let now = MultiviewRecordContext(session: session)
        XCTAssertTrue(now.canConfirm)
        XCTAssertNotEqual(approved, now)
        XCTAssertFalse(
            approved.plan.isCurrent(in: session.multicamGroup, at: session.multicamSnapshot()))
        await session.record(approved.plan, together: true)
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(session.groupRecordingNote, "Cameras changed · try again")
        XCTAssertFalse(session.groupRecordingBusy)
    }

    func testRoutineTelemetryKeepsTheConfirmationValid() {
        let session = linked(MultiviewUIReview.makeSession(count: 3))
        let approved = MultiviewRecordContext(session: session)
        XCTAssertTrue(approved.canConfirm)
        for tile in session.recordingTiles {
            tile.settings.batteryPercent -= 3
            tile.settings.storageFreeMb -= 512
            tile.settings.timecodeValue =
                CameraTimecode(hours: 14, minutes: 32, seconds: 9, frames: 0)
            tile.settings.recordElapsedSec += 1
            tile.settings.whiteBalanceKelvin = 5_200
            tile.latestSettings = tile.settings
            tile.recordingObservation = (tile.recordingActive == true, Date())
        }
        XCTAssertEqual(approved, MultiviewRecordContext(session: session))
        XCTAssertTrue(
            approved.plan.isCurrent(in: session.multicamGroup, at: session.multicamSnapshot()))
    }

    func testOneCameraThatCannotRecordRefusesStrictAndIsListedForSubset() {
        let session = linked(MultiviewUIReview.makeSession(count: 3))
        let blocked = session.tiles[2]
        blocked.recordingAvailable = false  // its record report went stale
        let strict = session.recordPlan()
        XCTAssertEqual(MultiviewSession.recordPolicy, .strict)
        XCTAssertTrue(strict.isRefused)
        XCTAssertEqual(
            strict.exclusions,
            [Exclusion(entry: blocked.entryID, reason: .rejected(.recordingStateUnknown))])
        let context = MultiviewRecordContext(session: session)
        XCTAssertFalse(context.canConfirm)
        XCTAssertEqual(context.refusal, "Waiting for a camera's record state.")
        XCTAssertFalse(session.canRecordTogether)

        let subset = RecordPlan.make(
            strict.direction, policy: .eligibleSubset, entries: strict.requested,
            in: session.multicamGroup, at: session.multicamSnapshot())
        XCTAssertTrue(subset.isExecutable)
        XCTAssertEqual(subset.exclusions, strict.exclusions)
        XCTAssertEqual(
            Set((subset.targets + subset.satisfied).map(\.session)),
            Set(session.tiles.prefix(2).map(\.control.id)))
    }

    func testSomeCamerasStartOneTimesOutAndNothingIsRolledBack() async throws {
        let session = linked(MultiviewUIReview.makeSession(count: 3))
        var frames: [(UUID, [UInt8])] = []
        for (index, tile) in session.recordingTiles.enumerated() {
            tile.recordingObservation = (false, Date())
            tile.controlPort.confirmationWindow = .seconds(1)
            tile.controlPort.transmit = { _, frame in
                frames.append((tile.id, frame.payload))
                return UInt16(index + 1)
            }
        }
        let a = session.tiles[0]
        let b = session.tiles[1]
        let c = session.tiles[2]
        let plan = session.recordPlan()
        XCTAssertEqual(plan.direction, .start)
        XCTAssertEqual(plan.targets.count, 3)
        let run = Task { await session.record(plan, together: true) }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(session.groupRecordingBusy)
        // a ACKs then reports recording; b only reports; c stays silent.
        a.responses[1] = Duml.Frame(
            sender: 0, receiver: 0, seq: 1, flags: 0x80, cmdSet: 2, cmdId: 2, payload: [0])
        a.recordingObservation = (true, Date())
        b.recordingObservation = (true, Date())
        await run.value

        XCTAssertEqual(a.recordingNote, "Recording")
        XCTAssertEqual(b.recordingNote, "Recording")
        XCTAssertEqual(c.recordingNote, "No confirmation · check camera")
        XCTAssertEqual(session.groupRecordingNote, "2 of 3 confirmed · check camera tiles")
        XCTAssertFalse(session.groupRecordingBusy)
        try await Task.sleep(for: .milliseconds(300))
        // Only the three starts went out: no stop for a or b because c timed out.
        XCTAssertEqual(frames.count, 3)
        XCTAssertTrue(frames.allSatisfy { $0.1 == Commands.recordStart().payload })
        XCTAssertEqual(a.recordingActive, true)
        XCTAssertEqual(b.recordingActive, true)
    }

    func testSingleCameraRefusalIsReportedOnItsTileOnly() async throws {
        let session = linked(MultiviewUIReview.makeSession(count: 2))
        let tile = session.tiles[1]
        tile.controlPort.transmit = { _, _ in 7 }
        let plan = session.recordPlan(for: tile)
        XCTAssertEqual(plan.direction, .start)
        let run = Task { await session.record(plan, together: false) }
        try await Task.sleep(for: .milliseconds(150))
        tile.responses[7] = Duml.Frame(
            sender: 0, receiver: 0, seq: 7, flags: 0x80, cmdSet: 2, cmdId: 2, payload: [1])
        await run.value
        XCTAssertEqual(tile.recordingNote, "Recording command rejected · check camera")
        XCTAssertNil(session.tiles[0].recordingNote)
        XCTAssertNil(session.groupRecordingNote)
        XCTAssertFalse(tile.recordingBusy)
    }

    /// Live control links with fresh record reports, as `openPreview` and the 1 s monitor leave them.
    private func linked(_ session: MultiviewSession) -> MultiviewSession {
        for (index, tile) in session.recordingTiles.enumerated() {
            tile.driver = DjiAppleDatalink(
                port: UInt16(9040 + index), tcpPoke: false, pairingToken: "")
            tile.controlHost = "192.0.2.\(40 + index)"
            tile.recordingAvailable = true
        }
        return session
    }
}
