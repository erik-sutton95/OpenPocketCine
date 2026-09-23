import Testing

@testable import OpenPocketViewCore

@Suite struct ExposureMeterReadingTests {
    @Test func cameraMeterStaysSeparateFromConfiguredCompensation() {
        for mode: UInt8 in [0x01, 0x04] {
            var value = [UInt8](repeating: 0, count: 44)
            value[6] = 0x10
            value[7] = mode
            value[15] = 0x0E
            var status = CameraStatus()
            #expect(
                CameraStatusDecoder.applySubscribePush(
                    SubscribePush.pack(name: "cam_expo_param", value: value), to: &status))
            #expect(status.evComp == .zero)
            #expect(status.meteredEv?.thirds == -2)
            let reading = ExposureMeterReading(cameraValue: status.meteredEv)
            #expect(reading.label == "−0.7")
            #expect(reading.stops == -2.0 / 3)
            #expect(reading.needleFraction == 7.0 / 18)
        }
    }

    @Test func meterUsesEveryReportedThirdStop() {
        for raw: UInt8 in 0x07...0x19 {
            var value = [UInt8](repeating: 0, count: 46)
            value[15] = raw
            let ev = ExpoParam.meteredEv(value)
            #expect(ev?.thirds == Int(raw) - 16)
            let reading = ExposureMeterReading(cameraValue: ev)
            #expect(reading.needleFraction == Double(Int(raw) - 7) / 18)
            #expect(reading.label == ev?.label)
        }
        #expect(ExposureMeterReading(cameraValue: .zero).label == "0.0")
    }

    @Test func shortAndInvalidReportsClearTheMeterWithoutCompensationFallback() {
        var status = CameraStatus()
        status.meteredEv = .zero
        for length in [8, 15, 16, 44, 46] {
            var value = [UInt8](repeating: 0xFF, count: length)
            value[6] = 0x13
            #expect(
                CameraStatusDecoder.applySubscribePush(
                    SubscribePush.pack(name: "cam_expo_param", value: value), to: &status))
            #expect(status.evComp?.thirds == 3)
            #expect(status.meteredEv == nil)
            let reading = ExposureMeterReading(cameraValue: status.meteredEv)
            #expect(reading.label == "—")
            #expect(reading.needleFraction == nil)
        }
        #expect(ExpoParam.meteredEv([]) == nil)
        #expect(CameraStatus().meteredEv == nil)
    }

    @Test func cameraMeterUsesTheExistingHudCadence() {
        let previous = CameraStatus()
        var next = previous
        next.meteredEv = EvComp(thirds: 2)
        #expect(!LiveChromeThrottle.shouldNotify(previous: previous, next: next, elapsed: 0.19))
        #expect(LiveChromeThrottle.shouldNotify(previous: previous, next: next, elapsed: 0.2))
    }
}
