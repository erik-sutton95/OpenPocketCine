import Foundation
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class FeedSessionSummaryStoreTests: XCTestCase {
    func testHealthySessionsSurviveLaterSessionsAndInterruptedProcess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let healthy = FeedIncidentSessionSummary(
            sessionID: UUID().uuidString, healthyExposureSeconds: 600,
            incidentCount: 0, outcome: "healthy", sourceRevision: "test",
            testSource: .manual, buildIdentity: "ios-0123456789abcdef0123456789abcd")
        let live = FeedIncidentSessionSummary(
            sessionID: UUID().uuidString, healthyExposureSeconds: 30,
            incidentCount: 1, outcome: "live", sourceRevision: "test")
        FeedSessionSummaryStore.persist(healthy, root: root)
        FeedSessionSummaryStore.persist(live, root: root)
        FeedSessionSummaryStore.markInterrupted(root: root)
        let loaded = FeedSessionSummaryStore.load(root: root)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(
            loaded.first { $0.sessionID == healthy.sessionID }?.healthyExposureSeconds, 600)
        XCTAssertEqual(
            loaded.first { $0.sessionID == healthy.sessionID }?.testSource, .manual)
        XCTAssertEqual(
            loaded.first { $0.sessionID == healthy.sessionID }?.buildIdentity,
            "ios-0123456789abcdef0123456789abcd")
        XCTAssertEqual(loaded.first { $0.sessionID == live.sessionID }?.outcome, "interrupted")
        XCTAssertNil(loaded.first { $0.sessionID == live.sessionID }?.testSource)
        FeedSessionSummaryStore.deleteAll(root: root)
        XCTAssertTrue(FeedSessionSummaryStore.load(root: root).isEmpty)
    }

    func testRetentionAndInvalidIdentityCannotEscapeSpool() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var summary = FeedIncidentSessionSummary(
            sessionID: "../outside", healthyExposureSeconds: 0,
            incidentCount: 0, outcome: "no-exposure", sourceRevision: "test")
        FeedSessionSummaryStore.persist(summary, root: root)
        XCTAssertTrue(FeedSessionSummaryStore.load(root: root).isEmpty)
        for _ in 0..<25 {
            summary.sessionID = UUID().uuidString
            FeedSessionSummaryStore.persist(summary, root: root)
        }
        XCTAssertEqual(FeedSessionSummaryStore.load(root: root).count, 20)
        FeedSessionSummaryStore.persist(
            summary, root: root, now: Date().addingTimeInterval(604_801))
        XCTAssertTrue(FeedSessionSummaryStore.load(root: root).isEmpty)
    }
}
