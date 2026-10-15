import Foundation
import OpenCineAppKit
import OpenCineSentryApple
import OpenPocketViewCore
import UIKit

/// The app's diagnostics: OpenCine's reporting runtime with this app's names, destination,
/// camera network and OpenCine's Sentry adapter.
enum AppDiagnostics {
    static let host = DiagnosticsHost(
        product: "OpenPocketCine", listingName: "OpenPocketCine",
        releasePackage: "com.opencapture.openpocketcine",
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown",
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
        environment: environment,
        sourceRevision: Bundle.main.object(forInfoDictionaryKey: "OPCSourceRevision") as? String
            ?? "unknown",
        supportEmail: "support@openpocketcine.app",
        redact: { DJICameraNetwork.redact($0) })
    static let consent = ReliabilityReportingConsent()
    static let dsn = ReliabilityReportingDSN {
        [
            Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
            Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String,
            ProcessInfo.processInfo.environment["SENTRY_DSN"],
        ]
    }
    /// The camera network this app's cameras serve.
    static let gate = ReliabilityReportingGate(cameraIPv4Prefix: "192.168.2.")
    static let origin: FeedIncidentOrigin = {
        #if DEBUG
            let verification = ReliabilityReportingVerification.mode != nil
            let derives = true
        #else
            let verification = false
            let derives = false
        #endif
        return FeedIncidentOrigin(
            derivesTestSource: derives, verification: verification,
            buildIdentity: Bundle.main.object(forInfoDictionaryKey: "OPCBuildIdentity") as? String,
            injectionActivated: { FeedStressAutomation.injectionDidActivate })
    }()
    static let reporting = ReliabilityReporting(
        host: host, consent: consent, dsn: dsn, gate: gate, origin: origin,
        sink: SentryReliabilitySink(
            host: host, consent: consent, urlProtocol: AppReliabilityURLProtocol.self))
    /// The SDK transport's forwarding session over this runtime (`AppReliabilityURLProtocol`).
    static let forwarder = ReliabilityReportingForwarder(reporting: reporting)
    #if DEBUG
        static let verification = ReliabilityReportingVerification(
            sentry: reporting, isActive: { UIApplication.shared.applicationState == .active })
    #endif
    static let incidents = FeedIncidentRuntime(
        reporting: reporting,
        directory: DiagnosticCenter.diagnosticsDirectory?
            .appendingPathComponent("incidents", isDirectory: true))
    @MainActor static let problemReporting = ProblemReporting(
        host: host, gate: gate, dsnProvider: dsn.configured,
        isForeground: { UIApplication.shared.applicationState == .active })

    /// Only store builds report `production`; Xcode and ad hoc release installs are `local`.
    private static var environment: String {
        #if DEBUG
            ReliabilityEnvironment.apple(
                debug: true, verification: ReliabilityReportingVerification.mode != nil
            ).rawValue
        #else
            ReliabilityEnvironment.apple(debug: false, verification: false).rawValue
        #endif
    }
}

/// The Sentry SDK's URL protocol over this app's reporting runtime.
final class AppReliabilityURLProtocol: ReliabilityReportingURLProtocol, @unchecked Sendable {
    override class var forwarder: ReliabilityReportingForwarder { AppDiagnostics.forwarder }
}
