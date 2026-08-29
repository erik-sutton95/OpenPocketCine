import OpenPocketViewCore
import SwiftUI

/// OpenZCine `MonitorExperience.zoomGesturesTail` / Android `completeDrag`.
/// Down → clean (DISP 2). Up → live (DISP 1). `nil` if too short or not vertical.
enum LiveDispSwipe {
    /// Same +8 pt axis margin as the completed swipe, without the 44 pt floor.
    static func isVerticalDominant(_ translation: CGSize) -> Bool {
        abs(translation.height) > abs(translation.width) + 8
    }

    static func wantsClean(translation: CGSize) -> Bool? {
        let dy = translation.height
        guard isVerticalDominant(translation), abs(dy) > 44 else { return nil }
        return dy > 0
    }
}

/// Swipe = DISP. Slight long-press then drag = tracking box.
/// Short press = tap focus, or ActiveTrack if the tap is on the AF-C face box.
enum LiveFeedFocusGesture {
    enum Kind: Equatable {
        case tap
        case track
        case dispClean
        case dispLive
    }

    static let trackMinimum: CGFloat = 24
    /// Short enough to feel like a press, long enough that a swipe never arms.
    static let trackHoldDuration: TimeInterval = 0.20
    static let trackHoldSlop: CGFloat = 10

    static func classify(
        translation: CGSize, pinched: Bool = false, armed: Bool = false
    ) -> Kind? {
        if pinched { return nil }
        let distance = hypot(translation.width, translation.height)
        if armed {
            return distance >= trackMinimum ? .track : .tap
        }
        if let clean = LiveDispSwipe.wantsClean(translation: translation) {
            return clean ? .dispClean : .dispLive
        }
        if distance >= trackMinimum { return nil }
        return .tap
    }

    static func cameraPoint(
        _ location: CGPoint, in size: CGSize, mirrored: Bool
    ) -> (x: Double, y: Double) {
        let nx = min(max(Double(location.x / max(size.width, 1)), 0), 1)
        let ny = min(max(Double(location.y / max(size.height, 1)), 0), 1)
        return (mirrored ? 1 - nx : nx, ny)
    }

    static func cameraBox(
        from: CGPoint, to: CGPoint, in size: CGSize, mirrored: Bool
    ) -> TrackingBox {
        let a = cameraPoint(from, in: size, mirrored: mirrored)
        let b = cameraPoint(to, in: size, mirrored: mirrored)
        return TrackingBox.normalized(fromX: a.x, fromY: a.y, toX: b.x, toY: b.y)
    }
}

/// Feed-sized pinch + DISP swipe well. Lives in the chrome stack **under** the
/// zoom chip and scope panels, **above** `VideoView`. Do not hang these
/// gestures on the screen `GeometryReader` — the UIKit feed plus WAVE/HISTO/rails
/// eat that pinch, and a screen drag would steal record / assist hits.
struct LiveZoomPinchWell: View {
    var feed: CGRect
    var chip: CGRect
    var stick: CGRect = .zero
    var reset: CGRect = .zero
    var cancel: CGRect = .zero
    var enabled: Bool
    @State private var draftStart: CGPoint?
    @State private var draftEnd: CGPoint?

    var body: some View {
        let chipInFeed = chip.offsetBy(dx: -feed.minX, dy: -feed.minY)
        let stickInFeed = stick.offsetBy(dx: -feed.minX, dy: -feed.minY)
        let resetInFeed = reset.offsetBy(dx: -feed.minX, dy: -feed.minY)
        let cancelInFeed = cancel.offsetBy(dx: -feed.minX, dy: -feed.minY)
        ZStack {
            Color.white.opacity(0.001)
            if let start = draftStart, let end = draftEnd {
                draftBox(from: start, to: end)
            }
        }
        .frame(width: feed.width, height: feed.height)
        .contentShape(
            .interaction,
            LiveZoomPinchHitShape(holes: [chipInFeed, stickInFeed, resetInFeed, cancelInFeed]),
            eoFill: true
        )
        .modifier(
            LiveZoomPinchModifier(
                enabled: enabled,
                feedSize: CGSize(width: feed.width, height: feed.height),
                draftStart: $draftStart,
                draftEnd: $draftEnd
            )
        )
        .position(x: feed.midX, y: feed.midY)
        .allowsHitTesting(enabled)
        .accessibilityHidden(true)
    }

