import SwiftUI
import XCTest

@testable import OpenPocketCine

/// What VoiceOver reaches on the live screen, read from the hosting view's accessibility
/// elements. XCUITest also inventories hidden controls, so it cannot show this.
@MainActor
final class LiveChromeAccessibilityTests: XCTestCase {
    private static let chrome: Set<String> = [
        "monitor.system.lock", "monitor.system.settings", "monitor.system.media",
        "monitor.system.record", "monitor.system.display", "monitor.system.zoom",
        "monitor.capture.iso", "monitor.capture.shutter",
    ]

    func testControlsOutOfSightStayOutOfTheAccessibilityTree() async throws {
        setenv("OPV_UI_REVIEW_SCREEN", "live", 1)
        setenv("OPV_UI_REVIEW_COMMON_CONTROLS", "1", 1)
        defer {
            unsetenv("OPV_UI_REVIEW_SCREEN")
            unsetenv("OPV_UI_REVIEW_COMMON_CONTROLS")
        }
        let model = AppModel()
        model.prepareStartup()
        // A window outside the app's scene reports no active phase; the zoom dial (like the
        // app's scene) only takes input, and AX, while active.
        let host = UIHostingController(
            rootView: LiveViewScreen().environment(model).environment(\.scenePhase, .active))
        host.safeAreaRegions = []
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first {
                $0.activationState == .foregroundActive
            })
        let originalKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            window.isHidden = true
            window.rootViewController = nil
            model.session.disconnect()
            originalKeyWindow?.makeKeyAndVisible()
        }

        try await settle(host.view)
        let live = try exposed(host.view)
        XCTAssertTrue(Self.chrome.isSubset(of: live), "Live: \(live.sorted())")
        // The palette handle is its own element (its glyph hides itself). Under the zoom dial
        // the palette stays reachable, dimmed, as on main.
        XCTAssertTrue(live.contains("monitor.assists.expand"), "Live: \(live.sorted())")

        // An open picker hides the zoom chip beneath it; the chip hides itself. (The readout
        // opens through its own gesture, so the test sets the state a tap sets.)
        model.captureSheet = .iso
        try await settle(host.view)
        let picker = try exposed(host.view)
        XCTAssertTrue(picker.contains("monitor.capture.close"), "Picker: \(picker.sorted())")
        XCTAssertFalse(picker.contains("monitor.system.zoom"), "Picker: \(picker.sorted())")
        model.captureSheet = nil
        try await settle(host.view)

        // The zoom dial: the dimmed chrome beneath it is out of reach.
        let zoom = try element("monitor.system.zoom", in: host.view)
        let continuous = try XCTUnwrap(
            zoom.accessibilityCustomActions?.first { $0.name == "Continuous zoom" })
        XCTAssertTrue(continuous.actionHandler?(continuous) ?? false)
        try await settle(host.view)
        let dial = try exposed(host.view)
        XCTAssertTrue(dial.contains("monitor.zoom.dial"), "Dial: \(dial.sorted())")
        XCTAssertTrue(dial.isDisjoint(with: Self.chrome), "Dial: \(dial.sorted())")
        XCTAssertFalse(dial.contains { $0.hasPrefix("monitor.telemetry.") }, "Dial: \(dial.sorted())")
        let close = try XCTUnwrap(Self.nodes(host.view).first { $0.accessibilityLabel == "Close zoom dial" })
        XCTAssertTrue(close.accessibilityActivate())
        try await settle(host.view)

        // A covering page.
        model.shell.open(.settings)
        try await settle(host.view)
        let covered = try exposed(host.view)
        XCTAssertTrue(covered.isDisjoint(with: live), "Covered: \(covered.sorted())")
    }

    private func settle(_ view: UIView) async throws {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        view.layoutIfNeeded()
    }

    private func exposed(_ view: UIView) throws -> Set<String> {
        let ids = Set(Self.nodes(view).compactMap(Self.identifier))
        try XCTSkipIf(ids.isEmpty, "No accessibility tree: enable app accessibility")
        return ids
    }

    private func element(_ id: String, in view: UIView) throws -> NSObject {
        try XCTUnwrap(Self.nodes(view).first { Self.identifier($0) == id }, id)
    }

    /// The VoiceOver walk: SwiftUI vends nodes through `accessibilityElements`, a plain view
    /// its subviews, and an element stops the walk. Hidden subtrees are skipped. Containers
    /// count too: Record and the zoom dial carry their identifiers on one.
    private static func nodes(_ object: NSObject) -> [NSObject] {
        if object.accessibilityElementsHidden { return [] }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return [] }
        if object.isAccessibilityElement { return [object] }
        if let elements = object.accessibilityElements as? [NSObject], !elements.isEmpty {
            return [object] + elements.flatMap(nodes)
        }
        return [object] + ((object as? UIView)?.subviews ?? []).flatMap(nodes)
    }

    private static func identifier(_ object: NSObject) -> String? {
        let getter = NSSelectorFromString("accessibilityIdentifier")
        guard object.responds(to: getter),
            let id = object.perform(getter)?.takeUnretainedValue() as? String, id.hasPrefix("monitor.")
        else { return nil }
        return id
    }
}
