import XCTest

@testable import OpenPocketCine

@MainActor final class ProblemReportingTests: XCTestCase {
    func testDecliningIsPersistedAsDecisionAndCanBeEnabledLater() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let original = ReliabilityReportingConsent.defaults
        ReliabilityReportingConsent.defaults = defaults
        defer { ReliabilityReportingConsent.defaults = original }
        XCTAssertFalse(ReliabilityReportingConsent.hasDecision)
        ReliabilityReportingConsent.setOptedIn(false)
        XCTAssertTrue(ReliabilityReportingConsent.hasDecision)
        XCTAssertFalse(ReliabilityReportingConsent.isOptedIn)
        ReliabilityReportingConsent.setOptedIn(true)
        XCTAssertTrue(ReliabilityReportingConsent.isOptedIn)
    }

    func testExplicitManualSubmissionPersistsWithoutAutomaticConsentAndCanBeDiscarded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = ReliabilityReportingConsent.defaults
        ReliabilityReportingConsent.defaults = UserDefaults(suiteName: UUID().uuidString)!
        ReliabilityReportingConsent.setOptedIn(false)
        ReliabilityReportingGate.shared.setCameraIPv4PathReadyForTests(true)
        defer {
            ReliabilityReportingConsent.defaults = original
            ReliabilityReportingGate.shared.setCameraIPv4PathReadyForTests(nil)
        }
        let reporter = ProblemReporting(
            directory: root, dsnProvider: { "https://public@sentry.invalid/42" })
        XCTAssertNil(reporter.pending)
        try reporter.submit(message: "Synthetic test report", email: "", diagnostics: nil)
        XCTAssertFalse(ReliabilityReportingConsent.isOptedIn)
        XCTAssertNotNil(reporter.pending)
        XCTAssertThrowsError(try reporter.submit(message: "Second", email: "", diagnostics: nil))
        let restored = ProblemReporting(directory: root)
        XCTAssertEqual(restored.pending?.id, reporter.pending?.id)
        try restored.discard()
        XCTAssertNil(ProblemReporting(directory: root).pending)
    }

    func testFeedbackSchemaOmitsContactAndAttachmentsUnlessProvided() throws {
        let data = try ProblemReporting.envelope(
            id: "123", message: "Synthetic test", email: "", diagnostics: nil, date: Date())
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        let header = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any])
        XCTAssertEqual(header["type"] as? String, "feedback")
        let event = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(lines[2].utf8)) as? [String: Any])
        let contexts = try XCTUnwrap(event["contexts"] as? [String: Any])
        let feedback = try XCTUnwrap(contexts["feedback"] as? [String: Any])
        XCTAssertEqual(feedback["message"] as? String, "Synthetic test")
        XCTAssertNil(feedback["contact_email"])
        XCTAssertNil(event["user"])
        XCTAssertEqual(lines.count, 3)
    }

    func testExplicitEmailIsPreservedAndAttachmentIsBounded() throws {
        let data = try ProblemReporting.envelope(
            id: "123", message: "Synthetic test", email: "reply@example.invalid",
            diagnostics: String(repeating: "a", count: 200_000), date: Date())
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("reply@example.invalid"))
        XCTAssertTrue(text.contains("diagnostics.txt"))
        XCTAssertLessThan(data.count, 34_000)
    }

    func testEndpointRejectsInvalidDestinationsAndRemovesUserInfo() {
        XCTAssertNil(ProblemReporting.endpoint(dsn: "http://key@sentry.invalid/42"))
        let url = ProblemReporting.endpoint(dsn: "https://key@sentry.invalid/prefix/42")
        XCTAssertEqual(url?.path, "/prefix/api/42/envelope")
        XCTAssertNil(url?.user)
        XCTAssertEqual(url?.host, "sentry.invalid")
    }

    func testRetryAfterIsRespected() {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.invalid")!, statusCode: 429, httpVersion: nil,
            headerFields: ["Retry-After": "900"])!
        XCTAssertEqual(ProblemReporting.retryDelay(response: response, attempts: 1), 900)
    }

    func testHTTPAcceptanceClearsQueueWithoutEnablingAutomaticReports() async throws {
        try await verifyHTTPResponse(code: 200, shouldRemainQueued: false)
    }

    func testServerFailureKeepsOriginalReportForRetry() async throws {
        try await verifyHTTPResponse(code: 503, shouldRemainQueued: true)
    }

    private func verifyHTTPResponse(code: Int, shouldRemainQueued: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = ReliabilityReportingConsent.defaults
        ReliabilityReportingConsent.defaults = UserDefaults(suiteName: UUID().uuidString)!
        ReliabilityReportingConsent.setOptedIn(false)
        ReliabilityReportingGate.shared.setCameraIPv4PathReadyForTests(false)
        ReliabilityReportingGate.shared.setValidInternetForTests(true)
        defer {
            try? FileManager.default.removeItem(at: root)
            ReliabilityReportingConsent.defaults = original
            ReliabilityReportingGate.shared.setCameraIPv4PathReadyForTests(nil)
        }
        ManualReportHTTPStub.code = code
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManualReportHTTPStub.self]
        let reporter = ProblemReporting(
            directory: root,
            dsnProvider: { "https://public@sentry.invalid/42" },
            sessionConfiguration: configuration, isForeground: { true })
        try reporter.submit(message: "Synthetic transport test", email: "", diagnostics: nil)
        let id = reporter.pending?.id
        for _ in 0..<100 {
            if !reporter.status.hasPrefix("Sending") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(ReliabilityReportingConsent.isOptedIn)
        if shouldRemainQueued {
            XCTAssertEqual(reporter.pending?.id, id)
            XCTAssertGreaterThan(try XCTUnwrap(reporter.pending?.nextAttempt), Date())
            XCTAssertEqual(ProblemReporting(directory: root).pending?.id, id)
        } else {
            XCTAssertNil(reporter.pending)
            XCTAssertTrue(reporter.status.hasPrefix("Report sent"))
            XCTAssertNil(ProblemReporting(directory: root).pending)
        }
    }

    func testExpiredReportIsRemovedAfterRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reporter = ProblemReporting(
            directory: root,
            dsnProvider: { "https://public@sentry.invalid/42" }, isForeground: { false })
        try reporter.submit(message: "Synthetic expiry test", email: "", diagnostics: nil)
        let restored = ProblemReporting(directory: root, isForeground: { false })
        restored.tick(now: Date().addingTimeInterval(ProblemReporting.lifetime + 1))
        XCTAssertNil(restored.pending)
        XCTAssertNil(ProblemReporting(directory: root).pending)
        XCTAssertTrue(restored.status.contains("expired"))
    }

    func testAutomaticOptOutDoesNotCancelManualReportButCameraGateDoes() {
        let gate = ReliabilityReportingGate()
        gate.setCameraIPv4PathReadyForTests(false)
        let manual = ManualCancellationProbe()
        gate.register(manual)
        gate.cancelPending(includeIndependent: false)
        XCTAssertFalse(manual.cancelled)
        gate.setCameraSessionActive(true)
        XCTAssertTrue(manual.cancelled)
    }
}

private final class ManualCancellationProbe: ReliabilityReportingCancellable {
    var independentOfAutomaticConsent: Bool { true }
    var cancelled = false
    func cancel() { cancelled = true }
}

/// No socket is opened by these transport tests.
private final class ManualReportHTTPStub: URLProtocol {
    static var code = 200
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "sentry.invalid"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
