import MonitorPresentation
import SwiftUI
import XCTest

@testable import MonitorUI

@MainActor
final class CameraDeferredRenderingTests: XCTestCase {
    func testLazyCatalogMaterializesAnIndividualCardOffMainWithoutNativeActions() async {
        let probe = CameraRenderProbe()
        let items = (0..<10_000).map { index in
            CameraListItem(
                id: String(index), name: "Camera \(index)", subtitle: "Saved",
                status: "Ready", actionTitle: "Connect")
        }
        let actions = CameraCatalogActions(
            activate: { item in
                MainActor.assertIsolated()
                probe.selectedID = item.id
            }, cancel: { probe.cancelled = true }, rename: nil, remove: nil)
        let rows = CameraRenderBox(
            CameraCatalogRows.make(items, saved: true, busy: false, actions: actions))
        let value = await Task.detached {
            precondition(!Thread.isMainThread)
            // The production collection retains data, not 10,000 eagerly built
            // cards. Only the row requested by the lazy grid is materialized.
            let last = rows.value.content(rows.value.data[9_999])
            return (last.item.id, last.saved, last.busy, rows.value.data.count)
        }.value
        XCTAssertEqual(value.0, "9999")
        XCTAssertTrue(value.1)
        XCTAssertFalse(value.2)
        XCTAssertEqual(value.3, 10_000)
        XCTAssertNil(probe.selectedID)
        XCTAssertFalse(probe.cancelled)
        rows.value.content(items[9_999]).actions.activate(items[9_999])
        XCTAssertEqual(probe.selectedID, "9999")
    }

    func testDiscoveredCameraRowsKeepSelectionOnTheMainActor() async {
        let probe = CameraRenderProbe()
        let devices = [
            CameraListItem(
                id: "camera", name: "Pocket", subtitle: "Nearby",
                status: "Ready", actionTitle: "Pair", isBusy: true)
        ]
        let rows = CameraRenderBox(
            CameraPairingDeviceRows.make(devices) { id in
                MainActor.assertIsolated()
                probe.selectedID = id
            })
        let value = await Task.detached {
            precondition(!Thread.isMainThread)
            let row = rows.value.content(rows.value.data[0])
            return (row.device.id, row.device.isBusy)
        }.value
        XCTAssertEqual(value.0, "camera")
        XCTAssertTrue(value.1)
        XCTAssertNil(probe.selectedID)
    }

    func testZoomCanvasUsesFrozenNativeLabelsAndValue() async {
        let probe = CameraRenderProbe()
        let dial = MonitorZoomDial(
            viewport: CGSize(width: 874, height: 402),
            scale: MonitorZoomScale(minimum: 1, maximum: 4), marks: [0.5, 1, 2, 4, 8],
            value: Binding(
                get: {
                    MainActor.assertIsolated()
                    probe.valueReads += 1
                    return probe.zoom
                }, set: { _ in XCTFail("Drawing cannot write zoom") }),
            label: { value in
                MainActor.assertIsolated()
                probe.labelCalls += 1
                return "\(probe.prefix)\(value)"
            }, onEditing: { _ in XCTFail("Drawing cannot start an edit") }, onClose: {})
        let snapshot = dial.canvasSnapshot
        let reads = probe.valueReads
        XCTAssertEqual(probe.labelCalls, 3)
        probe.prefix = "New "
        probe.zoom = 4
        let result = await Task.detached {
            precondition(!Thread.isMainThread)
            _ = MonitorZoomDial.canvas(snapshot)
            return (snapshot.marks.map(\.label), snapshot.position)
        }.value
        XCTAssertEqual(result.0, ["1.0", "2.0", "4.0"])
        XCTAssertEqual(result.1, MonitorZoomScale(minimum: 1, maximum: 4).position(2))
        XCTAssertEqual(probe.valueReads, reads)
        XCTAssertEqual(probe.labelCalls, 3)
    }
}

@MainActor
private final class CameraRenderProbe {
    var selectedID: String?
    var cancelled = false
    var zoom = 2.0
    var prefix = ""
    var valueReads = 0
    var labelCalls = 0
}

/// Test-only transfer of SwiftUI's deferred collection, matching AsyncRenderer.
private final class CameraRenderBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
