import Foundation
import Testing

@testable import OpenPocketCineAndroidFacade

@Suite struct KnownReferenceLossWireTests {
    @Test func knownRejectedReferencesDoNotWaitForTheGenericOutputTimeout() {
        #expect(
            AndroidSessionWire.feedWatchdogAction(snapshotJSON: Self.snapshot(loss: true))
                == "rebuildVTSession")
        #expect(
            AndroidSessionWire.feedWatchdogAction(snapshotJSON: Self.snapshot(loss: nil)) == "none",
            "Older callers retain the ordinary output-stall threshold")
    }

    @Test func earlyRepairKeepsItsDeadlineWhenTheLossFlagClearsBeforeNewOutput() {
        let handle = AndroidSessionWire.feedWatchdogCreate()
        defer { AndroidSessionWire.feedWatchdogDestroy(handle: handle) }
        func tick(_ now: Double, _ age: Double, _ loss: Bool) -> String {
            AndroidSessionWire.feedWatchdogTick(
                handle: handle, snapshotJSON: Self.snapshot(now: now, outputAge: age, loss: loss))
        }
        #expect(tick(100, 0.239, true) == "rebuildVTSession")
        #expect(tick(100.1, 0.339, false) == "none")
        #expect(tick(101, 1.239, true) == "none")
        #expect(tick(115.999, 16.238, true) == "none")
        #expect(tick(116, 16.239, true) == "fullSessionRejoin")
        #expect(tick(117, 17.239, true) == "none")
    }

    private static func snapshot(
        now: Double = 100, outputAge: Double = 0.239, loss: Bool?
    ) -> String {
        var values: [String: Any] = [
            "now": now, "lastDecodedFrameAge": outputAge,
            "lastDecoderOutputAge": outputAge, "lastVideoPacketAge": 0.01,
            "lastAccessUnitAge": 0.01, "lastStatusAge": 0.01,
            "flowHealthy": true, "pathReady": true, "hasFormat": true,
            "decoderFailed": false, "live": true, "sawPicture": true,
            "decoderOutputExpected": true, "repairReady": true,
        ]
        if let loss { values["referenceRecoveryNeeded"] = loss }
        let data = try! JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
