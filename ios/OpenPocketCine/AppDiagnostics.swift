import Foundation
import OpenCineAppKit
import OpenPocketViewCore
import UIKit

#if DEBUG
    import Sentry
#endif

/// The app's diagnostics: OpenCine's reporting runtime with this app's names, destination,
/// camera network and Sentry.
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
        redact: { PrivacyRedactor.redact($0) })
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
        sink: SentryReliabilitySink())
    /// The SDK transport's forwarding session over this runtime (`AppReliabilityURLProtocol`).
    static let forwarder = ReliabilityReportingForwarder(reporting: reporting)
    #if DEBUG
        static let verification = ReliabilityReportingVerification(
            reporting: reporting, sdkEnabled: { SentrySDK.isEnabled }, crash: { SentrySDK.crash() },
            isActive: { UIApplication.shared.applicationState == .active })
    #endif
    static let incidents = FeedIncidentRuntime(
        reporting: reporting,
        directory: DiagnosticCenter.diagnosticsDirectory?
            .appendingPathComponent("incidents", isDirectory: true))
    @MainActor static let problemReporting = ProblemReporting(
        host: host, gate: gate, dsnProvider: dsn.configured,
        isForeground: { UIApplication.shared.applicationState == .active })

    private static var environment: String {
        #if DEBUG
            return ReliabilityReportingVerification.mode == nil ? "development" : "verification"
        #else
            return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
                ? "testflight" : "production"
        #endif
    }
}

/// The Sentry SDK's URL protocol over this app's reporting runtime.
final class AppReliabilityURLProtocol: ReliabilityReportingURLProtocol, @unchecked Sendable {
    override class var forwarder: ReliabilityReportingForwarder { AppDiagnostics.forwarder }
}
