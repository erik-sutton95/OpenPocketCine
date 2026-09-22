import Observation
import SwiftUI
import XCTest

@testable import OpenPocketCine

@MainActor
final class MotionControlDragInvalidationTests: XCTestCase {
    func testActionGuardBlocksDraggingAndTheReleaseTapWithoutARefreshTimer() {
        XCTAssertTrue(MotionControlInteraction().allowsInteraction(at: 10))
        XCTAssertFalse(MotionControlInteraction(isDragging: true).allowsInteraction(at: 10))
        let released = MotionControlInteraction(blockedUntil: 10.15)
        XCTAssertFalse(released.allowsInteraction(at: 10.14))
        XCTAssertTrue(released.allowsInteraction(at: 10.15))
        XCTAssertTrue(released.allowsInteraction(at: 10.30))
    }

    func testMovingTheWindowDoesNotReevaluateControlsThatReadItsActionGuard() async throws {
        let input = MotionDragInput()
        let recorder = MotionDragRecorder()
        let host = UIHostingController(
            rootView: MotionDragFixture(input: input, recorder: recorder))
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await settle(host.view)
        // Complete the host's initial measurement and binding propagation before
        // measuring repeated translation of the retained control subtree.
        input.center = CGPoint(x: 200, y: 200)
        try await settle(host.view)
        let native = try XCTUnwrap(recorder.native)
        let initial = native.convert(native.bounds, to: host.view)
        let evaluations = recorder.evaluations
        XCTAssertGreaterThan(evaluations, 0)

        // Exercise the real floating modifier's placement updates. The content
        // consumes the same environment guard as the full Motion Control editor.
        for step in 1...8 {
            input.center = CGPoint(x: 200 + step * 6, y: 200 + step * 9)
            try await settle(host.view)
        }
        let moved = native.convert(native.bounds, to: host.view)
        XCTAssertEqual(moved.midX - initial.midX, 48, accuracy: 1)
        XCTAssertEqual(moved.midY - initial.midY, 72, accuracy: 1)
        XCTAssertTrue(recorder.native === native)
        XCTAssertEqual(
            recorder.evaluations, evaluations,
            "Translation must not rebuild the controls through a new action-guard environment value"
        )
    }

    private func settle(_ view: UIView) async throws {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        view.layoutIfNeeded()
    }
}

@MainActor
@Observable
private final class MotionDragInput {
    var center: CGPoint? = CGPoint(x: 190, y: 190)
}

@MainActor
private final class MotionDragRecorder {
    var evaluations = 0
    var native: UIView?
}

private struct MotionDragFixture: View {
    let input: MotionDragInput
    let recorder: MotionDragRecorder

    var body: some View {
        MotionDragGuardConsumer(recorder: recorder)
            .modifier(
                LiveGimbalFloatMove(
                    stored: Binding(get: { input.center }, set: { input.center = $0 }),
                    sizeHint: CGSize(width: 120, height: 80),
                    bounds: CGRect(x: 0, y: 0, width: 400, height: 800),
                    viewport: CGSize(width: 400, height: 800))
            )
            .frame(width: 400, height: 800)
    }
}

private struct MotionDragGuardConsumer: View {
    @Environment(\.motionControlCanInteract) private var canInteract
    let recorder: MotionDragRecorder

    var body: some View {
        recorder.evaluations += 1
        return MotionDragNativeProbe(recorder: recorder)
            .frame(width: 120, height: 80)
            .onTapGesture { _ = canInteract() }
    }
}

private struct MotionDragNativeProbe: UIViewRepresentable {
    let recorder: MotionDragRecorder
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        recorder.native = view
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
