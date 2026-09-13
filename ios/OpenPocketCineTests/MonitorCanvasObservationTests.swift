import MonitorPresentation
import MonitorUI
import Observation
import SwiftUI
import XCTest

@MainActor
final class MonitorCanvasObservationTests: XCTestCase {
    func testTelemetryReevaluatesOnlyItsSlotWithoutInvalidatingTheGeometryOwner() async throws {
        let inputs = CanvasInputs()
        let recorder = CanvasRecorder()
        let host = UIHostingController(rootView: CanvasFixture(inputs: inputs, recorder: recorder))
        let window = mount(host)
        defer { unmount(window) }
        try await settle(host.view)
        try assertMounted(recorder)
        let identities = recorder.views.mapValues(ObjectIdentifier.init)

        // Reads occur in the supplied builders, not a further child body. The
        // old eager initializer therefore subscribes CanvasFixture to all three.
        for slot in CanvasSlot.allCases {
            for value in [1, 2] {
                let parentCount = recorder.parentEvaluations
                let counts = recorder.evaluations
                inputs.setTelemetry(value, for: slot)
                try await settle(host.view)

                XCTAssertEqual(recorder.parentEvaluations, parentCount, "Geometry owner: \(slot)")
                XCTAssertGreaterThan(
                    recorder.evaluations[slot, default: 0], counts[slot, default: 0])
                XCTAssertEqual(recorder.values[slot], value, "Changed telemetry must reach UIKit")
                for other in CanvasSlot.allCases where other != slot {
                    XCTAssertEqual(
                        recorder.evaluations[other], counts[other], "Sibling: \(other)")
                }
                XCTAssertEqual(recorder.views.mapValues(ObjectIdentifier.init), identities)
                XCTAssertTrue(recorder.dismantles.isEmpty)
                XCTAssertTrue(recorder.makes.values.allSatisfy { $0 == 1 })
            }
        }
    }

    func testGeometryAndFreshClosureCapturesPropagateWithoutRemountingCoveredSlots() async throws {
        let inputs = CanvasInputs()
        let recorder = CanvasRecorder()
        let host = UIHostingController(rootView: CanvasFixture(inputs: inputs, recorder: recorder))
        let window = mount(host)
        defer { unmount(window) }
        try await settle(host.view)
        try assertMounted(recorder)
        let identities = recorder.views.mapValues(ObjectIdentifier.init)

        let layouts = [
            FieldMonitorLayout(width: 800, height: 400),
            FieldMonitorLayout(width: 400, height: 800, fill: true),
            FieldMonitorLayout(width: 400, height: 800, sourceAspect: 9 / 16),
            FieldMonitorLayout(width: 400, height: 800),
        ]
        for (index, layout) in layouts.enumerated() {
            let parentCount = recorder.parentEvaluations
            inputs.covered = index.isMultiple(of: 2)
            inputs.aspect = index == 2 ? 9 / 16 : 16 / 9
            inputs.layout = layout
            try await settle(host.view)

            XCTAssertGreaterThan(recorder.parentEvaluations, parentCount)
            let chrome = try XCTUnwrap(recorder.views[.chrome])
            let expectedWidth =
                layout.portrait && layout.fillsPicture && inputs.aspect >= 1
                ? layout.picture.height * inputs.aspect : layout.picture.width
            for slot in [CanvasSlot.picture, .assists] {
                let view = try XCTUnwrap(recorder.views[slot])
                XCTAssertEqual(view.bounds.width, expectedWidth, accuracy: 0.5)
                XCTAssertEqual(view.bounds.height, layout.picture.height, accuracy: 0.5)
                let frame = view.convert(view.bounds, to: chrome)
                XCTAssertEqual(frame.midX, layout.picture.midX, accuracy: 0.5)
                XCTAssertEqual(frame.midY, layout.picture.midY, accuracy: 0.5)
            }
            XCTAssertEqual(chrome.bounds.width, layout.viewport.width, accuracy: 0.5)
            XCTAssertEqual(chrome.bounds.height, layout.viewport.height, accuracy: 0.5)
            for slot in CanvasSlot.allCases {
                XCTAssertEqual(recorder.capturedLayouts[slot], layout, "Stale capture: \(slot)")
            }
            XCTAssertEqual(recorder.views.mapValues(ObjectIdentifier.init), identities)
            XCTAssertTrue(recorder.dismantles.isEmpty)
            XCTAssertTrue(recorder.makes.values.allSatisfy { $0 == 1 })
        }

        // The graph must remain subscribed after replacing the parent closures.
        inputs.chrome = 42
        try await settle(host.view)
        XCTAssertEqual(recorder.values[.chrome], 42)
        XCTAssertEqual(recorder.views.mapValues(ObjectIdentifier.init), identities)
    }

