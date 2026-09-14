import Foundation
import XCTest

@testable import OpenPocketCine

final class ReliabilityReportingEnvelopeTests: XCTestCase {
    private let eventID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private let otherID = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

    func testGzipEnvelopeHeaderYieldsEventID() throws {
        let plain = envelope(eventID: eventID, trailer: String(repeating: "x", count: 8_192))
        let gzipped = try XCTUnwrap(ReliabilityReportingGzip.deflateForTests(plain))
        XCTAssertEqual(gzipped[0], 0x1F)
        XCTAssertEqual(gzipped[1], 0x8B)
        XCTAssertNil(
            ReliabilityReportingEnvelopeID.eventID(
                fromBody: gzipped, contentEncoding: "identity"),
            "gzip bytes must not parse as plaintext JSON")
        XCTAssertEqual(
            ReliabilityReportingEnvelopeID.eventID(fromBody: gzipped, contentEncoding: "gzip"),
            eventID)
        var request = URLRequest(url: URL(string: "https://o0.ingest.sentry.io/api/0/envelope/")!)
        request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        request.httpBody = gzipped
        XCTAssertEqual(ReliabilityReportingEnvelopeID.eventID(from: request), eventID)
    }

    func testGzipMagicWithoutContentEncodingStillParses() throws {
        let gzipped = try XCTUnwrap(
            ReliabilityReportingGzip.deflateForTests(envelope(eventID: eventID)))
        XCTAssertEqual(
            ReliabilityReportingEnvelopeID.eventID(fromBody: gzipped, contentEncoding: nil),
            eventID)
    }

    func testHttpBodyStreamDoesNotRequirePlaintextBody() throws {
        let gzipped = try XCTUnwrap(
            ReliabilityReportingGzip.deflateForTests(envelope(eventID: eventID)))
        var request = URLRequest(url: URL(string: "https://o0.ingest.sentry.io/api/0/envelope/")!)
        request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        request.httpBodyStream = InputStream(data: gzipped)
        let materialized = ReliabilityReportingURLProtocol.materialized(request)
        XCTAssertEqual(materialized.1, gzipped)
        XCTAssertEqual(materialized.0.httpBody, gzipped)
        XCTAssertNil(materialized.0.httpBodyStream)
        XCTAssertEqual(
            ReliabilityReportingEnvelopeID.eventID(
                fromBody: materialized.1, contentEncoding: "gzip"),
            eventID)
    }

    func testMalformedAndTruncatedGzipYieldNil() {
        XCTAssertNil(
            ReliabilityReportingEnvelopeID.eventID(
                fromBody: Data([0x1F, 0x8B, 0x08, 0x00, 0xFF]), contentEncoding: "gzip"))
        XCTAssertNil(
            ReliabilityReportingEnvelopeID.eventID(
                fromBody: Data([0x1F, 0x8B]), contentEncoding: "gzip"))
        XCTAssertNil(
            ReliabilityReportingEnvelopeID.eventID(
                fromBody: Data("not-gzip".utf8), contentEncoding: "gzip"))
        let truncated = ReliabilityReportingGzip.deflateForTests(envelope(eventID: eventID))
            .map { Data($0.prefix(8)) }
        XCTAssertNil(
            ReliabilityReportingEnvelopeID.eventID(fromBody: truncated, contentEncoding: "gzip"))
    }

    func testOversizedHeaderWithoutNewlineIsBounded() throws {
        let huge = Data(repeating: 0x41, count: ReliabilityReportingEnvelopeID.maxHeaderBytes + 64)
        let gzipped = try XCTUnwrap(ReliabilityReportingGzip.deflateForTests(huge))
        XCTAssertNil(
            ReliabilityReportingEnvelopeID.eventID(fromBody: gzipped, contentEncoding: "gzip"))
        let inflated = ReliabilityReportingGzip.inflateHeader(
            from: gzipped, maxOutput: ReliabilityReportingEnvelopeID.maxHeaderBytes)
        XCTAssertLessThanOrEqual(
            inflated?.count ?? 0, ReliabilityReportingEnvelopeID.maxHeaderBytes)
    }

    func testNonmatchingAndShortEventIDsAreRejected() {
        let short = envelope(eventID: "abc")
        XCTAssertNil(
            ReliabilityReportingEnvelopeID.eventID(fromBody: short, contentEncoding: nil))
        let gzipped = ReliabilityReportingGzip.deflateForTests(envelope(eventID: otherID))
        XCTAssertNotEqual(
            ReliabilityReportingEnvelopeID.eventID(fromBody: gzipped, contentEncoding: "gzip"),
            eventID)
        XCTAssertNil(
            ReliabilityReportingEnvelopeID.eventID(
                fromBody: Data("{\"sent_at\":\"1\"}\n".utf8), contentEncoding: nil))
    }

    func testRedirectsOffDSNHostAreRejected() {
        let dsn = "o0.ingest.sentry.io"
        XCTAssertTrue(
            ReliabilityReportingRedirectGuard.shouldFollow(
                url: URL(string: "https://o0.ingest.sentry.io/api/1/envelope/"),
                dsnHost: dsn))
        XCTAssertFalse(
            ReliabilityReportingRedirectGuard.shouldFollow(
                url: URL(string: "https://evil.example/steal"),
                dsnHost: dsn))
        XCTAssertFalse(
            ReliabilityReportingRedirectGuard.shouldFollow(
                url: URL(string: "http://o0.ingest.sentry.io/api/1/envelope/"),
                dsnHost: dsn))
        XCTAssertFalse(ReliabilityReportingRedirectGuard.shouldFollow(url: nil, dsnHost: dsn))
    }

    func testCameraGateStillBlocksForwardDecision() {
        let gate = ReliabilityReportingGate.shared
        gate.resetForTests()
        let url = URL(string: "https://o0.ingest.sentry.io/api/0/envelope/")!
        XCTAssertEqual(
            ReliabilityReportingNetwork.decision(for: url, dsnHost: url.host, gate: gate),
            .forward)
        gate.setCameraSessionActive(true)
        XCTAssertEqual(
            ReliabilityReportingNetwork.decision(for: url, dsnHost: url.host, gate: gate),
            .blockCameraPath)
        gate.resetForTests()
    }

    private func envelope(eventID: String, trailer: String = "payload") -> Data {
        Data(
            "{\"event_id\":\"\(eventID)\",\"sent_at\":\"2026-09-14T00:00:00Z\"}\n{\"type\":\"event\"}\n\(trailer)\n"
                .utf8)
    }
}
