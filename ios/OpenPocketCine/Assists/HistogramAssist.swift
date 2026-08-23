import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine histogram operator options + `MovablePanel` (id `"histo"`).
///
/// Long-press toolbar rows (`AssistQuickSettingsContent.histogramRows`):
/// * Traffic Lights — RGB crush/clip edge blocks
/// * Crush/Clip Compensation — 0…1 stop, shared with the goal-post meter
///
/// Plot geometry is WAVE’s `WaveformAxis` — IRE 0 / 100 on the plot edges,
/// same paper-black / live-tap clip mapping as WAVE / PARADE. Crush / clip
/// lamps sit outside those strokes. No 0 / 50 / 100 labels. On the panel:
/// 0.3s long-press then drag to reposition (4pt snap,
/// 22pt haptic grid); L-corner grip long-press-drags to scale 0.6…1.6.
/// Position persists as a normalised centre (OpenZCine `MovablePanelStoredCenter`).
enum HistogramAssist {
    static let panelID = "histo"
    static let longPressPanelWidth: CGFloat = 400
    static let baseSize = ScopePanelSize.histogram
    static let scaleRange: ClosedRange<Double> = 0.6...1.6
    static let defaultScale = 1.0
    static let holdDuration: Double = 0.3
    static let positionGrid: CGFloat = 4
    static let hapticGrid: CGFloat = 22
    static let dragHitPadding: CGFloat = 10
    static let gripHitSize: CGFloat = 56
    static let gripVisualSize: CGFloat = 14
    static let gripExteriorGap: CGFloat = 2
    /// OpenZCine `ScopeMini` title / chip (`"Histo"` → HISTO, `"RGBL"`).
    static let panelTitle = "Histo"
    static let chip = "RGBL"
    static let plotTop: CGFloat = WaveformAxis.titleHeight
    /// OpenZCine `histogramReferenceX(95)` clip band — on WAVE’s IRE axis.
    static let clipZoneIRE = 95.0
    /// Crush / clip lamp size — must match ``HistogramScopePlot`` blocks.
    static let trafficLampWidth: CGFloat = 7.5
    static let trafficLampHeight: CGFloat = 15
    /// Inset from the panel edge so the top lamp clears the rounded corner.
    static let trafficOuterPad: CGFloat = 6
    /// Gap between a lamp column and the 0 / 100 stroke.
    static let trafficLineGap: CGFloat = 4

    static let trafficLightsTitle = "Traffic Lights"
    static let trafficLightsHelp =
        "Show small RGB edge blocks for crushed and clipped channels."
    static let compensationTitle = "Crush/Clip Compensation"
    static let compensationHelp =
        "Stops of crush/clip tolerance before a traffic light glows. Shared with the goal-post meter."

    /// Side gutter that holds a lamp column outside the 0 / 100 strokes.
    static var trafficGutter: CGFloat {
        trafficOuterPad + trafficLampWidth + trafficLineGap
    }