    private func mount(_ host: UIHostingController<CanvasFixture>) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        return window
    }

    private func unmount(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }

    private func settle(_ view: UIView) async throws {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        view.layoutIfNeeded()
    }

    private func assertMounted(_ recorder: CanvasRecorder) throws {
        XCTAssertGreaterThan(recorder.parentEvaluations, 0)
        for slot in CanvasSlot.allCases {
            _ = try XCTUnwrap(recorder.views[slot])
            XCTAssertEqual(recorder.makes[slot], 1)
            XCTAssertGreaterThan(recorder.evaluations[slot, default: 0], 0)
            XCTAssertEqual(recorder.values[slot], 0)
        }
    }
}

private enum CanvasSlot: CaseIterable {
    case picture
    case assists
    case chrome
}

@MainActor
@Observable
private final class CanvasInputs {
    var picture = 0
    var assists = 0
    var chrome = 0
    var layout = FieldMonitorLayout(width: 400, height: 800)
    var aspect = 16.0 / 9
    var covered = false

    func setTelemetry(_ value: Int, for slot: CanvasSlot) {
        switch slot {
        case .picture: picture = value
        case .assists: assists = value
        case .chrome: chrome = value
        }
    }
}

// Deliberately not observable: recording a body evaluation must not invalidate
// the graph being measured or add dependencies to its observation scope.
@MainActor
private final class CanvasRecorder {
    var parentEvaluations = 0
    var evaluations: [CanvasSlot: Int] = [:]
    var makes: [CanvasSlot: Int] = [:]
    var dismantles: [CanvasSlot: Int] = [:]
    var values: [CanvasSlot: Int] = [:]
    var capturedLayouts: [CanvasSlot: FieldMonitorLayout] = [:]
    var views: [CanvasSlot: UIView] = [:]

    func content(_ slot: CanvasSlot, value: Int, layout: FieldMonitorLayout) -> CanvasNativeProbe {
        evaluations[slot, default: 0] += 1
        return CanvasNativeProbe(slot: slot, value: value, layout: layout, recorder: self)
    }
}

private struct CanvasFixture: View {
    let inputs: CanvasInputs
    let recorder: CanvasRecorder

    var body: some View {
        recorder.parentEvaluations += 1
        let layout = inputs.layout
        return MonitorCanvas(layout: layout, sourceAspect: inputs.aspect) {
            recorder.content(.picture, value: inputs.picture, layout: layout)
        } assists: {
            recorder.content(.assists, value: inputs.assists, layout: layout)
        } chrome: {
            recorder.content(.chrome, value: inputs.chrome, layout: layout)
        }
        .monitorPresentationVisibility(!inputs.covered)
    }
}

private struct CanvasNativeProbe: UIViewRepresentable {
    let slot: CanvasSlot
    let value: Int
    let layout: FieldMonitorLayout
    let recorder: CanvasRecorder

    func makeCoordinator() -> Coordinator {
        Coordinator(slot: slot, recorder: recorder)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        recorder.makes[slot, default: 0] += 1
        recorder.views[slot] = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        recorder.values[slot] = value
        recorder.capturedLayouts[slot] = layout
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.recorder.dismantles[coordinator.slot, default: 0] += 1
    }

    @MainActor
    final class Coordinator {
        let slot: CanvasSlot
        let recorder: CanvasRecorder

        init(slot: CanvasSlot, recorder: CanvasRecorder) {
            self.slot = slot
            self.recorder = recorder
        }
    }
}
