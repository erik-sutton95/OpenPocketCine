import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct FacePriorityExposureTests {
    @Test func oneDarkFaceAddsPositiveEV() {
        let transfer = MonitorTransfer.rec709
        let dark = transfer.encodeLinear(0.18 / 4)
        let next = FacePriorityExposure.nextEV(
            current: .zero, encoded: dark, transfer: transfer)
        #expect(next != nil)
        #expect((next?.thirds ?? 0) > 0)
    }

    @Test func oneBrightFaceSubtractsEV() {
        let transfer = MonitorTransfer.rec709
        let bright = transfer.encodeLinear(0.18 * 4)
        let next = FacePriorityExposure.nextEV(
            current: .zero, encoded: bright, transfer: transfer)
        #expect(next != nil)
        #expect((next?.thirds ?? 0) < 0)
    }

    @Test func largeErrorMovesOneThird() {
        let transfer = MonitorTransfer.rec709
        let dark = transfer.encodeLinear(0.18 / 4)
        let next = FacePriorityExposure.nextEV(
            current: .zero, encoded: dark, transfer: transfer)
        #expect(next == EvComp(thirds: 1))
    }

    @Test func twoThirdsDeadbandHolds() {
        let transfer = MonitorTransfer.rec709
        let near = transfer.encodeLinear(0.18 * pow(2.0, -0.5))
        #expect(
            FacePriorityExposure.nextEV(
                current: .zero, encoded: near, transfer: transfer)
                == nil)
    }

    @Test func alreadyOnGrayIsDeadband() {
        let transfer = MonitorTransfer.dlog2
        #expect(
            FacePriorityExposure.nextEV(
                current: .zero, encoded: transfer.middleGrayEncoded, transfer: transfer)
                == nil)
    }

    @Test func restoreUsesSavedOrZero() {
        #expect(FacePriorityExposure.restoreEV(saved: nil) == .zero)
        #expect(FacePriorityExposure.restoreEV(saved: EvComp(thirds: 3)) == EvComp(thirds: 3))
        #expect(FacePriorityExposure.restoreEV(saved: EvComp(thirds: -2)) == EvComp(thirds: -2))
    }

    @Test func twoFacesUseMedian() {
        #expect(FacePriorityExposure.median([0.1, 0.9]) == 0.5)
        #expect(FacePriorityExposure.median([0.2, 0.4, 0.9]) == 0.4)
        #expect(FacePriorityExposure.median([]) == nil)
    }

    @Test func emptyTapWritesNothing() {
        let bytes = [UInt8](repeating: 128, count: 16)
        #expect(
            FacePriorityExposure.medianEncoded(
                bytes: bytes, width: 2, height: 2, bytesPerRow: 8,
                boxes: [], transfer: .rec709)
                == nil)
    }

    @Test func samplesPixelsInsideTheBox() {
        // 8×8 BGRA, left half black, right half white.
        var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for y in 0..<8 {
            for x in 4..<8 {
                let i = (y * 8 + x) * 4
                bytes[i] = 255
                bytes[i + 1] = 255
                bytes[i + 2] = 255
            }
        }
        let left = TrackingBox(x: 0, y: 0, width: 0.5, height: 1)
        let right = TrackingBox(x: 0.5, y: 0, width: 0.5, height: 1)
        let dark = FacePriorityExposure.medianEncoded(
            bytes: bytes, width: 8, height: 8, bytesPerRow: 32,
            boxes: [left], transfer: .rec709)
        let bright = FacePriorityExposure.medianEncoded(
            bytes: bytes, width: 8, height: 8, bytesPerRow: 32,
            boxes: [right], transfer: .rec709)
        let both = FacePriorityExposure.medianEncoded(
            bytes: bytes, width: 8, height: 8, bytesPerRow: 32,
            boxes: [left, right], transfer: .rec709)
        #expect(dark != nil && dark! < 0.1)
        #expect(bright != nil && bright! > 0.9)
        #expect(both != nil)
        #expect(abs(both! - 0.5) < 0.15)
    }

    @Test func intervalIsFastWhileAcquiring() {
        let start = Date()
        #expect(
            FacePriorityExposure.interval(sinceAcquire: start, now: start)
                == FacePriorityExposure.acquireInterval)
        #expect(
            FacePriorityExposure.interval(
                sinceAcquire: start, now: start.addingTimeInterval(2.4))
                == FacePriorityExposure.acquireInterval)
    }

    @Test func intervalSettlesAfterAcquireWindow() {
        let start = Date()
        #expect(
            FacePriorityExposure.interval(
                sinceAcquire: start, now: start.addingTimeInterval(2.5))
                == FacePriorityExposure.settleInterval)
        #expect(
            FacePriorityExposure.interval(
                sinceAcquire: start, now: start.addingTimeInterval(10))
                == FacePriorityExposure.settleInterval)
    }

    @Test func intervalIsFastBeforeAcquireStarts() {
        #expect(
            FacePriorityExposure.interval(sinceAcquire: nil, now: Date())
                == FacePriorityExposure.acquireInterval)
    }

    @Test func clampsToEvRange() {
        let transfer = MonitorTransfer.rec709
        let black = transfer.encodeLinear(0.18 / 64)
        let next = FacePriorityExposure.nextEV(
            current: EvComp(thirds: 8), encoded: black, transfer: transfer)
        #expect(next?.thirds == EvComp.maxThirds)
    }
}