    /// WAVE title / floor, with extra side chrome so crush sits left of 0
    /// and clip sits right of 100. IRE mapping inside the plot is ``WaveformAxis``.
    static func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: trafficGutter,
            y: WaveformAxis.titleHeight,
            width: max(1, size.width - trafficGutter * 2),
            height: max(1, size.height - WaveformAxis.titleHeight - WaveformAxis.bottomPad))
    }

    /// Left-to-right twin of ``WaveformAxis.plotY``.
    static func plotX(_ ire: Double, in rect: CGRect) -> CGFloat {
        WaveformAxis.plotX(ire, rect)
    }

    static func ireX(_ scaleIRE: Double, in rect: CGRect) -> CGFloat {
        WaveformAxis.plotX(scaleIRE, rect)
    }

    /// Panel-edge inset for the crush / clip columns (outside 0 / 100).
    static var trafficHorizontalInset: CGFloat { trafficOuterPad }

    /// OpenZCine `AssistConfiguration.CrushClipCompensation`.
    enum CrushClipCompensation: Int, CaseIterable, Codable, Equatable, Sendable, Identifiable {
        case zero = 0
        case quarter = 2
        case half = 5
        case threeQuarter = 7
        case one = 10

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .zero: "0"
            case .quarter: "0.25"
            case .half: "0.5"
            case .threeQuarter: "0.75"
            case .one: "1.0"
            }
        }

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

        /// OpenZCine: each quarter-stop adds 2.5 percentage points (0 → 0%, 1.0 → 10%).
        var pixelFractionThreshold: Double { stops / 10.0 }

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(Int.self)
            self = CrushClipCompensation(rawValue: raw) ?? (raw > 10 ? .one : .zero)
        }
    }

    /// OpenZCine `MovablePanelStoredCenter` — centre as a fraction of the overlay bounds.
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

    struct Options: Equatable, Codable, Sendable {
        var trafficLights: Bool
        var crushClipCompensation: CrushClipCompensation
        var scale: Double
        var storedCenter: StoredCenter?
        var storedCenterPortrait: StoredCenter?

        static let `default` = Options(
            trafficLights: true,
            crushClipCompensation: .zero,
            scale: defaultScale,
            storedCenter: nil,
            storedCenterPortrait: nil)

        init(
            trafficLights: Bool = true,
            crushClipCompensation: CrushClipCompensation = .zero,
            scale: Double = defaultScale,
            storedCenter: StoredCenter? = nil,
            storedCenterPortrait: StoredCenter? = nil
        ) {
            self.trafficLights = trafficLights
            self.crushClipCompensation = crushClipCompensation
            self.scale = Self.clampedScale(scale)
            self.storedCenter = storedCenter
            self.storedCenterPortrait = storedCenterPortrait
        }

        enum CodingKeys: String, CodingKey {
            case trafficLights, crushClipCompensation, scale, storedCenter, storedCenterPortrait
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            trafficLights = try c.decodeIfPresent(Bool.self, forKey: .trafficLights) ?? true
            crushClipCompensation =
                try c.decodeIfPresent(CrushClipCompensation.self, forKey: .crushClipCompensation)
                ?? .zero
            scale = Self.clampedScale(
                try c.decodeIfPresent(Double.self, forKey: .scale) ?? defaultScale)
            storedCenter = try c.decodeIfPresent(StoredCenter.self, forKey: .storedCenter)
            storedCenterPortrait = try c.decodeIfPresent(
                StoredCenter.self, forKey: .storedCenterPortrait)
        }

        static func clampedScale(_ value: Double) -> Double {
            min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
        }
    }

    static func panelSize(scale: Double) -> CGSize {
        let clamped = Options.clampedScale(scale)
        return CGSize(
            width: (baseSize.width * clamped).rounded(),
            height: (baseSize.height * clamped).rounded())
    }

    /// OpenZCine `feedOutsideCenter` for the histogram's bottom-trailing default.
    static func defaultCenter(
        feed: CGRect,
        size: CGSize,
        bounds: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        gap: CGFloat = 10
    ) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let x = feed.maxX - halfWidth
        let outside = feed.maxY + gap + halfHeight
        let y: CGFloat
        if outside + halfHeight <= bounds.maxY {
            y = outside
        } else {
            y = min(feed.maxY, bounds.maxY - chromeClearance.bottom) - gap - halfHeight
        }
        return clamp(CGPoint(x: x, y: y), size: size, bounds: bounds)
    }

    static func clamp(_ point: CGPoint, size: CGSize, bounds: CGRect) -> CGPoint {
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
        session: CGPoint?,
        stored: StoredCenter?,
        defaultCenter: CGPoint,
        size: CGSize,
        bounds: CGRect
    ) -> CGPoint {
        if let session { return clamp(session, size: size, bounds: bounds) }
        if let stored { return clamp(stored.center(in: bounds), size: size, bounds: bounds) }
        return clamp(defaultCenter, size: size, bounds: bounds)
    }

    @MainActor
    static var store: HistogramAssistStore { HistogramAssistStore.shared }

    /// OpenZCine `AssistQuickSettingsContent.histogramRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> HistogramLongPressMenu {
        HistogramLongPressMenu(options: options, compact: compact)
    }

    /// Binds the shared histogram store. Crush/clip compensation is also written to
    /// `LiveAssistState` so LIGHTS stays on the same OpenZCine value.
    @MainActor
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> HistogramLongPressMenu {
        longPressMenu(
            options: Binding(
                get: { store.options },
                set: { next in
                    store.options = next
                    if let shared = TrafficLightsAssist.CrushClipCompensation(
                        rawValue: next.crushClipCompensation.rawValue)
                    {
                        assist.crushClipCompensation = shared
                    }
                }
            ),
            compact: compact
        )
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> HistogramLongPressMenu {
        longPressMenu(assist: assist)
    }

    @MainActor
    static func longPressMenu() -> HistogramLongPressMenu {
        longPressMenu(options: store.optionsBinding)
    }

    /// Long-press-drag + L-corner resize wrapper (OpenZCine `MovablePanel`).
    static func overlay<Content: View>(
        canvas: CGRect,
        feed: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        @ViewBuilder content: @escaping () -> Content
    ) -> HistogramMovablePanel<Content> {
        HistogramMovablePanel(
            canvas: canvas, feed: feed, chromeClearance: chromeClearance, content: content)
    }
}

