import Foundation
import OpenCineAppKit
import OpenPocketViewCore
import Sentry
import XCTest

@testable import OpenPocketCine

final class ReliabilityReportingTests: XCTestCase {
    private var suite: UserDefaults!
    private var cacheRoot: URL!

    override func setUp() {
        super.setUp()
        suite = UserDefaults(suiteName: "opc.reliability.test.\(UUID().uuidString)")
        AppDiagnostics.consent.defaults = suite
        AppDiagnostics.consent.resetForTests()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-rel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        AppDiagnostics.reporting.sdkCacheRoot = cacheRoot
        AppDiagnostics.reporting.setCaptureHandlerForTests(nil)
        AppDiagnostics.gate.resetForTests()
        AppDiagnostics.reporting.dsnHost = "o0.ingest.sentry.io"
        AppDiagnostics.forwarder.session = URLSession(
            configuration: {
                let config = URLSessionConfiguration.ephemeral
                config.waitsForConnectivity = false
                return config
            }())
    }

    override func tearDown() {
        AppDiagnostics.gate.resetForTests()
        AppDiagnostics.consent.resetForTests()
        AppDiagnostics.consent.defaults = .standard
        AppDiagnostics.reporting.setCaptureHandlerForTests(nil)
        AppDiagnostics.origin.resetForTests()
        try? FileManager.default.removeItem(at: cacheRoot)
        super.tearDown()
    }

