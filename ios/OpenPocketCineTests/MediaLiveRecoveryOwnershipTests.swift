import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class MediaLiveRecoveryOwnershipTests: XCTestCase {
    func testProductionMediaLoopSendsOneEnableThenExhaustsItsPictureDeadline() async {
        var exits = 0
        var enables = 0
        let result = await MediaLiveResumeRunner.run(
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
        let result = await MediaLiveResumeRunner.run(
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
            await MediaLiveResumeRunner.run(
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
            let session = CameraSession(borrowing: HevcDecoder())
            let driver = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "")
            session.datalink = driver
            let token = session.cameraMedia.resumeID
            var entered = false
            let waiting = Task {
                entered = true
                return await session.finishDatalinkRecoveryPicture(
                    driver: driver, since: Date(), timeout: .seconds(2), pictureOwner: token)
            }
            while !entered { await Task.yield() }
            session.beginMediaBrowse()
            if returnToLive {
                session.endMediaBrowse()
                // Avoid camera I/O in this test; the actual entry/return already
                // changed the generation and queued its replacement owner.
                session.cameraMedia.resumeLiveTask?.cancel()
            }
            let result = await waiting.value
            XCTAssertEqual(result, .superseded)
            XCTAssertFalse(driver.isClosed, "Media transition must preserve negotiated transport")
            session.cameraMedia.cancelResumeLive()
            session.resetFeedWatchdog()
            session.datalink = nil
            driver.close()
        }
    }

    func testMediaRoundTripDuringRealNegotiationSeamRetiresOnlyPictureWork() async {
        let session = CameraSession(borrowing: HevcDecoder())
        let token = session.cameraMedia.resumeID
        var negotiation: CheckedContinuation<Void, Never>?
        var negotiated = false
        var enables = 0
        var pictureWaits = 0
        var failures = 0
        let owner = Task {
            await runNegotiatedPictureRepair(
                negotiate: {
                    await withCheckedContinuation { negotiation = $0 }
                    negotiated = true
                },
                driverIsCurrent: { true },
                ownsPicture: { session.isLivePictureRepairCurrent(token) },
                enable: { enables += 1 },
                waitForPicture: { pictureWaits += 1 },
                failed: { _ in failures += 1 })
        }
        while negotiation == nil { await Task.yield() }
        session.beginMediaBrowse()
        session.endMediaBrowse()
        negotiation?.resume()
        await owner.value
        XCTAssertTrue(negotiated)
        XCTAssertEqual(enables, 0)
        XCTAssertEqual(pictureWaits, 0)
        XCTAssertEqual(failures, 0)
    }

    func testFailedNegotiationDuringMediaStillHandsOffAndReleasesTheRepairSlot() async {
        enum Failure: Error { case handshake }
        let session = CameraSession(borrowing: HevcDecoder())
        let token = session.cameraMedia.resumeID
        var negotiation: CheckedContinuation<Void, Never>?
        var failed = false
        session.startFeedRecovery {
            await runNegotiatedPictureRepair(
                negotiate: {
                    await withCheckedContinuation { negotiation = $0 }
                    throw Failure.handshake
                },
                driverIsCurrent: { true },
                ownsPicture: { session.isLivePictureRepairCurrent(token) },
                enable: { XCTFail("A failed negotiation cannot enable") },
                waitForPicture: { XCTFail("A failed negotiation cannot wait for picture") },
                failed: { _ in
                    failed = true
                    // A genuine failed endpoint transfers to the full-session
                    // owner; the queued media return must yield to that owner.
                    session.holdsMonitor = true
                })
        }
        while negotiation == nil { await Task.yield() }
        session.beginMediaBrowse()
        session.endMediaBrowse()
        negotiation?.resume()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while session.cameraMedia.resumeLiveTask != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(failed, "Media only retires picture demand, not a genuine endpoint failure")
        XCTAssertNil(
            session.cameraMedia.resumeLiveTask, "Queued media return must yield to session recovery"
        )
        XCTAssertFalse(
            session.hasFeedRecoveryInFlight, "The retired picture owner cannot stay latched")
        session.disconnect()
    }

    func testMediaReturnDuringNilDriverNegotiationQueuesTheReplacementPictureOwner() async {
        let session = CameraSession(borrowing: HevcDecoder())
        let originalGeneration = session.cameraMedia.resumeID
        var negotiation: CheckedContinuation<Void, Never>?
        var finishedNegotiation = false
        session.startFeedRecovery {
            await withCheckedContinuation { negotiation = $0 }
            finishedNegotiation = true
        }
        while negotiation == nil { await Task.yield() }
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
        let driver = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "")
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
