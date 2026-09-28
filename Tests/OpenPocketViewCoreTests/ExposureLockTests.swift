import Testing

@testable import OpenPocketViewCore

@Suite struct ExposureLockTests {
    @Test func aeLockPinsAppliedAutoAndEndsOnAutoOrModeChange() {
        var value = [UInt8](repeating: 0, count: 46)
        value[7] = 0x01  // Auto.
        value[16] = 0x78
        value[17] = 0x05  // Applied ISO 1400.
        value[20] = 48
        value[21] = 0x80  // Applied 1/48.
        var status = CameraStatus()
        status.shootingMode = 3
        status.availableShutterDenoms = [25, 50, 100]
        _ = CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_expo_param", value: value), to: &status)

        let lock = AutoExposureLock.capture(status)
        #expect(lock == AutoExposureLock(isoIndex: .iso1600, shutterDenom: 50, shootingMode: 3))
        status.expoMode = .manual
        #expect(AutoExposureLock.capture(status) == nil)
        #expect(lock?.holds(status) == true)
        status.shootingMode = 4
        #expect(lock?.holds(status) == false)
        status.shootingMode = 3
        status.expoMode = .auto
        #expect(lock?.holds(status) == false)
    }

    @Test func awbLockUsesLiveAutoKelvinAndKeepsTint() {
        var status = CameraStatus()
        // Auto, `@5` 35 = 3500K; `@6` 04 is not Kelvin (Action 6 T06 46094). Tint +20.
        let auto: [UInt8] = [0, 0, 0x3F, 0, 0x00, 0x23, 0x04, 0x14, 0x00]
        _ = CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_image_effect", value: auto), to: &status)
        #expect(WhiteBalance.lockingAuto(status) == .custom(kelvin: 3_500, tint: 20))
        // Snaps to the Custom drum: nearest 100K, a tie keeps the lower value.
        #expect(WhiteBalance.snappedKelvin(4_900) == 4_900)
        #expect(WhiteBalance.snappedKelvin(4_950) == 4_900)
        #expect(WhiteBalance.snappedKelvin(4_951) == 5_000)
        #expect(WhiteBalance.snappedKelvin(1_500) == 2_000)

        var custom = auto
        custom[4] = 0x06
        _ = CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_image_effect", value: custom), to: &status)
        #expect(status.autoWhiteBalanceKelvin == -1)
        #expect(WhiteBalance.lockingAuto(status) == nil)

        // The lock holds while the body reports Custom at the locked Kelvin.
        let lock = AutoWhiteBalanceLock(kelvin: 3_500)
        custom[5] = 0x23
        custom[6] = 0x00
        _ = CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_image_effect", value: custom), to: &status)
        #expect(lock.holds(status))
        status.whiteBalance = .custom(kelvin: 3_600, tint: 20)
        #expect(!lock.holds(status))
        status.whiteBalance = .auto(tint: 20)
        #expect(!lock.holds(status))
        status.whiteBalance = nil
        #expect(lock.holds(status))
    }
}
