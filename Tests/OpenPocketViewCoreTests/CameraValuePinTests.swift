import Testing

@testable import OpenPocketViewCore

struct CameraValuePinTests {
    @Test func unrelatedFramesAndOlderEchoesCannotConfirmARequest() {
        var pin: CameraValuePin<String>? = .init("SlowMo", now: 10)
        #expect(CameraValuePin.reconcile(&pin, reported: nil, now: 10.1) == "SlowMo")
        #expect(CameraValuePin.reconcile(&pin, reported: "Video", now: 10.2) == "SlowMo")
        #expect(CameraValuePin.reconcile(&pin, reported: "SlowMo", now: 10.3) == nil)
        #expect(pin == nil)
        #expect(CameraValuePin.reconcile(&pin, reported: "Photo", now: 10.4) == nil)
    }

    @Test func rejectedOrSupersededRequestsCannotHoldTheDisplayForever() {
        var pin: CameraValuePin<Int>? = .init(1, now: 0)
        let first = pin?.id
        pin = .init(2, now: 1)
        #expect(pin?.id != first)
        #expect(CameraValuePin.reconcile(&pin, reported: 1, now: 2) == 2)
        #expect(CameraValuePin.reconcile(&pin, reported: 1, now: 3) == nil)
        #expect(pin == nil)
    }
}