    private func draftBox(from start: CGPoint, to end: CGPoint) -> some View {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        return RoundedRectangle(
            cornerRadius: LiveTrackingChrome.cornerRadius(for: rect), style: .continuous
        )
        .stroke(LiveDesign.text.opacity(0.88), lineWidth: 1.5)
        .shadow(color: .black.opacity(0.6), radius: 1)
        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
    }
}

/// Feed pinch well with holes over the zoom chip and gimbal stick.
private struct LiveZoomPinchHitShape: Shape {
    var holes: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        for hole in holes {
            let cut = hole.insetBy(dx: -2, dy: -2).intersection(rect)
            if !cut.isEmpty { path.addRect(cut) }
        }
        return path
    }
}

struct LiveZoomPinchModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    var enabled: Bool
    var feedSize: CGSize
    @Binding var draftStart: CGPoint?
    @Binding var draftEnd: CGPoint?
    @State private var pinchUsed = false
    @State private var detentTick = 0.0
    @State private var focusTick = 0
    @State private var armTick = 0
    @State private var trackArmed = false
    @State private var holdStarted = false
    @State private var holdTask: Task<Void, Never>?
    @State private var lastTranslation: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .gesture(zoomGestures, including: enabled ? .gesture : .none)
            .sensoryFeedback(.impact(weight: .medium), trigger: detentTick)
            .sensoryFeedback(.impact(weight: .light), trigger: focusTick)
            .sensoryFeedback(.impact(weight: .medium), trigger: armTick)
    }

    /// OpenZCine `zoomGesturesTail`: one drag beside pinch so they coexist.
    /// Pocket pinch writes the hybrid slider at Mimo's 50 ms cadence.
    private var zoomGestures: some Gesture {
        pinch.simultaneously(with: feedDrag)
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard enabled else { return }
                pinchUsed = true
                cancelTrackHold()
                draftStart = nil
                draftEnd = nil
                model.session.updateZoomPinch(magnification: Double(value.magnification))
                let preview = model.session.zoomPinchPreview ?? 0
                if CamFov.isJumpStop(preview, stops: model.session.zoomStops) {
                    if detentTick != preview { detentTick = preview }
                } else if detentTick != 0 {
                    detentTick = 0
                }
            }
            .onEnded { _ in
                model.session.endZoomPinch()
                detentTick = 0
                DispatchQueue.main.async { pinchUsed = false }
            }
    }

    private var feedDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard enabled, !pinchUsed else { return }
                lastTranslation = value.translation
                if !holdStarted {
                    holdStarted = true
                    beginTrackHold()
                }
                let slop = hypot(value.translation.width, value.translation.height)
                if !trackArmed, slop > LiveFeedFocusGesture.trackHoldSlop {
                    holdTask?.cancel()
                    holdTask = nil
                }
                guard trackArmed else {
                    draftStart = nil
                    draftEnd = nil
                    return
                }
                draftStart = value.startLocation
                draftEnd = value.location
            }
            .onEnded { value in
                let armed = trackArmed
                cancelTrackHold()
                draftStart = nil
                draftEnd = nil
                guard enabled else { return }
                guard
                    let kind = LiveFeedFocusGesture.classify(
                        translation: value.translation, pinched: pinchUsed, armed: armed)
                else { return }
                switch kind {
                case .dispClean:
                    model.setDisplayMode(clean: true)
                case .dispLive:
                    model.setDisplayMode(clean: false)
                case .tap:
                    let point = LiveFeedFocusGesture.cameraPoint(
                        value.location, in: feedSize, mirrored: model.livePictureViewFlip)
                    model.session.handleFeedTap(at: CGPoint(x: point.x, y: point.y))
                    focusTick += 1
                case .track:
                    model.session.startTracking(
                        LiveFeedFocusGesture.cameraBox(
                            from: value.startLocation,
                            to: value.location,
                            in: feedSize,
                            mirrored: model.livePictureViewFlip
                        )
                    )
                    focusTick += 1
                }
            }
    }

    private func beginTrackHold() {
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(LiveFeedFocusGesture.trackHoldDuration))
            guard !Task.isCancelled, enabled, !pinchUsed else { return }
            let slop = hypot(lastTranslation.width, lastTranslation.height)
            guard slop <= LiveFeedFocusGesture.trackHoldSlop else { return }
            trackArmed = true
            armTick += 1
        }
    }

    private func cancelTrackHold() {
        holdTask?.cancel()
        holdTask = nil
        holdStarted = false
        trackArmed = false
        lastTranslation = .zero
    }
}

