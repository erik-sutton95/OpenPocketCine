import Observation
import SwiftUI
import XCTest

@testable import MonitorUI

@MainActor
final class MonitorPresentationVisibilityTests: XCTestCase {
    func testCoverageStopsAndResumesTheMountedPulseWithoutRemountingItsHost() async throws {
        let probe = VisibilityProbe()
        let host = UIHostingController(rootView: VisibilityFixture(probe: probe))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 240, height: 160))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await settle(host.view)
        let running = try await isPulsing(probe, host.view)
        XCTAssertTrue(running)
        XCTAssertTrue(probe.inheritedVisibility)
        XCTAssertEqual(probe.appearances, 1)
        let identity = probe.hostIdentity

        probe.visible = false
        try await settle(host.view)
        XCTAssertEqual(probe.phase, 0)
        XCTAssertFalse(
            probe.inheritedVisibility, "A child cannot override covered parent visibility")
        XCTAssertEqual(probe.pageAppearances, 1, "The sibling page remains mounted")
        XCTAssertEqual(probe.pageDisappearances, 0)
        let stoppedCount = probe.pulseChanges
        try await settle(host.view)
        XCTAssertEqual(probe.pulseChanges, stoppedCount, "The covered pulse remains stopped")

        probe.visible = true
        try await settle(host.view)
        let resumed = try await isPulsing(probe, host.view)
        XCTAssertTrue(resumed)
        XCTAssertEqual(probe.hostIdentity, identity)
        XCTAssertEqual(probe.appearances, 1)
        XCTAssertEqual(probe.disappearances, 0)
        XCTAssertEqual(probe.pageAppearances, 1)

        probe.scene = .inactive
        try await settle(host.view)
        XCTAssertEqual(probe.phase, 0)
        let inactive = try await isPulsing(probe, host.view)
        XCTAssertFalse(inactive)
        probe.scene = .active
        try await settle(host.view)
        let active = try await isPulsing(probe, host.view)
        XCTAssertTrue(active)

        // Recording can stop while the control is covered; reveal must not
        // restart its decorative glow until recording starts again.
        probe.visible = false
        probe.enabled = false
        try await settle(host.view)
        probe.visible = true
        try await settle(host.view)
        XCTAssertEqual(probe.phase, 0)
        let disabled = try await isPulsing(probe, host.view)
        XCTAssertFalse(disabled)
        probe.enabled = true
        try await settle(host.view)
        let enabled = try await isPulsing(probe, host.view)
        XCTAssertTrue(enabled)
        XCTAssertEqual(probe.appearances, 1)

        probe.mounted = false
        try await settle(host.view)
        let unmounted = try await isPulsing(probe, host.view)
        XCTAssertFalse(unmounted, "Disappearance stops the timeline")
        XCTAssertEqual(probe.disappearances, 1)
    }

    func testCoveredContentIsTransparentWhileSiblingPageIsUnaffected() throws {
        for visible in [true, false] {
            let renderer = ImageRenderer(
                content: HStack(spacing: 0) {
                    Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 20, height: 20)
                        .monitorPresentationVisibility(true)
                        .monitorPresentationVisibility(visible)
                    Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 20, height: 20)
                }
                .background(Color.white))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            var pixels = [UInt8](repeating: 0, count: 40 * 20 * 4)
            let context = try XCTUnwrap(
                CGContext(
                    data: &pixels, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 40 * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 40, height: 20))
            let live = (10 * 40 + 10) * 4
            let page = (10 * 40 + 30) * 4
            XCTAssertEqual(
                Array(pixels[live..<(live + 3)]), visible ? [255, 0, 0] : [255, 255, 255])
            XCTAssertEqual(Array(pixels[page..<(page + 3)]), [0, 0, 255])
        }
    }

    func testVisibilityPreservesControlOrderingAboveLaterPopupSiblings() throws {
        for visible in [true, false] {
            let renderer = ImageRenderer(
                content: ZStack {
                    // Match the live Record layer: its ordering is established
                    // before presentation visibility, and the popup comes later.
                    Color(.sRGB, red: 1, green: 0, blue: 0)
                        .zIndex(11)
                        .monitorPresentationVisibility(visible)
                    Color(.sRGB, red: 0, green: 0, blue: 1)
                        .zIndex(10)
                        .monitorPresentationVisibility(true)
                }
                .frame(width: 20, height: 20))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            var pixels = [UInt8](repeating: 0, count: 20 * 20 * 4)
            let context = try XCTUnwrap(
                CGContext(
                    data: &pixels, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 20 * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 20, height: 20))
            let center = (10 * 20 + 10) * 4
            XCTAssertEqual(
                Array(pixels[center..<(center + 3)]), visible ? [255, 0, 0] : [0, 0, 255],
                "Visible Record must stay above the later popup; coverage reveals that popup")
        }
    }

    /// A running pulse keeps changing phase on its 30 Hz timeline; a stopped
    /// one rests at phase 0 without further updates.
    /// Polls up to a second so a loaded host cannot miss the next 30 Hz step.
    private func isPulsing(_ probe: VisibilityProbe, _ view: UIView) async throws -> Bool {
        let before = probe.pulseChanges
        for _ in 0..<10 {
            try await settle(view)
            if probe.pulseChanges > before + 1 { return true }
        }
        return false
    }

    func testPulsePhaseIsAnEasedTriangle() {
        typealias Pulse = MonitorDecorativePulse<EmptyView>
        XCTAssertEqual(Pulse.phase(0, period: 1.6), 0, accuracy: 1e-9)
        XCTAssertEqual(Pulse.phase(0.8, period: 1.6), 1, accuracy: 1e-9)
        XCTAssertEqual(Pulse.phase(1.6, period: 1.6), 0, accuracy: 1e-9)
        XCTAssertEqual(Pulse.phase(0.4, period: 1.6), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Pulse.phase(0.2, period: 1.6), Pulse.phase(1.4, period: 1.6), accuracy: 1e-9)
        XCTAssertEqual(Pulse.phase(1, period: 0), 0)
    }

    private func settle(_ view: UIView) async throws {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
    }
}

