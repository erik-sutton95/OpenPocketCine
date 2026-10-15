import MonitorPresentation
import OpenCineAppUITesting
import XCTest

/// The bundle's principal class (`NSPrincipalClass` in project.yml), created before any test runs.
/// It declares what the review body lays out: `OsmoMonitorPresentation.capabilities` for the
/// Osmo Pocket 4 Pro the review stages (the Pocket gimbal with its pose, zoom and focus, no iris,
/// plus the app's audio, clip delete, clip star, internet hop and timecode). A UI test bundle
/// cannot link the app, so the value is declared here and the scenarios derive from it.
final class ConformanceApp: NSObject {
    override init() {
        ConformanceProfile.current = ConformanceProfile(
            app: "OpenPocketCine",
            capabilities: MonitorCapabilities(
                gimbal: true, zoom: true, focus: true, iris: false, audio: true, headTracking: true,
                clipDelete: true, clipStar: true, requiresInternetHop: true, timecode: true))
        super.init()
    }
}

// The conformance scenarios every app runs (OpenCine docs/conformance/SCENARIOS.md).
final class GalleryRoundTrip: OpenCineAppUITesting.GalleryRoundTrip {}
final class ShareRoundTrip: OpenCineAppUITesting.ShareRoundTrip {}
final class ConfirmationCancel: OpenCineAppUITesting.ConfirmationCancel {}
final class ChromeEditReturn: OpenCineAppUITesting.ChromeEditReturn {}
final class AccessibilityTraversal: OpenCineAppUITesting.AccessibilityTraversal {}
final class ConformanceCoverageTests: OpenCineAppUITesting.ConformanceCoverageTests {}
