#if DEBUG
    import Foundation
    import OpenCineAppKit
    import OpenPocketViewCore
    import Sentry
    import UIKit

    /// Explicit development launch only. Uses isolated consent and no camera UI.
    enum ReliabilityReportingVerification {
        static var mode: String? {
            let value = ProcessInfo.processInfo.environment["OPV_RELIABILITY_VERIFY"]
            return ["incident", "gatedIncident", "crash", "hang", "resume"].contains(value ?? "")
                ? value : nil
        }

        static func prepareIfRequested() {
            guard mode != nil,
                let defaults = UserDefaults(suiteName: "opc.reliability.verification")
            else { return }
            AppDiagnostics.consent.defaults = defaults
            AppDiagnostics.consent.setOptedIn(true)
            AppDiagnostics.reporting.sdkCacheRoot = AppDiagnostics.reporting.sdkCacheRoot
                .appendingPathComponent("verification", isDirectory: true)
            if mode == "gatedIncident" {
                AppDiagnostics.gate.setCameraSessionActive(true)
            }
        }

        static func runIfRequested() {
            guard let mode else { return }
            let id =
                UUID(
                    uuidString:
                        ProcessInfo.processInfo.environment["OPV_RELIABILITY_VERIFY_ID"] ?? "")
                ?? UUID()
            poll(mode: mode, id: id.uuidString, remaining: 60, captured: false)
        }

        private static func poll(mode: String, id: String, remaining: Int, captured: Bool) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if mode == "gatedIncident", remaining == 30 {
                    AppDiagnostics.reporting.setCameraSessionActive(false)
                }
                let ready = SentrySDK.isEnabled
                var submitted = captured
                if ready, !captured {
                    if mode == "crash" {
                        writeStatus(id: id, phase: "crashing")
                        SentrySDK.crash()
                        return
                    }
                    if mode == "hang", remaining <= 55,
                        UIApplication.shared.applicationState == .active
                    {
                        writeStatus(id: id, phase: "hanging")
                        // Deliberate main-thread stall, confined to this explicit Debug probe.
                        Thread.sleep(forTimeInterval: 5)
                        submitted = true
                    }
                    if ["incident", "gatedIncident"].contains(mode),
                        let bundle = syntheticIncident(id: id)
                    {
                        AppDiagnostics.reporting.setFinalizedSpoolLoader { [bundle] }
                        submitted = true
                    }
                }
                AppDiagnostics.reporting.enqueueFinalizedFromSpool()
                writeStatus(id: id, phase: ready ? "capturing" : "starting")
                if remaining > 0 {
                    poll(mode: mode, id: id, remaining: remaining - 1, captured: submitted)
                }
            }
        }

        private static func writeStatus(id: String, phase: String) {
            let status: [String: Any] = [
                "id": id, "phase": phase, "sdkEnabled": SentrySDK.isEnabled,
                "uploadBlocked": AppDiagnostics.gate.shouldBlockUpload,
                "receipt": AppDiagnostics.reporting.receipt(for: id)?.state.rawValue ?? "none",
                "applicationActive": UIApplication.shared.applicationState == .active,
            ]
            guard
                let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                    .first,
                let data = try? JSONSerialization.data(withJSONObject: status, options: .sortedKeys)
            else { return }
            try? data.write(
                to: root.appendingPathComponent("reliability-verification.json"), options: .atomic)
        }

        static func syntheticIncident(id: String) -> FeedIncidentBundle? {
            var recorder = FeedIncidentRecorder(makeIncidentID: { id })
            _ = recorder.beginSession(
                FeedIncidentSessionContext(
                    sessionID: UUID().uuidString,
                    appVersion: Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    appBuild: AppDiagnostics.host.build,
                    sourceRevision: Bundle.main.object(forInfoDictionaryKey: "OPCSourceRevision")
                        as? String ?? "unknown",
                    osName: "iOS", osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                    hardwareClass: "verification", cameraFamily: "synthetic",
                    testSource: .verification,
                    buildIdentity: AppDiagnostics.origin.currentBuildIdentity()))
            let now = Date()
            func snapshot(_ time: Double, healthy: Bool) -> FeedIncidentSnapshot {
                FeedIncidentSnapshot(
                    monotonicNow: time, wallClock: now,
                    rates: FeedIncidentRates(
                        packetHz: 25, accessUnitHz: 25, decodeSubmitHz: 25,
                        decodeAcceptHz: 25,
                        decodedOutputHz: healthy ? 25 : 0, presentHz: healthy ? 25 : 0),
                    ages: FeedIncidentAges(
                        packetAge: 0.04, accessUnitAge: 0.04, decodeAcceptAge: 0.04,
                        decodedOutputAge: healthy ? 0.04 : 3, presentAge: healthy ? 0.04 : 3),
                    lifecycle: FeedIncidentLifecycle(connected: true, liveEstablished: true))
            }
            _ = recorder.recordSnapshot(snapshot(1, healthy: true))
            recorder.recordBreadcrumb(FeedIncidentBreadcrumb(monotonicAt: 2, kind: .settingsEnter))
            _ = recorder.recordSnapshot(snapshot(4, healthy: false))
            _ = recorder.recordSnapshot(snapshot(5, healthy: true))
            return recorder.recordSnapshot(snapshot(36, healthy: true))?.bundle
        }
    }
#endif