    func testColdStartOnCameraNetworkStillInstallsCrashCapture() {
        AppDiagnostics.consent.setOptedIn(true)
        AppDiagnostics.gate.setCameraIPv4PathReadyForTests(true)
        let previousDSN = ProcessInfo.processInfo.environment["SENTRY_DSN"]
        setenv("SENTRY_DSN", "https://publickey@o0.ingest.sentry.io/0", 1)
        defer {
            if let previousDSN {
                setenv("SENTRY_DSN", previousDSN, 1)
            } else {
                unsetenv("SENTRY_DSN")
            }
            AppDiagnostics.reporting.setConsent(false)
        }
        AppDiagnostics.reporting.install()
        let installed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in SentrySDK.isEnabled }, object: nil)
        wait(for: [installed], timeout: 10)
        XCTAssertTrue(AppDiagnostics.gate.shouldBlockUpload)
    }

    func testScrubDoesNotStampCurrentOriginOntoLegacyOrFatalEvents() {
        AppDiagnostics.origin.overrideTestSourceForTests = .verification
        AppDiagnostics.origin.overrideBuildIdentityForTests = "ios-current-run-identity-value"
        let event = Event(level: .fatal)
        event.tags = ["failingStage": "decodedOutput"]
        _ = AppDiagnostics.reporting.privacy.scrub(event)
        XCTAssertNil(event.tags?["testSource"])
        XCTAssertNil(event.tags?["buildIdentity"])
        event.tags = ["testSource": "manual", "buildIdentity": "ios-priorrun0123456789abcdefab"]
        _ = AppDiagnostics.reporting.privacy.scrub(event)
        XCTAssertEqual(event.tags?["testSource"], "manual")
        XCTAssertEqual(event.tags?["buildIdentity"], "ios-priorrun0123456789abcdefab")
    }

    func testUnknownBreadcrumbTokensAreRejected() {
        let event = Event(level: .error)
        let scene = Breadcrumb(level: .info, category: "feed")
        scene.message = "sceneActivity"
        scene.data = ["sceneState": "Erik", "assistState": "private_project"]
        let assist = Breadcrumb(level: .info, category: "feed")
        assist.message = "assistChange"
        assist.data = ["assistState": "private_project"]
        event.breadcrumbs = [scene, assist]
        _ = AppDiagnostics.reporting.privacy.scrub(event)
        XCTAssertEqual(event.breadcrumbs?.count, 2)
        XCTAssertNil(event.breadcrumbs?[0].data?["sceneState"])
        XCTAssertNil(event.breadcrumbs?[1].data?["assistState"])
    }

    func testOnlyTypedFeedBreadcrumbsSurviveScrubbing() {
        let event = Event(level: .error)
        let typed = Breadcrumb(level: .info, category: "feed")
        typed.message = "settingsEnter"
        typed.data = ["password": "must-not-leave-phone"]
        let scene = Breadcrumb(level: .info, category: "feed")
        scene.message = "sceneActivity"
        scene.data = ["sceneState": "inactive", "password": "must-not-leave-phone"]
        let repair = Breadcrumb(level: .info, category: "feed")
        repair.message = "repair"
        repair.data = ["repairAction": "decoder", "repairPhase": "requested"]
        let arbitrary = Breadcrumb(level: .info, category: "feed")
        arbitrary.message = "arbitrary operator text"
        event.breadcrumbs = [
            typed, scene, repair, arbitrary, Breadcrumb(level: .info, category: "http"),
        ]
        _ = AppDiagnostics.reporting.privacy.scrub(event)
        XCTAssertEqual(event.breadcrumbs?.count, 3)
        XCTAssertEqual(event.breadcrumbs?[0].message, "settingsEnter")
        XCTAssertNil(event.breadcrumbs?[0].data)
        XCTAssertEqual(event.breadcrumbs?[1].message, "sceneActivity")
        XCTAssertEqual(event.breadcrumbs?[1].data?["sceneState"] as? String, "inactive")
        XCTAssertNil(event.breadcrumbs?[1].data?["password"])
        XCTAssertEqual(event.breadcrumbs?[2].message, "repair")
        XCTAssertEqual(event.breadcrumbs?[2].data?["repairAction"] as? String, "decoder")
    }

    func testSDKCapturePreservesOriginalBuildAfterUpgrade() {
        AppDiagnostics.consent.setOptedIn(true)
        let options = SentryReliabilitySink.makeOptions(
            dsn: "https://publickey@o0.ingest.sentry.io/0",
            urlSession: AppReliabilityURLProtocol.makeSDKSession())
        let prepared = expectation(description: "SDK prepared original provenance")
        options.beforeSend = { event in
            XCTAssertEqual(event.releaseName, "com.opencapture.openpocketcine@0.1.0+107")
            XCTAssertEqual(event.dist, "107")
            prepared.fulfill()
            return nil
        }
        SentrySDK.start(options: options)
        defer { SentrySDK.close() }
        let event = Event(level: .error)
        event.releaseName = "com.opencapture.openpocketcine@0.1.0+107"
        event.dist = "107"
        SentrySDK.capture(event: event)
        wait(for: [prepared], timeout: 10)
    }

    func testQueuedReplayOriginSurvivesActualSDKScopeMerge() throws {
        AppDiagnostics.consent.setOptedIn(true)
        var bundle = try stallBundle(id: UUID().uuidString)
        bundle.header.outcome = .recovered
        bundle.header.kind = .transportStall
        bundle.header.testSource = .faultInjection
        bundle.header.buildIdentity = "ios-queuedorigin0123456789abcdef"
        AppDiagnostics.origin.overrideTestSourceForTests = .verification
        AppDiagnostics.origin.overrideBuildIdentityForTests = "ios-current-run-identity-value"
        let options = SentryReliabilitySink.makeOptions(
            dsn: "https://publickey@o0.ingest.sentry.io/0",
            urlSession: AppReliabilityURLProtocol.makeSDKSession())
        let prepared = expectation(description: "SDK beforeSend original origin")
        options.beforeSend = { event in
            let scrubbed = AppDiagnostics.reporting.privacy.scrub(event)
            guard scrubbed.fingerprint?.first == "feed-incident" else { return nil }
            XCTAssertEqual(scrubbed.tags?["testSource"], "faultInjection")
            XCTAssertEqual(scrubbed.tags?["buildIdentity"], "ios-queuedorigin0123456789abcdef")
            XCTAssertTrue(scrubbed.fingerprint?.contains("kind:transportStall") == true)
            XCTAssertNotEqual(scrubbed.tags?["testSource"], "verification")
            XCTAssertNotEqual(scrubbed.tags?["buildIdentity"], "ios-current-run-identity-value")
            prepared.fulfill()
            return nil
        }
        SentrySDK.start(options: options)
        defer { SentrySDK.close() }
        SentrySDK.configureScope { scope in
            scope.setTag(value: "verification", key: "testSource")
            scope.setTag(value: "ios-current-run-identity-value", key: "buildIdentity")
        }
        let constructed = expectation(description: "constructed event")
        AppDiagnostics.reporting.setCaptureHandlerForTests { typed, _ in
            let event = SentryReliabilitySink.event(typed)
            XCTAssertEqual(event.eventId.sentryIdString, typed.eventID)
            XCTAssertNil(event.user)
            XCTAssertEqual(event.breadcrumbs?.count, 0)
            XCTAssertEqual(event.tags?["testSource"], "faultInjection")
            XCTAssertTrue(event.fingerprint?.contains("kind:transportStall") == true)
            SentrySDK.capture(event: event) { scope in
                SentryReliabilitySink.applyOriginalTags(event.tags, to: scope)
            }
            constructed.fulfill()
        }
        AppDiagnostics.reporting.enqueueFinalized(bundle)
        wait(for: [constructed, prepared], timeout: 10)
    }

    func testScrubRemovesUserRequestBreadcrumbsAndPaths() {
        let event = Event(level: .error)
        let user = User()
        user.email = "tester@example.com"
        user.username = "example-user"
        event.user = user
        event.request = SentryRequest()
        event.breadcrumbs = [Breadcrumb(level: .info, category: "http")]
        event.tags = [
            "failingStage": "decodedOutput", "email": "tester@example.com",
            "testSource": "automation",
            "buildIdentity": "ios-0123456789abcdef0123456789abcd",
        ]
        event.extra = ["password": "hunter2", "failingStage": "decodedOutput"]
        event.context = [
            "device": [
                "name": "Example Phone", "model": "iPhone17,2", "free_memory": 1_024,
                "memory_size": 8_192, "thermal_state": "nominal",
            ],
            "app": ["app_memory": 512, "in_foreground": true, "device_app_hash": "x"],
            "feed": ["failingStage": "decodedOutput", "serial": "ABC"],
        ]
        event.exceptions = [
            Exception(value: "/" + "Users/example/Library/crash", type: "NSError")
        ]
        _ = AppDiagnostics.reporting.privacy.scrub(event)
        XCTAssertNil(event.user)
        XCTAssertNil(event.request)
        XCTAssertEqual(event.breadcrumbs?.count ?? 0, 0)
        XCTAssertNil(event.tags?["email"])
        XCTAssertEqual(event.tags?["failingStage"], "decodedOutput")
        XCTAssertEqual(event.tags?["testSource"], "automation")
        XCTAssertEqual(event.tags?["buildIdentity"], "ios-0123456789abcdef0123456789abcd")
        XCTAssertNil(event.extra?["password"])
        XCTAssertEqual(event.extra?["failingStage"] as? String, "decodedOutput")
        XCTAssertNil(event.context?["device"]?["name"])
        XCTAssertEqual(event.context?["device"]?["model"] as? String, "iPhone17,2")
        XCTAssertEqual(event.context?["device"]?["free_memory"] as? Int, 1_024)
        XCTAssertEqual(event.context?["device"]?["memory_size"] as? Int, 8_192)
        XCTAssertEqual(event.context?["device"]?["thermal_state"] as? String, "nominal")
        XCTAssertEqual(event.context?["app"]?["app_memory"] as? Int, 512)
        XCTAssertEqual(event.context?["app"]?["in_foreground"] as? Bool, true)
        XCTAssertNil(event.context?["app"]?["device_app_hash"])
        XCTAssertNil(event.context?["feed"]?["serial"])
        XCTAssertFalse(event.exceptions?.first?.value?.contains("example/Library") ?? true)
    }

    func testOptionsPrivacyFlags() {
        let session = AppReliabilityURLProtocol.makeSDKSession()
        let options = SentryReliabilitySink.makeOptions(
            dsn: "https://publickey@o0.ingest.sentry.io/0", urlSession: session)
        XCTAssertFalse(options.sendDefaultPii)
        XCTAssertFalse(options.enableSwizzling)
        XCTAssertFalse(options.enableNetworkBreadcrumbs)
        XCTAssertFalse(options.enableAutoSessionTracking)
        XCTAssertFalse(options.enableAutoPerformanceTracing)
        XCTAssertEqual(options.tracesSampleRate?.intValue ?? 0, 0)
        XCTAssertFalse(options.attachScreenshot)
        XCTAssertFalse(options.attachViewHierarchy)
        XCTAssertFalse(options.enableMetricKit)
        XCTAssertTrue(options.enableCrashHandler)
        XCTAssertTrue(options.enableAppHangTracking)
        // Tests run a development build: reinstalls must not read as watchdog kills.
        XCTAssertEqual(AppDiagnostics.host.environment, "development")
        XCTAssertFalse(options.enableWatchdogTerminationTracking)
        XCTAssertEqual(options.maxCacheItems, 30)
        XCTAssertEqual(options.maxAttachmentSize, 256 * 1_024)
        XCTAssertEqual(options.sessionReplay.sessionSampleRate, 0)
        XCTAssertEqual(options.sessionReplay.onErrorSampleRate, 0)
    }

    private func stallBundle(id: String) throws -> FeedIncidentBundle {
        var recorder = FeedIncidentRecorder(makeIncidentID: { id })
        _ = recorder.beginSession(
            FeedIncidentSessionContext(
                sessionID: "session-1",
                appVersion: "0.1.0",
                appBuild: "107",
                sourceRevision: "test",
                osName: "iOS",
                osVersion: "17.0",
                hardwareClass: "iPhone17,2",
                cameraFamily: "pocket"))
        _ = recorder.recordSnapshot(
            FeedIncidentSnapshot(
                monotonicNow: 1,
                wallClock: Date(),
                rates: FeedIncidentRates(packetHz: 25, decodedOutputHz: 25, presentHz: 25),
                ages: FeedIncidentAges(
                    packetAge: 0.04, decodedOutputAge: 0.04, presentAge: 0.04),
                lifecycle: FeedIncidentLifecycle(
                    connected: true, liveEstablished: true)))
        let job = recorder.recordSnapshot(
            FeedIncidentSnapshot(
                monotonicNow: 4,
                wallClock: Date(),
                rates: FeedIncidentRates(packetHz: 25, decodeSubmitHz: 25, decodedOutputHz: 0),
                ages: FeedIncidentAges(
                    packetAge: 0.04, decodedOutputAge: 3, presentAge: 3),
                lifecycle: FeedIncidentLifecycle(
                    connected: true, liveEstablished: true)))
        return try XCTUnwrap(job?.bundle)
    }
}
