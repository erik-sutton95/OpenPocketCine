import MonitorPresentation
import MonitorUI
import Observation
import SwiftUI
import XCTest

@MainActor
final class CaptureReadoutLifecycleTests: XCTestCase {
    func testSharedReadoutNeverArmsWithoutTouchAndInvalidationRetiresPendingHostWork() async throws
    {
        let probe = ReadoutLifecycleProbe()
        let size = CGSize(width: 400, height: 200)
        let host = UIHostingController(rootView: ReadoutLifecycleCanvas(probe: probe))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertNil(probe.ownership.owner)
        XCTAssertTrue(probe.events.allSatisfy(\.isCancellation), "Mounting cannot open a picker")

        var count = probe.events.count
        probe.source += 1
        try await settle(host.view)
        XCTAssertGreaterThan(probe.events.count, count, "Source change must retire delayed work")
        count = probe.events.count
        probe.enabled = false
        try await settle(host.view)
        XCTAssertGreaterThan(probe.events.count, count, "Lock must retire delayed work")
        count = probe.events.count
        probe.geometry = MonitorWindowGeometry(size: CGSize(width: 200, height: 400))
        try await settle(host.view)
        XCTAssertGreaterThan(probe.events.count, count, "Rotation must retire delayed work")
        count = probe.events.count
        probe.scene = .inactive
        try await settle(host.view)
        XCTAssertGreaterThan(probe.events.count, count, "Scene inactivity must retire delayed work")
        count = probe.events.count
        probe.visible = false
        try await settle(host.view)
        XCTAssertGreaterThan(probe.events.count, count, "Disappearance must retire delayed work")
        XCTAssertTrue(probe.events.allSatisfy(\.isCancellation))
    }

    private func settle(_ view: UIView) async throws {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(60))
    }
}

@MainActor
@Observable
private final class ReadoutLifecycleProbe {
    var source = 1
    var enabled = true
    var visible = true
    var scene = ScenePhase.active
    var geometry = MonitorWindowGeometry(size: CGSize(width: 400, height: 200))
    var ownership = MonitorReadoutOwnership()
    var events: [MonitorReadoutEvent<Int>] = []
}

private struct ReadoutLifecycleCanvas: View {
    @Bindable var probe: ReadoutLifecycleProbe
    private let snapshot = MonitorReadoutSnapshot(
        title: "Temperature", options: ["5500K", "5600K", "5700K"], selection: "5600K")

    var body: some View {
        Group {
            if probe.visible {
                Text("5600K")
                    .modifier(
                        MonitorReadoutGesture(
                            snapshot: snapshot, sourceIdentity: probe.source,
                            isEnabled: probe.enabled, ownership: $probe.ownership,
                            presentationOwner: { nil }, onEvent: { probe.events.append($0) }))
            }
        }
        .environment(\.scenePhase, probe.scene)
        .environment(\.monitorWindowGeometry, probe.geometry)
    }
}

extension MonitorReadoutEvent {
    fileprivate var isCancellation: Bool {
        if case .cancel = self { return true }
        return false
    }
}
