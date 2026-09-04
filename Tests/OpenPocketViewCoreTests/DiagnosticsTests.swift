import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct DiagnosticsTests {
    @Test func redactsHomePathEmailMacAndPassword() {
        let home = "/" + "Users" + "/example"
        let raw =
            "crash \(home)/Library/foo email=tester@example.com mac=EC:9E:EA:11:22:33 password=hunter2"
        let out = PrivacyRedactor.redact(raw)
        #expect(!out.contains("example/Library"))
        #expect(out.contains("/" + "Users" + "/<redacted>"))
        #expect(!out.contains("tester@example.com"))
        #expect(out.contains("<email>"))
        #expect(!out.contains("EC:9E:EA:11:22:33"))
        #expect(out.contains("<mac>"))
        #expect(!out.contains("hunter2"))
        #expect(out.contains("password=<redacted>"))
    }

    @Test func keepsCameraSSIDAndSoftAPAddress() {
        let raw = "ssid=OsmoPocket3-A1B2 path=192.168.2.15 seq=42054"
        let out = PrivacyRedactor.redact(raw)
        #expect(out.contains("OsmoPocket3-A1B2"))
        #expect(out.contains("192.168.2.15"))
        #expect(out.contains("seq=42054"))
    }

    @Test func redactsHomeSSIDAndPublicIP() {
        let raw = "ssid=CafeWiFi join=8.8.8.8"
        let out = PrivacyRedactor.redact(raw)
        #expect(!out.contains("CafeWiFi"))
        #expect(out.contains("ssid=<redacted>"))
        #expect(!out.contains("8.8.8.8"))
        #expect(out.contains("<ip>"))
    }

    @Test func cameraNetworkDetection() {
        #expect(PrivacyRedactor.isCameraNetwork("OsmoPocket3-AAAA"))
        #expect(PrivacyRedactor.isCameraNetwork("Xtra-Muse-1"))
        #expect(!PrivacyRedactor.isCameraNetwork("ErikHome"))
    }

    @Test func compactSummaryOmitsPersonFields() {
        let env = DiagnosticEnvironment(
            appVersion: "0.1.0",
            appBuild: "59",
            osName: "iOS",
            osVersion: "26.6",
            deviceModel: "iPhone17,2",
            cameraFamily: "pocket",
            cameraModel: "Osmo Pocket 3",
            phase: "live")
        let text = DiagnosticReport.compactSummary(
            environment: env,
            recent: ["info session first-picture needsPoke=1"])
        #expect(text.contains("iPhone17,2"))
        #expect(text.contains("Osmo Pocket 3"))
        #expect(text.contains("vpn=off"))
        #expect(!text.contains("Erik"))
        #expect(text.count <= PrivacyRedactor.compactCharacterCap)
    }

    @Test func compactSummaryFlagsActiveVPN() {
        let env = DiagnosticEnvironment(
            appVersion: "0.1.0",
            appBuild: "59",
            osName: "Android",
            osVersion: "16",
            deviceModel: "CPH2583",
            cameraFamily: "pocket",
            cameraModel: "Osmo Pocket 3",
            phase: "live",
            vpnActive: true)
        let text = DiagnosticReport.compactSummary(environment: env, recent: [])
        #expect(text.contains("vpn=on"))
        let full = DiagnosticReport.fullReport(
            environment: env, journal: [], exceptions: [])
        #expect(full.contains("vpn: on"))
    }

    @Test func journalLineIsStable() {
        let event = DiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 0),
            level: .error,
            category: .feed,
            code: "first-picture",
            message: "no HEVC",
            fields: ["needsPoke": "1", "boot": "4K · 25p"])
        #expect(event.journalLine.contains("error feed first-picture no HEVC"))
        #expect(event.journalLine.contains("boot=4K · 25p"))
        #expect(event.journalLine.contains("needsPoke=1"))
    }

    @Test func debugDoesNotPersist() {
        #expect(!DiagnosticLevel.debug.persistsToJournal)
        #expect(DiagnosticLevel.info.persistsToJournal)
        #expect(DiagnosticLevel.fault.persistsToJournal)
    }
}
