import Foundation
import OpenPocketViewCore
import Sentry
import XCTest

@testable import OpenPocketCine

final class ReliabilityReportingTests: XCTestCase {
    private var suite: UserDefaults!
    private var cacheRoot: URL!

    private func waitForReceipt(_ id: String, state: ReliabilityReportingReceiptState) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                ReliabilityReporting.receipt(for: id)?.state == state
            }, object: nil)
        wait(for: [ready], timeout: 2)
    }

    override func setUp() {
        super.setUp()
        suite = UserDefaults(suiteName: "opc.reliability.test.\(UUID().uuidString)")
        ReliabilityReportingConsent.defaults = suite
        ReliabilityReportingConsent.resetForTests()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-rel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        ReliabilityReporting.sdkCacheRoot = cacheRoot
        ReliabilityReporting.setCaptureHandlerForTests(nil)
        ReliabilityReportingURLProtocol.gate = ReliabilityReportingGate.shared
        ReliabilityReportingGate.shared.resetForTests()
        ReliabilityReportingURLProtocol.dsnHost = "o0.ingest.sentry.io"
        ReliabilityReportingURLProtocol.onEnvelopeAccepted = nil
        ReliabilityReportingURLProtocol.forwardingSession = URLSession(
            configuration: {
                let config = URLSessionConfiguration.ephemeral
                config.waitsForConnectivity = false
                return config
            }())
    }

    override func tearDown() {
        ReliabilityReportingGate.shared.resetForTests()
        ReliabilityReportingConsent.resetForTests()
        ReliabilityReportingConsent.defaults = .standard
        ReliabilityReporting.setCaptureHandlerForTests(nil)
        FeedIncidentOrigin.resetForTests()
        try? FileManager.default.removeItem(at: cacheRoot)
        super.tearDown()
    }

    func testConsentDefaultsOffAndRevokePurgesOnlySDKOwnedSpool() {
        XCTAssertFalse(ReliabilityReportingConsent.isOptedIn)
        XCTAssertFalse(ReliabilityReporting.isOptedIn)
        ReliabilityReportingConsent.setOptedIn(true)
        XCTAssertTrue(ReliabilityReporting.isOptedIn)
        let localDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-local-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        let local = localDir.appendingPathComponent("incident-keep.json")
        try? Data("keep".utf8).write(to: local)
        defer { try? FileManager.default.removeItem(at: localDir) }
        ReliabilityReportingReceipts.store(
            ReliabilityReportingReceipt(
                incidentID: "inc-1", eventID: "abc", state: .queued, updatedAt: Date()),
            root: cacheRoot)
        XCTAssertNotNil(ReliabilityReportingReceipts.load(incidentID: "inc-1", root: cacheRoot))
        ReliabilityReporting.setConsent(false)
        XCTAssertFalse(ReliabilityReporting.isOptedIn)
        let purged = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                ReliabilityReportingReceipts.load(incidentID: "inc-1", root: cacheRoot) == nil
            }, object: nil)
        wait(for: [purged], timeout: 2)
        XCTAssertNil(ReliabilityReportingReceipts.load(incidentID: "inc-1", root: cacheRoot))
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.path))
    }

    func testDSNRequiresHTTPSSentryShape() {
        XCTAssertNil(ReliabilityReportingDSN.validated(""))
        XCTAssertNil(ReliabilityReportingDSN.validated("http://key@host/1"))
        XCTAssertNil(ReliabilityReportingDSN.validated("https://ingest.sentry.io/1"))
        XCTAssertNil(ReliabilityReportingDSN.validated("https://key:secret@ingest.sentry.io/1"))
        XCTAssertNil(
            ReliabilityReportingDSN.validated("https://key@ingest.sentry.io/1?token=value"))
        XCTAssertNil(
            ReliabilityReportingDSN.validated("https://key@ingest.sentry.io/not-a-project"))
        XCTAssertNotNil(
            ReliabilityReportingDSN.validated("https://publickey@o0.ingest.sentry.io/0"))
    }

    func testColdStartOnCameraNetworkStillInstallsCrashCapture() {
        ReliabilityReportingConsent.setOptedIn(true)
        ReliabilityReportingGate.shared.setCameraIPv4PathReadyForTests(true)
        let previousDSN = ProcessInfo.processInfo.environment["SENTRY_DSN"]
        setenv("SENTRY_DSN", "https://publickey@o0.ingest.sentry.io/0", 1)
        defer {
            if let previousDSN {
                setenv("SENTRY_DSN", previousDSN, 1)
            } else {
                unsetenv("SENTRY_DSN")
            }
            ReliabilityReporting.setConsent(false)
        }
        ReliabilityReporting.install()
        let installed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in SentrySDK.isEnabled }, object: nil)
        wait(for: [installed], timeout: 3)
        XCTAssertTrue(ReliabilityReportingGate.shared.shouldBlockUpload)
    }

    func testCameraGateBlocksEvenWithInternetAndCancelsPending() {
        let fake = FakeTask()
        ReliabilityReportingGate.shared.setValidInternetForTests(true)
        ReliabilityReportingGate.shared.setCameraIPv4PathReadyForTests(false)
        ReliabilityReportingGate.shared.setCameraSessionActive(false)
        ReliabilityReportingGate.shared.register(fake)
        XCTAssertFalse(ReliabilityReportingGate.shared.shouldBlockUpload)
        ReliabilityReportingGate.shared.setCameraSessionActive(true)
        XCTAssertTrue(ReliabilityReportingGate.shared.shouldBlockUpload)
        XCTAssertTrue(fake.cancelled)
        ReliabilityReportingGate.shared.setCameraSessionActive(false)
        ReliabilityReportingGate.shared.setCameraIPv4PathReadyForTests(true)
        XCTAssertTrue(ReliabilityReportingGate.shared.shouldBlockUpload)
    }

    func testHostIsolationRejectsNonDSNHosts() {
        let dsnHost = "o0.ingest.sentry.io"
        let allowed = URL(string: "https://o0.ingest.sentry.io/api/0/envelope/")!
        let other = URL(string: "https://example.com/ingest")!
        XCTAssertTrue(ReliabilityReportingHostPolicy.allows(allowed, dsnHost: dsnHost))
        XCTAssertFalse(ReliabilityReportingHostPolicy.allows(other, dsnHost: dsnHost))
        XCTAssertEqual(
            ReliabilityReportingNetwork.decision(
                for: other, dsnHost: dsnHost, gate: ReliabilityReportingGate.shared),
            .rejectHost)
        ReliabilityReportingGate.shared.setCameraSessionActive(true)
        XCTAssertEqual(
            ReliabilityReportingNetwork.decision(
                for: allowed, dsnHost: dsnHost, gate: ReliabilityReportingGate.shared),
            .blockCameraPath)
        XCTAssertEqual(
            ReliabilityReportingNetwork.retentionError(for: .blockCameraPath).code,
            URLError.notConnectedToInternet)
    }

    func testBlockedSDKSessionFailsWithoutHTTPResponse() {
        ReliabilityReportingGate.shared.setCameraSessionActive(true)
        let session = ReliabilityReportingURLProtocol.makeSDKSession()
        let url = URL(string: "https://o0.ingest.sentry.io/api/0/envelope/")!
        let done = expectation(description: "blocked")
        var response: URLResponse?
        session.dataTask(with: url) { _, resp, error in
            response = resp
            XCTAssertEqual((error as NSError?)?.code, NSURLErrorNotConnectedToInternet)
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 2)
        XCTAssertNil(response)
    }

    func testRevokedConsentBlocksCachedEnvelopeWithoutHTTPResponse() {
        ReliabilityReportingConsent.setOptedIn(false)
        ReliabilityReportingGate.shared.setCameraSessionActive(false)
        let session = ReliabilityReportingURLProtocol.makeSDKSession()
        let done = expectation(description: "revoked transport")
        session.dataTask(with: URL(string: "https://o0.ingest.sentry.io/api/0/envelope/")!) {
            _, response, error in
            XCTAssertNil(response)
            XCTAssertEqual((error as NSError?)?.code, NSURLErrorNotConnectedToInternet)
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 2)
    }

    func testHostIsolationOnSessionDoesNotForward() {
        ReliabilityReportingConsent.setOptedIn(true)
        let session = ReliabilityReportingURLProtocol.makeSDKSession()
        let url = URL(string: "https://example.com/secret")!
        let done = expectation(description: "reject")
        var response: URLResponse?
        session.dataTask(with: url) { _, resp, error in
            response = resp
            XCTAssertEqual((error as NSError?)?.code, NSURLErrorCannotFindHost)
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 2)
        XCTAssertNil(response)
    }

    func testCameraActivationCancelsInFlightForwardWithoutResponse() {
        ReliabilityReportingConsent.setOptedIn(true)
        SlowForwardProtocol.reset()
        let forwardConfig = URLSessionConfiguration.ephemeral
        forwardConfig.protocolClasses = [SlowForwardProtocol.self]
        ReliabilityReportingURLProtocol.forwardingSession = URLSession(
            configuration: forwardConfig)
        ReliabilityReportingGate.shared.setCameraSessionActive(false)
        let session = ReliabilityReportingURLProtocol.makeSDKSession()
        let url = URL(string: "https://o0.ingest.sentry.io/api/0/envelope/")!
        let done = expectation(description: "race")
        var response: URLResponse?
        session.dataTask(with: url) { _, resp, error in
            response = resp
            XCTAssertEqual((error as NSError?)?.code, NSURLErrorNotConnectedToInternet)
            done.fulfill()
        }.resume()
        wait(for: [SlowForwardProtocol.started], timeout: 2)
        ReliabilityReporting.setCameraSessionActive(true)
        wait(for: [done], timeout: 2)
        XCTAssertNil(response)
        ReliabilityReportingURLProtocol.forwardingSession = {
            let config = URLSessionConfiguration.ephemeral
            config.waitsForConnectivity = false
            return URLSession(configuration: config)
        }()
    }

    func testLaunchEnvironmentMarksAutomationWithoutXCTestClass() {
        XCTAssertTrue(
            FeedIncidentOrigin.isAutomationLaunch(["OPV_PHYSICAL_UI_REVIEW": "1"]))
        XCTAssertTrue(
            FeedIncidentOrigin.isAutomationLaunch(["OPV_UI_REVIEW_SCREEN": "live"]))
        XCTAssertTrue(
            FeedIncidentOrigin.isAutomationLaunch(["OPV_FEED_STRESS": "1"]))
        XCTAssertFalse(
            FeedIncidentOrigin.isAutomationLaunch(["OPV_UI_REVIEW_SCREEN": ""]))
        XCTAssertFalse(FeedIncidentOrigin.isAutomationLaunch([:]))
        FeedIncidentOrigin.overrideTestSourceForTests = nil
        XCTAssertEqual(
            FeedIncidentOrigin.currentTestSource(
                environment: ["OPV_PHYSICAL_UI_REVIEW": "1"], injectionActivated: false),
            .automation)
        XCTAssertEqual(
            FeedIncidentOrigin.currentTestSource(
                environment: [:], injectionActivated: true),
            .faultInjection)
    }

    func testScrubDoesNotStampCurrentOriginOntoLegacyOrFatalEvents() {
        FeedIncidentOrigin.overrideTestSourceForTests = .verification
        FeedIncidentOrigin.overrideBuildIdentityForTests = "ios-current-run-identity-value"
        let event = Event(level: .fatal)
        event.tags = ["failingStage": "decodedOutput"]
        _ = ReliabilityReportingPrivacy.scrub(event)
        XCTAssertNil(event.tags?["testSource"])
        XCTAssertNil(event.tags?["buildIdentity"])
        event.tags = ["testSource": "manual", "buildIdentity": "ios-priorrun0123456789abcdefab"]
        _ = ReliabilityReportingPrivacy.scrub(event)
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
        _ = ReliabilityReportingPrivacy.scrub(event)
        XCTAssertEqual(event.breadcrumbs?.count, 2)
        XCTAssertNil(event.breadcrumbs?[0].data?["sceneState"])
        XCTAssertNil(event.breadcrumbs?[1].data?["assistState"])
    }

    func testEventIDAndFingerprintAreStable() {
        let id = "12c2d058-d584-4270-9aa2-eca08bf20986"
        let first = ReliabilityReportingPrivacy.eventID(fromIncidentID: id)
        let second = ReliabilityReportingPrivacy.eventID(fromIncidentID: id)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.sentryIdString, "12c2d058d58442709aa2eca08bf20986")
        let prints = ReliabilityReportingPrivacy.fingerprint(
            schema: 1, kind: "freshInputStaleOutput", stage: "decodedOutput",
            errorClass: "invalidSession")
        XCTAssertEqual(
            prints,
            [
                "feed-incident", "schema:1", "kind:freshInputStaleOutput",
                "stage:decodedOutput", "errorClass:invalidSession",
            ]
        )
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
        _ = ReliabilityReportingPrivacy.scrub(event)
        XCTAssertEqual(event.breadcrumbs?.count, 3)
        XCTAssertEqual(event.breadcrumbs?[0].message, "settingsEnter")
        XCTAssertNil(event.breadcrumbs?[0].data)
        XCTAssertEqual(event.breadcrumbs?[1].message, "sceneActivity")
        XCTAssertEqual(event.breadcrumbs?[1].data?["sceneState"] as? String, "inactive")
        XCTAssertNil(event.breadcrumbs?[1].data?["password"])
        XCTAssertEqual(event.breadcrumbs?[2].message, "repair")
        XCTAssertEqual(event.breadcrumbs?[2].data?["repairAction"] as? String, "decoder")
    }

    func testVerificationUsesTheRealRecorderAndProducesRecoveredIncident() throws {
        let id = UUID().uuidString
        let bundle = try XCTUnwrap(ReliabilityReportingVerification.syntheticIncident(id: id))
        XCTAssertEqual(bundle.header.incidentID, id)
        XCTAssertEqual(bundle.header.outcome, .recovered)
        XCTAssertEqual(bundle.header.failingStage, .decodedOutput)
        XCTAssertEqual(bundle.header.cameraFamily, "synthetic")
        XCTAssertFalse(bundle.prelude.isEmpty)
        XCTAssertEqual(bundle.breadcrumbs.first?.kind, .settingsEnter)
    }

    func testSDKCapturePreservesOriginalBuildAfterUpgrade() {
        ReliabilityReportingConsent.setOptedIn(true)
        let options = ReliabilityReporting.makeOptions(
            dsn: "https://publickey@o0.ingest.sentry.io/0",
            urlSession: ReliabilityReportingURLProtocol.makeSDKSession())
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
        wait(for: [prepared], timeout: 3)
    }

    func testQueuedIncidentKeepsOriginalReleaseAndOccurrenceTime() throws {
        ReliabilityReportingConsent.setOptedIn(true)
        var bundle = try stallBundle(id: UUID().uuidString)
        bundle.header.outcome = .recovered
        bundle.header.appVersion = "0.1.0"
        bundle.header.appBuild = "107"
        bundle.header.sourceRevision = String(repeating: "a", count: 40)
        bundle.header.testSource = .faultInjection
        bundle.header.buildIdentity = "ios-0123456789abcdef0123456789abcd"
        bundle.header.startedAtWallClock = Date(timeIntervalSince1970: 1_780_000_000)
        FeedIncidentOrigin.overrideTestSourceForTests = .verification
        FeedIncidentOrigin.overrideBuildIdentityForTests = "ios-current-run-identity-value"
        let captured = expectation(description: "original provenance")
        let expectedTime = bundle.header.startedAtWallClock
        ReliabilityReporting.setCaptureHandlerForTests { event, _ in
            XCTAssertEqual(event.releaseName, "com.opencapture.openpocketcine@0.1.0+107")
            XCTAssertEqual(event.dist, "107")
            XCTAssertEqual(event.timestamp, expectedTime)
            XCTAssertEqual(event.tags?["sourceRevision"], String(repeating: "a", count: 40))
            XCTAssertEqual(event.tags?["testSource"], "faultInjection")
            XCTAssertEqual(event.tags?["buildIdentity"], "ios-0123456789abcdef0123456789abcd")
            XCTAssertNotEqual(event.tags?["testSource"], "verification")
            captured.fulfill()
        }
        ReliabilityReporting.enqueueFinalized(bundle)
        wait(for: [captured], timeout: 2)
    }

    func testQueuedReplayOriginSurvivesActualSDKScopeMerge() throws {
        ReliabilityReportingConsent.setOptedIn(true)
        var bundle = try stallBundle(id: UUID().uuidString)
        bundle.header.outcome = .recovered
        bundle.header.kind = .transportStall
        bundle.header.testSource = .faultInjection
        bundle.header.buildIdentity = "ios-queuedorigin0123456789abcdef"
        FeedIncidentOrigin.overrideTestSourceForTests = .verification
        FeedIncidentOrigin.overrideBuildIdentityForTests = "ios-current-run-identity-value"
        let options = ReliabilityReporting.makeOptions(
            dsn: "https://publickey@o0.ingest.sentry.io/0",
            urlSession: ReliabilityReportingURLProtocol.makeSDKSession())
        let prepared = expectation(description: "SDK beforeSend original origin")
        options.beforeSend = { event in
            let scrubbed = ReliabilityReportingPrivacy.scrub(event)
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
        ReliabilityReporting.setCaptureHandlerForTests { event, _ in
            XCTAssertEqual(event.tags?["testSource"], "faultInjection")
            XCTAssertTrue(event.fingerprint?.contains("kind:transportStall") == true)
            SentrySDK.capture(event: event) { scope in
                ReliabilityReporting.applyOriginalTags(event.tags, to: scope)
            }
            constructed.fulfill()
        }
        ReliabilityReporting.enqueueFinalized(bundle)
        wait(for: [constructed, prepared], timeout: 3)
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
            "device": ["name": "Example Phone", "model": "iPhone17,2"],
            "feed": ["failingStage": "decodedOutput", "serial": "ABC"],
        ]
        event.exceptions = [
            Exception(value: "/" + "Users/example/Library/crash", type: "NSError")
        ]
        _ = ReliabilityReportingPrivacy.scrub(event)
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
        XCTAssertNil(event.context?["feed"]?["serial"])
        XCTAssertFalse(event.exceptions?.first?.value?.contains("example/Library") ?? true)
    }

    func testImmediateConfirmationIsNotOverwrittenByQueuedReceipt() throws {
        ReliabilityReportingConsent.setOptedIn(true)
        let id = "cccccccccccccccccccccccccccccccc"
        var bundle = try stallBundle(id: id)
        bundle.header.outcome = .recovered
        ReliabilityReporting.setCaptureHandlerForTests { event, _ in
            ReliabilityReporting.noteTransportSuccess(eventID: event.eventId.sentryIdString)
        }
        ReliabilityReporting.enqueueFinalized(bundle)
        waitForReceipt(id, state: .confirmed)
    }

    func testIncidentExposureDoesNotInheritPreviousSessionSummary() throws {
        ReliabilityReportingConsent.setOptedIn(true)
        ReliabilityReporting.noteSessionSummary(
            FeedIncidentSessionSummary(
                sessionID: UUID().uuidString, healthyExposureSeconds: 123456,
                incidentCount: 99, outcome: "healthy", sourceRevision: "test"))
        var bundle = try stallBundle(id: "dddddddddddddddddddddddddddddddd")
        bundle.header.outcome = .recovered
        let captured = expectation(description: "incident")
        ReliabilityReporting.setCaptureHandlerForTests { event, _ in
            guard event.fingerprint?.first == "feed-incident" else { return }
            XCTAssertNotEqual(event.extra?["healthyExposureSeconds"] as? Double, 123456)
            XCTAssertNil(event.extra?["incidentCount"])
            captured.fulfill()
        }
        ReliabilityReporting.enqueueFinalized(bundle)
        wait(for: [captured], timeout: 2)
    }

    func testCaptureEnqueueIsQueuedNotDeliveredAndDedupsConfirmed() throws {
        ReliabilityReportingConsent.setOptedIn(true)
        var bundle = try stallBundle(id: "12c2d058d58442709aa2eca08bf20986")
        bundle.header.outcome = .recovered
        let captured = expectation(description: "handler")
        captured.expectedFulfillmentCount = 1
        ReliabilityReporting.setCaptureHandlerForTests { event, data in
            XCTAssertEqual(event.eventId.sentryIdString, "12c2d058d58442709aa2eca08bf20986")
            XCTAssertEqual(event.fingerprint?.first, "feed-incident")
            XCTAssertTrue(event.fingerprint?.contains("kind:freshInputStaleOutput") == true)
            XCTAssertNil(event.user)
            let text = String(data: data, encoding: .utf8) ?? ""
            XCTAssertTrue(text.contains("prelude"))
            XCTAssertTrue(text.contains("repairs") || text.contains("during"))
            XCTAssertFalse(text.contains("control-live.log"))
            captured.fulfill()
        }
        ReliabilityReporting.enqueueFinalized(bundle)
        wait(for: [captured], timeout: 2)
        waitForReceipt("12c2d058d58442709aa2eca08bf20986", state: .queued)
        XCTAssertEqual(
            ReliabilityReporting.receipt(for: "12c2d058d58442709aa2eca08bf20986")?.state,
            .queued)
        ReliabilityReporting.noteTransportSuccess(eventID: "12c2d058d58442709aa2eca08bf20986")
        waitForReceipt("12c2d058d58442709aa2eca08bf20986", state: .confirmed)
        XCTAssertEqual(
            ReliabilityReporting.receipt(for: "12c2d058d58442709aa2eca08bf20986")?.state,
            .confirmed)
        let again = expectation(description: "no-second")
        again.isInverted = true
        ReliabilityReporting.setCaptureHandlerForTests { _, _ in again.fulfill() }
        ReliabilityReporting.enqueueFinalized(bundle)
        wait(for: [again], timeout: 0.3)
    }

    func testOpenCheckpointDoesNotEnqueueDuplicate() throws {
        ReliabilityReportingConsent.setOptedIn(true)
        let open = try stallBundle(id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertEqual(open.header.outcome, .open)
        XCTAssertFalse(ReliabilityReporting.isFinalized(open))
        let captured = expectation(description: "open-must-not-capture")
        captured.isInverted = true
        ReliabilityReporting.setCaptureHandlerForTests { _, _ in captured.fulfill() }
        ReliabilityReporting.enqueueFinalized(open)
        wait(for: [captured], timeout: 0.4)
        XCTAssertNil(ReliabilityReporting.receipt(for: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
    }

    func testHealthyOnlyEndSummaryDoesNotClaimHealthyAtZeroExposure() {
        XCTAssertEqual(
            FeedIncidentRuntime.summaryOutcome(incidentCount: 0, exposure: 12), "healthy")
        XCTAssertEqual(
            FeedIncidentRuntime.summaryOutcome(incidentCount: 0, exposure: 0), "no-exposure")
        XCTAssertEqual(FeedIncidentRuntime.summaryOutcome(incidentCount: 2, exposure: 40), "ended")
    }

    func testDeleteStoredIncidentsClearsExtrasCache() {
        FeedIncidentRuntime.seedExtrasCacheForTests([
            ("incident-dead.json", "should-not-share")
        ])
        XCTAssertEqual(FeedIncidentRuntime.reportExtras().count, 1)
        let done = expectation(description: "deleted")
        FeedIncidentRuntime.deleteStoredIncidents { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(FeedIncidentRuntime.reportExtras().isEmpty)
    }

    func testRevokeAbortsQueuedCapture() throws {
        ReliabilityReportingConsent.setOptedIn(true)
        var bundle = try stallBundle(id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        bundle.header.outcome = .interrupted
        let captured = expectation(description: "revoked")
        captured.isInverted = true
        ReliabilityReporting.setCaptureHandlerForTests { _, _ in captured.fulfill() }
        ReliabilityReporting.enqueueFinalized(bundle)
        ReliabilityReporting.setConsent(false)
        wait(for: [captured], timeout: 0.5)
        XCTAssertFalse(ReliabilityReporting.isOptedIn)
        XCTAssertNil(ReliabilityReporting.receipt(for: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"))
    }

    func testTransportSuccessConfirmsOnlyMatchingEventID() {
        ReliabilityReportingConsent.setOptedIn(true)
        ReliabilityReportingReceipts.store(
            ReliabilityReportingReceipt(
                incidentID: "a", eventID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                state: .queued, updatedAt: Date()),
            root: cacheRoot)
        ReliabilityReportingReceipts.store(
            ReliabilityReportingReceipt(
                incidentID: "b", eventID: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                state: .queued, updatedAt: Date()),
            root: cacheRoot)
        ReliabilityReporting.noteTransportSuccess(eventID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        waitForReceipt("a", state: .confirmed)
        XCTAssertEqual(
            ReliabilityReportingReceipts.load(incidentID: "a", root: cacheRoot)?.state,
            .confirmed)
        XCTAssertEqual(
            ReliabilityReportingReceipts.load(incidentID: "b", root: cacheRoot)?.state,
            .queued)
        var request = URLRequest(url: URL(string: "https://o0.ingest.sentry.io/api/0/envelope/")!)
        request.httpBody = Data("{\"event_id\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}\n{}".utf8)
        XCTAssertEqual(
            ReliabilityReportingEnvelopeID.eventID(from: request),
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    }

    func testReceiptTTLAndOptionsPrivacyFlags() {
        var old = ReliabilityReportingReceipt(
            incidentID: "old", eventID: "e", state: .queued,
            updatedAt: Date(timeIntervalSince1970: 1))
        ReliabilityReportingReceipts.store(old, root: cacheRoot)
        let url = ReliabilityReportingReceipts.directory(root: cacheRoot)
            .appendingPathComponent("old.json")
        try? FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: url.path)
        ReliabilityReportingReceipts.applyTTL(
            root: cacheRoot, now: Date(), ttl: 10)
        XCTAssertNil(ReliabilityReportingReceipts.load(incidentID: "old", root: cacheRoot))
        let session = ReliabilityReportingURLProtocol.makeSDKSession()
        let options = ReliabilityReporting.makeOptions(
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
        XCTAssertEqual(options.maxCacheItems, 30)
        XCTAssertEqual(options.maxAttachmentSize, 256 * 1_024)
        XCTAssertEqual(options.sessionReplay.sessionSampleRate, 0)
        XCTAssertEqual(options.sessionReplay.onErrorSampleRate, 0)
    }

    func testBackoffGrowsWithJitterBound() {
        let first = ReliabilityReportingBackoff.delaySeconds(attempt: 0, jitter: 0)
        let later = ReliabilityReportingBackoff.delaySeconds(attempt: 5, jitter: 1)
        XCTAssertGreaterThan(later, first)
        XCTAssertLessThanOrEqual(later, 30)
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

private final class FakeTask: ReliabilityReportingCancellable {
    var cancelled = false
    func cancel() { cancelled = true }
}

private final class SlowForwardProtocol: URLProtocol {
    static var started = XCTestExpectation(description: "slow-start")

    static func reset() {
        started = XCTestExpectation(description: "slow-start")
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.started.fulfill() }
    override func stopLoading() {}
}