@MainActor
@Observable
final class HistogramAssistStore {
    static let shared = HistogramAssistStore(options: load())
    private static let defaultsKey = "OpenPocketCine.HistogramAssist.v1"

    var options: HistogramAssist.Options {
        didSet { persist() }
    }
    /// Session centre in canvas space (OpenZCine `movablePanelCenters["histo"]`).
    var sessionCenter: CGPoint?
    var sessionCenterPortrait: CGPoint?

    var optionsBinding: Binding<HistogramAssist.Options> {
        Binding(
            get: { self.options },
            set: { self.options = $0 }
        )
    }

    init(options: HistogramAssist.Options = .default) {
        self.options = options
    }

    static func load() -> HistogramAssist.Options {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(HistogramAssist.Options.self, from: data)
        else { return .default }
        return decoded
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    func setScale(_ scale: Double) {
        options.scale = HistogramAssist.Options.clampedScale(scale)
    }

    func sessionCenter(in bounds: CGRect) -> CGPoint? {
        ScopeCanvasSlot.pick(sessionCenter, sessionCenterPortrait, in: bounds)
    }

    func storedCenter(in bounds: CGRect) -> HistogramAssist.StoredCenter? {
        ScopeCanvasSlot.pick(options.storedCenter, options.storedCenterPortrait, in: bounds)
    }

    func beginDrag(center: CGPoint, in bounds: CGRect) {
        ScopeCanvasSlot.assign(&sessionCenter, &sessionCenterPortrait, in: bounds, center)
    }

    func drag(to center: CGPoint, in bounds: CGRect) {
        beginDrag(center: center, in: bounds)
    }

    func endDrag(bounds: CGRect) {
        guard let center = sessionCenter(in: bounds) else { return }
        var next = options
        let stored = HistogramAssist.StoredCenter(center: center, in: bounds)
        if ScopeCanvasSlot.forBounds(bounds) == .portrait {
            next.storedCenterPortrait = stored
        } else {
            next.storedCenter = stored
        }
        options = next
    }
}

/// OpenZCine `AssistQuickSettingsContent.histogramRows`.
struct HistogramLongPressMenu: View {
    @Binding var options: HistogramAssist.Options
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSwitchInlineRow(
                title: HistogramAssist.trafficLightsTitle,
                help: HistogramAssist.trafficLightsHelp,
                showTopDivider: false,
                stacked: compact,
                isOn: options.trafficLights
            ) {
                HistogramAssistHaptics.selection()
                options.trafficLights.toggle()
            }
            SettingsInlineRow(
                title: HistogramAssist.compensationTitle,
                help: HistogramAssist.compensationHelp,
                stacked: compact
            ) {
                HistogramCrushClipSegmented(
                    selected: options.crushClipCompensation,
                    compact: compact
                ) { match in
                    guard match != options.crushClipCompensation else { return }
                    HistogramAssistHaptics.selection()
                    options.crushClipCompensation = match
                }
            }
        }
    }
}

