import Foundation

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
