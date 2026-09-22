import MonitorUI
import SwiftUI
import XCTest

@MainActor
final class MonitorMotionInputTests: XCTestCase {
    func testExpandedBackdropKeepsOriginalStickAndZoomTargetsAndPanelPriority() async throws {
        let stick = UIView()
        stick.backgroundColor = .blue
        let zoom = UIView()
        zoom.backgroundColor = .green
        let panel = UIView()
        panel.backgroundColor = .red
        let joystickBounds = CGRect(x: 250, y: 250, width: 100, height: 100)
        let zoomBounds = CGRect(x: 250, y: 180, width: 44, height: 44)
        let host = UIHostingController(
            rootView:
                ZStack(alignment: .topLeading) {
                    MotionNativeTarget(view: stick)
                        .frame(width: 100, height: 100).offset(x: 250, y: 250)
                    MotionNativeTarget(view: zoom)
                        .frame(width: 44, height: 44).offset(x: 250, y: 180)
                    MonitorMotionDismissBackdrop(excluding: [joystickBounds, zoomBounds]) {}
                    // An editor overlapping the upper stick edge must retain input.
                    MotionNativeTarget(view: panel)
                        .frame(width: 180, height: 80).offset(x: 150, y: 220)
                }.frame(width: 400, height: 400)
        )
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()

        let stickPoint = stick.convert(CGPoint(x: 50, y: 80), to: host.view)
        let stickHit = try XCTUnwrap(host.view.hitTest(stickPoint, with: nil))
        XCTAssertTrue(
            stickHit === stick || stickHit.isDescendant(of: stick),
            "The expanded backdrop must let the original stick receive pointer down")
        let zoomPoint = zoom.convert(CGPoint(x: 22, y: 22), to: host.view)
        let zoomHit = try XCTUnwrap(host.view.hitTest(zoomPoint, with: nil))
        XCTAssertTrue(
            zoomHit === zoom || zoomHit.isDescendant(of: zoom),
            "The original zoom chip must receive tap, double-tap and hold pointer sequences")
        let overlap = panel.convert(CGPoint(x: 150, y: 50), to: host.view)
        let panelHit = try XCTUnwrap(host.view.hitTest(overlap, with: nil))
        XCTAssertTrue(
            panelHit === panel || panelHit.isDescendant(of: panel),
            "The floating panel must win where it covers the joystick")
        let outsideHit = try XCTUnwrap(host.view.hitTest(CGPoint(x: 30, y: 30), with: nil))
        XCTAssertFalse(outsideHit === stick || outsideHit.isDescendant(of: stick))
        XCTAssertFalse(outsideHit === zoom || outsideHit.isDescendant(of: zoom))
    }
}

private struct MotionNativeTarget: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
