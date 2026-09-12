import CoreMotion
import XCTest
import os

@testable import OpenPocketCine

@MainActor
final class HeadphoneMotionStartupTests: XCTestCase {
    func testPermissionPendingRepeatedSyncKeepsTheFirstStartAndItsCallback() async {
        let saved = OperatorPrefs.headTrackingEnabled
        defer { OperatorPrefs.headTrackingEnabled = saved }
        let motion = PendingHeadphoneMotionManager()
        var auth = CMAuthorizationStatus.notDetermined
        let bridge = HeadphoneMotionBridge(
            motion: motion, authorizationStatus: { auth }, uptime: { 100 })
        let model = AppModel()
        model.headTrackingEnabled = true
        bridge.attach(model: model)
        defer { bridge.detach() }
        bridge.sync()
        bridge.headphoneMotionManagerDidConnect(motion)
        // The delegate hops onto MainActor, where it calls startMotion then sync.
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(motion.starts.count, 1, "Pending permission must have one owned start")

        auth = .authorized
        motion.active = true
        bridge.sync()
        // Deliberately retain the first handler: duplicate-start handler ownership
        // is undocumented by Core Motion and must not be needed for correctness.
        motion.starts.first?(HeadphoneMotionSample(timestamp: 99.95), nil)
        XCTAssertEqual(
            bridge.receivedHeadSampleAt, 99.95, "Permission approval must not need an off/on toggle"
        )
    }

    func testStoppingPendingPermissionCancelsTheRequestAndFencesItsCallback() {
        let saved = OperatorPrefs.headTrackingEnabled
        defer { OperatorPrefs.headTrackingEnabled = saved }
        let motion = PendingHeadphoneMotionManager()
        let bridge = HeadphoneMotionBridge(
            motion: motion, authorizationStatus: { .notDetermined }, uptime: { 100 })
        let model = AppModel()
        model.headTrackingEnabled = true
        bridge.attach(model: model)
        defer { bridge.detach() }
        let initialStops = motion.stopCount
        let oldCallback = motion.starts.first
        model.headTrackingEnabled = false
        bridge.sync()
        XCTAssertEqual(
            motion.stopCount, initialStops + 1,
            "An inactive OS stream can still have a pending start")
        oldCallback?(HeadphoneMotionSample(timestamp: 99.95), nil)
        XCTAssertNil(bridge.receivedHeadSampleAt)

        model.headTrackingEnabled = true
        bridge.sync()
        motion.starts.last?(HeadphoneMotionSample(timestamp: 99.96), nil)
        XCTAssertEqual(bridge.receivedHeadSampleAt, 99.96)
        oldCallback?(HeadphoneMotionSample(timestamp: 99.97), nil)
        XCTAssertEqual(
            bridge.receivedHeadSampleAt, 99.96, "Prior callback cannot replace the new stream")
    }

    func testPermissionDeniedTapPreservesPermissionGuidance() {
        let saved = OperatorPrefs.headTrackingEnabled
        defer { OperatorPrefs.headTrackingEnabled = saved }
        let motion = PendingHeadphoneMotionManager()
        let bridge = HeadphoneMotionBridge(motion: motion, authorizationStatus: { .denied })
        let model = AppModel()
        model.headTrackingEnabled = true
        bridge.attach(model: model)
        defer { bridge.detach() }
        bridge.tapControl()
        XCTAssertEqual(
            model.session.controlNote, "Allow Motion & Fitness for OpenPocketCine in Settings")
        XCTAssertTrue(motion.starts.isEmpty)
    }

    func testMotionFailureStopsTheStreamAndRequiresAnExplicitRetry() async {
        let saved = OperatorPrefs.headTrackingEnabled
        defer { OperatorPrefs.headTrackingEnabled = saved }
        let motion = PendingHeadphoneMotionManager()
        let bridge = HeadphoneMotionBridge(
            motion: motion, authorizationStatus: { .authorized }, uptime: { 100 })
        let model = AppModel()
        model.headTrackingEnabled = true
        bridge.attach(model: model)
        defer { bridge.detach() }
        let stopped = expectation(description: "Failed motion request cancelled")
        motion.onStop = { stopped.fulfill() }
        let failedCallback = motion.starts.first
        failedCallback?(nil, NSError(domain: "HeadphoneMotionTest", code: 1))
        await fulfillment(of: [stopped], timeout: 1)
        motion.onStop = nil
        bridge.sync()
        XCTAssertEqual(motion.starts.count, 1, "Ordinary sync must not retry an error indefinitely")
        XCTAssertEqual(
            model.session.controlNote, "Headphone motion stopped — tap Calibrate to retry")
        bridge.tapControl()
        XCTAssertEqual(motion.starts.count, 2)
        motion.starts.last?(HeadphoneMotionSample(timestamp: 99.95), nil)
        failedCallback?(HeadphoneMotionSample(timestamp: 99.97), nil)
        XCTAssertEqual(bridge.receivedHeadSampleAt, 99.95)
    }

