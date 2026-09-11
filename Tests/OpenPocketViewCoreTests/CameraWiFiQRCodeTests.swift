import Testing

@testable import OpenPocketViewCore

struct CameraWiFiQRCodeTests {
    @Test func encodesWiFiJoinPayload() {
        #expect(
            CameraWiFiQRCode.payload(ssid: "Test Camera", password: "example-only")
                == "WIFI:T:WPA;S:Test Camera;P:example-only;;")
    }

    @Test func escapesFieldSeparatorsAndBackslashes() {
        #expect(
            CameraWiFiQRCode.payload(ssid: #"test;,:"\"#, password: #"example;\"#)
                == #"WIFI:T:WPA;S:test\;\,\:\"\\;P:example\;\\;;"#)
    }

    @Test func missingCredentialsCannotProduceAJoinCode() {
        #expect(CameraWiFiQRCode.payload(ssid: "", password: "example-only") == nil)
        #expect(CameraWiFiQRCode.payload(ssid: "Test Camera", password: "") == nil)
    }
}
