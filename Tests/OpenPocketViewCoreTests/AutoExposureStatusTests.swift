import Testing

@testable import OpenPocketViewCore

@Suite struct AutoExposureStatusTests {
    @Test func autoShutterTracksAppliedValueWhileManualSettingStaysFixed() {
        var status = CameraStatus()
        for (shutter, iso) in [(25, 800), (200, 100)] {
            let previous = status
            var value = [UInt8](repeating: 0, count: 46)
            value[2] = 0x40
            value[3] = 0x9F  // Remembered manual shutter: 1/8000.
            value[6] = 0x10
            value[7] = 0x01  // Auto exposure.
            value[16] = UInt8(iso & 0xFF)
            value[17] = UInt8(iso >> 8)
            value[20] = UInt8(shutter)
            value[21] = 0x80  // Applied reciprocal shutter.
            #expect(
                CameraStatusDecoder.applySubscribePush(
                    SubscribePush.pack(name: "cam_expo_param", value: value), to: &status))
            #expect(status.expoMode == .auto)
            #expect(status.shutterDenom == shutter)
            #expect(status.iso == iso)
            #expect(status.evComp == .zero)
            #expect(
                LiveChromeThrottle.shouldNotify(
                    previous: previous, next: status,
                    elapsed: LiveChromeThrottle.statusInterval))
        }
    }

    @Test func manualShutterStillUsesConfiguredValueWhileAppliedValueSettles() {
        var value = [UInt8](repeating: 0, count: 46)
        value[2] = 0x32
        value[3] = 0x80  // Configured 1/50, still applied 1/200.
        value[7] = 0x04
        value[20] = 0xC8
        value[21] = 0x80
        var status = CameraStatus()
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "cam_expo_param", value: value), to: &status))
        #expect(status.expoMode == .manual)
        #expect(status.shutterDenom == 50)
    }

    @Test func unsupportedAutoShutterNeverKeepsAnOldReadout() {
        var value = [UInt8](repeating: 0, count: 46)
        value[2] = 0x40
        value[3] = 0x9F
        value[7] = 0x01
        let invalidTriplets: [[UInt8]] = [
            [0, 0, 0], [0, 0x80, 0], [2, 0, 0],  // Empty, zero, seconds.
            [12, 0x80, 5], [0xFF, 0xFF, 0],  // Fractional reciprocal, out of range.
        ]
        var invalidValues = (8..<23).map { Array(value.prefix($0)) }
        invalidValues += invalidTriplets.map { triplet in
            var payload = value
            payload.replaceSubrange(20...22, with: triplet)
            return payload
        }
        for payload in invalidValues {
            var status = CameraStatus()
            status.shutterDenom = 200
            #expect(
                CameraStatusDecoder.applySubscribePush(
                    SubscribePush.pack(name: "cam_expo_param", value: payload), to: &status))
            #expect(status.shutterDenom == -1)
        }
    }

    @Test func expoParamDoesNotInventWhiteBalance() {
        // WB is `cam_image_effect` `@4–8`, not expo `@41`. `@6` is EV (`0x02/0x2E`). ISO is `@16`, not `@13`.
        var expo = [UInt8](repeating: 0, count: 46)
        expo[13] = 0xE7
        expo[14] = 0x03  // 999 sitting at the old wrong offset
        expo[16] = 0xC8
        expo[17] = 0x00  // ISO 200
        expo[6] = 0x0F
        expo[7] = 0x01
        expo[41] = 0x02
        var s = CameraStatus()
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "cam_expo_param", value: expo), to: &s))
        #expect(s.iso == 200)
        #expect(s.expoMode == .auto)  // @7 == 0x01 is exposure auto, not WB
        #expect(s.evComp == EvComp(thirds: -1))  // @6 == 0x0F
        #expect(s.whiteBalanceKelvin == -1)
        #expect(s.whiteBalance == nil)
        #expect(s.irisHundredths == nil)
    }
}