    func testExplicitRetryAfterNoSamplesDoesNotRestartPendingPermission() {
        let saved = OperatorPrefs.headTrackingEnabled
        defer { OperatorPrefs.headTrackingEnabled = saved }
        let motion = PendingHeadphoneMotionManager()
        let clock = OSAllocatedUnfairLock(initialState: 100.0)
        var auth = CMAuthorizationStatus.notDetermined
        let bridge = HeadphoneMotionBridge(
            motion: motion, authorizationStatus: { auth }, uptime: { clock.withLock { $0 } })
        let model = AppModel()
        model.headTrackingEnabled = true
        bridge.attach(model: model)
        defer { bridge.detach() }
        clock.withLock { $0 = 110 }
        bridge.tapControl()
        XCTAssertEqual(motion.starts.count, 1)
        XCTAssertEqual(model.session.controlNote, "Allow Motion & Fitness to start head tracking")

        auth = .authorized
        motion.active = true
        bridge.tapControl()
        XCTAssertEqual(
            motion.starts.count, 2, "An explicit tap can replace a silent authorized stream")
        XCTAssertEqual(model.session.controlNote, "Waiting for headphone motion")
        motion.starts.last?(HeadphoneMotionSample(timestamp: 109.95), nil)
        XCTAssertEqual(bridge.receivedHeadSampleAt, 109.95)
    }

    func testStartupDiagnosticsAreBoundedAndDistinguishAcceptedFromRejectedSamples() {
        let saved = OperatorPrefs.headTrackingEnabled
        defer { OperatorPrefs.headTrackingEnabled = saved }
        let motion = PendingHeadphoneMotionManager()
        let clock = OSAllocatedUnfairLock(initialState: 100.0)
        var lines: [String] = []
        let bridge = HeadphoneMotionBridge(
            motion: motion, authorizationStatus: { .authorized }, uptime: { clock.withLock { $0 } },
            startupLog: { lines.append($0) })
        let model = AppModel()
        model.headTrackingEnabled = true
        bridge.attach(model: model)
        defer { bridge.detach() }
        for _ in 0..<20 { bridge.sync() }
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("requested=1"))
        XCTAssertTrue(lines[0].contains("accepted=0 rejected=0 sampleAgeMs=-"))

        motion.starts.first?(HeadphoneMotionSample(timestamp: 99.95), nil)
        motion.starts.first?(HeadphoneMotionSample(timestamp: 99.95), nil)
        motion.starts.first?(HeadphoneMotionSample(timestamp: 99), nil)
        clock.withLock { $0 = 101 }
        bridge.sync()
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("accepted=1 rejected=2 sampleAgeMs=1050"))
        XCTAssertEqual(motion.starts.count, 1)
    }
}

private final class PendingHeadphoneMotionManager: CMHeadphoneMotionManager {
    var active = false
    var connectionActive = false
    var starts: [CMHeadphoneMotionManager.DeviceMotionHandler] = []
    var stopCount = 0
    var onStop: (() -> Void)?
    override var isDeviceMotionAvailable: Bool { true }
    override var isDeviceMotionActive: Bool { active }
    override var isConnectionStatusActive: Bool { connectionActive }
    override func startConnectionStatusUpdates() { connectionActive = true }
    override func stopConnectionStatusUpdates() { connectionActive = false }
    override func startDeviceMotionUpdates(
        to queue: OperationQueue,
        withHandler handler: @escaping CMHeadphoneMotionManager.DeviceMotionHandler
    ) {
        starts.append(handler)
    }
    override func stopDeviceMotionUpdates() {
        stopCount += 1
        active = false
        onStop?()
    }
}

private final class HeadphoneMotionSample: CMDeviceMotion {
    private let measuredAt: TimeInterval
    init(timestamp: TimeInterval) {
        measuredAt = timestamp
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override var timestamp: TimeInterval { measuredAt }
    override var attitude: CMAttitude { IdentityHeadphoneAttitude() }
    override var rotationRate: CMRotationRate { CMRotationRate(x: 0, y: 0, z: 0) }
}

private final class IdentityHeadphoneAttitude: CMAttitude {
    override var quaternion: CMQuaternion { CMQuaternion(x: 0, y: 0, z: 0, w: 1) }
    override var yaw: Double { 0 }
    override var pitch: Double { 0 }
    override var roll: Double { 0 }
}