/// OpenZCine `SettingsCrushClipSegmented` — fraction glyphs, 46pt floor.
private struct HistogramCrushClipSegmented: View {
    let selected: HistogramAssist.CrushClipCompensation
    var compact: Bool = false
    let onSelect: (HistogramAssist.CrushClipCompensation) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HistogramAssist.CrushClipCompensation.allCases) { option in
                let active = option == selected
                Button {
                    onSelect(option)
                } label: {
                    Text(option.compactLabel)
                        .font(
                            LiveType.ui(
                                size: compact ? 12 : 11, weight: active ? .semibold : .medium)
                        )
                        .foregroundStyle(active ? LiveDesign.text : LiveDesign.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(minWidth: 46, minHeight: 34)
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

/// OpenZCine `MovablePanel` specialised for histogram — long-press-drag + L-corner resize.
struct HistogramMovablePanel<Content: View>: View {
    let canvas: CGRect
    let feed: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()
    @ViewBuilder var content: () -> Content

    @Environment(\.interfaceLocked) private var interfaceLocked
    private var store: HistogramAssistStore { HistogramAssist.store }

    @State private var dragOrigin: CGPoint?
    @State private var isDragging = false
    @State private var snapCell = 0
    @State private var isResizing = false
    @State private var resizeStartScale = 1.0

    private var gripCornerInset: CGFloat {
        HistogramAssist.gripVisualSize - HistogramAssist.gripExteriorGap
    }

    var body: some View {
        let options = store.options
        let size = HistogramAssist.panelSize(scale: options.scale)
        let fallback = HistogramAssist.defaultCenter(
            feed: feed, size: size, bounds: canvas, chromeClearance: chromeClearance)
        let center = HistogramAssist.resolvedCenter(
            session: store.sessionCenter(in: canvas),
            stored: store.storedCenter(in: canvas),
            defaultCenter: fallback,
            size: size,
            bounds: canvas)
        let gripPad = HistogramAssist.gripHitSize - gripCornerInset
        ZStack(alignment: .topLeading) {
            content()
                .overlay(alignment: .bottomTrailing) {
                    resizeHandle
                        .offset(
                            x: HistogramAssist.gripExteriorGap,
                            y: HistogramAssist.gripExteriorGap)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .padding(HistogramAssist.dragHitPadding)
                .contentShape(Rectangle())
                .padding(-HistogramAssist.dragHitPadding)
                .gesture(interfaceLocked ? nil : panelDragGesture(center: center))
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
        .allowsHitTesting(!interfaceLocked)
    }

    private func panelDragGesture(center: CGPoint) -> some Gesture {
        LongPressGesture(minimumDuration: HistogramAssist.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !isDragging {
                    isDragging = true
                    dragOrigin = center
                    store.beginDrag(center: center, in: canvas)
                }
                guard let drag, let origin = dragOrigin else { return }
                let proposed = CGPoint(
                    x: origin.x + drag.translation.width,
                    y: origin.y + drag.translation.height)
                let size = HistogramAssist.panelSize(scale: store.options.scale)
                let snapped = HistogramAssist.clamp(
                    HistogramAssist.snap(proposed), size: size, bounds: canvas)
                let cell = HistogramAssist.hapticCell(snapped)
                if cell != snapCell { snapCell = cell }
                store.drag(to: snapped, in: canvas)
            }
            .onEnded { _ in
                store.endDrag(bounds: canvas)
                isDragging = false
                dragOrigin = nil
            }
    }

    private var resizeHandle: some View {
        let gripColor = isResizing ? LiveDesign.accent : LiveDesign.muted
        return HistogramCornerResizeGrip()
            .stroke(gripColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
            .frame(
                width: HistogramAssist.gripVisualSize, height: HistogramAssist.gripVisualSize,
                alignment: .bottomTrailing
            )
            .frame(
                width: HistogramAssist.gripHitSize, height: HistogramAssist.gripHitSize,
                alignment: .bottomTrailing
            )
            .contentShape(Rectangle())
            .gesture(interfaceLocked ? nil : resizeGesture)
            .accessibilityLabel("Resize histogram")
    }

    private var resizeGesture: some Gesture {
        LongPressGesture(minimumDuration: HistogramAssist.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !isResizing {
                    isResizing = true
                    resizeStartScale = store.options.scale
                }
                guard let drag else { return }
                let reach = HistogramAssist.baseSize.width + HistogramAssist.baseSize.height
                let delta = (drag.translation.width + drag.translation.height) / reach
                store.setScale(resizeStartScale + delta)
            }
            .onEnded { _ in isResizing = false }
    }
}

/// OpenZCine `CornerResizeGrip` — L-bracket at the bottom-trailing exterior corner.
struct HistogramCornerResizeGrip: Shape {
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

/// OpenZCine `OperatorSettingsHaptics.selection`.
private enum HistogramAssistHaptics {
    @MainActor
    static func selection() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}
