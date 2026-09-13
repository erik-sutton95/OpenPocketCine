import MonitorUI
import Observation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class MonitorCardColumnsTests: XCTestCase {
    func testPlacementReusesIntrinsicProposalAndRemeasuresGrowingCards() async throws {
        let inputs = CardColumnsInputs()
        let trace = CardColumnsTrace()
        let native = CardColumnsNativeRegistry()
        let host = UIHostingController(
            rootView: CardColumnsFixture(inputs: inputs, trace: trace, native: native))
        let window = mount(host)
        defer { unmount(window) }
        try await settle(host.view)
        try assertGeometry(
            native, width: 700, height: 360,
            frames: [
                .first: CGRect(x: 0, y: 0, width: 345, height: 120),
                .second: CGRect(x: 355, y: 0, width: 345, height: 160),
                .banner: CGRect(x: 0, y: 170, width: 700, height: 50),
                .fourth: CGRect(x: 0, y: 230, width: 345, height: 100),
                .fifth: CGRect(x: 355, y: 230, width: 345, height: 130),
            ])
        assertIntrinsicProposals(trace, width: 700)
        let identities = native.views.mapValues(ObjectIdentifier.init)

        trace.clear()
        inputs.firstHeight = 180
        inputs.bannerHeight = 75
        try await settle(host.view)
        try assertGeometry(
            native, width: 700, height: 445,
            frames: [
                .first: CGRect(x: 0, y: 0, width: 345, height: 220),
                .second: CGRect(x: 355, y: 0, width: 345, height: 160),
                .banner: CGRect(x: 0, y: 230, width: 700, height: 75),
                .fourth: CGRect(x: 0, y: 315, width: 345, height: 100),
                .fifth: CGRect(x: 355, y: 315, width: 345, height: 130),
            ])
        // Unchanged siblings can reuse SwiftUI measurements; only the changed
        // cards must remeasure. All observed placement proposals must stay nil.
        assertIntrinsicProposals(trace, width: 700, measuredCards: [.first, .banner])
        XCTAssertEqual(native.views.mapValues(ObjectIdentifier.init), identities)
        XCTAssertTrue(native.dismantles.isEmpty)
    }

    func testRotationAndColumnThresholdPreserveFullWidthPlacementAndNativeIdentity() async throws {
        let inputs = CardColumnsInputs()
        let trace = CardColumnsTrace()
        let native = CardColumnsNativeRegistry()
        let host = UIHostingController(
            rootView: CardColumnsFixture(inputs: inputs, trace: trace, native: native))
        let window = mount(host)
        defer { unmount(window) }
        try await settle(host.view)
        let identities = native.views.mapValues(ObjectIdentifier.init)
        XCTAssertEqual(identities.count, 6)

        for width: CGFloat in [400, 559, 560, 700] {
            trace.clear()
            inputs.width = width
            try await settle(host.view)
            if width < 560 {
                try assertGeometry(
                    native, width: width, height: 440,
                    frames: [
                        .first: CGRect(x: 0, y: 0, width: width, height: 80),
                        .second: CGRect(x: 0, y: 90, width: width, height: 120),
                        .banner: CGRect(x: 0, y: 220, width: width, height: 50),
                        .fourth: CGRect(x: 0, y: 280, width: width, height: 60),
                        .fifth: CGRect(x: 0, y: 350, width: width, height: 90),
                    ])
            } else {
                let cardWidth = (width - 10) / 2
                try assertGeometry(
                    native, width: width, height: 360,
                    frames: [
                        .first: CGRect(x: 0, y: 0, width: cardWidth, height: 120),
                        .second: CGRect(x: cardWidth + 10, y: 0, width: cardWidth, height: 160),
                        .banner: CGRect(x: 0, y: 170, width: width, height: 50),
                        .fourth: CGRect(x: 0, y: 230, width: cardWidth, height: 100),
                        .fifth: CGRect(x: cardWidth + 10, y: 230, width: cardWidth, height: 130),
                    ])
            }
            // The framework may reuse a previously measured width on return.
            assertIntrinsicProposals(trace, width: width, measuredCards: [])
            XCTAssertEqual(native.views.mapValues(ObjectIdentifier.init), identities)
            XCTAssertTrue(native.makes.values.allSatisfy { $0 == 1 })
            XCTAssertTrue(native.dismantles.isEmpty)
        }
    }

    private func assertIntrinsicProposals(
        _ trace: CardColumnsTrace, width: CGFloat,
        measuredCards: Set<CardColumnsID> = Set(CardColumnsID.cards),
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let events = trace.snapshot()
        for id in CardColumnsID.cards {
            let measured = events.filter { $0.id == id && !$0.placement }
            let placed = events.filter { $0.id == id && $0.placement }
            if measuredCards.contains(id) {
                XCTAssertGreaterThan(
                    measured.count, 0, "No measurement: \(id)", file: file, line: line)
                XCTAssertGreaterThan(placed.count, 0, "No placement: \(id)", file: file, line: line)
            }
            let expectedWidth = id == .banner || width < 560 ? width : (width - 10) / 2
            for event in measured + placed {
                XCTAssertEqual(event.width, expectedWidth, "\(id)", file: file, line: line)
                XCTAssertNil(
                    event.height, "Second explicit-height proposal for \(id): \(event)",
                    file: file, line: line)
            }
        }
        XCTContext.runActivity(named: "Child proposal counts at width \(width)") { activity in
            let counts = CardColumnsID.cards.map { id in
                let measured = events.filter { $0.id == id && !$0.placement }
                let placed = events.filter { $0.id == id && $0.placement }
                let explicit = measured.filter { $0.height != nil }.count
                return "\(id): measurements=\(measured.count), explicitHeight=\(explicit), "
                    + "placements=\(placed.count)"
            }
            let attachment = XCTAttachment(string: counts.joined(separator: "\n"))
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    private func assertGeometry(
        _ native: CardColumnsNativeRegistry, width: CGFloat, height: CGFloat,
        frames: [CardColumnsID: CGRect], file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let container = try XCTUnwrap(native.views[.container], file: file, line: line)
        XCTAssertEqual(container.bounds.width, width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(container.bounds.height, height, accuracy: 0.5, file: file, line: line)
        for (id, expected) in frames {
            let view = try XCTUnwrap(native.views[id], file: file, line: line)
            let actual = view.convert(view.bounds, to: container)
            XCTAssertEqual(
                actual.minX, expected.minX, accuracy: 0.5, "\(id)", file: file, line: line)
            XCTAssertEqual(
                actual.minY, expected.minY, accuracy: 0.5, "\(id)", file: file, line: line)
            XCTAssertEqual(
                actual.width, expected.width, accuracy: 0.5, "\(id)", file: file, line: line)
            XCTAssertEqual(
                actual.height, expected.height, accuracy: 0.5, "\(id)", file: file, line: line)
        }
    }

    private func mount(_ host: UIHostingController<CardColumnsFixture>) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 900))
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
}

private enum CardColumnsID: String, Sendable {
    case first, second, banner, fourth, fifth, container
    static let cards: [Self] = [.first, .second, .banner, .fourth, .fifth]
}

@MainActor
@Observable
private final class CardColumnsInputs {
    var width: CGFloat = 700
    var firstHeight: CGFloat = 80
    var bannerHeight: CGFloat = 50
}

private struct CardColumnsFixture: View {
    let inputs: CardColumnsInputs
    let trace: CardColumnsTrace
    let native: CardColumnsNativeRegistry

    var body: some View {
        MonitorCardColumns {
            card(.first, height: inputs.firstHeight)
            card(.second, height: 120)
            card(.banner, height: inputs.bannerHeight).monitorFullWidthCard()
            card(.fourth, height: 60)
            card(.fifth, height: 90)
        }
        .frame(width: inputs.width)
        .background(CardColumnsNativeProbe(id: .container, registry: native))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func card(_ id: CardColumnsID, height: CGFloat) -> some View {
        CardColumnsChildLayout(id: id, naturalHeight: height, trace: trace) {
            CardColumnsNativeProbe(id: id, registry: native)
        }
    }
}

// Layout can be queried outside MainActor. Keep instrumentation synchronized and
// nonobservable so recording measurements cannot invalidate the measured graph.
private final class CardColumnsTrace: @unchecked Sendable {
    struct Event: Sendable {
        let id: CardColumnsID
        let width: CGFloat?
        let height: CGFloat?
        let placement: Bool
    }

    private let lock = NSLock()
    private var events: [Event] = []

    func record(_ id: CardColumnsID, _ proposal: ProposedViewSize, placement: Bool) {
        lock.lock()
        defer { lock.unlock() }
        events.append(
            Event(id: id, width: proposal.width, height: proposal.height, placement: placement))
    }

    func snapshot() -> [Event] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        events.removeAll()
    }
}

private struct CardColumnsChildLayout: Layout {
    let id: CardColumnsID
    let naturalHeight: CGFloat
    let trace: CardColumnsTrace

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        trace.record(id, proposal, placement: false)
        let width = proposal.width ?? 275
        // Model width-sensitive wrapping as well as changing card content. This
        // deliberately has no cache and does not mirror the columns algorithm.
        return CGSize(width: width, height: naturalHeight + (width < 400 ? 40 : 0))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        trace.record(id, proposal, placement: true)
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

@MainActor
private final class CardColumnsNativeRegistry {
    var views: [CardColumnsID: UIView] = [:]
    var makes: [CardColumnsID: Int] = [:]
    var dismantles: [CardColumnsID: Int] = [:]
}

private struct CardColumnsNativeProbe: UIViewRepresentable {
    let id: CardColumnsID
    let registry: CardColumnsNativeRegistry

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        registry.views[id] = view
        registry.makes[id, default: 0] += 1
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(id: id, registry: registry) }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.registry.dismantles[coordinator.id, default: 0] += 1
    }

    @MainActor
    final class Coordinator {
        let id: CardColumnsID
        let registry: CardColumnsNativeRegistry

        init(id: CardColumnsID, registry: CardColumnsNativeRegistry) {
            self.id = id
            self.registry = registry
        }
    }
}
