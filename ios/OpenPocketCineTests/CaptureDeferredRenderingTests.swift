import MonitorPresentation
import SwiftUI
import XCTest

@testable import MonitorUI

final class CaptureDeferredRenderingTests: XCTestCase {
    @MainActor func testCaptureTabsKeepLabelsWhenCameraModesShrinkBeforeRendering() {
        var labels = ["Speed", "Angle"]
        let tabs = MonitorCaptureTabs(
            options: Array(labels.indices), selection: 1,
            title: { labels[$0] }, select: { _ in })
        // Camera telemetry can remove these modes between the parent's body and
        // SwiftUI's later evaluation of the child. Indices belong to that snapshot.
        labels = []
        XCTAssertEqual(tabs.rows.data.map(\.title), ["Speed", "Angle"])
    }

    @MainActor func testCaptureTabsRenderFrozenLabelsAndSelectionOffMainActor() async {
        let probe = Probe()
        let tabs = MonitorCaptureTabs(
            options: ["Auto", "Manual"], selection: "Manual",
            title: { option in
                MainActor.assertIsolated()
                probe.labelCalls += 1
                return "\(probe.prefix)\(option)"
            },
            select: { _ in probe.actionCalls += 1 })
        let rows = SendableRenderBox(tabs.rows)
        XCTAssertEqual(probe.labelCalls, 2)
        probe.prefix = "Changed "
        let rendered = await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return rows.value.data.map { item in
                let button = rows.value.content(item)
                return (button.row.title, button.row.selected)
            }
        }.value
        XCTAssertEqual(rendered.map(\.0), ["Auto", "Manual"])
        XCTAssertEqual(rendered.map(\.1), [false, true])
        XCTAssertEqual(
            probe.labelCalls, 2, "Deferred rendering must never call the host projection")
        XCTAssertEqual(probe.actionCalls, 0)
    }

    @MainActor func testDrumRowsCanMaterializeOffMainWithoutInvokingCameraActions() async {
        let probe = Probe()
        let metrics = MonitorDrumMetrics(options: ["AF-S", "AF-C", "Showcase"])
        let snapshot = [
            MonitorDrumRow(
                option: "AF-S", distance: -1, selected: false, marked: false,
                metrics: metrics, action: { probe.actionCalls += 1 }),
            MonitorDrumRow(
                option: "AF-C", distance: 0, selected: true, marked: false,
                metrics: metrics, action: { probe.actionCalls += 1 }),
        ]
        let rows = SendableRenderBox(MonitorValueDrum.renderRows(snapshot, width: 452))
        let rendered = await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return rows.value.data.map { item in
                let cell = rows.value.content(item)
                return (cell.row.option, cell.row.selected, cell.row.distance, cell.canvasWidth)
            }
        }.value
        XCTAssertEqual(rendered.map(\.0), ["AF-S", "AF-C"])
        XCTAssertEqual(rendered.map(\.1), [false, true])
        XCTAssertEqual(rendered.map(\.2), [-1, 0])
        XCTAssertEqual(rendered.map(\.3), [452, 452])
        XCTAssertEqual(probe.actionCalls, 0)
    }

    @MainActor private final class Probe {
        var prefix = ""
        var labelCalls = 0
        var actionCalls = 0
    }
}

/// SwiftUI's render container is not Sendable, but the renderer deliberately
/// materializes its content off-main. Only these immutable test snapshots cross.
private final class SendableRenderBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
