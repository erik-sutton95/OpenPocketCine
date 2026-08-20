import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine Traffic Lights — `AssistQuickSettingsContent.trafficLightsRows` plus
/// `MovablePanel(id: "traffic-lights")` (long-press drag + corner resize).
///
/// Long-press options are **only** Crush/Clip Compensation (0 / 0.25 / 0.5 / 0.75 / 1.0 stops).
/// That value is shared with the histogram's edge lights. The floating meter is the
/// RED-style RGB goal-post (`TrafficLightsMeterMini`): `TL` title, three centre-anchored
/// columns, clip lamps on top, crush lamps on the floor. Draggable after a 0.3s hold
/// and uniformly scalable 0.6…1.6 from the bottom-trailing grip.
enum TrafficLightsAssist {
    static let panelID = "traffic-lights"
    static let baseSize = CGSize(width: 74, height: 168)
    static let scaleRange: ClosedRange<Double> = 0.6...1.6
    static let defaultScale = 1.0
    static let defaultCompensation = CrushClipCompensation.zero
    static let longPressPanelWidth: CGFloat = 400
    static let compensationTitle = "Crush/Clip Compensation"
    static let compensationHelp =
        "Stops of crush/clip tolerance before a channel indicator glows. Shared with the histogram traffic lights."

    static let holdDuration: Double = 0.3
    static let positionGrid: CGFloat = 4
    static let hapticGrid: CGFloat = 22
    static let dragHitPadding: CGFloat = 10
    static let gripHitSize: CGFloat = 56
    static let gripVisualSize: CGFloat = 14
    static let gripExteriorGap: CGFloat = 2

    /// OpenZCine `TrafficLightsMeterMini` chrome — 74×168 landscape box.
    static let meterTitle = "TL"
    static let accessibilityTitle = "Traffic Lights"
    static let titleSize: CGFloat = 8.5
    static let titleSpacing: CGFloat = 6
    static let columnSpacing: CGFloat = 6
    static let postSpacing: CGFloat = 4
    static let panelPad: CGFloat = 8
    static let trackWidth: CGFloat = 11
    static let columnHeight: CGFloat = 108
    static let indicatorSize: CGFloat = 8
    static let fillsWidthMaxColumn: CGFloat = 44
    static let trackCorner: CGFloat = 2
    static let minBarHeight: CGFloat = 1.5
    static let centerLineFactor: CGFloat = 0.85
    static let segmentMinWidth: CGFloat = 46
    static let segmentMinHeight: CGFloat = 34
    static let meterRedRGB: (Double, Double, Double) = (255, 92, 82)
    static let meterGreenRGB: (Double, Double, Double) = (86, 235, 132)
    static let meterBlueRGB: (Double, Double, Double) = (96, 158, 255)
    static let leanBalanced = "balanced"
    static let leanOver = "over"
    static let leanUnder = "under"
    static let flagClip = "clip"
    static let flagCrush = "crush"
    static let channelNames = ["red", "green", "blue"]

    /// OpenZCine `TrafficLightsMeter.balanceCenter` / `balanceDeadZone`.
    static let balanceCenter = 0.5
    static let balanceDeadZone = 0.03

    /// OpenZCine `AssistConfiguration.CrushClipCompensation`.
    enum CrushClipCompensation: Int, CaseIterable, Codable, Equatable, Sendable, Identifiable {
        case zero = 0
        case quarter = 2
        case half = 5
        case threeQuarter = 7
        case one = 10

        var id: Int { rawValue }

        /// Operator-facing label in stops (OpenZCine `label`).
        var label: String {
            switch self {
            case .zero: "0"
            case .quarter: "0.25"
            case .half: "0.5"
            case .threeQuarter: "0.75"
            case .one: "1.0"
            }
        }

        /// In-app compact glyphs (OpenZCine `compactLabel`).
        var compactLabel: String {
            switch self {
            case .zero: "0"
            case .quarter: "¼"
            case .half: "½"
            case .threeQuarter: "¾"
            case .one: "1"
            }
        }

        var stops: Double {
            switch self {
            case .zero: 0
            case .quarter: 0.25
            case .half: 0.5
            case .threeQuarter: 0.75
            case .one: 1.0
            }
        }