@MainActor
@Observable
private final class VisibilityProbe {
    var visible = true
    var enabled = true
    var mounted = true
    var scene = ScenePhase.active
    var phase = 0.0
    var inheritedVisibility = true
    var appearances = 0
    var disappearances = 0
    var pageAppearances = 0
    var pageDisappearances = 0
    var hostIdentity: UUID?
    var pulseChanges = 0
}

private struct VisibilityFixture: View {
    @Bindable var probe: VisibilityProbe

    var body: some View {
        ZStack {
            if probe.mounted {
                VisibilityPulseHost(probe: probe)
                    .monitorPresentationVisibility(true)
                    .monitorPresentationVisibility(probe.visible)
            }
            Text("Opaque page owner")
                .onAppear { probe.pageAppearances += 1 }
                .onDisappear { probe.pageDisappearances += 1 }
        }
        .environment(\.scenePhase, probe.scene)
    }
}

private struct VisibilityPulseHost: View {
    @Bindable var probe: VisibilityProbe
    @Environment(\.monitorPresentationIsVisible) private var visible
    @State private var identity = UUID()

    var body: some View {
        MonitorDecorativePulse(period: 0.4, enabled: probe.enabled) { phase in
            Color.red
                .frame(width: 40, height: 40)
                .opacity(1 - 0.75 * phase)
                .onChange(of: phase) { _, value in
                    probe.phase = value
                    probe.pulseChanges += 1
                }
        }
            .onChange(of: visible, initial: true) { _, value in probe.inheritedVisibility = value }
            .onAppear {
                probe.appearances += 1
                probe.hostIdentity = identity
            }
            .onDisappear { probe.disappearances += 1 }
    }
}
