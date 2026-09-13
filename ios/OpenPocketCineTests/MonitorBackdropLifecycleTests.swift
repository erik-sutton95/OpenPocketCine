import CoreImage
import MonitorPresentation
import XCTest

@testable import OpenPocketCine

@MainActor
final class MonitorBackdropLifecycleTests: XCTestCase {
    func testCancellationRemountAndThermalBackoffKeepOneOccupiedSlotAndRejectOldResults()
        async throws
    {
        let clock = InspectorPreviewTestClock()
        let started = expectation(description: "Native work began")
        let release = DispatchSemaphore(value: 0)
        let renderer = MonitorVideoBackdropRenderer(
            clock: { clock.now }, minimumInterval: { 1 },
            operation: { _, _ in
                started.fulfill()
                _ = release.wait(timeout: .now() + 3)
                return nil
            })
        let first = UUID()
        renderer.activate(first)
        let pending = Task {
            await renderer.render(owner: first, canvasSize: CGSize(width: 900, height: 600)) { [] }
        }
        await fulfillment(of: [started], timeout: 2)
        pending.cancel()
        let second = UUID()
        renderer.activate(second)
        clock.now = 2_000_000_000
        var prepared = false
        let overlap = await renderer.render(
            owner: second, canvasSize: CGSize(width: 900, height: 600)
        ) {
            prepared = true
            return []
        }
        XCTAssertNil(overlap)
        XCTAssertFalse(prepared, "Rejected jobs must not fetch/retain source buffers")
        renderer.deactivate(first)
        release.signal()
        let stale = await pending.value
        XCTAssertNil(stale, "An old source must not publish after cancellation/remount")

        // A separate completed-job case verifies the retained thermal deadline,
        // independent of task sleeps or rapidly replaced view owners.
        clock.now = 0
        let thermal = MonitorVideoBackdropRenderer(
            clock: { clock.now }, minimumInterval: { 1 }, operation: { _, _ in nil })
        thermal.activate(first)
        let firstResult = await thermal.render(
            owner: first, canvasSize: CGSize(width: 9, height: 6)
        ) { [] }
        let admitted = try XCTUnwrap(firstResult)
        XCTAssertTrue(thermal.isCurrent(admitted))
        thermal.deactivate(first)
        for timestamp in [UInt64(200_000_000), 600_000_000, 999_999_999] {
            clock.now = timestamp
            let owner = UUID()
            thermal.activate(owner)
            let tooEarly = await thermal.render(
                owner: owner, canvasSize: CGSize(width: 9, height: 6)
            ) { [] }
            XCTAssertNil(tooEarly)
        }
        clock.now = 1_000_000_000
        thermal.activate(second)
        let next = await thermal.render(owner: second, canvasSize: CGSize(width: 9, height: 6)) {
            []
        }
        XCTAssertNotNil(next)
        XCTAssertFalse(thermal.isCurrent(admitted))
    }

    func testFitFillZoomAndOffsetPreserveSourceCoordinates() {
        let rect = CGRect(x: 100, y: 200, width: 300, height: 300)
        let fit = MonitorVideoBackdropSource.fittedFrame(aspect: 2, in: rect)
        XCTAssertEqual(fit, CGRect(x: 100, y: 275, width: 300, height: 150))
        let fill = MonitorVideoBackdropSource.fittedFrame(aspect: 2, in: rect, fill: true)
        XCTAssertEqual(fill, CGRect(x: -50, y: 200, width: 600, height: 300))
        let zoom = MonitorVideoBackdropSource.fittedFrame(
            aspect: 2, in: rect, zoom: 2, offset: CGSize(width: 20, height: -10))
        XCTAssertEqual(zoom, CGRect(x: -30, y: 190, width: 600, height: 300))
        var effects = LiveImageEffects()
        effects.desqueezeFactor = 2
        let stretched = MonitorVideoBackdropSource.displayedFrame(
            sourceAspect: 2, effects: effects, in: rect, fill: true)
        XCTAssertEqual(
            stretched, CGRect(x: -50, y: 275, width: 600, height: 150),
            "De-squeeze fits inside the existing native host after its source fill")
        let unstretchedHost = MonitorVideoBackdropSource.displayedFrame(
            sourceAspect: 2, effects: effects, in: rect)
        XCTAssertEqual(unstretchedHost, CGRect(x: 100, y: 312.5, width: 300, height: 75))
    }
}
