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

    @Test func manualReportIncludesGeneratedUTCAndSubmissionHeader() {
        let text = DiagnosticReport.manualReport(
            environment: sampleEnv(), journal: [], exceptions: [])
        #expect(text.contains("Generated: "))
        #expect(text.contains("Prepared for explicit manual submission."))
        #expect(
            text.contains(
                "Environment below is a report-time snapshot, not necessarily the failure state."))
        #expect(text.contains("incidents: none captured"))
        #expect(!text.contains("Not uploaded"))
        let stamp = text.split(separator: "\n").first { $0.hasPrefix("Generated: ") }
        #expect(stamp?.hasSuffix("Z") == true)
        #expect(stamp?.contains("T") == true)
    }

    @Test func manualReportKeepsJournalAndIncidentsWhenMetricKitIsHuge() {
        let journal = [
            "info feed first-picture needsPoke=0",
            "warning feed stall gapMs=400",
        ]
        let incidents = """
            OpenPocketCine feed incidents (typed snapshots, no journal)
            count=1 schema=1
            id=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee kind=freshInputStaleOutput
            """
        let summary = #"{"sessionID":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","outcome":"recovered"}"#
        let metric = "{\"crashDiagnostics\":\"" + String(repeating: "M", count: 40_000) + "\"}"
        let text = DiagnosticReport.manualReport(
            environment: sampleEnv(),
            journal: journal,
            exceptions: ["error decoder vt-fail code=4"],
            extras: [
                ("incidents.txt", incidents),
                ("session-summary.json", summary),
                ("metrickit-diagnostic-1.json", metric),
            ])
        #expect(text.count <= DiagnosticReport.manualReportCharacterCap)
        #expect(text.contains("first-picture"))
        #expect(text.contains("stall gapMs=400"))
        #expect(text.contains("vt-fail"))
        #expect(text.contains("freshInputStaleOutput"))
        #expect(text.contains("session-summary.json"))
        #expect(!text.contains(String(repeating: "M", count: 1_000)))
        #expect(text.contains("[truncated:"))
        #expect(!text.contains("incidents: none captured"))
    }

    @Test func manualReportOmitsCollectorStacksAndKeepsNewestJournal() {
        var journal: [String] = []
        for index in 0..<80 {
            journal.append("info feed tick n=\(index)")
        }
        let exceptions = [
            "2026-09-14T00:00:00Z error diagnostics metrickit MetricKit diagnostic payload received stack=DiagnosticCenterC12currentStack",
            "2026-09-14T00:00:01Z error decoder vt-fail code=1",
        ]
        let text = DiagnosticReport.manualReport(
            environment: sampleEnv(), journal: journal, exceptions: exceptions)
        #expect(text.contains("vt-fail"))
        #expect(!text.contains("currentStack"))
        #expect(!text.contains("MetricKit diagnostic payload received"))
        #expect(text.contains("tick n=79"))
        #expect(text.contains("collector MetricKit stacks"))
    }

    @Test func manualReportOmitsWholeJSONExtraRatherThanSlicing() {
        let token = "UNIQUE_METRIC_TOKEN_SHOULD_NOT_APPEAR"
        let huge = "{" + String(repeating: "x", count: 40_000) + token + "}"
        let text = DiagnosticReport.manualReport(
            environment: sampleEnv(),
            journal: ["notice session live picture=1"],
            exceptions: [],
            extras: [
                ("incidents.txt", "count=1 kind=packet"),
                ("metrickit-diagnostic-9.json", huge),
            ])
        #expect(text.count <= DiagnosticReport.manualReportCharacterCap)
        #expect(text.contains("count=1 kind=packet"))
        #expect(text.contains("picture=1"))
        #expect(!text.contains(token))
        #expect(text.contains("omitted extra metrickit-diagnostic-9.json"))
    }

    @Test func manualReportStaysWithinCharacterCapWithHugeJournal() {
        let line = String(repeating: "a", count: 120)
        let journal = (0..<400).map { "info feed row \($0) \(line)" }
        let text = DiagnosticReport.manualReport(
            environment: sampleEnv(), journal: journal, exceptions: [])
        #expect(text.count <= DiagnosticReport.manualReportCharacterCap)
        #expect(text.contains("[truncated:"))
        #expect(text.contains("row 399"))
        #expect(!text.contains("row 0 \(line)"))
    }

    @Test func manualReportRetainsRealCollectorCallsiteAndOversizedNewestLine() {
        let text = DiagnosticReport.manualReport(
            environment: sampleEnv(),
            journal: ["notice prior", "error latest " + String(repeating: "x", count: 40_000)],
            exceptions: ["error decoder failed stack=DiagnosticCenterC12currentStack"])
        #expect(text.contains("error latest"))
        #expect(text.contains("decoder failed"))
        #expect(text.contains("newest line shortened"))
        #expect(text.count <= DiagnosticReport.manualReportCharacterCap)
    }

    @Test func manualReportCapMakesProgressWithOversizedEnvironmentAndOmissions() {
        let environment = DiagnosticEnvironment(
            appVersion: String(repeating: "v", count: 40_000), appBuild: "1", osName: "test",
            osVersion: "1", deviceModel: "test", cameraFamily: "none", cameraModel: "none",
            phase: "idle")
        let text = DiagnosticReport.manualReport(
            environment: environment, journal: [], exceptions: [],
            extras: [(name: "metrickit-large.json", body: String(repeating: "x", count: 40_000))])
        #expect(text.count <= DiagnosticReport.manualReportCharacterCap)
        #expect(text.contains("[truncated:"))
    }

    @Test func manualReportPrioritizesNewestFirstIncidentExports() {
        let text = DiagnosticReport.manualReport(
            environment: sampleEnv(), journal: ["latest activity"], exceptions: [],
            extras: [
                (
                    name: "incidents.txt",
                    body: "newest incident\n" + String(repeating: "old detail\n", count: 4_000)
                ),
                (name: "incident-new.json", body: "{\"id\":\"new\"}"),
                (name: "incident-old.json", body: "{\"id\":\"old\"}"),
            ])
        #expect(text.contains("newest incident"))
        #expect(text.contains("latest activity"))
        #expect(
            text.range(of: "incident-new.json")!.lowerBound
                < text.range(of: "incident-old.json")!.lowerBound)
        #expect(text.count <= DiagnosticReport.manualReportCharacterCap)
    }

    private func sampleEnv() -> DiagnosticEnvironment {
        DiagnosticEnvironment(
            appVersion: "0.1.0",
            appBuild: "1",
            osName: "iOS",
            osVersion: "26.6",
            deviceModel: "iPhone17,2",
            cameraFamily: "pocket",
            cameraModel: "Osmo Pocket 3",
            phase: "live")
    }
}