        /// Fraction of channel energy in the crush/clip band required to light a lamp.
        /// Each quarter-stop adds 2.5 percentage points (0 → 0%, 1.0 → 10%).
        var pixelFractionThreshold: Double { stops / 10.0 }

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(Int.self)
            self = CrushClipCompensation(rawValue: raw) ?? (raw > 10 ? .one : .zero)
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(rawValue)
        }
    }

    /// OpenZCine `TrafficLightsBarSide` — which half of a goal-post shows fill.
    enum BarSide: Equatable, Sendable {
        case neutral
        case over
        case under
    }

    /// OpenZCine `TrafficLightsChannelDisplay` — display transform only (not IRE).
    struct ChannelDisplay: Equatable, Sendable {
        var side: BarSide
        var barFill: Double

        static let neutral = ChannelDisplay(side: .neutral, barFill: 0)
    }

    /// OpenZCine `TrafficLightsMeter.channelDisplay` — centre-anchored single-sided fill.
    static func channelDisplay(
        for channel: ScopeChannelLight,
        balanceCenter center: Double = balanceCenter,
        deadZone: Double = balanceDeadZone
    ) -> ChannelDisplay {
        channelDisplay(level: channel.level, balanceCenter: center, deadZone: deadZone)
    }

    static func channelDisplay(
        level: Double,
        balanceCenter center: Double = balanceCenter,
        deadZone: Double = balanceDeadZone
    ) -> ChannelDisplay {
        let deviation = level - center
        if abs(deviation) <= deadZone { return .neutral }
        if deviation > 0 {
            let span = max(1 - center, .leastNonzeroMagnitude)
            return ChannelDisplay(side: .over, barFill: min(1, deviation / span))
        }
        let span = max(center, .leastNonzeroMagnitude)
        return ChannelDisplay(side: .under, barFill: min(1, abs(deviation) / span))
    }

    /// OpenZCine `TrafficLightsMeterMini` column width — 11pt locked, or spread when `fillsWidth`.
    static func columnWidth(fillsWidth: Bool, panelWidth: CGFloat, uiScale: CGFloat) -> CGFloat {
        if fillsWidth {
            return min(
                fillsWidthMaxColumn,
                max(trackWidth * uiScale, (panelWidth - 16 * uiScale) / 6))
        }
        return trackWidth * uiScale
    }

    static func meterColor(_ rgb: (Double, Double, Double)) -> Color {
        Color(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
    }

    /// OpenZCine `trafficLightsAccessibilityValue`.
    static func accessibilityValue(for reading: ScopeTrafficLightsReading) -> String {
        func channel(_ name: String, _ ch: ScopeChannelLight) -> String {
            let shown = channelDisplay(for: ch)
            let lean: String
            switch shown.side {
            case .neutral: lean = leanBalanced
            case .over: lean = leanOver
            case .under: lean = leanUnder
            }
            let flags = [ch.clip ? flagClip : nil, ch.crush ? flagCrush : nil].compactMap { $0 }
            let flagSuffix = flags.isEmpty ? "" : " (\(flags.joined(separator: ", ")))"
            return "\(name) \(lean)\(flagSuffix)"
        }
        return [
            channel(channelNames[0], reading.red),
            channel(channelNames[1], reading.green),
            channel(channelNames[2], reading.blue),
        ].joined(separator: ", ")
    }

    /// Normalized centre — OpenZCine `MovablePanelStoredCenter`.
    struct StoredCenter: Codable, Equatable, Sendable {
        var xFraction: Double
        var yFraction: Double

        init(center: CGPoint, in bounds: CGRect) {
            let width = max(bounds.width, 1)
            let height = max(bounds.height, 1)
            xFraction = Double((center.x - bounds.minX) / width)
            yFraction = Double((center.y - bounds.minY) / height)
        }

        func center(in bounds: CGRect) -> CGPoint {
            CGPoint(
                x: bounds.minX + CGFloat(xFraction) * bounds.width,
                y: bounds.minY + CGFloat(yFraction) * bounds.height)
        }
    }

    static func clampedScale(_ value: Double) -> Double {
        min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
    }

    static func panelSize(scale: Double) -> CGSize {
        let clamped = clampedScale(scale)
        return CGSize(
            width: (baseSize.width * clamped).rounded(),
            height: (baseSize.height * clamped).rounded())
    }

    /// OpenZCine `feedOutsideCenter` for `.bottomLeading`. Full-bleed feed parks the
    /// panel just inside the picture, above the assist/capture strip.
    static func defaultCenter(
        feed: CGRect,
        size: CGSize,
        bounds: CGRect,
        chromeClearance: EdgeInsets,
        gap: CGFloat = 10
    ) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let x = feed.minX + halfWidth
        let outside = feed.maxY + gap + halfHeight
        let y: CGFloat
        if outside + halfHeight <= bounds.maxY {
            y = outside
        } else {
            y = min(feed.maxY, bounds.maxY - chromeClearance.bottom) - gap - halfHeight
        }
        return clamp(CGPoint(x: x, y: y), size: size, in: bounds)
    }

    static func clamp(_ point: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        return CGPoint(
            x: min(max(bounds.minX + halfWidth, point.x), bounds.maxX - halfWidth),
            y: min(max(bounds.minY + halfHeight, point.y), bounds.maxY - halfHeight))
    }

    static func snap(_ point: CGPoint, grid: CGFloat = positionGrid) -> CGPoint {
        CGPoint(
            x: (point.x / grid).rounded() * grid,
            y: (point.y / grid).rounded() * grid)
    }

    static func hapticCell(_ point: CGPoint, grid: CGFloat = hapticGrid) -> Int {
        Int((point.x / grid).rounded()) &* 100_000
            &+ Int((point.y / grid).rounded())
    }

    static func resolvedCenter(
        session: CGPoint? = nil,
        stored: StoredCenter?,
        defaultCenter: CGPoint,
        size: CGSize,
        bounds: CGRect
    ) -> CGPoint {
        if let session { return clamp(session, size: size, in: bounds) }
        let raw = stored?.center(in: bounds) ?? defaultCenter
        return clamp(raw, size: size, in: bounds)
    }

    /// OpenZCine keeps one `scopes.crushClipCompensation` for histogram + goal-post.
    @MainActor
    static var store: TrafficLightsAssistStore { TrafficLightsAssistStore.shared }

    @MainActor
    static func sharedCompensation() -> CrushClipCompensation {
        CrushClipCompensation(
            rawValue: HistogramAssist.store.options.crushClipCompensation.rawValue)
            ?? store.compensation
    }

    @MainActor
    static func setSharedCompensation(_ value: CrushClipCompensation) {
        store.compensation = value
        if let histo = HistogramAssist.CrushClipCompensation(rawValue: value.rawValue) {
            HistogramAssist.store.options.crushClipCompensation = histo
        }
    }

    @MainActor
    static func longPressMenu(assist: LiveAssistState, compact: Bool = false)
        -> TrafficLightsLongPressMenu
    {
        TrafficLightsLongPressMenu(assist: assist, compact: compact)
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> TrafficLightsLongPressMenu {
        longPressMenu(assist: assist)
    }

    fileprivate struct Snapshot: Codable {
        var compensation: CrushClipCompensation
        var scale: Double
        var position: StoredCenter?
        var positionPortrait: StoredCenter?
    }
}

