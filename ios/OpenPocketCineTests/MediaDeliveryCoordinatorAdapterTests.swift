import Foundation
import XCTest

@testable import OpenPocketCine

/// SIMULATED operation completion gates; shipping coordinator and filesystem lease cleanup.
@MainActor private final class DeliveryAdapterGate {
    var waiters: [CheckedContinuation<MediaDeliveryRunOutcome, Never>] = []
    func wait() async -> MediaDeliveryRunOutcome {
        await withCheckedContinuation { waiters.append($0) }
    }
    func release(_ outcome: MediaDeliveryRunOutcome) {
        waiters.removeFirst().resume(returning: outcome)
    }
}

/// This app's coordinator wrapper: the sheet binding's captured lease and the staging cleanup.
/// The lifetime cases (acknowledgement order, callback replacement) are OpenCineAppKit
/// `MonitorDeliveryModelTests`.
@MainActor final class MediaDeliveryCoordinatorAdapterTests: XCTestCase {
    private func settle(_ predicate: () -> Bool) async {
        for _ in 0..<1000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Coordinator did not reach the manual operation gate")
    }

    private var request: MediaDeliveryBeginRequest {
        .init(files: [], destination: .nativeShare, configuration: .init())
    }

    func testCapturedSheetBindingAndOldCompletionCannotClearSuccessorLease() async {
        let gate = DeliveryAdapterGate()
        let coordinator = MediaDeliveryCoordinator(execute: { _, _, _ in await gate.wait() })
        let model = AppModel()
        defer {
            coordinator.close()
            model.session.disconnect()
        }
        coordinator.begin(request, model: model)
        await settle { gate.waiters.count == 1 }
        gate.release(
            .share(
                urls: [URL(fileURLWithPath: "/SIMULATED/A.mp4")],
                metadataText: nil, stagingCleanupURL: nil))
        await settle { coordinator.sharePayload != nil }
        let old = coordinator.sharePresentation
        let oldID = coordinator.sharePayload?.id
        XCTAssertEqual(old.wrappedValue?.id, oldID)
        coordinator.begin(request, model: model)
        await settle { gate.waiters.count == 1 }
        gate.release(
            .share(
                urls: [URL(fileURLWithPath: "/SIMULATED/B.mp4")],
                metadataText: nil, stagingCleanupURL: nil))
        await settle { coordinator.sharePayload?.id != oldID }
        let current = coordinator.sharePayload
        old.wrappedValue = nil
        XCTAssertEqual(coordinator.sharePayload?.id, current?.id)
        XCTAssertEqual(coordinator.sharePayload?.urls, current?.urls)
        if let oldID { XCTAssertFalse(coordinator.completeSharePresentation(id: oldID)) }
        XCTAssertEqual(coordinator.sharePayload?.id, current?.id)
        let accepted = coordinator.sharePresentation
        accepted.wrappedValue = nil
        XCTAssertNil(coordinator.sharePayload)
        if let id = current?.id { XCTAssertTrue(coordinator.completeSharePresentation(id: id)) }
    }

    func testCancelledLateShareCleansOnlyReturnedStagingLease() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SIMULATED-delivery-lease-\(UUID())", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        let original = root.appendingPathComponent("original.mp4")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: original)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = DeliveryAdapterGate()
        let coordinator = MediaDeliveryCoordinator(execute: { _, _, _ in await gate.wait() })
        let model = AppModel()
        defer {
            coordinator.close()
            model.session.disconnect()
        }
        coordinator.begin(request, model: model)
        await settle { gate.waiters.count == 1 }
        coordinator.cancel()
        gate.release(.share(urls: [original], metadataText: nil, stagingCleanupURL: staging))
        await settle { !FileManager.default.fileExists(atPath: staging.path) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertNil(coordinator.sharePayload)
        XCTAssertNil(coordinator.overlayState)
        XCTAssertFalse(coordinator.isActive)
    }
}
