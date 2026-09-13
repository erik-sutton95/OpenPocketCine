#if os(iOS)
    import MonitorPresentation
    import SwiftUI
    import UIKit

    /// Native input and scrolling for the shared lazy catalog. Geometry comes from
    /// mounted cell anchors, without publishing scroll offsets through SwiftUI.
    @MainActor final class MonitorMediaSelectionInteraction: NSObject, UIGestureRecognizerDelegate {
        private struct Anchor {
            let id: String
            weak var view: UIView?
        }

        // Old and new lazy layouts can coexist during a grid/list transition.
        // Retiring one view must not remove its successor with the same clip ID.
        private var anchors: [ObjectIdentifier: Anchor] = [:]
        private var ids: [String] = []
        private var indices: [String: Int] = [:]
        private var selected: Set<String> = []
        private var selecting = false
        private var publish: (Set<String>) -> Void = { _ in }
        private weak var scrollView: UIScrollView?
        private var sweep: MonitorMediaDragSelection?
        private weak var activeRecognizer: UIGestureRecognizer?
        private var touchOrigin: String?
        private var touchStart: CGPoint = .zero
        private var windowPoint: CGPoint = .zero
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        private var viewportWidth: CGFloat = 0
        private var context = ""

        private lazy var hold: UILongPressGestureRecognizer = {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handle))
            recognizer.minimumPressDuration = 0.28
            recognizer.allowableMovement = 8
            recognizer.delegate = self
            return recognizer
        }()
        private lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handle))
            recognizer.maximumNumberOfTouches = 1
            recognizer.delegate = self
            return recognizer
        }()

        func configure(
            ids: [String], selected: Set<String>, selecting: Bool, context: String,
            publish: @escaping (Set<String>) -> Void
        ) {
            if self.ids != ids || self.context != context || (self.selecting && !selecting) {
                cancel()
            }
            if let scroll = scrollView, sweep != nil,
                abs(scroll.bounds.width - viewportWidth) >= 1
            {
                cancel()
            }
            if self.ids != ids {
                self.ids = ids
                indices = Dictionary(
                    ids.enumerated().map { ($0.element, $0.offset) },
                    uniquingKeysWith: { a, _ in a })
            }
            self.selected = selected
            self.selecting = selecting
            self.context = context
            self.publish = publish
        }

        func register(id: String, view: UIView) {
            anchors[ObjectIdentifier(view)] = Anchor(id: id, view: view)
        }

        func unregister(view: UIView) {
            anchors.removeValue(forKey: ObjectIdentifier(view))
        }

        func attach(from view: UIView) {
            var ancestor = view.superview
            while let candidate = ancestor {
                if let scroll = candidate as? UIScrollView {
                    guard scrollView !== scroll else { return }
                    detach()
                    scrollView = scroll
                    viewportWidth = scroll.bounds.width
                    scroll.addGestureRecognizer(hold)
                    scroll.addGestureRecognizer(pan)
                    // Browsing rejects this pan immediately. Selection gives it
                    // first refusal so scrolling and pull-refresh cannot compete.
                    scroll.panGestureRecognizer.require(toFail: pan)
                    return
                }
                ancestor = candidate.superview
            }
        }

        func detach() {
            cancel()
            scrollView?.removeGestureRecognizer(hold)
            scrollView?.removeGestureRecognizer(pan)
            scrollView = nil
        }

        func cancel() {
            finish()
            hold.isEnabled = false
            pan.isEnabled = false
            hold.isEnabled = true
            pan.isEnabled = true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            guard let scroll = scrollView, scroll.window != nil,
                gestureRecognizer !== pan || selecting,
                let id = item(at: touch.location(in: scroll), nearest: false)
            else { return false }
            touchOrigin = id
            touchStart = touch.location(in: scroll)
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard sweep == nil, touchOrigin != nil else { return false }
            if gestureRecognizer === pan {
                guard selecting else { return false }
                let location = gestureRecognizer.location(in: scrollView)
                // Vertical swipes remain native scrolling, even in selection
                // mode. A sideways start claims a sweep; hold permits any axis.
                return abs(location.x - touchStart.x) > abs(location.y - touchStart.y)
            }
            return true
        }

        @objc private func handle(_ recognizer: UIGestureRecognizer) {
            guard let scroll = scrollView else { return }
            windowPoint = recognizer.location(in: scroll.window)
            switch recognizer.state {
            case .began:
                guard let origin = touchOrigin,
                    let initial = MonitorMediaDragSelection(
                        orderedIDs: ids, originID: origin, selectedIDs: selected)
                else { return }
                activeRecognizer = recognizer
                sweep = initial
                viewportWidth = scroll.bounds.width
                publishSelection(initial.selectedIDs)
                updateSelection()
                updateClock()
            case .changed:
                guard activeRecognizer === recognizer else { return }
                updateSelection()
                updateClock()
            case .ended:
                guard activeRecognizer === recognizer else { return }
                updateSelection()
                finish()
            case .cancelled, .failed:
                guard activeRecognizer === recognizer else { return }
                finish()
            default: break
            }
        }

        private func publishSelection(_ value: Set<String>) {
            selected = value
            publish(value)
        }

        private func updateSelection() {
            guard let scroll = scrollView, sweep != nil else { return }
            let point = scroll.convert(windowPoint, from: scroll.window)
            if let id = item(at: point, nearest: true), let index = indices[id],
                sweep?.move(to: index) == true, let value = sweep?.selectedIDs
            {
                publishSelection(value)
            }
        }

        private func item(at point: CGPoint, nearest: Bool) -> String? {
            guard let scroll = scrollView else { return nil }
            let visible = scroll.bounds
            if !nearest && !visible.contains(point) { return nil }
            let clamped = CGPoint(
                x: min(visible.maxX - 1, max(visible.minX + 1, point.x)),
                y: min(visible.maxY - 1, max(visible.minY + 1, point.y)))
            var closest: (String, CGFloat)?
            for anchor in anchors.values {
                let id = anchor.id
                guard indices[id] != nil, let view = anchor.view, view.window != nil else {
                    continue
                }
                let frame = view.convert(view.bounds, to: scroll)
                guard !frame.isEmpty, frame.intersects(visible) else { continue }
                if frame.contains(clamped) { return id }
                if nearest {
                    let dx = max(frame.minX - clamped.x, 0, clamped.x - frame.maxX)
                    let dy = max(frame.minY - clamped.y, 0, clamped.y - frame.maxY)
                    let distance = dx * dx + dy * dy
                    if closest == nil || distance < closest!.1 { closest = (id, distance) }
                }
            }
            return nearest ? closest?.0 : nil
        }

        private var scrollVelocity: Double {
            guard sweep != nil, let scroll = scrollView else { return 0 }
            let point = scroll.convert(windowPoint, from: scroll.window)
            guard point.x >= scroll.bounds.minX - 32, point.x <= scroll.bounds.maxX + 32 else {
                return 0
            }
            return MonitorMediaSelectionScroll.velocity(
                pointerY: point.y - scroll.bounds.minY, viewportHeight: scroll.bounds.height)
        }

        private func updateClock() {
            guard scrollVelocity != 0 else {
                stopClock()
                return
            }
            guard displayLink == nil else { return }
            let link = CADisplayLink(
                target: DisplayTarget(self), selector: #selector(DisplayTarget.tick))
            let maximum = Float(scrollView?.window?.screen.maximumFramesPerSecond ?? 60)
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30, maximum: maximum, preferred: maximum)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        fileprivate func tick(_ link: CADisplayLink) {
            guard sweep != nil, let scroll = scrollView, scroll.window != nil,
                abs(scroll.bounds.width - viewportWidth) < 1,
                UIApplication.shared.applicationState == .active
            else {
                cancel()
                return
            }
            let elapsed =
                lastTimestamp == 0
                ? link.targetTimestamp - link.timestamp : link.timestamp - lastTimestamp
            lastTimestamp = link.timestamp
            let velocity = scrollVelocity
            guard velocity != 0 else {
                stopClock()
                return
            }
            let minimum = -scroll.adjustedContentInset.top
            let maximum = max(
                minimum,
                scroll.contentSize.height - scroll.bounds.height
                    + scroll.adjustedContentInset.bottom)
            let offset = min(
                maximum,
                max(minimum, scroll.contentOffset.y + velocity * min(0.05, max(0, elapsed))))
            if abs(offset - scroll.contentOffset.y) > 0.01 {
                scroll.setContentOffset(
                    CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
            } else {
                stopClock()
            }
            updateSelection()
        }

        private func finish() {
            stopClock()
            sweep = nil
            activeRecognizer = nil
            touchOrigin = nil
            touchStart = .zero
        }

        private func stopClock() {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = 0
        }

        @MainActor private final class DisplayTarget: NSObject {
            weak var owner: MonitorMediaSelectionInteraction?
            init(_ owner: MonitorMediaSelectionInteraction) { self.owner = owner }
            @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
        }
    }

    struct MonitorMediaSelectionBridge: UIViewRepresentable {
        let interaction: MonitorMediaSelectionInteraction
        let ids: [String]
        let selected: Set<String>
        let selecting: Bool
        let context: String
        let publish: (Set<String>) -> Void

        func makeUIView(context: Context) -> Probe { Probe(interaction: interaction) }
        func updateUIView(_ view: Probe, context: Context) {
            if view.interaction !== interaction {
                view.interaction.detach()
                view.interaction = interaction
            }
            interaction.configure(
                ids: ids, selected: selected, selecting: selecting, context: self.context,
                publish: publish)
            interaction.attach(from: view)
        }
        static func dismantleUIView(_ view: Probe, coordinator: ()) { view.interaction.detach() }

        final class Probe: UIView {
            var interaction: MonitorMediaSelectionInteraction
            init(interaction: MonitorMediaSelectionInteraction) {
                self.interaction = interaction
                super.init(frame: .zero)
                isUserInteractionEnabled = false
            }
            required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
            override func didMoveToWindow() {
                super.didMoveToWindow()
                if window == nil { interaction.detach() } else { interaction.attach(from: self) }
            }
        }
    }

    struct MonitorMediaSelectionAnchor: UIViewRepresentable {
        let id: String
        let interaction: MonitorMediaSelectionInteraction
        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.isUserInteractionEnabled = false
            interaction.register(id: id, view: view)
            return view
        }
        func updateUIView(_ view: UIView, context: Context) {
            if context.coordinator.interaction !== interaction {
                context.coordinator.interaction.unregister(view: view)
                context.coordinator.interaction = interaction
            }
            interaction.register(id: id, view: view)
        }
        func makeCoordinator() -> Coordinator { Coordinator(interaction: interaction) }
        static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
            coordinator.interaction.unregister(view: view)
        }
        final class Coordinator {
            var interaction: MonitorMediaSelectionInteraction
            init(interaction: MonitorMediaSelectionInteraction) {
                self.interaction = interaction
            }
        }
    }
#endif
