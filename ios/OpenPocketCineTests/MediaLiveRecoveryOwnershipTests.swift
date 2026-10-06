import OpenCineDJIApple
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class MediaLiveRecoveryOwnershipTests: XCTestCase {
    func testProductionMediaLoopSendsOneEnableThenExhaustsItsPictureDeadline() async {
        var exits = 0
        var enables = 0
        let result = await DjiAppleMediaLiveReturn.run(
            timeout: .milliseconds(450),
            isCurrent: { true }, inPlayback: { false }, pictureFresh: { false },
            exitPlayback: {
                exits += 1
                return true
            },
            enableLiveView: {
                enables += 1
                return true
            })
        XCTAssertEqual(result, .exhausted)
        XCTAssertEqual(exits, 1)
        XCTAssertEqual(enables, 1, "Waiting for the first picture must not repeat a successful PLI")
    }

    func testProductionMediaLoopWaitsForAcceptedEnableAndFreshPicture() async {
        var attempts = 0
        var accepted = 0
        let result = await DjiAppleMediaLiveReturn.run(
            timeout: .seconds(2),
            isCurrent: { true }, inPlayback: { false }, pictureFresh: { accepted == 1 },
            exitPlayback: { true },
            enableLiveView: {
                attempts += 1
                guard attempts == 2 else { return false }
                accepted += 1
                return true
            })
        XCTAssertEqual(result, .restored)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(accepted, 1)
    }

    func testMediaEntryDuringExitAwaitPreventsLateEnable() async {
        var current = true
        var exit: CheckedContinuation<Bool, Never>?
        var enables = 0
        let task = Task {
            await DjiAppleMediaLiveReturn.run(
                isCurrent: { current }, inPlayback: { false }, pictureFresh: { false },
                exitPlayback: { await withCheckedContinuation { exit = $0 } },
                enableLiveView: {
                    enables += 1
                    return true
                })
        }
        while exit == nil { await Task.yield() }
        current = false
        exit?.resume(returning: true)
        let result = await task.value
        XCTAssertEqual(result, .superseded)
        XCTAssertEqual(enables, 0)
    }

    func testActualEndpointPictureWaitRetiresOnMediaEntryAndQuickReturn() async {
        for returnToLive in [false, true] {
            let now = Date.timeIntervalSinceReferenceDate
            var waits: [CheckedContinuation<Void, Never>] = []
            let session = CameraSession(pictureRecoveryTiming: .init(
                wallNow: { now }, monotonicNow: { now }, wait: { delay in
                    XCTAssertEqual(delay, .milliseconds(100))
                    await withCheckedContinuation { waits.append($0) }
                }))
            let peer = ConnectionDonorPeer(cached: true)
            guard await peer.admitExistingConnection(session) else { return }
            let driver = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
            defer {
                session.disconnect(); driver.close(); session.decoder.close()
                withExtendedLifetime(peer) {}
            }
            session.datalink = driver
            XCTAssertNil(session.decoder.lastSourceFrameAt, "Admission does not fabricate native picture")
            let token = session.cameraMedia.resumeID
            var entered = false
            let waiting = Task {
                await withCheckedContinuation { continuation in
                    let admitted = session.startFeedRecovery { attempt in
                        entered = true
                        let result = await attempt.waitForPicture(.init(datalink: driver),
                            since: now, pictureIntent: token,
                            timeout: .seconds(2))
                        continuation.resume(returning: result)
                    }
                    if !admitted {
                        XCTFail("The actual picture-repair owner must admit this empty slot")
                        entered = true
                        continuation.resume(returning: DjiApplePictureRecovery.Result.superseded)
                    }
                }
            }
            while !entered { await Task.yield() }
            session.beginMediaBrowse()
            if returnToLive {
                session.endMediaBrowse()
                // Avoid camera I/O in this test; the actual entry/return already
                // changed the generation and queued its replacement owner.
                session.cameraMedia.resumeLiveTask?.cancel()
            }
            XCTAssertEqual(waits.count, 1, "The actual native adapter reaches the shared manual wait")
            waits.forEach { $0.resume() }
            let result = await waiting.value
            XCTAssertEqual(result, .superseded)
            XCTAssertFalse(driver.isClosed, "Media transition must preserve negotiated transport")
            session.cameraMedia.cancelResumeLive()
            session.resetFeedWatchdog()
            session.datalink = nil
            driver.close()
        }
    }

    func testMediaReturnDuringNilDriverNegotiationQueuesTheReplacementPictureOwner() async {
        let session = CameraSession()
        let peer = ConnectionDonorPeer(cached: true)
        defer { session.disconnect(); session.decoder.close(); withExtendedLifetime(peer) {} }
        guard await peer.admitExistingConnection(session) else { return }
        let originalGeneration = session.cameraMedia.resumeID
        var negotiation: CheckedContinuation<Void, Never>?
        var finishedNegotiation = false
        guard session.startFeedRecovery({ _ in
            await withCheckedContinuation { negotiation = $0 }
            finishedNegotiation = true
        }) else { XCTFail("Current real run must admit negotiation in the genuine nil-driver gap"); return }
        let negotiationDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while negotiation == nil, ContinuousClock.now < negotiationDeadline { await Task.yield() }
        guard negotiation != nil else { XCTFail("Admitted negotiation must reach the manual wait"); return }
        XCTAssertNil(session.datalink, "Exercise the full-rejoin gap before a driver is adopted")
        session.beginMediaBrowse()
        session.endMediaBrowse()
        XCTAssertEqual(session.cameraMedia.resumeID, originalGeneration + 2)
        XCTAssertNotNil(
            session.cameraMedia.resumeLiveTask, "Media return cannot lose ownership in this gap")
        XCTAssertFalse(finishedNegotiation, "Opening media must not cancel negotiation")
        negotiation?.resume()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while session.cameraMedia.resumeLiveTask != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(finishedNegotiation)
        XCTAssertNil(
            session.cameraMedia.resumeLiveTask, "Pending return must transfer into the feed slot")
        XCTAssertTrue(session.hasFeedRecoveryInFlight)
        session.disconnect()
    }

    func testRepeatedMediaReturnWithoutDriverClearsTheCanceledPendingOwner() {
        let session = CameraSession(borrowing: HevcDecoder())
        let driver = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
        session.datalink = driver
        session.endMediaBrowse()
        let pending = session.cameraMedia.resumeLiveTask
        let generation = session.cameraMedia.resumeID
        XCTAssertNotNil(pending)

        // The transport can disappear before the queued return gets actor time.
        // A repeated dismissal must not leave its canceled task as a live gate.
        session.datalink = nil
        session.endMediaBrowse()
        XCTAssertTrue(pending?.isCancelled == true)
        XCTAssertNil(session.cameraMedia.resumeLiveTask)
        XCTAssertEqual(session.cameraMedia.resumeID, generation + 1)
        session.endMediaBrowse()
        XCTAssertNil(session.cameraMedia.resumeLiveTask)
        XCTAssertEqual(session.cameraMedia.resumeID, generation + 2)
        driver.close()
        session.disconnect()
    }
}