/// Ignore sub-tenth `cam_fov` jitter on the chip unless the operator is pinching.
enum LiveZoomLabelHold {
    static func shouldReplace(
        held: Double, next: Double, pinching: Bool, epsilon: Double = 0.12
    ) -> Bool {
        if pinching { return true }
        return abs(next - held) >= epsilon
    }
}

/// One round cycle hit inside the feed: 1× → 3× → 6× → 12× → 1×.
struct LiveZoomChip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked
    @State private var heldFactor: Double?
    @State private var snapTick = 0

    private var factor: Double { model.session.zoomReadout }
    private var displayFactor: Double { heldFactor ?? factor }
    /// Unsnapped live / preview so 2.89× (shown 2.9×, still wide) cycles to 3×, not 12×.
    private var cycleFrom: Double {
        model.session.zoomPinchPreview
            ?? model.session.zoomOptimistic
            ?? model.session.status.zoomFactor
            ?? model.session.zoomStop
    }
    private var title: String { CamFov.displayLabel(factor: displayFactor) }
    /// D-Log2 while rolling: gray like lock, but keep the tap so we can toast.
    private var zoomBlockedWhileRecording: Bool {
        CamFov.zoomNeedsColorHopWhileRecording(
            factor: CamFov.nextJump(from: cycleFrom, stops: model.session.zoomStops),
            current: model.session.status.colorMode,
            isRecording: model.session.status.isRecording)
    }

    var body: some View {
        Button {
            let next = CamFov.nextJump(from: cycleFrom, stops: model.session.zoomStops)
            ControlLiveLog.line(
                "zoom: chip tap \(title) → \(CamFov.displayLabel(factor: next)) locked=\(interfaceLocked)"
            )
            guard !interfaceLocked else { return }
            snapTick += 1
            model.session.setZoom(next)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(LiveDesign.text)
                .minimumScaleFactor(0.75)
                .frame(
                    width: LiveChromeMetrics.zoomButtonSize,
                    height: LiveChromeMetrics.zoomButtonSize
                )
                .liveChromeCircle()
        }
        .buttonStyle(.zcTapTarget)
        .opacity(interfaceLocked || zoomBlockedWhileRecording ? 0.4 : 1)
        .allowsHitTesting(!interfaceLocked)
        .disabled(interfaceLocked)
        .accessibilityLabel("Zoom \(title)")
        .accessibilityHint("Cycles 1×, 3×, 6×, and 12×")
        .accessibilityIdentifier("monitor.system.zoom")
        .sensoryFeedback(.impact(weight: .medium), trigger: snapTick)
        .onAppear { heldFactor = factor }
        .onChange(of: factor) { _, next in
            let pinching = model.session.zoomPinchPreview != nil
            if let held = heldFactor,
                !LiveZoomLabelHold.shouldReplace(held: held, next: next, pinching: pinching)
            {
                return
            }
            heldFactor = next
        }
    }
}
