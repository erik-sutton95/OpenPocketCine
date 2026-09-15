import Foundation
import OpenPocketViewCore

enum ReliabilityReportingConfiguration {
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    static func release(version: String? = nil, build: String? = nil) -> String {
        let version =
            version
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
        return "com.opencapture.openpocketcine@\(version)+\(build ?? self.build)"
    }

    static var environment: String {
        #if DEBUG
            return ReliabilityReportingVerification.mode == nil ? "development" : "verification"
        #else
            return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
                ? "testflight" : "production"
        #endif
    }
}

/// Current-run origin only. Cached incidents keep the values persisted with them.
enum FeedIncidentOrigin {
    static var overrideTestSourceForTests: FeedIncidentTestSource?
    static var overrideBuildIdentityForTests: String?

    static func resetForTests() {
        overrideTestSourceForTests = nil
        overrideBuildIdentityForTests = nil
    }

    static func currentTestSource(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        injectionActivated: Bool = FeedStressAutomation.injectionDidActivate
    ) -> FeedIncidentTestSource {
        if let overrideTestSourceForTests { return overrideTestSourceForTests }
        #if DEBUG
            return FeedIncidentTestSource.derive(
                verification: ReliabilityReportingVerification.mode != nil,
                injectionActivated: injectionActivated,
                automation: isAutomationLaunch(environment))
        #else
            _ = environment
            _ = injectionActivated
            return .manual
        #endif
    }

    /// Launch-env markers that exist in the target app. `XCTestCase` lives in the
    /// test runner; UI-test apps are tagged via these variables instead.
    static func isAutomationLaunch(_ environment: [String: String]) -> Bool {
        if environment["OPV_FEED_STRESS"] == "1" { return true }
        if environment["OPV_PHYSICAL_UI_REVIEW"] == "1" { return true }
        if let screen = environment["OPV_UI_REVIEW_SCREEN"], !screen.isEmpty { return true }
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        return false
    }

    static func currentBuildIdentity() -> String {
        if let overrideBuildIdentityForTests { return overrideBuildIdentityForTests }
        return FeedIncidentBuildIdentity.parse(
            Bundle.main.object(forInfoDictionaryKey: "OPCBuildIdentity") as? String)
    }
}