@MainActor
@Observable
final class TrafficLightsAssistStore {
    static let shared = TrafficLightsAssistStore()
    fileprivate static let prefsKey = "OpenPocketCine.Assist.trafficLights.v1"

    var compensation: TrafficLightsAssist.CrushClipCompensation
    var scale: Double
    var position: TrafficLightsAssist.StoredCenter?
    var positionPortrait: TrafficLightsAssist.StoredCenter?
    var sessionCenter: CGPoint?
    var sessionCenterPortrait: CGPoint?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.prefsKey),
            let snap = try? JSONDecoder().decode(TrafficLightsAssist.Snapshot.self, from: data)
        {
            compensation = snap.compensation
            scale = TrafficLightsAssist.clampedScale(snap.scale)
            position = snap.position
            positionPortrait = snap.positionPortrait
        } else if let shared = TrafficLightsAssist.CrushClipCompensation(
            rawValue: HistogramAssist.store.options.crushClipCompensation.rawValue)
        {
            compensation = shared
            scale = TrafficLightsAssist.defaultScale
            position = nil
            positionPortrait = nil
        } else {
            compensation = TrafficLightsAssist.defaultCompensation
            scale = TrafficLightsAssist.defaultScale
            position = nil
            positionPortrait = nil
        }
        if let histo = HistogramAssist.CrushClipCompensation(rawValue: compensation.rawValue) {
            HistogramAssist.store.options.crushClipCompensation = histo
        }
    }

    func persist() {
        let snap = TrafficLightsAssist.Snapshot(
            compensation: compensation,
            scale: TrafficLightsAssist.clampedScale(scale),
            position: position,
            positionPortrait: positionPortrait)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        UserDefaults.standard.set(data, forKey: Self.prefsKey)
    }
}

