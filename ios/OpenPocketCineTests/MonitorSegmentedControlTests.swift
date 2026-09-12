import SwiftUI
import XCTest

@testable import MonitorUI

@MainActor
final class MonitorSegmentedControlTests: XCTestCase {
    func testDeferredRowsCanBeMaterializedOffMainActor() async {
        let state = SegmentedSelectionProbe()
        let control = MonitorSegmentedControl(
            options: ["Waveform", "False Color", "Peaking"],
            selection: Binding(
                get: {
                    MainActor.assertIsolated()
                    state.reads += 1
                    return state.selection
                },
                set: {
                    MainActor.assertIsolated()
                    state.selection = $0
                }),
            title: {
                MainActor.assertIsolated()
                state.labels += 1
                return $0
            },
            onSelectionFeedback: { state.feedback += 1 })
        let rows = DeferredSegmentRows(control.rows)
        let readsBeforeRender = state.reads
        let labelsBeforeRender = state.labels
        // Changing the native source after body evaluation must not make a
        // background render read its live Binding or title closure.
        state.selection = "Peaking"
        let values = await Task.detached {
            precondition(!Thread.isMainThread)
            return rows.materialize()
        }.value
        XCTAssertEqual(values.map(\.title), ["Waveform", "False Color", "Peaking"])
        XCTAssertEqual(values.map(\.active), [true, false, false])
        XCTAssertEqual(state.selection, "Peaking")
        XCTAssertEqual(state.reads, readsBeforeRender)
        XCTAssertEqual(state.labels, labelsBeforeRender)
        XCTAssertEqual(state.feedback, 0, "Rendering must never dispatch a selection")

        let refreshedRows = control.rows
        XCTAssertEqual(refreshedRows.data.map { $0.content.active }, [false, false, true])
        let falseColor = refreshedRows.content(refreshedRows.data[1])
        falseColor.action()
        falseColor.action()
        XCTAssertEqual(state.selection, "False Color")
        XCTAssertEqual(state.feedback, 1, "Only the first changed selection emits feedback")
    }
}

@MainActor
private final class SegmentedSelectionProbe {
    var selection = "Waveform"
    var reads = 0
    var labels = 0
    var feedback = 0
}

private struct SegmentRenderValue: Sendable {
    let title: String
    let active: Bool
}

/// SwiftUI itself transfers its non-Sendable ForEach collection to AsyncRenderer.
/// This test bridge reproduces only that boundary; no View body or action is run.
private final class DeferredSegmentRows: @unchecked Sendable {
    let rows:
        ForEach<[MonitorRowSnapshot<String, MonitorSegmentButton>], String, MonitorSegmentButton>

    init(
        _ rows: ForEach<
            [MonitorRowSnapshot<String, MonitorSegmentButton>], String, MonitorSegmentButton
        >
    ) {
        self.rows = rows
    }

    func materialize() -> [SegmentRenderValue] {
        rows.data.map { option in
            let row = rows.content(option)
            return SegmentRenderValue(title: row.title, active: row.active)
        }
    }
}