// MARK: - Long-press rows

struct TrafficLightsLongPressMenu: View {
    var assist: LiveAssistState
    var compact: Bool = false

    var body: some View {
        SettingsInlineRow(
            title: TrafficLightsAssist.compensationTitle,
            help: TrafficLightsAssist.compensationHelp,
            showTopDivider: false,
            stacked: compact
        ) {
            TrafficLightsCrushClipSegmented(
                selected: TrafficLightsAssist.sharedCompensation(),
                compact: compact
            ) { match in
                guard match != TrafficLightsAssist.sharedCompensation() else { return }
                TrafficLightsAssistHaptics.selection()
                TrafficLightsAssist.setSharedCompensation(match)
                assist.crushClipCompensation = match
                assist.persist()
                TrafficLightsAssist.store.persist()
            }
        }
    }
}

/// OpenZCine `SettingsCrushClipSegmented` — fraction glyphs, 46×34 floor, full stop in VoiceOver.
private struct TrafficLightsCrushClipSegmented: View {
    let selected: TrafficLightsAssist.CrushClipCompensation
    var compact: Bool = false
    let onSelect: (TrafficLightsAssist.CrushClipCompensation) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TrafficLightsAssist.CrushClipCompensation.allCases) { option in
                let active = option == selected
                Button {
                    onSelect(option)
                } label: {
                    Text(option.compactLabel)
                        .font(LiveType.ui(size: compact ? 12 : 11, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? LiveDesign.text : LiveDesign.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(
                            minWidth: TrafficLightsAssist.segmentMinWidth,
                            minHeight: TrafficLightsAssist.segmentMinHeight)
                        .background(
                            active ? LiveDesign.surface : Color.clear,
                            in: RoundedRectangle(
                                cornerRadius: DesignTokens.cornerRadius, style: .continuous))
                }
                .buttonStyle(.zcTapTarget)
                .accessibilityLabel(option.label)
            }
        }
        .padding(4)
        .background(
            LiveDesign.background.opacity(0.5),
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                .stroke(LiveDesign.hairline, lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }
}

private enum TrafficLightsAssistHaptics {
    @MainActor
    static func selection() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}

// MARK: - Movable panel (OpenZCine `MovablePanel`)

/// Long-press then drag to reposition; corner grip long-press-drags to scale.
struct TrafficLightsMovablePanel<Content: View>: View {
    @Bindable var store: TrafficLightsAssistStore
    let size: CGSize
    let defaultCenter: CGPoint
    let bounds: CGRect
    @ViewBuilder var content: () -> Content

    @State private var dragOrigin: CGPoint?
    @State private var isDragging = false
    @State private var snapCell = 0
    @State private var isResizing = false
    @State private var resizeStartScale = 1.0
    @State private var sessionCenter: CGPoint?
    @State private var sessionCenterPortrait: CGPoint?

    private var gripHitSize: CGFloat { TrafficLightsAssist.gripHitSize }
    private var gripVisualSize: CGFloat { TrafficLightsAssist.gripVisualSize }
    private var dragHitPadding: CGFloat { TrafficLightsAssist.dragHitPadding }
    private var gripExteriorGap: CGFloat { TrafficLightsAssist.gripExteriorGap }
    private var gripCornerInset: CGFloat { gripVisualSize - gripExteriorGap }

    var body: some View {
        let center = clamp(resolvedCenter())
        let gripPad = gripHitSize - gripCornerInset
        ZStack(alignment: .topLeading) {
            content()
                .overlay(alignment: .bottomTrailing) {
                    resizeHandle
                        .offset(x: gripExteriorGap, y: gripExteriorGap)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .padding(dragHitPadding)
                .contentShape(Rectangle())
                .padding(-dragHitPadding)
                .gesture(panelDragGesture(center: center))
        }
        .frame(
            width: size.width + gripPad,
            height: size.height + gripPad,
            alignment: .topLeading
        )
        .scaleEffect((isDragging || isResizing) ? 1.03 : 1)
        .shadow(color: .black.opacity((isDragging || isResizing) ? 0.5 : 0), radius: 18, y: 8)
        .position(x: center.x + gripPad / 2, y: center.y + gripPad / 2)
        .sensoryFeedback(trigger: isDragging) { _, dragging in
            dragging ? .impact(flexibility: .rigid, intensity: 1) : nil
        }
        .sensoryFeedback(.selection, trigger: snapCell)
        .sensoryFeedback(trigger: isResizing) { _, resizing in
            resizing ? .impact(flexibility: .rigid, intensity: 0.8) : nil
        }
        .animation(.easeOut(duration: 0.14), value: isDragging)
        .animation(.easeOut(duration: 0.14), value: isResizing)
    }

    private var resizeHandle: some View {
        let gripColor = isResizing ? LiveDesign.accent : LiveDesign.muted
        return TrafficLightsCornerGrip()
            .stroke(gripColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
            .frame(width: gripVisualSize, height: gripVisualSize, alignment: .bottomTrailing)
            .frame(width: gripHitSize, height: gripHitSize, alignment: .bottomTrailing)
            .contentShape(Rectangle())
            .gesture(resizeGesture)
    }

    private func panelDragGesture(center: CGPoint) -> some Gesture {
        LongPressGesture(minimumDuration: TrafficLightsAssist.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !isDragging {
                    isDragging = true
                    dragOrigin = center
                }
                guard let drag, let origin = dragOrigin else { return }
                let proposed = CGPoint(
                    x: origin.x + drag.translation.width,
                    y: origin.y + drag.translation.height)
                let snapped = clamp(TrafficLightsAssist.snap(proposed))
                let cell = TrafficLightsAssist.hapticCell(snapped)
                if cell != snapCell { snapCell = cell }
                ScopeCanvasSlot.assign(
                    &sessionCenter, &sessionCenterPortrait, in: bounds, snapped)
            }
            .onEnded { _ in
                if let final = ScopeCanvasSlot.pick(
                    sessionCenter, sessionCenterPortrait, in: bounds)
                {
                    let stored = TrafficLightsAssist.StoredCenter(center: final, in: bounds)
                    if ScopeCanvasSlot.forBounds(bounds) == .portrait {
                        store.positionPortrait = stored
                    } else {
                        store.position = stored
                    }
                    store.persist()
                }
                isDragging = false
                dragOrigin = nil
            }
    }

    private var resizeGesture: some Gesture {
        LongPressGesture(minimumDuration: TrafficLightsAssist.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !isResizing {
                    isResizing = true
                    resizeStartScale = store.scale
                }
                guard let drag else { return }
                let reach = TrafficLightsAssist.baseSize.width + TrafficLightsAssist.baseSize.height
                let delta = (drag.translation.width + drag.translation.height) / reach
                store.scale = TrafficLightsAssist.clampedScale(resizeStartScale + delta)
            }
            .onEnded { _ in
                isResizing = false
                store.persist()
            }
    }

    private func resolvedCenter() -> CGPoint {
        TrafficLightsAssist.resolvedCenter(
            session: ScopeCanvasSlot.pick(sessionCenter, sessionCenterPortrait, in: bounds),
            stored: ScopeCanvasSlot.pick(store.position, store.positionPortrait, in: bounds),
            defaultCenter: defaultCenter,
            size: size,
            bounds: bounds)
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        TrafficLightsAssist.clamp(point, size: size, in: bounds)
    }
}

private struct TrafficLightsCornerGrip: Shape {
    func path(in rect: CGRect) -> Path {
        let leg = min(rect.width, rect.height)
        let vertex = CGPoint(x: rect.maxX, y: rect.maxY)
        var path = Path()
        path.move(to: vertex)
        path.addLine(to: CGPoint(x: vertex.x - leg, y: vertex.y))
        path.move(to: vertex)
        path.addLine(to: CGPoint(x: vertex.x, y: vertex.y - leg))
        return path
    }
}
